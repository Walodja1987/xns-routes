// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IXNSMinimal} from "./interfaces/IXNSMinimal.sol";

///////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                           //
//   __   __ _   _   _____         ___    _____    ____   _    _  _______  ______   _____    //
//   \ \ / /| \ | | / ____|       /  /   |  __ \  / __ \ | |  | ||__   __||  ____| / ____|   //
//    \ V / |  \| || (___        /  /    | |__) || |  | || |  | |   | |   | |__   | (___     //
//     > <  | . ` | \___ \      /  /     |  _  / | |  | || |  | |   | |   |  __|   \___ \    //
//    / . \ | |\  | ____) |    /  /      | | \ \ | |__| || |__| |   | |   | |____  ____) |   //
//   /_/ \_\|_| \_||_____/    /_ /       |_|  \_\ \____/  \____/    |_|   |______||_____/    //
//                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////

/// @title XNSRoutes
/// @author Wladimir Weinbender (DIVA Technologies AG)
/// @notice A simple named-endpoint registry attached to XNS names.
///
/// The ERC-173-compatible `owner()` is an identity/administrative pointer for external
/// integrations only. It has no authority over routes. Route mutations are authorized
/// exclusively through current XNS name ownership.
///
/// XNS name owners can create named routes under their XNS name which resolve to opaque
/// endpoint payloads (`bytes`). Routes may represent EVM addresses, other-chain addresses,
/// identifiers, or other application-defined data — interpreted via `routeType`.
///
/// ### Route format
///
/// label AT namespace/routeLabel
///
/// Examples:
/// - `alice AT pay/treasury`
/// - `alice AT pay/treasury-eth`
/// - `alice AT pay/treasury-arb`
/// - `aave AT defi/v3-pool`
///
/// The route label must:
/// - Be 1–32 characters long.
/// - Consist only of [a-z0-9-].
/// - Not start or end with '-'.
/// - Not contain consecutive hyphens ('--').
///
/// Application-layer parameters use URL query syntax (e.g. `?amount=10&to=0x…`) and are
/// not part of the on-chain route format. Callers must strip any `?...` suffix before using
/// string-based helpers.
///
/// ### Route record
///
/// Each route stores:
/// - `target` — opaque endpoint payload (mutable until frozen); must be non-empty.
/// - `routeType` — generic off-chain interpretation hint (mutable until frozen).
/// - `isActive` — whether applications should currently treat the route as usable
///   (toggled by the XNS name owner).
/// - `isFrozen` — whether this route's `target` / `routeType` are permanently locked.
/// - `routeLabel` — immutable route label.
///
/// `routeLabel` is immutable after route creation. `target` and `routeType` may be updated by
/// the XNS name owner until that route is frozen (`isFrozen`).
///
/// The exact semantics of `routeType` are intentionally not enforced by this contract.
/// Applications may define their own interpretation conventions.
///
/// Example route types (illustrative; see `routeTypes/`):
/// - `0` = EVM address
/// - `1` = Bitcoin address
/// - `2` = Solana pubkey
/// - `3` = EVM calldata
/// - `4` = URI
/// - `5` = EVM route builder
/// - etc.
///
/// This contract does not validate `target` contents beyond requiring non-empty.
///
/// ### Active status
///
/// A route starts active by default.
///
/// The XNS name owner may activate or deactivate the route at any time, including after the
/// route has been frozen. Freezing a route does **not** lock `isActive`.
///
/// ### Route freezing
///
/// The XNS name owner may permanently freeze an individual route (`freezeRoute`), or create
/// it already frozen (`createRouteAndFreeze`).
///
/// Once `isFrozen` is true:
/// - `target` and `routeType` can never change again.
/// - The XNS name owner may continue toggling `isActive`.
///
/// ### Route-book closing
///
/// The XNS name owner may permanently close the route book (`closeRouteBook`).
///
/// After closing:
/// - No new routes may be created under that name.
/// - Existing routes are unchanged (not frozen by the close).
/// - Per-route freeze and `isActive` controls remain independent.
///
/// ### Resolution
///
/// `resolveRoute` returns the `target` only when the route is frozen and active.
/// Integrations that need mutable or inactive routes can inspect `getRouteRecord` directly.
///
/// Efficient contract integrations should use the separate:
///
///     (label, namespace, routeLabel)
///
/// parameters.
///
/// Convenience view functions additionally support complete strings such as:
///
///     alice AT pay/treasury
///
/// No reverse lookup is provided because multiple routes may point to the same target.
///
/// ### Keys and indexing
///
/// - XNS name key: `keccak256(abi.encodePacked(label, " AT ", namespace))`.
/// - Route key: `keccak256(abi.encodePacked(label, " AT ", namespace, "/", routeLabel))`
///   (the hash of the canonical route string `label AT namespace/routeLabel`).
///   Unambiguous because XNSv2 forbids the at-sign and `/` in `label` and `namespace`,
///   and a route label cannot contain `/`.
/// - The route list can be queried with `getRouteKeyCount`, `getRouteKeys`, and `getRouteEntries`.
///   `getRouteEntries` returns each route's key plus stored `routeLabel` and metadata.
///
/// @dev The comments use AT instead of @ as solc treats @ as a documentation tag in NatSpec.
contract XNSRoutes is Ownable2Step {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @notice Metadata associated with a route.
    struct RouteRecord {
        bytes target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
        string routeLabel;
    }

    /// @notice Paginated route listing entry.
    struct RouteEntry {
        bytes32 routeKey;
        RouteRecord record;
    }

    // -------------------------------------------------------------------------
    // Constants and storage
    // -------------------------------------------------------------------------

    /// @notice XNSv2 registry used for name ownership resolution.
    IXNSMinimal public immutable XNS;

    /// @dev Whether the route book for an XNS name is permanently closed.
    ///
    /// XNS name key: keccak256(abi.encodePacked(label, " AT ", namespace))
    mapping(bytes32 xnsNameKey => bool isClosed) private _routeBookClosed;

    /// @dev Canonical route key => route record.
    mapping(bytes32 routeKey => RouteRecord record) private _routes;

    /// @dev Append-only list of route keys created under an XNS name.
    mapping(bytes32 xnsNameKey => bytes32[] routeKeys) private _routeKeysByXNSName;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted by `createRoute` and `createRouteAndFreeze`.
    event RouteCreated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        bytes32 indexed targetHash,
        string label,
        string namespace,
        string routeLabel,
        uint32 routeType
    );

    /// @dev Emitted by `activateRoute` and `deactivateRoute` (only when `isActive` changes).
    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bool isActive
    );

    /// @dev Emitted by `updateRoute`.
    event RouteUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        bytes32 indexed targetHash,
        string label,
        string namespace,
        string routeLabel,
        uint32 routeType
    );

    /// @dev Emitted by `freezeRoute`, `batchFreezeRoutes`, and `createRouteAndFreeze`.
    event RouteFrozen(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel
    );

    /// @dev Emitted by `closeRouteBook`.
    event RouteBookClosed(bytes32 indexed xnsNameKey, string label, string namespace);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Sets the contract owner and XNSv2 registry, then registers `routes AT xns`.
    ///
    /// Ownership uses a two-step transfer and grants no authority over route state.
    ///
    /// **Requirements:**
    /// - `xnsContract` must not be the zero address.
    /// - `initialOwner` must not be the zero address.
    /// - `msg.value` must be sufficient for XNS `registerName("routes", "xns")` (query
    ///   `getNamespacePrice("xns")` on the XNS contract before deploying).
    /// - The `xns` namespace must already exist on the XNS registry.
    ///
    /// @param initialOwner Initial ERC-173 owner used as an external identity pointer.
    /// @param xnsContract Address of the XNSv2 registry.
    constructor(address initialOwner, address xnsContract) payable Ownable(initialOwner) {
        require(xnsContract != address(0), "XNSRoutes: 0x XNS address");

        XNS = IXNSMinimal(xnsContract);

        XNS.registerName{value: msg.value}("routes", "xns");
    }

    // =========================================================================
    // STATE-MODIFYING FUNCTIONS
    // =========================================================================

    // -------------------------------------------------------------------------
    // Route creation
    // -------------------------------------------------------------------------

    /// @notice Creates a route under an XNS name.
    ///
    /// The route starts active and unfrozen.
    /// `target` and `routeType` remain mutable until the route is frozen.
    ///
    /// Example:
    ///
    ///     createRoute("alice", "pay", "treasury", target, 0)
    ///
    /// creates:
    ///
    ///     alice AT pay/treasury
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - `routeLabel` must be valid.
    /// - `target` must be non-empty.
    /// - The route book must not be closed.
    /// - The route must not already exist.
    ///
    /// Emits `RouteCreated`.
    function createRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType
    ) external {
        _createRoute(label, namespace, routeLabel, target, routeType, false);
    }

    /// @notice Creates a route and permanently freezes it in the same transaction.
    ///
    /// The route starts active and frozen, so it is immediately returned by `resolveRoute`.
    /// Use only with a verified `target` and `routeType`: a mistaken route can never be
    /// corrected or removed, only deactivated.
    ///
    /// **Requirements:**
    /// - Same as `createRoute`.
    ///
    /// Emits `RouteCreated` followed by `RouteFrozen`.
    function createRouteAndFreeze(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType
    ) external {
        _createRoute(label, namespace, routeLabel, target, routeType, true);
    }

    /// @dev Shared implementation for `createRoute` and `createRouteAndFreeze`.
    function _createRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType,
        bool frozen
    ) private {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);

        require(_isValidRouteLabel(routeLabel), "XNSRoutes: invalid route label");
        require(target.length > 0, "XNSRoutes: invalid target");
        require(!_routeBookClosed[xnsNameKey], "XNSRoutes: route book closed");

        bytes32 routeKey = _routeKey(label, namespace, routeLabel);

        require(_routes[routeKey].target.length == 0, "XNSRoutes: route already exists");

        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: true,
            isFrozen: frozen,
            routeLabel: routeLabel
        });

        _routeKeysByXNSName[xnsNameKey].push(routeKey);

        emit RouteCreated(
            xnsNameKey,
            routeKey,
            keccak256(target),
            label,
            namespace,
            routeLabel,
            routeType
        );

        if (frozen) {
            emit RouteFrozen(xnsNameKey, routeKey, label, namespace, routeLabel);
        }
    }

    // -------------------------------------------------------------------------
    // Route active status
    // -------------------------------------------------------------------------

    /// @notice Activates an existing route.
    ///
    /// Allowed even if the route is frozen — freeze does not lock `isActive`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes.
    function activateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external {
        _updateRouteActiveStatus(label, namespace, routeLabel, true);
    }

    /// @notice Deactivates an existing route.
    ///
    /// Allowed even if the route is frozen — freeze does not lock `isActive`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes.
    function deactivateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external {
        _updateRouteActiveStatus(label, namespace, routeLabel, false);
    }

    /// @dev Shared implementation for route activation/deactivation.
    function _updateRouteActiveStatus(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bool active
    ) private {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);
        bytes32 routeKey = _routeKey(label, namespace, routeLabel);

        RouteRecord storage record = _routes[routeKey];

        require(record.target.length > 0, "XNSRoutes: route not found");

        if (record.isActive != active) {
            record.isActive = active;

            emit RouteActiveStatusUpdated(
                xnsNameKey,
                routeKey,
                label,
                namespace,
                routeLabel,
                active
            );
        }
    }

    // -------------------------------------------------------------------------
    // Route update and freeze
    // -------------------------------------------------------------------------

    /// @notice Updates `target` and `routeType` for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - The route must exist.
    /// - The route must not be frozen (`isFrozen`).
    /// - `newTarget` must be non-empty.
    ///
    /// Emits `RouteUpdated` only when `target` or `routeType` actually changes.
    function updateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata newTarget,
        uint32 newRouteType
    ) external {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);
        bytes32 routeKey = _routeKey(label, namespace, routeLabel);

        RouteRecord storage record = _routes[routeKey];

        require(record.target.length > 0, "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: route frozen");
        require(newTarget.length > 0, "XNSRoutes: invalid target");

        if (keccak256(record.target) != keccak256(newTarget) || record.routeType != newRouteType) {
            record.target = newTarget;
            record.routeType = newRouteType;

            emit RouteUpdated(
                xnsNameKey,
                routeKey,
                keccak256(newTarget),
                label,
                namespace,
                routeLabel,
                newRouteType
            );
        }
    }

    /// @notice Permanently freezes an individual route so `target` and `routeType` cannot change.
    ///
    /// Freezing is irreversible. `isActive` remains independently controllable by the XNS name owner.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - The route must exist.
    ///
    /// Emits `RouteFrozen` only if the route was not already frozen.
    function freezeRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);
        _freezeRoute(xnsNameKey, label, namespace, routeLabel);
    }

    /// @notice Permanently freezes multiple routes under one XNS name.
    ///
    /// Same per-route semantics as `freezeRoute`. Already-frozen routes are skipped
    /// (no event). Missing routes cause the entire call to revert.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    /// - Every `routeLabels[i]` must refer to an existing route.
    ///
    /// Emits `RouteFrozen` for each route that newly becomes frozen.
    function batchFreezeRoutes(
        string calldata label,
        string calldata namespace,
        string[] calldata routeLabels
    ) external {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);

        uint256 n = routeLabels.length;
        for (uint256 i = 0; i < n; ++i) {
            _freezeRoute(xnsNameKey, label, namespace, routeLabels[i]);
        }
    }

    /// @dev Shared freeze implementation used by `freezeRoute` and `batchFreezeRoutes`.
    function _freezeRoute(
        bytes32 xnsNameKey,
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) private {
        bytes32 routeKey = _routeKey(label, namespace, routeLabel);

        RouteRecord storage record = _routes[routeKey];

        require(record.target.length > 0, "XNSRoutes: route not found");

        if (!record.isFrozen) {
            record.isFrozen = true;

            emit RouteFrozen(xnsNameKey, routeKey, label, namespace, routeLabel);
        }
    }

    // -------------------------------------------------------------------------
    // Route-book close
    // -------------------------------------------------------------------------

    /// @notice Permanently closes the route book associated with an XNS name.
    ///
    /// After closing, no additional routes may be created under that name.
    /// Existing routes are unchanged: they are not frozen, and `isActive` remains
    /// controllable by the XNS name owner.
    ///
    /// **Requirements:**
    /// - `msg.sender` must own `label AT namespace`.
    ///
    /// Emits `RouteBookClosed` only if the route book was not already closed.
    function closeRouteBook(string calldata label, string calldata namespace) external {
        _closeRouteBook(label, namespace);
    }

    /// @notice Permanently closes the route book for `label AT namespace`.
    ///
    /// Same requirements and effects as `closeRouteBook(label, namespace)`.
    ///
    /// Emits `RouteBookClosed` only if the route book was not already closed.
    function closeRouteBook(string calldata xnsName) external {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        _closeRouteBook(label, namespace);
    }

    /// @dev Shared implementation for both route-book close overloads.
    function _closeRouteBook(string memory label, string memory namespace) private {
        require(msg.sender == XNS.getAddress(label, namespace), "XNSRoutes: not XNS name owner");

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);

        if (!_routeBookClosed[xnsNameKey]) {
            _routeBookClosed[xnsNameKey] = true;

            emit RouteBookClosed(xnsNameKey, label, namespace);
        }
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    // -------------------------------------------------------------------------
    // Route records
    // -------------------------------------------------------------------------

    /// @notice Returns a route record directly by route key.
    ///
    /// `record.target.length == 0` means the route does not exist.
    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record) {
        return _routes[routeKey];
    }

    /// @notice Returns a route record using separate XNS components.
    function getRouteRecord(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record) {
        return _routes[_routeKey(label, namespace, routeLabel)];
    }

    /// @notice Returns a route record using a complete route string.
    ///
    /// Example:
    ///
    ///     alice AT pay/treasury
    ///
    /// Parsed like `splitRoute` (no component validation). Returns an empty record if no
    /// route matches.
    function getRouteRecord(
        string calldata route
    ) external view returns (RouteRecord memory record) {
        (string memory label, string memory namespace, string memory routeLabel) = _splitRoute(
            route
        );

        return _routes[_routeKey(label, namespace, routeLabel)];
    }

    // -------------------------------------------------------------------------
    // Route key derivation
    // -------------------------------------------------------------------------

    /// @notice Returns the canonical XNS name key for separate name components.
    ///
    /// Equal to the hash of the UTF-8 string `label AT namespace`.
    function getXNSNameKey(
        string calldata label,
        string calldata namespace
    ) external pure returns (bytes32 xnsNameKey) {
        return _xnsNameKey(label, namespace);
    }

    /// @notice Returns the canonical XNS name key for a complete XNS name.
    ///
    /// Parsed like `splitXNSName` (no component validation).
    function getXNSNameKey(string calldata xnsName) external pure returns (bytes32 xnsNameKey) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _xnsNameKey(label, namespace);
    }

    /// @notice Returns the canonical route key for separate XNS components.
    ///
    /// Equal to the hash of the UTF-8 string `label AT namespace/routeLabel`.
    function getRouteKey(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external pure returns (bytes32 routeKey) {
        return _routeKey(label, namespace, routeLabel);
    }

    /// @notice Returns the canonical route key for a complete route string.
    ///
    /// Example:
    ///
    ///     getRouteKey("alice AT pay/treasury")
    ///
    /// Parsed like `splitRoute` (no component validation), so an invalid route string still
    /// yields a key; no created route can have it.
    function getRouteKey(string calldata route) external pure returns (bytes32 routeKey) {
        (string memory label, string memory namespace, string memory routeLabel) = _splitRoute(
            route
        );

        return _routeKey(label, namespace, routeLabel);
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /// @notice Resolves a frozen and active route using separate XNS components.
    ///
    /// Reverts if the route does not exist, is not frozen, or is inactive.
    function resolveRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (bytes memory target, uint32 routeType) {
        return _resolveRoute(label, namespace, routeLabel);
    }

    /// @notice Resolves a frozen and active route using a complete route string.
    ///
    /// Example:
    ///
    ///     resolveRoute("alice AT pay/treasury")
    ///
    /// Parsed like `splitRoute` (no component validation). Reverts if the string cannot be split
    /// (missing delimiter or empty component), or if the route does not exist, is not frozen,
    /// or is inactive.
    function resolveRoute(
        string calldata route
    ) external view returns (bytes memory target, uint32 routeType) {
        (string memory label, string memory namespace, string memory routeLabel) = _splitRoute(
            route
        );

        return _resolveRoute(label, namespace, routeLabel);
    }

    /// @dev Shared implementation for both route-resolution overloads.
    function _resolveRoute(
        string memory label,
        string memory namespace,
        string memory routeLabel
    ) private view returns (bytes memory target, uint32 routeType) {
        RouteRecord storage record = _routes[_routeKey(label, namespace, routeLabel)];

        require(record.target.length > 0, "XNSRoutes: route not found");
        require(record.isFrozen, "XNSRoutes: route not frozen");
        require(record.isActive, "XNSRoutes: route inactive");

        return (record.target, record.routeType);
    }

    // -------------------------------------------------------------------------
    // Route book and route list
    // -------------------------------------------------------------------------

    /// @notice Returns whether the route book belonging to an XNS name is closed.
    function isRouteBookClosed(
        string calldata label,
        string calldata namespace
    ) external view returns (bool closed) {
        return _routeBookClosed[_xnsNameKey(label, namespace)];
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    ///
    /// Example:
    ///
    ///     isRouteBookClosed("alice AT pay")
    function isRouteBookClosed(string calldata xnsName) external view returns (bool closed) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _routeBookClosed[_xnsNameKey(label, namespace)];
    }

    /// @notice Returns the number of routes ever created under an XNS name.
    function getRouteKeyCount(
        string calldata label,
        string calldata namespace
    ) external view returns (uint256 count) {
        return _routeKeysByXNSName[_xnsNameKey(label, namespace)].length;
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _routeKeysByXNSName[_xnsNameKey(label, namespace)].length;
    }

    /// @notice Returns route keys `[start:end]` for an XNS name.
    ///
    /// `end` is exclusive and is clamped to the array length. Returns an empty array if
    /// `start` is at or beyond the clamped `end`. Reverts if `start > end`.
    function getRouteKeys(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys) {
        return _sliceRouteKeys(_routeKeysByXNSName[_xnsNameKey(label, namespace)], start, end);
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    ///
    /// Same pagination rules as `getRouteKeys(label, namespace, start, end)`.
    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _sliceRouteKeys(_routeKeysByXNSName[_xnsNameKey(label, namespace)], start, end);
    }

    /// @notice Returns full route entries `[start:end]` for an XNS name.
    ///
    /// Same pagination rules as `getRouteKeys(label, namespace, start, end)`.
    function getRouteEntries(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries) {
        return _getRouteEntries(_xnsNameKey(label, namespace), start, end);
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    ///
    /// Same pagination rules as `getRouteKeys(label, namespace, start, end)`.
    function getRouteEntries(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _getRouteEntries(_xnsNameKey(label, namespace), start, end);
    }

    /// @dev Shared implementation for both route-entry listing overloads.
    function _getRouteEntries(
        bytes32 xnsNameKey,
        uint256 start,
        uint256 end
    ) private view returns (RouteEntry[] memory entries) {
        bytes32[] memory keys = _sliceRouteKeys(_routeKeysByXNSName[xnsNameKey], start, end);

        uint256 n = keys.length;

        entries = new RouteEntry[](n);

        for (uint256 i = 0; i < n; ++i) {
            bytes32 routeKey = keys[i];

            entries[i] = RouteEntry({routeKey: routeKey, record: _routes[routeKey]});
        }
    }

    // -------------------------------------------------------------------------
    // Parsing
    // -------------------------------------------------------------------------

    /// @notice Parses a complete route string into:
    ///
    ///     (label, namespace, routeLabel)
    ///
    /// Example:
    ///
    ///     alice AT pay/treasury
    ///
    /// becomes:
    ///
    ///     ("alice", "pay", "treasury")
    ///
    /// Splits at the first `/` and the first at-sign before it. Components are not validated:
    /// for example, `alice AT pay/foo/bar` becomes `("alice", "pay", "foo/bar")`.
    /// Reverts only if a delimiter is missing or a component is empty.
    function splitRoute(
        string calldata route
    )
        external
        pure
        returns (string memory label, string memory namespace, string memory routeLabel)
    {
        return _splitRoute(route);
    }

    /// @notice Parses `label AT namespace`.
    ///
    /// Splits at the first at-sign. Components are not validated.
    /// Reverts only if the at-sign is missing or a component is empty.
    function splitXNSName(
        string calldata xnsName
    ) external pure returns (string memory label, string memory namespace) {
        return _splitXNSName(xnsName);
    }

    // -------------------------------------------------------------------------
    // Validation
    // -------------------------------------------------------------------------

    /// @notice Returns whether a route label satisfies the XNS Routes label rules.
    function isValidRouteLabel(string calldata routeLabel) external pure returns (bool valid) {
        return _isValidRouteLabel(routeLabel);
    }

    // =========================================================================
    // INTERNAL HELPERS
    // =========================================================================

    /// @dev Returns the same canonical name hash used by XNSv2:
    ///
    ///     keccak256(abi.encodePacked(label, " AT ", namespace))
    function _xnsNameKey(
        string memory label,
        string memory namespace
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(label, "@", namespace));
    }

    /// @dev Canonical route key: hash of `label AT namespace/routeLabel`:
    ///
    ///     keccak256(abi.encodePacked(label, " AT ", namespace, "/", routeLabel))
    ///
    /// Unambiguous because XNSv2 forbids the at-sign and `/` in `label` and
    /// `namespace`, and a route label cannot contain `/`.
    function _routeKey(
        string memory label,
        string memory namespace,
        string memory routeLabel
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel));
    }

    /// @dev Parses:
    ///
    ///     label AT namespace/routeLabel
    ///
    /// Splits at the first `/`; everything after it becomes `routeLabel`. Components are not
    /// validated. Query-string params (`?...`) are not stripped; callers must remove them
    /// before calling.
    function _splitRoute(
        string calldata route
    )
        private
        pure
        returns (string memory label, string memory namespace, string memory routeLabel)
    {
        bytes calldata b = bytes(route);
        uint256 len = b.length;

        uint256 slashIndex = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            if (b[i] == 0x2F) {
                slashIndex = i;
                break;
            }
        }

        require(slashIndex != type(uint256).max, "XNSRoutes: invalid route");
        require(slashIndex > 0, "XNSRoutes: invalid route");

        (label, namespace) = _splitXNSName(string(b[:slashIndex]));

        uint256 routeStart = slashIndex + 1;

        require(routeStart < len, "XNSRoutes: invalid route");

        routeLabel = string(b[routeStart:]);
    }

    /// @dev Parses `label AT namespace`, splitting at the first at-sign. Components are not validated.
    function _splitXNSName(
        string calldata xnsName
    ) private pure returns (string memory label, string memory namespace) {
        bytes calldata b = bytes(xnsName);
        uint256 len = b.length;

        uint256 atIndex = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            if (b[i] == 0x40) {
                atIndex = i;
                break;
            }
        }

        require(
            atIndex != type(uint256).max && atIndex > 0 && atIndex + 1 < len,
            "XNSRoutes: invalid XNS name"
        );

        label = string(b[:atIndex]);
        namespace = string(b[atIndex + 1:]);
    }

    /// @dev Returns `arr[start:end]`, with `end` clamped to array length.
    function _sliceRouteKeys(
        bytes32[] storage arr,
        uint256 start,
        uint256 end
    ) private view returns (bytes32[] memory keys) {
        require(start <= end, "XNSRoutes: invalid slice");

        uint256 len = arr.length;
        uint256 adjustedEnd = end > len ? len : end;

        if (start >= adjustedEnd) {
            return new bytes32[](0);
        }

        uint256 n = adjustedEnd - start;

        keys = new bytes32[](n);

        for (uint256 i = 0; i < n; ++i) {
            keys[i] = arr[start + i];
        }
    }

    /// @dev Validates a route label:
    /// - 1–32 characters.
    /// - [a-z0-9-] only.
    /// - No leading/trailing '-'.
    /// - No consecutive '--'.
    function _isValidRouteLabel(string calldata routeLabel) private pure returns (bool isValid) {
        bytes calldata b = bytes(routeLabel);
        uint256 len = b.length;

        if (len == 0 || len > 32) {
            return false;
        }

        for (uint256 i = 0; i < len; ++i) {
            bytes1 c = b[i];

            bool isLowercaseLetter = c >= 0x61 && c <= 0x7A;

            bool isDigit = c >= 0x30 && c <= 0x39;

            bool isHyphen = c == 0x2D;

            if (!(isLowercaseLetter || isDigit || isHyphen)) {
                return false;
            }

            if (isHyphen && i > 0 && b[i - 1] == 0x2D) {
                return false;
            }
        }

        if (b[0] == 0x2D || b[len - 1] == 0x2D) {
            return false;
        }

        return true;
    }
}

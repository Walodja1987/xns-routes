// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
/// @notice A simple immutable named-endpoint registry attached to XNS names.
///
/// XNS name owners can create named routes under their XNS name which resolve to opaque
/// endpoint payloads (`bytes`). Routes may represent EVM addresses, other-chain addresses,
/// identifiers, or other application-defined data — interpreted via `routeType`.
///
/// Route format:
///
///     label AT namespace/route
///
/// Examples:
/// - `alice AT pay/treasury`
/// - `alice AT pay/treasury-eth`
/// - `alice AT pay/treasury-arb`
/// - `aave AT defi/v3-pool`
///
/// The route portion must:
/// - Be 1–32 characters long.
/// - Consist only of [a-z0-9-].
/// - Not start or end with '-'.
/// - Not contain consecutive hyphens ('--').
///
/// Routes may optionally include an application-layer `/params...` suffix when using the
/// string-based view functions. Anything after the second `/` is ignored by this contract.
///
/// Example:
///
///     alice AT pay/payment/amount=10
///
/// resolves the stored route:
///
///     alice AT pay/payment
///
/// Params are not validated, stored, interpreted, or processed on-chain.
///
/// ### Route record
///
/// Each route stores:
/// - `target` — opaque endpoint payload (mutable until frozen); 1–256 bytes.
/// - `routeType` — generic off-chain interpretation hint (mutable until frozen).
/// - `isActive` — whether applications should currently treat the route as usable
///   (toggled by the XNS name owner).
/// - `isFrozen` — whether this route's `target` / `routeType` are permanently locked.
/// - `routeLabel` — immutable route label.
///
/// `routeLabel` is immutable after route creation. `target` and `routeType` may be updated by
/// the XNS name owner until the route is effectively frozen (`isFrozen` or route-book freeze).
///
/// The exact semantics of `routeType` are intentionally not enforced by this contract.
/// Applications may define their own interpretation conventions.
///
/// Example route types:
/// - `0` = `target` is a 20-byte EVM address.
/// - `1` = `target` is a resolver/view contract address (20 bytes).
/// - `2` = `target` is interpreted according to another application-level convention
///   (e.g. Bitcoin address UTF-8, Solana pubkey, etc.).
///
/// This contract does not validate `target` contents beyond non-empty and max length.
///
/// ### Active status
///
/// A route starts active by default.
///
/// The XNS name owner may activate or deactivate the route at any time (including after freeze).
///
/// ### Route freezing
///
/// The XNS name owner may permanently freeze an individual route (`freezeRoute`) or the entire
/// route book (`freezeRouteBook`).
///
/// A route is effectively frozen when `isFrozen` is true **or** its route book is frozen:
///
///     effectiveRouteFrozen = record.isFrozen || routeBookFrozen
///
/// After effective freeze:
/// - `target` and `routeType` can no longer be updated.
/// - The XNS name owner may continue toggling `isActive`.
///
/// After route-book freeze:
/// - No new routes may be created under that name.
/// - All existing routes under that name are treated as effectively frozen for updates.
///
/// ### Resolution
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
/// **Resolution & indexing**
/// - Forward: route -> `target` via `resolveRouteIfActive` (requires `isActive`) or
///   `resolveRoute` (ignores `isActive`).
/// - XNS name key: `keccak256(abi.encodePacked(label, " AT ", namespace))`.
/// - Route key: `keccak256(abi.encode(xnsNameKey, keccak256(bytes(routeLabel))))`.
/// - The route list can be queried with `getRouteKeyCount`, `getRouteKeys`, and `getRouteEntries`.
///   `getRouteEntries` returns each route's key plus stored `routeLabel` and metadata.
contract XNSRoutes {
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

    /// @notice Maximum allowed `target` payload length (bytes).
    uint256 public constant MAX_TARGET_LENGTH = 256;

    /// @notice XNSv2 registry used for name ownership resolution.
    IXNSMinimal public immutable XNS;

    /// @dev XNS name key => whether its route book has been permanently frozen.
    ///
    /// XNS name key:
    ///
    ///     keccak256(abi.encodePacked(label, " AT ", namespace))
    mapping(bytes32 => bool) private _routeBookFrozen;

    /// @dev Route key => route record.
    mapping(bytes32 => RouteRecord) private _routes;

    /// @dev XNS name key => all route keys created under that XNS name.
    mapping(bytes32 => bytes32[]) private _routeKeysByXNSName;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event RouteCreated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bytes target,
        uint32 routeType,
        bool isActive
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bool isActive
    );

    event RouteUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bytes target,
        uint32 routeType
    );

    event RouteFrozen(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel
    );

    event RouteBookFrozen(
        bytes32 indexed xnsNameKey,
        string label,
        string namespace
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Sets the XNSv2 registry and registers `routes AT xns` for this contract.
    ///
    /// **Requirements:**
    /// - `xnsContract` must not be the zero address.
    /// - `msg.value` must be sufficient for XNS `registerName("routes", "xns")` (query
    ///   `getNamespacePrice("xns")` on the XNS contract before deploying).
    /// - The `xns` namespace must already exist on the XNS registry.
    ///
    /// @param xnsContract Address of the XNSv2 registry.
    constructor(address xnsContract) payable {
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
    /// `target` and `routeType` remain mutable until the route or route book is frozen.
    ///
    /// Example:
    ///
    ///     createRoute("alice", "pay", "treasury", target, 0)
    ///
    /// creates:
    ///
    ///     alice AT pay/treasury
    ///
    /// Requirements:
    /// - `msg.sender` must own `label AT namespace`.
    /// - `routeLabel` must be valid.
    /// - `target` must be non-empty and at most `MAX_TARGET_LENGTH` bytes.
    /// - The route book must not be frozen.
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
        bytes32 xnsNameKey = _requireXNSNameOwner(label, namespace);

        _createRoute(
            xnsNameKey,
            label,
            namespace,
            routeLabel,
            target,
            routeType
        );
    }

    /// @dev Shared route-creation implementation.
    function _createRoute(
        bytes32 xnsNameKey,
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType
    ) private {
        require(_isValidRouteLabel(routeLabel), "XNSRoutes: invalid route label");
        require(_isValidTarget(target), "XNSRoutes: invalid target");
        require(!_routeBookFrozen[xnsNameKey], "XNSRoutes: route book frozen");

        bytes32 routeKey = _routeKey(xnsNameKey, routeLabel);

        require(
            _routes[routeKey].target.length == 0,
            "XNSRoutes: route already exists"
        );

        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: true,
            isFrozen: false,
            routeLabel: routeLabel
        });

        _routeKeysByXNSName[xnsNameKey].push(routeKey);

        emit RouteCreated(
            xnsNameKey,
            routeKey,
            label,
            namespace,
            routeLabel,
            target,
            routeType,
            true
        );
    }

    // -------------------------------------------------------------------------
    // Route active status
    // -------------------------------------------------------------------------

    /// @notice Activates an existing route.
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
        _updateRouteActiveStatus(
            label,
            namespace,
            routeLabel,
            true
        );
    }

    /// @notice Deactivates an existing route.
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
        _updateRouteActiveStatus(
            label,
            namespace,
            routeLabel,
            false
        );
    }

    /// @dev Shared implementation for route activation/deactivation.
    function _updateRouteActiveStatus(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bool active
    ) private {
        bytes32 xnsNameKey = _requireXNSNameOwner(label, namespace);
        bytes32 routeKey = _routeKey(xnsNameKey, routeLabel);

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
    /// - The route must not be effectively frozen (`isFrozen` or route-book freeze).
    /// - `newTarget` must be non-empty and at most `MAX_TARGET_LENGTH` bytes.
    ///
    /// Emits `RouteUpdated` only when `target` or `routeType` actually changes.
    function updateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata newTarget,
        uint32 newRouteType
    ) external {
        bytes32 xnsNameKey = _requireXNSNameOwner(label, namespace);
        bytes32 routeKey = _routeKey(xnsNameKey, routeLabel);

        RouteRecord storage record = _routes[routeKey];

        require(record.target.length > 0, "XNSRoutes: route not found");
        require(
            !_isEffectivelyFrozen(xnsNameKey, record),
            "XNSRoutes: route frozen"
        );
        require(_isValidTarget(newTarget), "XNSRoutes: invalid target");

        if (
            keccak256(record.target) != keccak256(newTarget) ||
            record.routeType != newRouteType
        ) {
            record.target = newTarget;
            record.routeType = newRouteType;

            emit RouteUpdated(
                xnsNameKey,
                routeKey,
                label,
                namespace,
                routeLabel,
                newTarget,
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
        bytes32 xnsNameKey = _requireXNSNameOwner(label, namespace);
        bytes32 routeKey = _routeKey(xnsNameKey, routeLabel);

        RouteRecord storage record = _routes[routeKey];

        require(record.target.length > 0, "XNSRoutes: route not found");

        if (!record.isFrozen) {
            record.isFrozen = true;

            emit RouteFrozen(
                xnsNameKey,
                routeKey,
                label,
                namespace,
                routeLabel
            );
        }
    }

    // -------------------------------------------------------------------------
    // Route-book freeze
    // -------------------------------------------------------------------------

    /// @notice Permanently freezes the route book associated with an XNS name.
    ///
    /// After freezing:
    /// - No additional routes may be created.
    /// - All existing routes under the name are treated as effectively frozen for
    ///   `target` / `routeType` updates (without iterating or writing each route).
    /// - The XNS name owner may continue toggling `isActive` on existing routes.
    ///
    /// Requires `msg.sender` to own `label AT namespace`.
    ///
    /// Emits `RouteBookFrozen` only if the route book was not already frozen.
    function freezeRouteBook(
        string calldata label,
        string calldata namespace
    ) external {
        bytes32 xnsNameKey = _requireXNSNameOwner(label, namespace);

        if (!_routeBookFrozen[xnsNameKey]) {
            _routeBookFrozen[xnsNameKey] = true;

            emit RouteBookFrozen(
                xnsNameKey,
                label,
                namespace
            );
        }
    }

    /// @notice Permanently freezes the route book for `label AT namespace`.
    ///
    /// Same requirements and effects as `freezeRouteBook(label, namespace)`.
    ///
    /// Emits `RouteBookFrozen` only if the route book was not already frozen.
    function freezeRouteBook(string calldata xnsName) external {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);
        bytes32 xnsNameKey = _requireXNSNameOwnerMemory(label, namespace);

        if (!_routeBookFrozen[xnsNameKey]) {
            _routeBookFrozen[xnsNameKey] = true;

            emit RouteBookFrozen(
                xnsNameKey,
                label,
                namespace
            );
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
    function getRouteRecord(
        bytes32 routeKey
    ) external view returns (RouteRecord memory record) {
        return _copyRouteRecord(_routes[routeKey]);
    }

    /// @notice Returns a route record using separate XNS components.
    function getRouteRecord(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record) {
        bytes32 xnsNameKey = _xnsNameKey(label, namespace);

        return _copyRouteRecord(
            _routes[_routeKey(xnsNameKey, routeLabel)]
        );
    }

    /// @notice Returns a route record using a complete route string.
    ///
    /// Example:
    ///
    ///     alice AT pay/treasury
    ///
    /// An optional suffix after the second `/` is ignored.
    function getRouteRecord(
        string calldata route
    ) external view returns (RouteRecord memory record) {
        (
            string memory label,
            string memory namespace,
            string memory routeLabel
        ) = _splitRoute(route);

        bytes32 xnsNameKey = _xnsNameKey(label, namespace);

        return _copyRouteRecord(
            _routes[_routeKey(xnsNameKey, routeLabel)]
        );
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /// @notice Resolves an active route using separate XNS components.
    function resolveRouteIfActive(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (
        bytes memory target,
        uint32 routeType
    ) {
        return _resolveRouteIfActive(
            label,
            namespace,
            routeLabel
        );
    }

    /// @notice Resolves an active route using a complete route string.
    ///
    /// Example:
    ///
    ///     resolveRouteIfActive("alice AT pay/treasury")
    function resolveRouteIfActive(
        string calldata route
    ) external view returns (
        bytes memory target,
        uint32 routeType
    ) {
        (
            string memory label,
            string memory namespace,
            string memory routeLabel
        ) = _splitRoute(route);

        return _resolveRouteIfActive(
            label,
            namespace,
            routeLabel
        );
    }

    /// @notice Resolves a route regardless of its active status.
    function resolveRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (
        bytes memory target,
        uint32 routeType
    ) {
        return _resolveRoute(
            label,
            namespace,
            routeLabel
        );
    }

    /// @notice Resolves a route regardless of active status using a complete route string.
    ///
    /// Example:
    ///
    ///     resolveRoute("alice AT pay/treasury")
    function resolveRoute(
        string calldata route
    ) external view returns (
        bytes memory target,
        uint32 routeType
    ) {
        (
            string memory label,
            string memory namespace,
            string memory routeLabel
        ) = _splitRoute(route);

        return _resolveRoute(
            label,
            namespace,
            routeLabel
        );
    }

    // -------------------------------------------------------------------------
    // Route-book metadata
    // -------------------------------------------------------------------------

    /// @notice Returns whether the route book belonging to an XNS name is frozen.
    function isRouteBookFrozen(
        string calldata label,
        string calldata namespace
    ) external view returns (bool frozen) {
        return _routeBookFrozen[
            _xnsNameKey(label, namespace)
        ];
    }

    /// @notice Convenience overload accepting a complete XNS name.
    ///
    /// Example:
    ///
    ///     isRouteBookFrozen("alice AT pay")
    function isRouteBookFrozen(
        string calldata xnsName
    ) external view returns (bool frozen) {
        (
            string memory label,
            string memory namespace
        ) = _splitXNSName(xnsName);

        return _routeBookFrozen[
            _xnsNameKey(label, namespace)
        ];
    }

    /// @notice Returns whether a route is effectively frozen for `target` / `routeType` updates.
    ///
    /// True when the route's `isFrozen` flag is set or its route book is frozen.
    /// Returns false when the route does not exist.
    function isRouteFrozen(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (bool frozen) {
        bytes32 xnsNameKey = _xnsNameKey(label, namespace);
        RouteRecord storage record = _routes[_routeKey(xnsNameKey, routeLabel)];

        if (record.target.length == 0) {
            return false;
        }

        return _isEffectivelyFrozen(xnsNameKey, record);
    }

    /// @notice Returns the number of routes ever created under an XNS name.
    function getRouteKeyCount(
        string calldata label,
        string calldata namespace
    ) external view returns (uint256 count) {
        return _routeKeysByXNSName[
            _xnsNameKey(label, namespace)
        ].length;
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    function getRouteKeyCount(
        string calldata xnsName
    ) external view returns (uint256 count) {
        (
            string memory label,
            string memory namespace
        ) = _splitXNSName(xnsName);

        return _routeKeysByXNSName[
            _xnsNameKey(label, namespace)
        ].length;
    }

    /// @notice Returns route keys `[start:end]` for an XNS name.
    ///
    /// `end` is exclusive and is clamped to the array length.
    function getRouteKeys(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys) {
        return _sliceRouteKeys(
            _routeKeysByXNSName[_xnsNameKey(label, namespace)],
            start,
            end
        );
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        return _sliceRouteKeys(
            _routeKeysByXNSName[_xnsNameKey(label, namespace)],
            start,
            end
        );
    }

    /// @notice Returns full route entries `[start:end]` for an XNS name.
    function getRouteEntries(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries) {
        bytes32[] memory keys = _sliceRouteKeys(
            _routeKeysByXNSName[_xnsNameKey(label, namespace)],
            start,
            end
        );

        uint256 n = keys.length;

        entries = new RouteEntry[](n);

        for (uint256 i = 0; i < n; ++i) {
            bytes32 routeKey = keys[i];

            entries[i] = RouteEntry({
                routeKey: routeKey,
                record: _copyRouteRecord(_routes[routeKey])
            });
        }
    }

    /// @notice Convenience overload accepting `label AT namespace`.
    function getRouteEntries(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries) {
        (string memory label, string memory namespace) = _splitXNSName(xnsName);

        bytes32[] memory keys = _sliceRouteKeys(
            _routeKeysByXNSName[_xnsNameKey(label, namespace)],
            start,
            end
        );

        uint256 n = keys.length;

        entries = new RouteEntry[](n);

        for (uint256 i = 0; i < n; ++i) {
            bytes32 routeKey = keys[i];

            entries[i] = RouteEntry({
                routeKey: routeKey,
                record: _copyRouteRecord(_routes[routeKey])
            });
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
    /// An optional `/params...` suffix is ignored:
    ///
    ///     alice AT pay/payment/amount=10
    ///
    /// also returns:
    ///
    ///     ("alice", "pay", "payment")
    function splitRoute(
        string calldata route
    )
        external
        pure
        returns (
            string memory label,
            string memory namespace,
            string memory routeLabel
        )
    {
        return _splitRoute(route);
    }

    /// @notice Parses `label AT namespace`.
    function splitXNSName(
        string calldata xnsName
    )
        external
        pure
        returns (
            string memory label,
            string memory namespace
        )
    {
        return _splitXNSName(xnsName);
    }

    // -------------------------------------------------------------------------
    // Validation
    // -------------------------------------------------------------------------

    /// @notice Returns whether a route label satisfies the XNS Routes label rules.
    function isValidRouteLabel(
        string calldata routeLabel
    ) external pure returns (bool valid) {
        return _isValidRouteLabel(routeLabel);
    }

    /// @notice Returns whether a target payload is non-empty and within `MAX_TARGET_LENGTH`.
    function isValidTarget(
        bytes calldata target
    ) external pure returns (bool valid) {
        return _isValidTarget(target);
    }

    // =========================================================================
    // INTERNAL VIEW HELPERS
    // =========================================================================

    /// @dev Resolves an active route.
    function _resolveRouteIfActive(
        string memory label,
        string memory namespace,
        string memory routeLabel
    ) private view returns (
        bytes memory target,
        uint32 routeType
    ) {
        RouteRecord storage record = _routes[
            _routeKey(
                _xnsNameKey(label, namespace),
                routeLabel
            )
        ];

        require(
            record.target.length > 0,
            "XNSRoutes: route not found"
        );

        require(
            record.isActive,
            "XNSRoutes: route inactive"
        );

        return (
            record.target,
            record.routeType
        );
    }

    /// @dev Resolves a route regardless of active status.
    function _resolveRoute(
        string memory label,
        string memory namespace,
        string memory routeLabel
    ) private view returns (
        bytes memory target,
        uint32 routeType
    ) {
        RouteRecord storage record = _routes[
            _routeKey(
                _xnsNameKey(label, namespace),
                routeLabel
            )
        ];

        require(
            record.target.length > 0,
            "XNSRoutes: route not found"
        );

        return (
            record.target,
            record.routeType
        );
    }

    /// @dev Requires msg.sender to be the current XNS owner of `label AT namespace`.
    ///
    /// Uses the separate XNSv2 getter to avoid constructing and then parsing a full XNS name.
    function _requireXNSNameOwner(
        string calldata label,
        string calldata namespace
    ) private view returns (bytes32 xnsNameKey) {
        require(
            msg.sender == XNS.getAddress(label, namespace),
            "XNSRoutes: not XNS name owner"
        );

        return _xnsNameKey(label, namespace);
    }

    /// @dev Memory-string variant of `_requireXNSNameOwner`.
    function _requireXNSNameOwnerMemory(
        string memory label,
        string memory namespace
    ) private view returns (bytes32 xnsNameKey) {
        require(
            msg.sender == XNS.getAddress(label, namespace),
            "XNSRoutes: not XNS name owner"
        );

        return _xnsNameKey(label, namespace);
    }

    /// @dev True when `target` / `routeType` updates are permanently blocked.
    function _isEffectivelyFrozen(
        bytes32 xnsNameKey,
        RouteRecord storage record
    ) private view returns (bool) {
        return record.isFrozen || _routeBookFrozen[xnsNameKey];
    }

    // =========================================================================
    // INTERNAL PURE HELPERS
    // =========================================================================

    /// @dev Returns the same canonical name hash used by XNSv2:
    ///
    ///     keccak256(abi.encodePacked(label, " AT ", namespace))
    function _xnsNameKey(
        string memory label,
        string memory namespace
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                label,
                "@",
                namespace
            )
        );
    }

    /// @dev Derives a route key from the XNS name key and route-label hash.
    ///
    /// Using `abi.encode` creates an unambiguous fixed-size encoding.
    function _routeKey(
        bytes32 xnsNameKey,
        string memory routeLabel
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                xnsNameKey,
                keccak256(bytes(routeLabel))
            )
        );
    }

    /// @dev Parses:
    ///
    ///     label AT namespace/route
    ///
    /// and ignores anything after a second `/`.
    function _splitRoute(
        string calldata route
    )
        private
        pure
        returns (
            string memory label,
            string memory namespace,
            string memory routeLabel
        )
    {
        bytes calldata b = bytes(route);
        uint256 len = b.length;

        require(len > 0, "XNSRoutes: invalid route");

        uint256 slashIndex = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            if (b[i] == 0x2F) {
                slashIndex = i;
                break;
            }
        }

        require(
            slashIndex != type(uint256).max,
            "XNSRoutes: invalid route"
        );

        require(
            slashIndex > 0,
            "XNSRoutes: invalid route"
        );

        string memory xnsName =
            _calldataSubstringToString(
                b,
                0,
                slashIndex
            );

        (label, namespace) = _splitXNSNameMemory(xnsName);

        uint256 routeStart = slashIndex + 1;

        require(
            routeStart < len,
            "XNSRoutes: invalid route"
        );

        uint256 routeEnd = len;

        // Ignore optional application-layer params after second slash.
        for (uint256 i = routeStart; i < len; ++i) {
            if (b[i] == 0x2F) {
                routeEnd = i;
                break;
            }
        }

        require(
            routeEnd > routeStart,
            "XNSRoutes: invalid route"
        );

        routeLabel =
            _calldataSubstringToString(
                b,
                routeStart,
                routeEnd
            );
    }

    /// @dev Parses `label AT namespace` from calldata.
    function _splitXNSName(
        string calldata xnsName
    )
        private
        pure
        returns (
            string memory label,
            string memory namespace
        )
    {
        bytes calldata b = bytes(xnsName);
        uint256 len = b.length;

        require(len > 0, "XNSRoutes: invalid XNS name");

        uint256 atIndex = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            if (b[i] == 0x40) {
                require(
                    atIndex == type(uint256).max,
                    "XNSRoutes: invalid XNS name"
                );

                atIndex = i;
            }
        }

        require(
            atIndex != type(uint256).max &&
            atIndex > 0 &&
            atIndex + 1 < len,
            "XNSRoutes: invalid XNS name"
        );

        label =
            _calldataSubstringToString(
                b,
                0,
                atIndex
            );

        namespace =
            _calldataSubstringToString(
                b,
                atIndex + 1,
                len
            );
    }

    /// @dev Memory equivalent of `_splitXNSName`.
    function _splitXNSNameMemory(
        string memory xnsName
    )
        private
        pure
        returns (
            string memory label,
            string memory namespace
        )
    {
        bytes memory b = bytes(xnsName);
        uint256 len = b.length;

        require(len > 0, "XNSRoutes: invalid XNS name");

        uint256 atIndex = type(uint256).max;

        for (uint256 i = 0; i < len; ++i) {
            if (b[i] == 0x40) {
                require(
                    atIndex == type(uint256).max,
                    "XNSRoutes: invalid XNS name"
                );

                atIndex = i;
            }
        }

        require(
            atIndex != type(uint256).max &&
            atIndex > 0 &&
            atIndex + 1 < len,
            "XNSRoutes: invalid XNS name"
        );

        bytes memory labelBytes = new bytes(atIndex);

        for (uint256 i = 0; i < atIndex; ++i) {
            labelBytes[i] = b[i];
        }

        uint256 namespaceLength = len - atIndex - 1;
        bytes memory namespaceBytes = new bytes(namespaceLength);

        for (uint256 i = 0; i < namespaceLength; ++i) {
            namespaceBytes[i] = b[atIndex + 1 + i];
        }

        label = string(labelBytes);
        namespace = string(namespaceBytes);
    }

    /// @dev Copies calldata substring `[start:end]` into a string.
    function _calldataSubstringToString(
        bytes calldata data,
        uint256 start,
        uint256 end
    ) private pure returns (string memory out) {
        require(end >= start, "XNSRoutes: invalid substring");

        uint256 len = end - start;
        bytes memory buf = new bytes(len);

        for (uint256 i = 0; i < len; ++i) {
            buf[i] = data[start + i];
        }

        return string(buf);
    }

    /// @dev Copies a stored route record into memory.
    function _copyRouteRecord(
        RouteRecord storage s
    ) private view returns (RouteRecord memory record) {
        return RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            isFrozen: s.isFrozen,
            routeLabel: s.routeLabel
        });
    }

    /// @dev Returns `arr[start:end]`, with `end` clamped to array length.
    function _sliceRouteKeys(
        bytes32[] storage arr,
        uint256 start,
        uint256 end
    ) private view returns (bytes32[] memory keys) {
        require(start <= end, "XNSRoutes: invalid route key slice");

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
    function _isValidRouteLabel(
        string memory routeLabel
    ) private pure returns (bool isValid) {
        bytes memory b = bytes(routeLabel);
        uint256 len = b.length;

        if (len == 0 || len > 32) {
            return false;
        }

        for (uint256 i = 0; i < len; ++i) {
            bytes1 c = b[i];

            bool isLowercaseLetter =
                c >= 0x61 && c <= 0x7A;

            bool isDigit =
                c >= 0x30 && c <= 0x39;

            bool isHyphen =
                c == 0x2D;

            if (
                !(
                    isLowercaseLetter ||
                    isDigit ||
                    isHyphen
                )
            ) {
                return false;
            }

            if (
                isHyphen &&
                i > 0 &&
                b[i - 1] == 0x2D
            ) {
                return false;
            }
        }

        if (
            b[0] == 0x2D ||
            b[len - 1] == 0x2D
        ) {
            return false;
        }

        return true;
    }

    /// @dev Non-empty and at most `MAX_TARGET_LENGTH` bytes. Contents are not validated.
    function _isValidTarget(
        bytes calldata target
    ) private pure returns (bool isValid) {
        uint256 len = target.length;
        return len > 0 && len <= MAX_TARGET_LENGTH;
    }
}
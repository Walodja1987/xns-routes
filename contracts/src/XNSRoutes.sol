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
/// @notice Route registry for XNS names which enables XNS name owners to map URL-style
/// identifiers to any Ethereum address. Routes may point to EOAs and smart contracts,
/// including helper/view contracts returning arbitrary data, such as Bitcoin or
/// Solana addresses, calldata, or other information.
///
/// Routes are addressed with XRL (XNS Route Link) strings. The format is:
///
/// XRL = `xnsName/[routeScope:]routeLabel[/params]`
///
/// - **xnsName** — XNS name that owns the route book (e.g. `bob.xns`).
/// - **routeScope** — optional segment before `:` (1–20 chars if present).
/// - **routeLabel** — required slug (1–32 chars).
/// - **params** — optional parameters for off-chain route parsers; not stored or validated on-chain.
/// - The segment `[routeScope:]routeLabel` is also referred to as **route**.
/// - Registry XRL = `xnsName/[routeScope:]routeLabel` (XRL without the params tail). 
//
/// Examples XRLs:
/// - `alice.og/my-sub-wallet`
/// - `contracts.aave/eth:v3-pool-contract`
/// - `bob.xns/uniswap:approve-usdt/amount=10`
///
/// `routeScope` and `routeLabel` must follow the same character and hyphenation rules as `xnsName`:
/// - Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
/// - Cannot start or end with '-'
/// - Cannot contain consecutive hyphens ('--')
///
/// Key points:
/// - Routes are owned and managed by the XNS name owner.
/// - An XNS name owner can register unlimited routes for free.
/// - A route record stores `target`, `routeType`, `isActive`, `isFrozen`, and `activeController`.
/// - Route freeze and route book freeze are irreversible.
/// - Only `activeController` may toggle `isActive` via `activateRoute` / `deactivateRoute`.
/// - `activeController` is set at `createRoute` and cannot be changed afterward.
/// - `activeController == address(0)` locks `isActive` at its create-time value forever.
/// - `activeController` may still toggle `isActive` after route or route-book freeze.
/// - `routeType` is a `uint32` tag whose meaning and interpretation are defined off-chain by route parsers.
///   For example, `routeType = 0` may suggest that the `target` is an EOA.
///   `routeType = 1` may suggest that the `target` is a smart contract.
///   `routeType = 2` may suggest that the `target` is a special contract that returns parametrized calldata.
///   `routeType = 3` may suggest that the `target` returns a Bitcoin address.
/// - Forward resolution is direct: registry XRL -> `target`. Use `resolveRouteIfActive` or
///   `resolveRouteIfActiveAndFrozen` for strict resolution; `getRouteRecord` returns raw storage.
///   Reverse lookup is not supported because many routes may point to the same `target`.
/// - Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
/// - `routeKey` is `keccak256` of canonical registry XRL (`xnsName/route`; params excluded).
/// - For one known `xnsName`, on-chain enumeration is available without an indexer via the append-only
///   route-key log (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecord`).
contract XNSRoutes {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @dev Data structure to store route metadata.
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
        address activeController;
    }

    // -------------------------------------------------------------------------
    // Storage variables
    // -------------------------------------------------------------------------

    /// @notice XNS registry this contract calls for name resolution.
    IXNSMinimal public immutable XNS;

    // keccak256(bytes(canonical xnsName)) => true if the route book for an XNS name is frozen
    mapping(bytes32 => bool) private _routeBookFrozen;

    // _routeKey(canonical xnsName, routeScope, routeLabel) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    // keccak256(bytes(canonical xnsName)) => append-only log of route keys ever created
    // under that XNS name (not shortened on delete)
    mapping(bytes32 => bytes32[]) private _routeKeysByXNSName;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted in `createRoute`.
    event RouteCreated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType,
        address activeController
    );

    /// @dev Emitted in `updateTarget` and `updateRoute` when `target` changes.
    event RouteTargetUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address previousTarget,
        address indexed newTarget
    );

    /// @dev Emitted in `updateRouteType` and `updateRoute` when `routeType` changes.
    event RouteTypeUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        uint32 previousRouteType,
        uint32 newRouteType
    );

    /// @dev Emitted in `activateRoute` and `deactivateRoute` when `isActive` changes.
    event RouteActiveStatusUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        bool isActive
    );

    /// @dev Emitted in `updateRoute` and `freezeRoute` when an existing route becomes frozen.
    /// Initial freeze-at-create is reflected only in `RouteCreated` (`isFrozen`).
    event RouteFrozen(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel
    );

    /// @dev Emitted in `freezeRouteBook` when the route book is frozen for an XNS name.
    event RouteBookFrozenForName(
        bytes32 indexed nameHash,
        string canonicalXNSName
    );

    /// @dev Emitted in `deleteRoute`.
    event RouteDeleted(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel
    );

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Sets the XNS registry and registers the name `routes.xns` for this contract.
    ///
    /// **Requirements:**
    /// - `_xns` must not be the zero address.
    /// - `msg.value` must be exactly 0.001 ETH for the registration of `routes.xns`.
    ///
    /// @param _xns XNS registry address.
    constructor(address _xns) payable {
        require(_xns != address(0), "XNSRoutes: 0x XNS address");
        XNS = IXNSMinimal(_xns);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    // -------------------------------------------------------------------------
    // State-modifying functions
    // -------------------------------------------------------------------------

    /// @notice Create a route `[xnsName]/[routeScope:][route]`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner for `xnsName`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy local character rules.
    /// - `routeLabel` must be a non-empty string.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - The route key must not already exist.
    ///
    /// On success, appends the route key to the append-only array `_routeKeysByXNSName` associated
    /// with `xnsName`, querieable via `getRouteKeys`.
    /// Note: Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action".
    /// @param routeScope Optional path segment before `:`; non-empty must pass local route scope
    /// rules ([a-z0-9-], max length 20); empty means `xnsName/routeLabel` only (no `:` in the route).
    /// @param routeLabel Required route label ([a-z0-9-], max length 32).
    /// @param target Target address for `routeType`; must be non-zero (`address(0)` is reserved
    /// for non-existent route).
    /// @param routeType Parser hint for how to interpret `target` (off-chain semantics),
    /// e.g. 0 = plain address, 2 = Bitcoin address, 3 = address exposing a html, etc.
    /// @param activate Initial value for stored `isActive`.
    /// @param freeze If true, renders the route immutable.
    /// @param activeController Account that may toggle `isActive`; `address(0)` locks active status
    /// at `activate` forever (requires `activate == true`).
    function createRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze,
        address activeController
    ) external {
        // Confirm that the XNS name is owned by the caller
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        // Derive the name key (`keccak256(bytes(canonical xnsName))`) for the XNS name
        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Validate that the target is not the zero address
        require(target != address(0), "XNSRoutes: invalid target");

        // Locked active status requires an initially active route
        require(
            activeController != address(0) || activate,
            "XNSRoutes: locked route must be active"
        );

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Derive the route key and check if the route already exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        require(_routes[routeKey].target == address(0), "XNSRoutes: route already exists");

        // Create the route record
        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: activate,
            isFrozen: freeze,
            activeController: activeController
        });

        _routeKeysByXNSName[nameKey].push(routeKey);

        // Emit the `RouteCreated` event
        emit RouteCreated(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            target,
            activate,
            freeze,
            routeType,
            activeController
        );
    }

    /// @notice Update an existing route (target, routeType, freeze in one tx).
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action".
    /// @param routeScope Route scope of the route path to be updated (may be empty).
    /// @param routeLabel Route label of the route path to be updated.
    /// @param target New target address. Must be non-zero.
    /// @param routeType New route type integer.
    /// @param freeze If true, renders the route immutable.
    ///
    /// Does not change `isActive`; use `activateRoute` / `deactivateRoute` as `activeController`.
    ///
    /// Emits `RouteTargetUpdated` and/or `RouteTypeUpdated` only when the corresponding stored
    /// field changes; emits `RouteFrozen` when `freeze` is true.
    function updateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool freeze
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        require(target != address(0), "XNSRoutes: invalid target");

        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot update frozen route");

        address oldTarget = record.target;
        uint32 oldRouteType = record.routeType;

        record.target = target;
        record.routeType = routeType;

        if (target != oldTarget) {
            emit RouteTargetUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                oldTarget,
                target
            );
        }
        if (routeType != oldRouteType) {
            emit RouteTypeUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                oldRouteType,
                routeType
            );
        }
        if (freeze) {
            record.isFrozen = true;
            emit RouteFrozen(nameKey, routeKey, canonicalXNSName, routeScope, routeLabel);
        }
    }

    /// @notice Mark an existing route as active.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be `record.activeController`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be activated (may be empty).
    /// @param routeLabel Route label of the route path to be activated.
    function activateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        _updateRouteActiveStatus(xnsName, routeScope, routeLabel, true);
    }

    /// @notice Mark an existing route as inactive.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be `record.activeController`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be deactivated (may be empty).
    /// @param routeLabel Route label of the route path to be deactivated.
    function deactivateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        _updateRouteActiveStatus(xnsName, routeScope, routeLabel, false);
    }

    /// @dev Implementation for `activateRoute` / `deactivateRoute`.
    /// Requirements, validation, reverts, and events match the documentation on `activateRoute`
    /// and `deactivateRoute`.
    function _updateRouteActiveStatus(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        bool active
    ) private {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        // Update the routeLabel active status and emit the `RouteActiveStatusUpdated` event,
        // if the active status changes
        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(
                _xnsNameKey(canonicalXNSName),
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                active
            );
        }
    }

    /// @notice Remove a routeLabel so `createRoute` may register the same key again.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.
    /// 
    /// Emits `RouteDeleted` only when the route is deleted.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be deleted (may be empty).
    /// @param routeLabel Route label of the route path to be deleted.
    function deleteRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot delete frozen route");

        // Delete the route record
        delete _routes[routeKey];

        // Emit the `RouteDeleted` event
        emit RouteDeleted(nameKey, routeKey, canonicalXNSName, routeScope, routeLabel);
    }

    /// @notice Update the `target` address for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    /// - `newTarget` must not be the zero address.
    ///
    /// Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be updated (may be empty).
    /// @param routeLabel Route label of the route path to be updated.
    /// @param newTarget New target address; must be non-zero.
    function updateTarget(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address newTarget
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot update frozen route");

        // Confirm that the new target is not the zero address
        require(newTarget != address(0), "XNSRoutes: invalid target");

        // Update the target and emit the `RouteTargetUpdated` event, if the target changes
        if (record.target != newTarget) {
            address previousTarget = record.target;
            record.target = newTarget;
            emit RouteTargetUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                previousTarget,
                newTarget
            );
        }
    }

    /// @notice Update `routeType` for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be updated (may be empty).
    /// @param routeLabel Route label of the route path to be updated.
    /// @param newRouteType New route type integer.
    function updateRouteType(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        uint32 newRouteType
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot update frozen route");

        // Update the route type and emit the `RouteTypeUpdated` event, if the route type changes
        if (record.routeType != newRouteType) {
            uint32 previousRouteType = record.routeType;
            record.routeType = newRouteType;
            emit RouteTypeUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                previousRouteType,
                newRouteType
            );
        }
    }

    /// @notice Freeze a single routeLabel forever.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist.
    ///
    /// After freezing, `target` and `routeType` can never be changed again; `activeController`
    /// can still toggle `isActive`.
    ///
    /// Emits `RouteFrozen` only if the route was not already frozen.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope of the route path to be frozen (may be empty).
    /// @param routeLabel Route label of the route path to be frozen.
    function freezeRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate route scope and route label
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        // Derive the route key and check if the routeLabel exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");

        // Update the routeLabel freeze status and emit the `RouteFrozen` event, if the
        // route is not frozen
        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(nameKey, routeKey, canonicalXNSName, routeScope, routeLabel);
        }
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    ///
    /// **Effects (irreversible):**
    /// - No new routes may be added under `xnsName`.
    /// - No existing route targets may be changed under `xnsName`.
    /// - Routes may not be deleted under `xnsName`.
    /// - `freezeRoute` may not be called for routes under `xnsName`.
    /// - `activeController` can still toggle `isActive` for existing routes.
    ///
    /// Requires `msg.sender` to be the XNS name owner of `xnsName`.
    ///
    /// Emits `RouteBookFrozenForName` only if the route book was not already frozen.
    ///
    /// @param xnsName The XNS name whose route book to freeze.
    function freezeRouteBook(string calldata xnsName) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        // Check if the route book is not already frozen
        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        if (!_routeBookFrozen[nameKey]) {
            _routeBookFrozen[nameKey] = true;
            emit RouteBookFrozenForName(nameKey, canonicalXNSName);
        }
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Reads stored route record data by `routeKey`.
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param routeKey Canonical route storage key.
    /// @return record The route record (target, routeType, isActive, isFrozen, activeController).
    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record) {
        RouteRecord storage s = _routes[routeKey];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            isFrozen: s.isFrozen,
            activeController: s.activeController
        });
    }

    /// @notice Reads stored route record data by `(xnsName, routeScope, routeLabel)`.
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// Requires that `routeScope` and `routeLabel` are valid strings.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope (may be empty).
    /// @param routeLabel Route label.
    /// @return record The route record (target, routeType, isActive, isFrozen, activeController).
    function getRouteRecord(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record) {
        return _getRouteRecord(xnsName, routeScope, routeLabel);
    }

    /// @notice Reads stored route record data by registry XRL (`splitRegistryXRL`).
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param registryXRL Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any).
    /// @return record The route record (target, routeType, isActive, isFrozen, activeController).
    function getRouteRecord(string calldata registryXRL) external view returns (RouteRecord memory record) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRegistryXRL(registryXRL);
        return _getRouteRecord(xnsName, routeScope, routeLabel);
    }

    /// @dev Validates scope/label, derives key and returns the route record.
    function _getRouteRecord(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel
    ) private view returns (RouteRecord memory record) {
        _validateRouteScopeAndLabel(routeScope, routeLabel);
        RouteRecord storage s = _routes[_routeKey(xnsName, routeScope, routeLabel)];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            isFrozen: s.isFrozen,
            activeController: s.activeController
        });
    }

    /// @notice Resolves an active route to `(target, routeType)`.
    ///
    /// **Requirements:**
    /// - The route must exist (`target != address(0)`).
    /// - `isActive` must be true.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope (may be empty).
    /// @param routeLabel Route label.
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRouteIfActive(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType) {
        return _resolveRoute(xnsName, routeScope, routeLabel, false);
    }

    /// @notice Resolves an active route to `(target, routeType)` by registry XRL (`splitRegistryXRL`).
    ///
    /// **Requirements:** same as `resolveRouteIfActive(xnsName, routeScope, routeLabel)`.
    ///
    /// @param registryXRL Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any).
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRouteIfActive(
        string calldata registryXRL
    ) external view returns (address target, uint32 routeType) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRegistryXRL(registryXRL);
        return _resolveRoute(xnsName, routeScope, routeLabel, false);
    }

    /// @notice Resolves an active and frozen route to `(target, routeType)`.
    ///
    /// **Requirements:**
    /// - The route must exist (`target != address(0)`).
    /// - `isActive` must be true.
    /// - `record.isFrozen` must be true or the route book for `xnsName` must be frozen.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope (may be empty).
    /// @param routeLabel Route label.
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRouteIfActiveAndFrozen(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType) {
        return _resolveRoute(xnsName, routeScope, routeLabel, true);
    }

    /// @notice Resolves an active and frozen route to `(target, routeType)` by registry XRL
    /// (`splitRegistryXRL`).
    ///
    /// **Requirements:** same as `resolveRouteIfActiveAndFrozen(xnsName, routeScope, routeLabel)`.
    ///
    /// @param registryXRL Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any).
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRouteIfActiveAndFrozen(
        string calldata registryXRL
    ) external view returns (address target, uint32 routeType) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRegistryXRL(registryXRL);
        return _resolveRoute(xnsName, routeScope, routeLabel, true);
    }

    /// @dev Shared resolver for `resolveRouteIfActive` and `resolveRouteIfActiveAndFrozen`.
    function _resolveRoute(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel,
        bool requireFrozen
    ) private view returns (address target, uint32 routeType) {
        RouteRecord memory record = _getRouteRecord(xnsName, routeScope, routeLabel);
        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.isActive, "XNSRoutes: route inactive");
        if (requireFrozen) {
            string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
            require(
                record.isFrozen || _routeBookFrozen[_xnsNameKey(canonicalXNSName)],
                "XNSRoutes: route not frozen"
            );
        }
        return (record.target, record.routeType);
    }

    /// @notice Returns whether the entire route book under `xnsName` is frozen.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @return frozen True if the route book is frozen.
    function isRouteBookFrozen(string calldata xnsName) external view returns (bool frozen) {
        return _routeBookFrozen[_xnsNameKey(xnsName)];
    }

    /// @notice Number of entries in the append-only routeLabel-key log for `xnsName`
    /// (not the count of live routes; deletes do not shrink this).
    ///
    /// @param xnsName The XNS name to get the route key count for.
    /// @return count The number of route keys.
    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count) {
        return _routeKeysByXNSName[_xnsNameKey(xnsName)].length;
    }

    /// @notice Returns `keys[start:end]` from the route keys array associated with
    /// `xnsName` (`end` is exclusive). If `end` is greater than the array length, behaves
    /// like `end == length` (caller may pass any large upper bound to fetch "the rest"
    /// without needing to know the exact array length). If `start` lies past the end of
    /// the array, returns an empty array.
    ///
    /// Requires `start <= end`.
    ///
    /// @param xnsName The XNS name to get the route keys for.
    /// @param start The start index (inclusive).
    /// @param end The end index (exclusive); may exceed array length.
    /// @return keys The route keys.
    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys) {
        bytes32[] storage arr = _routeKeysByXNSName[_xnsNameKey(xnsName)];
        uint256 len = arr.length;
        require(start <= end, "XNSRoutes: invalid route key slice");
        uint256 adjustedEnd = end > len ? len : end;
        if (start > adjustedEnd) {
            return new bytes32[](0);
        }
        uint256 n = adjustedEnd - start;
        keys = new bytes32[](n);
        for (uint256 i = 0; i < n; ++i) {
            keys[i] = arr[start + i];
        }
    }

    /// @notice Parses a registry XRL into `(xnsName, routeScope, routeLabel)`.
    /// Example: `bro.xns/eth:my-wallet` -> `(bro.xns, eth, my-wallet)`.
    /// Useful when calling tuple-based mutating functions (`updateRoute`, `createRoute`, etc.).
    ///
    /// A registry XRL is `xnsName "/" route` — the on-chain subset of a full XRL (no `/params…` tail).
    /// Does not validate segments; malformed input may still parse but fail downstream.
    ///
    /// Requires `registryXRL` to contain at least one `/`.
    ///
    /// @param registryXRL Registry XRL (not a full XRL with params), e.g. `bob.xns/eth:transfer-usdt`.
    /// @return xnsName Segment before the first `/`.
    /// @return routeScope Segment before the first `:` in `route`, or empty if there is no `:`.
    /// @return routeLabel Segment after `:` if `routeScope` is present, else the whole `route` after `/`.
    function splitRegistryXRL(
        string calldata registryXRL
    )
        external
        pure
        returns (string memory xnsName, string memory routeScope, string memory routeLabel)
    {
        return _splitRegistryXRL(registryXRL);
    }

    /// @notice Returns whether `routeScope` satisfies local scope rules. Empty string is valid;
    /// non-empty must be 1–20 chars and match the slug charset/hyphen rules.
    ///
    /// @param routeScope Candidate route scope (may be empty).
    /// @return valid True if empty or a valid slug (1–20 chars).
    function isValidRouteScope(string calldata routeScope) external pure returns (bool valid) {
        return bytes(routeScope).length == 0 || _isValidRouteScope(routeScope);
    }

    /// @notice Returns whether `routeLabel` satisfies local label rules (1–32 chars, slug rules).
    ///
    /// @param routeLabel Candidate route label.
    /// @return valid True if a valid slug (1–32 chars).
    function isValidRouteLabel(string calldata routeLabel) external pure returns (bool valid) {
        return _isValidRouteLabel(routeLabel);
    }

    /// @notice Returns whether `routeScope` and `routeLabel` pass validation rules.
    ///
    /// @param routeScope Candidate route scope (may be empty).
    /// @param routeLabel Candidate route label.
    /// @return valid True if both inputs are valid slugs.
    function isValidRouteScopeAndLabel(
        string calldata routeScope,
        string calldata routeLabel
    ) external pure returns (bool valid) {
        if (bytes(routeScope).length != 0 && !_isValidRouteScope(routeScope)) return false;
        return _isValidRouteLabel(routeLabel);
    }

    /// @dev Splits `registryXRL` at the first `/`, then at the first `:` in the remainder.
    /// Does not validate XNS labels or slug rules on segments. Parsing rules and revert behavior
    /// match `splitRegistryXRL`.
    function _splitRegistryXRL(
        string calldata registryXRL
    ) private pure returns (string memory xnsName, string memory routeScope, string memory routeLabel) {
        bytes calldata b = bytes(registryXRL);
        uint256 n = b.length;
        uint256 slash;
        bool foundSlash;
        for (uint256 i = 0; i < n; ++i) {
            if (b[i] == 0x2f) {
                slash = i;
                foundSlash = true;
                break;
            }
        }
        require(foundSlash, "XNSRoutes: invalid XRL");

        xnsName = _calldataSubstringToString(b, 0, slash);

        uint256 routePathStart = slash + 1;
        if (routePathStart >= n) {
            return (xnsName, "", "");
        }

        bytes calldata routePath = b[routePathStart:n];

        uint256 colon;
        bool foundColon;
        for (uint256 j = 0; j < routePath.length; ++j) {
            if (routePath[j] == 0x3a) {
                colon = j;
                foundColon = true;
                break;
            }
        }
        if (!foundColon) {
            return (xnsName, "", _calldataSubstringToString(routePath, 0, routePath.length));
        }

        routeScope = _calldataSubstringToString(routePath, 0, colon);
        uint256 routeStart = colon + 1;
        if (routeStart >= routePath.length) {
            routeLabel = "";
        } else {
            routeLabel = _calldataSubstringToString(routePath, routeStart, routePath.length);
        }
    }

    /// @dev Copies `data[start:end]` (end exclusive) into memory as a string; requires `end >= start`.
    function _calldataSubstringToString(
        bytes calldata data,
        uint256 start,
        uint256 end
    ) private pure returns (string memory out) {
        require(end >= start, "XNSRoutes: invalid XRL");
        uint256 len = end - start;
        bytes memory buf = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            buf[i] = data[start + i];
        }
        out = string(buf);
    }

    /// @dev Bare names like `bob` become `bob.x`; otherwise returns `xnsName` unchanged.
    /// Requires non-empty `xnsName`.
    function _canonicalizeXNSName(
        string memory xnsName
    ) private pure returns (string memory canonicalXNSName) {
        bytes memory b = bytes(xnsName);
        require(b.length > 0, "XNSRoutes: invalid XNS name");

        bool hasDot;
        for (uint256 i = 0; i < b.length; ++i) {
            if (b[i] == 0x2E) {
                hasDot = true;
                break;
            }
        }

        if (!hasDot) {
            return string.concat(xnsName, ".x");
        }

        return xnsName;
    }

    /// @dev Canonicalizes `xnsName` and requires `msg.sender` == `XNS.getAddress(canonicalXNSName)`.
    /// In particular, reverts when the name is not registered on XNS (`getAddress` returns `address(0)`).
    function _requireXNSNameOwner(
        string calldata xnsName
    ) private view returns (string memory canonicalXNSName) {
        canonicalXNSName = _canonicalizeXNSName(xnsName);
        require(msg.sender == XNS.getAddress(canonicalXNSName), "XNSRoutes: not XNS name owner");
    }

    /// @dev Route-book scope key: `keccak256(bytes(_canonicalizeXNSName(xnsName)))`.
    function _xnsNameKey(string memory xnsName) private pure returns (bytes32) {
        return keccak256(bytes(_canonicalizeXNSName(xnsName)));
    }

    /// @dev Returns keccak256 of canonical registry routeLabel: `{canonicalXNSName}/{routeLabel}` when
    /// `routeScope` is empty, else `{canonicalXNSName}/{routeScope}:{routeLabel}`.
    /// Canonicalizes `xnsName` (e.g. `bob` -> `bob.x`) before hashing.
    function _routeKey(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel
    ) private pure returns (bytes32 key) {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        if (bytes(routeScope).length == 0) {
            return keccak256(abi.encodePacked(canonicalXNSName, "/", routeLabel));
        }
        return keccak256(abi.encodePacked(canonicalXNSName, "/", routeScope, ":", routeLabel));
    }

    /// @dev Enforces slug rules on `routeScope` and `routeLabel` (`routeScope` max 20 chars;
    /// `routeLabel` max 32 chars). Empty `routeScope` is allowed.
    function _validateRouteScopeAndLabel(
        string memory routeScope,
        string memory routeLabel
    ) private pure {
        require(
            bytes(routeScope).length == 0 || _isValidRouteScope(routeScope),
            "XNSRoutes: invalid route scope"
        );
        require(_isValidRouteLabel(routeLabel), "XNSRoutes: invalid route label");
    }

    /// @dev Validates `routeScope` against the slug rules, max length 20.
    function _isValidRouteScope(string memory routeScope) private pure returns (bool isValid) {
        return _isValidSlug(routeScope, 20);
    }

    /// @dev Validates `routeLabel` against the slug rules, max length 32.
    function _isValidRouteLabel(string memory routeLabel) private pure returns (bool isValid) {
        return _isValidSlug(routeLabel, 32);
    }

    /// @dev Validates that slug `s` is non-empty, up to `maxLen` characters long, only lowercase letters,
    /// digits, and hyphens, cannot start or end with '-', cannot contain consecutive hyphens ('--').
    function _isValidSlug(string memory s, uint256 maxLen) private pure returns (bool isValid) {
        bytes memory b = bytes(s);
        uint256 len = b.length;
        if (len == 0 || len > maxLen) return false;

        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            bool isLowercaseLetter = (c >= 0x61 && c <= 0x7A);
            bool isDigit = (c >= 0x30 && c <= 0x39);
            bool isHyphen = (c == 0x2D);
            if (!(isLowercaseLetter || isDigit || isHyphen)) return false;

            if (isHyphen && i > 0 && b[i - 1] == 0x2D) return false;
        }

        if (b[0] == 0x2D || b[len - 1] == 0x2D) return false;
        return true;
    }
}

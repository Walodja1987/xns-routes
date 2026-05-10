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
/// identifiers to any Ethereum address. Mappings are free and may point to EOAs and smart
/// contracts including helper/view contracts returning arbitrary data, such as Bitcoin or Solana
/// addresses, calldata, or other information.
///
/// Route format: `[xnsName]/[routePrefix:][route]` with `routePrefix` being optional.
///
/// Examples:
/// - `alice.og/my-sub-wallet`
/// - `contracts.aave/eth:v3-pool-contract`
/// - `bob.xns/eth:approve-usdt`
///
/// `routePrefix` and `route` must follow the same character and hyphenation rules as `xnsName`:
/// - Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
/// - Cannot start or end with '-'
/// - Cannot contain consecutive hyphens ('--')
///
/// `routePrefix` is optional; if provided, it must be 1-20 characters long.
/// `route` is required and must be 1-32 characters long.
///
/// Key points:
/// - Routes are owned and managed by the XNS name owner.
/// - An XNS name owner can register unlimited routes for free.
/// - A route stores `target`, `routeType`, `isActive`, and `isFrozen`.
/// - Route freeze and route book freeze are irreversible.
/// - Active status can still be toggled after freeze.
/// - `routeType` is a `uint32` tag whose meaning and interpretation are defined off-chain by route parsers.
///   For example, `routeType = 0` may suggest that the `target` is an EOA.
///   `routeType = 1` may suggest that the `target` is a smart contract.
///   `routeType = 2` may suggest that the `target` is a special contract that returns parametrized calldata.
///   `routeType = 3` may suggest that the `target` returns a Bitcoin address.
/// - Forward resolution is direct: `[xnsName]/[routePrefix:][route]` → `target`. Reverse lookup is not
///   supported because many routes may point to the same `target`.
/// - For one known `xnsName`, on-chain enumeration is available without an indexer via the append-only
///   route-key log (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecordByRouteKey` / batch overload).
/// - Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
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
    }

    // -------------------------------------------------------------------------
    // Storage variables
    // -------------------------------------------------------------------------

    /// @notice XNS registry this contract calls for name resolution.
    IXNSMinimal public immutable XNS;

    // keccak256(bytes(canonical xnsName)) => true if the route book for an XNS name is frozen
    mapping(bytes32 => bool) private _routeBookFrozen;

    // _routeKey(canonical xnsName, routePrefix, route) => route record
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
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    /// @dev Emitted in `updateTarget` when target changes, and in `updateRoute` when `target` changes.
    event RouteTargetUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        address previousTarget,
        address indexed newTarget
    );

    /// @dev Emitted in `updateRouteType` when route type changes, and in `updateRoute` when `routeType` changes.
    event RouteTypeUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        uint32 previousRouteType,
        uint32 newRouteType
    );

    /// @dev Emitted in `activateRoute`, `deactivateRoute`, and `updateRoute` when `isActive` changes.
    event RouteActiveStatusUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        bool isActive
    );

    /// @dev Emitted in `updateRoute` and `freezeRoute` when an existing route becomes frozen.
    /// Initial freeze-at-create is reflected only in `RouteCreated` (`isFrozen`).
    event RouteFrozen(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route
    );

    /// @dev Emitted in `freezeRouteBook` when the route book is frozen for an XNS name.
    event RouteBookFrozenForName(
        bytes32 indexed nameHash,
        string xnsName
    );

    /// @dev Emitted in `deleteRoute`.
    event RouteDeleted(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route
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
    /// @notice Create a route `[xnsName]/[routePrefix:][route]`. Reverts if the route already exists.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner for `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy local character set, hyphenation, and length rules.
    /// - `route` must be a non-empty string.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - The route key must not already exist.
    ///
    /// On success, appends the route key to the append-only array `_routeKeysByXNSName` associated with `xnsName`.
    ///
    /// Note: Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action".
    /// @param routePrefix Optional path segment before `:`; non-empty must pass local route-prefix
    /// rules ([a-z0-9-], max length 20).
    /// empty means `xnsName/route` only (no `:` in the routePath).
    /// @param route Required route label ([a-z0-9-], max length 32).
    /// @param target Target address for `routeType`; must be non-zero (`address(0)` is reserved
    /// for non-existent route).
    /// @param routeType Route type integer for how to interpret the `target` output
    /// (off-chain semantics), e.g. 0 = plain address, 2 = Bitcoin address, 3 = html, etc.
    /// @param activate Initial value for stored `isActive`.
    /// @param freeze If true, renders the route immutable.
    function createRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external {
        // Confirm that the XNS name is owned by the caller
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        // Derive the name key (`keccak256(bytes(canonical xnsName))`) for the XNS name
        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Validate that the target is not the zero address
        require(target != address(0), "XNSRoutes: invalid target");

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Derive the route key and check if the route already exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
        require(_routes[routeKey].target == address(0), "XNSRoutes: route already exists");

        // Create the route record
        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: activate,
            isFrozen: freeze
        });

        _routeKeysByXNSName[nameKey].push(routeKey);

        // Emit the `RouteCreated` event
        emit RouteCreated(
            nameKey,
            routeKey,
            canonicalXNSName,
            routePrefix,
            route,
            target,
            activate,
            freeze,
            routeType
        );
    }

    /// @notice Update an existing route (target, routeType, activate, freeze in one tx).
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action".
    /// @param routePrefix Route prefix of the route path to be updated (may be empty).
    /// @param route Route label of the route path to be updated.
    /// @param target New target address. Must be non-zero.
    /// @param routeType New route type integer.
    /// @param activate New value for stored `isActive`.
    /// @param freeze If true, renders the route immutable.
    ///
    /// Emits `RouteTargetUpdated`, `RouteTypeUpdated`, and/or `RouteActiveStatusUpdated` only when the
    /// corresponding stored field changes; emits `RouteFrozen` when `freeze` is true.
    function updateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        require(target != address(0), "XNSRoutes: invalid target");

        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot update frozen route");

        address oldTarget = record.target;
        uint32 oldRouteType = record.routeType;
        bool oldActive = record.isActive;

        record.target = target;
        record.routeType = routeType;
        record.isActive = activate;

        if (target != oldTarget) {
            emit RouteTargetUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routePrefix,
                route,
                oldTarget,
                target
            );
        }
        if (routeType != oldRouteType) {
            emit RouteTypeUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routePrefix,
                route,
                oldRouteType,
                routeType
            );
        }
        if (activate != oldActive) {
            emit RouteActiveStatusUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routePrefix,
                route,
                activate
            );
        }
        if (freeze) {
            record.isFrozen = true;
            emit RouteFrozen(nameKey, routeKey, canonicalXNSName, routePrefix, route);
        }
    }

    /// @notice Mark an existing route as active.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be activated (may be empty).
    /// @param route Route label of the route path to be activated.
    function activateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, true);
    }

    /// @notice Mark an existing route as inactive.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be deactivated (may be empty).
    /// @param route Route label of the route path to be deactivated.
    function deactivateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, false);
    }

    /// @dev Used by `activateRoute` and `deactivateRoute`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route
    /// or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be updated (may be empty).
    /// @param route Route label of the route path to be updated.
    /// @param active New active status to set.
    function _updateRouteActiveStatus(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        bool active
    ) private {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");

        // Update the route active status and emit the `RouteActiveStatusUpdated` event,
        // if the active status changes
        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(
                _xnsNameKey(canonicalXNSName),
                routeKey,
                canonicalXNSName,
                routePrefix,
                route,
                active
            );
        }
    }

    /// @notice Remove a route so `createRoute` may register the same key again.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be deleted (may be empty).
    /// @param route Route label of the route path to be deleted.
    function deleteRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(!record.isFrozen, "XNSRoutes: cannot delete frozen route");

        // Delete the route record
        delete _routes[routeKey];

        // Emit the `RouteDeleted` event
        emit RouteDeleted(nameKey, routeKey, canonicalXNSName, routePrefix, route);
    }

    /// @notice Update the `target` address for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    /// - `newTarget` must not be the zero address.
    ///
    /// Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be updated (may be empty).
    /// @param route Route label of the route path to be updated.
    /// @param newTarget New target address; must be non-zero.
    function updateTarget(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address newTarget
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
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
                routePrefix,
                route,
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
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist and must not already be frozen.
    ///
    /// Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be updated (may be empty).
    /// @param route Route label of the route path to be updated.
    /// @param newRouteType New route type integer.
    function updateRouteType(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        uint32 newRouteType
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);

        // Check if the route book is frozen
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
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
                routePrefix,
                route,
                previousRouteType,
                newRouteType
            );
        }
    }

    /// @notice Freeze a single route forever.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
    /// - The route book for `xnsName` must not be frozen.
    /// - Non-empty `routePrefix` and `route` must satisfy character rules.
    /// - The route must exist.
    ///
    /// After freezing, `target` and `routeType` can never be changed again; active/inactive can
    /// still be toggled.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be frozen (may be empty).
    /// @param route Route label of the route path to be frozen.
    function freezeRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        bytes32 routeKey = _routeKey(canonicalXNSName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");

        // Update the route freeze status and emit the `RouteFrozen` event, if the route is not frozen
        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(nameKey, routeKey, canonicalXNSName, routePrefix, route);
        }
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    ///
    /// **Effects (irreversible):**
    /// - No new routes may be added under `xnsName`.
    /// - No existing route targets may be changed under `xnsName`.
    /// - Routes may not be deleted under `xnsName`.
    /// - `freezeRoute` may not be called for routes under `xnsName`.
    /// - Route activation can still be toggled.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the XNS name owner of `xnsName`.
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

    /// @notice Return full route metadata. Applies the same `routePrefix`/`route` validation as
    /// mutating functions, then reads storage. Reverts when no route exists for the key.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be queried (may be empty).
    /// @param route Route label of the route path to be queried.
    /// @return target Stored target address for the route.
    /// @return isActive Whether the route is active.
    /// @return isFrozen Whether the route is frozen.
    /// @return routeType Route type integer.
    function getRouteInfo(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType) {
        return _getRouteInfo(xnsName, routePrefix, route);
    }

    /// @notice Same as `getRouteInfo` with `fullRoutePath` parsed by `splitFullPath`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/`.
    /// - Further requirements match `getRouteInfo` for the parsed components.
    function getRouteInfoFromPath(
        string calldata fullRoutePath
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType) {
        (string memory xnsName, string memory routePrefix, string memory route) = _splitFullPath(
            fullRoutePath
        );
        return _getRouteInfo(xnsName, routePrefix, route);
    }

    /// @dev Shared by `getRouteInfo` and `getRouteInfoFromPath`.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be queried (may be empty).
    /// @param route Route label of the route path to be queried.
    /// @return target Stored target address for the route.
    /// @return isActive Whether the route is active.
    /// @return isFrozen Whether the route is frozen.
    /// @return routeType Route type integer.
    function _getRouteInfo(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private view returns (address target, bool isActive, bool isFrozen, uint32 routeType) {
        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        require(record.target != address(0), "XNSRoutes: route not found");

        return (record.target, record.isActive, record.isFrozen, record.routeType);
    }

    /// @notice Returns whether a route exists (`target` was ever set via `createRoute`; zero
    /// `target` is never stored). Applies the same `routePrefix`/`route` validation as mutating
    /// functions before reading storage.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be queried (may be empty).
    /// @param route Route label of the route path to be queried.
    /// @return exists True if a route record exists for the key.
    function routeExists(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external view returns (bool exists) {
        return _routeExists(xnsName, routePrefix, route);
    }

    /// @notice Same as `routeExists` with `fullRoutePath` parsed by `splitFullPath`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/`.
    /// - Further requirements match `routeExists` for the parsed components.
    function routeExistsFromPath(
        string calldata fullRoutePath
    ) external view returns (bool exists) {
        (string memory xnsName, string memory routePrefix, string memory route) = _splitFullPath(
            fullRoutePath
        );
        return _routeExists(xnsName, routePrefix, route);
    }

    /// @dev Shared by `routeExists` and `routeExistsFromPath`.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Route prefix of the route path to be queried (may be empty).
    /// @param route Route label of the route path to be queried.
    /// @return exists True if a route record exists for the key.
    function _routeExists(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private view returns (bool exists) {
        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);
        return _routes[_routeKey(xnsName, routePrefix, route)].target != address(0);
    }

    /// @notice Returns whether the entire route book under `xnsName` is frozen.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @return frozen True if the route book is frozen.
    function isRouteBookFrozen(string calldata xnsName) external view returns (bool frozen) {
        return _routeBookFrozen[_xnsNameKey(xnsName)];
    }

    /// @notice Number of entries in the append-only route-key log for `xnsName`
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
    /// the array, returns an empty array. Reverts only when `start > end`.
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

    /// @notice Read stored metadata by canonical route storage key. Does not validate strings;
    /// `record.target == address(0)` means no record (never created or deleted).
    ///
    /// @param routeKey The route key to read.
    /// @return record The route record (same shape as each element of the batch overload).
    function getRouteRecordByRouteKey(
        bytes32 routeKey
    ) external view returns (RouteRecord memory record) {
        RouteRecord storage s = _routes[routeKey];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            isFrozen: s.isFrozen
        });
    }

    /// @notice Batch read of `RouteRecord` for each `routeKey`. Same semantics as
    /// `getRouteRecordByRouteKey(bytes32)` per element.
    ///
    /// @param routeKeys The route keys to read.
    /// @return records The route records.
    function getRouteRecordByRouteKey(
        bytes32[] calldata routeKeys
    ) external view returns (RouteRecord[] memory records) {
        uint256 n = routeKeys.length;
        records = new RouteRecord[](n);
        for (uint256 i = 0; i < n; ++i) {
            RouteRecord storage r = _routes[routeKeys[i]];
            records[i] = RouteRecord({
                target: r.target,
                routeType: r.routeType,
                isActive: r.isActive,
                isFrozen: r.isFrozen
            });
        }
    }

    /// @notice Utility function to parse `fullRoutePath` into `(xnsName, routePrefix, route)`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/`.
    ///
    /// Does not apply XNS label validation; pass the returned tuple into tuple-based functions,
    /// which validate `routePrefix` and `route`.
    ///
    /// @param fullRoutePath Full path, e.g. `bob.xns/eth:transfer-usdt` or `bob.xns/my-wallet`.
    /// @return xnsName Segment before the first `/`.
    /// @return routePrefix Segment before the first `:` in the routePath, or empty if there is no `:`.
    /// @return route Remainder of the routePath after `routePrefix` and `:`, or the whole
    /// routePath if there is no `:`.
    function splitFullPath(
        string calldata fullRoutePath
    )
        external
        pure
        returns (string memory xnsName, string memory routePrefix, string memory route)
    {
        return _splitFullPath(fullRoutePath);
    }

    /// @notice Returns whether `routePrefix` satisfies local prefix rules. Empty string is valid
    /// (no prefix); non-empty must be 1–20 chars and match the slug charset/hyphen rules.
    ///
    /// @param routePrefix Candidate route-prefix segment (may be empty).
    /// @return valid True when `routePrefix` is empty or passes `_isValidRoutePrefix`.
    function isValidRoutePrefix(string calldata routePrefix) external pure returns (bool valid) {
        return bytes(routePrefix).length == 0 || _isValidRoutePrefix(routePrefix);
    }

    /// @notice Returns whether `route` satisfies local route rules (1–32 chars, slug charset/hyphen rules).
    ///
    /// @param route Candidate route label.
    /// @return valid True when `route` passes `_isValidRoute`.
    function isValidRoute(string calldata route) external pure returns (bool valid) {
        return _isValidRoute(route);
    }

    /// @notice Returns whether `(routePrefix, route)` would pass validation used by mutating and tuple-based view functions.
    ///
    /// @param routePrefix Candidate route-prefix segment (may be empty).
    /// @param route Candidate route label.
    /// @return valid True when the tuple passes `_validateRoutePrefixAndRoute` rules.
    function isValidRoutePrefixAndRoute(
        string calldata routePrefix,
        string calldata route
    ) external pure returns (bool valid) {
        if (bytes(routePrefix).length != 0 && !_isValidRoutePrefix(routePrefix)) return false;
        return _isValidRoute(route);
    }

    /// @dev Splits `fullRoutePath` at the first `/` into `xnsName` and `routePath`. Within `routePath`,
    /// splits at the first `:` if any. Reverts with `"XNSRoutes: invalid route path"` only when no
    /// `/` is found. Does not validate XNS labels or reject extra `/` in `routePath`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/`.
    ///
    /// @param fullRoutePath The full route path to split.
    /// @return xnsName The XNS name.
    /// @return routePrefix The route prefix.
    /// @return route The route.
    function _splitFullPath(
        string calldata fullRoutePath
    ) private pure returns (string memory xnsName, string memory routePrefix, string memory route) {
        bytes calldata b = bytes(fullRoutePath);
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
        require(foundSlash, "XNSRoutes: invalid route path");

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

        routePrefix = _calldataSubstringToString(routePath, 0, colon);
        uint256 routeStart = colon + 1;
        if (routeStart >= routePath.length) {
            route = "";
        } else {
            route = _calldataSubstringToString(routePath, routeStart, routePath.length);
        }
    }

    /// @dev Copies `data[start:end]` (end exclusive) into a UTF-8 string in memory.
    ///
    /// **Requirements:**
    /// - `end` must be greater than or equal to `start`.
    ///
    /// @param data The bytes to copy.
    /// @param start The start index (inclusive).
    /// @param end The end index (exclusive).
    /// @return out The resulting string.
    function _calldataSubstringToString(
        bytes calldata data,
        uint256 start,
        uint256 end
    ) private pure returns (string memory out) {
        require(end >= start, "XNSRoutes: invalid route path");
        uint256 len = end - start;
        bytes memory buf = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            buf[i] = data[start + i];
        }
        out = string(buf);
    }

    /// @dev Bare names like `bob` become `bob.x`; otherwise returns `xnsName` unchanged.
    ///
    /// @param xnsName User-supplied XNS name.
    /// @return canonicalXNSName Canonical form of the XNS name.
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

    /// @dev Resolves ownership against the canonical name. XNS `getAddress` returns zero for unregistered names.
    ///
    /// @param xnsName XNS name as passed by the caller (bare or fully qualified).
    /// @return canonicalXNSName Canonical form used for keys, storage, and events.
    function _requireXNSNameOwner(
        string calldata xnsName
    ) private view returns (string memory canonicalXNSName) {
        canonicalXNSName = _canonicalizeXNSName(xnsName);
        address xnsNameOwner = XNS.getAddress(canonicalXNSName);
        require(xnsNameOwner != address(0), "XNSRoutes: invalid XNS name");
        require(msg.sender == xnsNameOwner, "XNSRoutes: not XNS name owner");
    }

    /// @dev `keccak256(bytes(_canonicalizeXNSName(xnsName)))`
    ///
    /// @param xnsName The XNS name to get the key for.
    /// @return key The key for the XNS name.
    function _xnsNameKey(string memory xnsName) private pure returns (bytes32) {
        return keccak256(bytes(_canonicalizeXNSName(xnsName)));
    }

    /// @dev Empty `routePrefix`: packed `canonicalXnsName/route` (matches human path without `:`).
    /// Non-empty: `canonicalXnsName/routePrefix:route`.
    ///
    /// @param xnsName XNS name (canonicalized before packing).
    /// @param routePrefix Route prefix of the route path to be packed (may be empty).
    /// @param route Route label of the route path to be packed.
    /// @return key Keccak-256 route storage key for `(canonical xnsName, routePrefix, route)`.
    function _routeKey(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private pure returns (bytes32 key) {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        if (bytes(routePrefix).length == 0) {
            return keccak256(abi.encodePacked(canonicalXNSName, "/", route));
        }
        return keccak256(abi.encodePacked(canonicalXNSName, "/", routePrefix, ":", route));
    }

    /// @dev Non-empty `routePrefix` and `route` must satisfy slug rules (charset/hyphen constraints)
    /// so malformed tuples cannot alias canonical keys. `routePrefix` max length is 20; `route` max
    /// length is 32.
    ///
    /// @param routePrefix Route prefix of the route path to be validated (may be empty).
    /// @param route Route label of the route path to be validated.
    function _validateRoutePrefixAndRoute(
        string memory routePrefix,
        string memory route
    ) private pure {
        require(
            bytes(routePrefix).length == 0 || _isValidRoutePrefix(routePrefix),
            "XNSRoutes: invalid route prefix"
        );
        require(_isValidRoute(route), "XNSRoutes: invalid route");
    }

    /// @dev Route-prefix validator (same character/hyphen rules as XNS labels, max length 20).
    ///
    /// @param routePrefix Candidate route-prefix label.
    /// @return isValid True when `routePrefix` is valid.
    function _isValidRoutePrefix(string memory routePrefix) private pure returns (bool isValid) {
        return _isValidSlug(routePrefix, 20);
    }

    /// @dev Route validator (same character/hyphen rules as XNS labels, max length 32).
    ///
    /// @param route Candidate route label.
    /// @return isValid True when `route` is valid.
    function _isValidRoute(string memory route) private pure returns (bool isValid) {
        return _isValidSlug(route, 32);
    }

    /// @dev Shared slug validator used by route-prefix and route checks.
    /// Rules:
    /// - length in [1, `maxLen`]
    /// - chars are only [a-z], [0-9], or '-'
    /// - no leading/trailing '-'
    /// - no consecutive '--'
    ///
    /// @param s Candidate slug string.
    /// @param maxLen Inclusive maximum length.
    /// @return isValid True when `s` satisfies all constraints.
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

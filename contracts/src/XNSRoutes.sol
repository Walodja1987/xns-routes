// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IXNSMinimal.sol";

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
/// @notice Route registry for XNS names.
///
/// Route format: `[xnsName]/[routePrefix]:[route]` or `[xnsName]/[route]` when no prefix is used.
///
/// Examples:
/// - `bob.xns/eth:transfer-usdt/to=0x.../amount=100`
/// - `alice.og/my-sub-wallet`
/// - `contracts.aave/v4:pools`
///
/// Key points:
/// - Routes are owned and managed by the current XNS name owner.
/// - A route stores `target`, `routeType`, `isActive`, and `isFrozen`.
/// - Route freeze and route-book freeze are irreversible.
/// - Active status can still be toggled after freeze.
/// - An append-only log of route storage keys per `xnsName` supports enumeration without an indexer (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecordByRouteKey`).
contract XNSRoutes {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error ZeroAddress();
    error InvalidXnsName();
    error InvalidRoutePrefix();
    error InvalidRoute();
    error InvalidTarget();
    error NotXnsNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error RouteBookFrozen();
    error RouteAlreadyExists();
    error CannotDeleteFrozenRoute();
    error InvalidRoutePath();
    error InvalidRouteKeySlice();

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

    /// @notice XNS registry this contract calls for name resolution and label validation.
    IXNSMinimal public immutable XNS;

    // keccak256(bytes(xnsName)) => entire route book under that name frozen?
    mapping(bytes32 => bool) private _routeBookFrozen;

    // _routeKey(xnsName, routePrefix, route) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    // keccak256(bytes(xnsName)) => append-only log of route keys ever created under that name (not shortened on delete)
    mapping(bytes32 => bytes32[]) private _routeKeysByName;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    /// @dev Emitted in `createRoute`.
    event RouteCreated(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 indexed routeType
    );

    /// @dev Emitted in `updateRoute`.
    event RouteUpdated(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 indexed routeType
    );

    /// @dev Emitted in `updateTarget` when target changes.
    event RouteTargetUpdated(string xnsName, string routePrefix, string route, address indexed newTarget);

    /// @dev Emitted in `updateRouteType` when route type changes.
    event RouteTypeUpdated(string xnsName, string routePrefix, string route, uint32 indexed newRouteType);

    /// @dev Emitted in `activateRoute` and `deactivateRoute` when active status changes.
    event RouteActiveStatusUpdated(string xnsName, string routePrefix, string route, bool isActive);

    /// @dev Emitted in `createRoute`, `updateRoute`, and `freezeRoute` when route freeze is applied.
    event RouteFrozen(string xnsName, string routePrefix, string route);

    /// @dev Emitted in `freezeRouteBook` when the route book is frozen for an XNS name.
    event RouteBookFrozenForName(string xnsName);

    /// @dev Emitted in `deleteRoute`.
    event RouteDeleted(string xnsName, string routePrefix, string route);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    /// @notice Constructs the registry and registers `routes.xns` to this contract via XNS.
    ///
    /// **Requirements:**
    /// - `_xns` must not be the zero address (`ZeroAddress`).
    /// - `msg.value` is forwarded to `registerName("routes","xns")` so `routes.xns` resolves to `address(this)`; XNS-side rules
    ///   (payment, exclusivity, name availability, etc.) apply and deployment reverts if registration fails.
    ///
    /// Because the owner of `routes.xns` is this contract, `createRoute` / `updateRoute` with `xnsName == "routes.xns"` require
    /// `msg.sender == address(this)`; use an authorized entrypoint with `this.createRoute` / `this.updateRoute` (or another XNS name owned by the operator).
    ///
    /// @param _xns XNS registry implementing `IXNSMinimal`.
    constructor(address _xns) payable {
        if (_xns == address(0)) revert ZeroAddress();
        XNS = IXNSMinimal(_xns);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    // -------------------------------------------------------------------------
    // State-modifying functions
    // -------------------------------------------------------------------------
    /// @notice Create a route under `(xnsName, routePrefix, route)`. Reverts if that key already exists.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName` (`InvalidXnsName`, `NotXnsNameOwner`).
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules (`InvalidRoutePrefix`, `InvalidRoute`).
    /// - `target` must not be the zero address (`InvalidTarget`).
    /// - The route book for `xnsName` must not be frozen (`RouteBookFrozen`).
    /// - The route key must not already exist (`RouteAlreadyExists`).
    ///
    /// On success, appends the route storage key to the per-name append-only log (`getRouteKeyCount` / `getRouteKeys`).
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action"
    /// @param routePrefix Optional path segment before `:`; non-empty must pass XNS label rules; empty means `xnsName/route/...` only (no `:` in the action segment).
    /// @param route Required action label (XNS label rules), e.g. "transfer-usdt"
    /// @param target Build address for `routeType`; must be non-zero (`address(0)` is reserved for "missing route").
    /// @param routeType Opaque hint for parsers (semantics offchain)
    /// @param activate Initial value for stored `isActive`.
    /// @param freeze If true, set stored `isFrozen` in this same tx (irreversible for that route).
    function createRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external {
        // Check if the caller is authorized to create a route (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Validate that the target is not the zero address
        if (target == address(0)) revert InvalidTarget();

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        // Derive the route key and check if the route already exists
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target != address(0)) revert RouteAlreadyExists();

        // Create the route record
        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: activate,
            isFrozen: freeze
        });

        _routeKeysByName[keccak256(bytes(xnsName))].push(routeKey);

        // Emit the `RouteFrozen` event, if the route is frozen
        if (freeze) {
            emit RouteFrozen(xnsName, routePrefix, route);
        }

        // Emit the `RouteCreated` event
        emit RouteCreated(xnsName, routePrefix, route, target, activate, freeze, routeType);
    }

    /// @notice Update an existing route (target, routeType, activate, optional freeze in one tx).
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - `target` must not be the zero address (`InvalidTarget`).
    /// - The route book for `xnsName` must not be frozen (`RouteBookFrozen`).
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`) and must not already be per-route frozen (`CannotUpdateFrozenRoute`).
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action"
    /// @param routePrefix Same as at create time (may be empty).
    /// @param route Same as at create time
    /// @param target Must be non-zero; use a burn address if an unusable target is required.
    /// @param routeType Opaque hint for parsers (semantics offchain)
    /// @param activate New value for stored `isActive`.
    /// @param freeze If true, set stored `isFrozen` in this same tx (irreversible for that route).
    function updateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external {
        // Check if the caller is authorized to update a route (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Confirm that the target is not the zero address
        if (target == address(0)) revert InvalidTarget();

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        // Update the route record
        record.target = target;
        record.routeType = routeType;
        record.isActive = activate;

        // Emit the `RouteFrozen` event, if the route is frozen
        if (freeze) {
            record.isFrozen = true;
            emit RouteFrozen(xnsName, routePrefix, route);
        }

        // Emit the `RouteUpdated` event
        emit RouteUpdated(xnsName, routePrefix, route, target, record.isActive, record.isFrozen, record.routeType);
    }

    /// @notice Mark an existing route as active.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`).
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    function activateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, true);
    }

    /// @notice Mark an existing route as inactive.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`).
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    function deactivateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, false);
    }

    /// @dev Used by `activateRoute` and `deactivateRoute`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`).
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    /// @param active New active status to set.
    function _updateRouteActiveStatus(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        bool active
    ) private {
        // Check if the caller is authorized to update the route active status (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();

        // Update the route active status and emit the `RouteActiveStatusUpdated` event, if the active status changes
        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(xnsName, routePrefix, route, active);
        }
    }

    /// @notice Remove a route so `createRoute` may register the same key again.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - The route book for `xnsName` must not be frozen (`RouteBookFrozen`).
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`) and must not be per-route frozen (`CannotDeleteFrozenRoute`).
    ///
    /// Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    function deleteRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        // Check if the caller is authorized to delete a route (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotDeleteFrozenRoute();

        // Delete the route record
        delete _routes[routeKey];

        // Emit the `RouteDeleted` event
        emit RouteDeleted(xnsName, routePrefix, route);
    }

    /// @notice Update the build `target` for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - The route book for `xnsName` must not be frozen (`RouteBookFrozen`).
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`) and must not be per-route frozen (`CannotUpdateFrozenRoute`).
    /// - `newTarget` must not be the zero address (`InvalidTarget`).
    ///
    /// Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    /// @param newTarget New build target; must be non-zero.
    function updateTarget(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address newTarget
    ) external {
        // Check if the caller is authorized to update the target (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        // Confirm that the new target is not the zero address
        if (newTarget == address(0)) revert InvalidTarget();

        // Update the target and emit the `RouteTargetUpdated` event, if the target changes
        if (record.target != newTarget) {
            record.target = newTarget;
            emit RouteTargetUpdated(xnsName, routePrefix, route, newTarget);
        }
    }

    /// @notice Update `routeType` for an existing route.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - The route book for `xnsName` must not be frozen (`RouteBookFrozen`).
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`) and must not be per-route frozen (`CannotUpdateFrozenRoute`).
    ///
    /// Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    /// @param newRouteType New opaque parser hint.
    function updateRouteType(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        uint32 newRouteType
    ) external {
        // Check if the caller is authorized to update the route type (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists and is not frozen
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        // Update the route type and emit the `RouteTypeUpdated` event, if the route type changes
        if (record.routeType != newRouteType) {
            record.routeType = newRouteType;
            emit RouteTypeUpdated(xnsName, routePrefix, route, newRouteType);
        }
    }

    /// @notice Freeze a single route forever.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    /// - Non-empty `routePrefix` and `route` must satisfy XNS label rules.
    /// - The route must exist (`RouteNotFound`).
    ///
    /// After freezing, `target` and `routeType` can never be changed again; active/inactive can still be toggled.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    function freezeRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        // Check if the caller is authorized to freeze the route (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();

        // Update the route freeze status and emit the `RouteFrozen` event, if the route is not frozen
        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(xnsName, routePrefix, route);
        }
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current XNS owner for `xnsName`.
    ///
    /// **Effects (irreversible):**
    /// - No new routes may be added under `xnsName`.
    /// - No existing route targets may be changed under `xnsName`.
    /// - Routes may not be deleted under `xnsName`.
    /// - Route activation can still be toggled.
    ///
    /// @param xnsName Fully-qualified XNS name whose route book to freeze.
    function freezeRouteBook(string calldata xnsName) external {
        // Check if the caller is authorized to freeze the route book (must be the XNS name owner)
        _requireXNSNameOwner(xnsName);

        // Check if the route book is not already frozen
        bytes32 xnsNameKey = keccak256(bytes(xnsName));
        if (!_routeBookFrozen[xnsNameKey]) {
            _routeBookFrozen[xnsNameKey] = true;
            emit RouteBookFrozenForName(xnsName);
        }
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Return full route metadata. Applies the same `routePrefix`/`route` validation as mutating functions, then reads storage.
    /// Reverts with `RouteNotFound` when no route exists for the key.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
    /// @return target Stored build target address.
    /// @return isActive Whether the route is active.
    /// @return isFrozen Whether the route is frozen per-route.
    /// @return routeType Opaque parser hint.
    function getRouteInfo(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    )
        external
        view
        returns (address target, bool isActive, bool isFrozen, uint32 routeType)
    {
        return _getRouteInfo(xnsName, routePrefix, route);
    }

    /// @notice Same as `getRouteInfo` with `fullRoutePath` parsed by `splitFullPath`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/` (`InvalidRoutePath` if not).
    /// - Further requirements match `getRouteInfo` for the parsed components.
    function getRouteInfoFromPath(string calldata fullRoutePath)
        external
        view
        returns (address target, bool isActive, bool isFrozen, uint32 routeType)
    {
        (string memory xnsName, string memory routePrefix, string memory route) = _splitFullPath(fullRoutePath);
        return _getRouteInfo(xnsName, routePrefix, route);
    }

    function _getRouteInfo(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private view returns (address target, bool isActive, bool isFrozen, uint32 routeType) {
        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);

        // Derive the route key and check if the route exists
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();

        return (record.target, record.isActive, record.isFrozen, record.routeType);
    }

    /// @notice Returns whether a route exists (`target` was ever set via `createRoute`; zero `target` is never stored).
    /// Applies the same `routePrefix`/`route` validation as mutating functions before reading storage.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routePrefix Optional route prefix segment (empty means no prefix).
    /// @param route Route label segment.
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
    /// - `fullRoutePath` must contain at least one `/` (`InvalidRoutePath` if not).
    /// - Further requirements match `routeExists` for the parsed components.
    function routeExistsFromPath(string calldata fullRoutePath) external view returns (bool exists) {
        (string memory xnsName, string memory routePrefix, string memory route) = _splitFullPath(fullRoutePath);
        return _routeExists(xnsName, routePrefix, route);
    }

    function _routeExists(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private view returns (bool exists) {
        // Validate that the route prefix and route are valid strings
        _validateRoutePrefixAndRoute(routePrefix, route);
        return _routes[_routeKey(xnsName, routePrefix, route)].target != address(0);
    }

    /// @notice Returns whether the entire route book under `xnsName` is frozen (reads `_routeBookFrozen[keccak256(bytes(xnsName))]`).
    ///
    /// @param xnsName Fully-qualified XNS name.
    /// @return frozen True if the route book is frozen.
    function isRouteBookFrozen(string calldata xnsName) external view returns (bool frozen) {
        return _routeBookFrozen[keccak256(bytes(xnsName))];
    }

    /// @notice Number of entries in the append-only route-key log for `xnsName` (not the count of live routes; deletes do not shrink this).
    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count) {
        return _routeKeysByName[keccak256(bytes(xnsName))].length;
    }

    /// @notice Returns `keys[start:end]` from the append-only log for `xnsName` (`end` is exclusive). Reverts `InvalidRouteKeySlice` if `start > end` or `end` exceeds length.
    function getRouteKeys(string calldata xnsName, uint256 start, uint256 end)
        external
        view
        returns (bytes32[] memory keys)
    {
        bytes32[] storage arr = _routeKeysByName[keccak256(bytes(xnsName))];
        uint256 len = arr.length;
        if (start > end || end > len) revert InvalidRouteKeySlice();
        uint256 n = end - start;
        keys = new bytes32[](n);
        for (uint256 i = 0; i < n; ++i) {
            keys[i] = arr[start + i];
        }
    }

    /// @notice Read stored metadata by canonical route storage key. Does not validate strings; `target == address(0)` means no record (never created or deleted).
    function getRouteRecordByRouteKey(bytes32 routeKey)
        external
        view
        returns (address target, uint32 routeType, bool isActive, bool isFrozen)
    {
        RouteRecord storage record = _routes[routeKey];
        return (record.target, record.routeType, record.isActive, record.isFrozen);
    }

    /// @notice Parse `fullRoutePath` into `(xnsName, routePrefix, route)` (first `/`, then first `:` in the action segment).
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/` (`InvalidRoutePath` if not).
    ///
    /// Does not apply XNS label validation; pass the returned tuple into tuple-based functions, which validate `routePrefix` and `route`.
    ///
    /// @param fullRoutePath Full path, e.g. `bob.xns/eth:transfer-usdt` or `bob.xns/my-wallet`.
    /// @return xnsName Segment before the first `/`.
    /// @return routePrefix Segment before the first `:` in the action part, or empty if there is no `:`.
    /// @return route Remainder of the action part after `routePrefix` and `:`, or the whole action part if there is no `:`.
    function splitFullPath(string calldata fullRoutePath)
        external
        pure
        returns (string memory xnsName, string memory routePrefix, string memory route)
    {
        return _splitFullPath(fullRoutePath);
    }

    /// @dev Splits `fullRoutePath` at the first `/` into `xnsName` and `action`. Within `action`, splits at the first `:` if any.
    /// Reverts `InvalidRoutePath` only when no `/` is found. Does not validate XNS labels or reject extra `/` in `action`.
    ///
    /// **Requirements:**
    /// - `fullRoutePath` must contain at least one `/` (`InvalidRoutePath` if not).
    ///
    /// @param fullRoutePath The full route path to split.
    /// @return xnsName The XNS name.
    /// @return routePrefix The route prefix.
    /// @return route The route.
    function _splitFullPath(string calldata fullRoutePath)
        private
        pure
        returns (string memory xnsName, string memory routePrefix, string memory route)
    {
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
        if (!foundSlash) revert InvalidRoutePath();

        xnsName = _calldataSubstringToString(b, 0, slash);

        uint256 actionStart = slash + 1;
        if (actionStart >= n) {
            return (xnsName, "", "");
        }

        bytes calldata action = b[actionStart:n];

        uint256 colon;
        bool foundColon;
        for (uint256 j = 0; j < action.length; ++j) {
            if (action[j] == 0x3a) {
                colon = j;
                foundColon = true;
                break;
            }
        }
        if (!foundColon) {
            return (xnsName, "", _calldataSubstringToString(action, 0, action.length));
        }

        routePrefix = _calldataSubstringToString(action, 0, colon);
        uint256 routeStart = colon + 1;
        if (routeStart >= action.length) {
            route = "";
        } else {
            route = _calldataSubstringToString(action, routeStart, action.length);
        }
    }

    /// @dev Copies `data[start:end]` (end exclusive) into a UTF-8 string in memory.
    ///
    /// **Requirements:**
    /// - `end` must be greater than or equal to `start` (`InvalidRoutePath` if not).
    ///
    /// @param data The bytes to copy.
    /// @param start The start index (inclusive).
    /// @param end The end index (exclusive).
    /// @return out The resulting string.
    function _calldataSubstringToString(bytes calldata data, uint256 start, uint256 end)
        private
        pure
        returns (string memory out)
    {
        if (end < start) revert InvalidRoutePath();
        uint256 len = end - start;
        bytes memory buf = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            buf[i] = data[start + i];
        }
        out = string(buf);
    }

    /// @dev XNS `getAddress` returns zero for empty `fullName` and for unregistered names.
    /// @param xnsName Fully-qualified XNS name to authorize against.
    function _requireXNSNameOwner(string calldata xnsName) private view {
        address xnsNameOwner = XNS.getAddress(xnsName);
        if (xnsNameOwner == address(0)) revert InvalidXnsName();
        if (msg.sender != xnsNameOwner) revert NotXnsNameOwner();
    }

    /// @dev Empty `routePrefix`: packed `xnsName/route` (matches human path without `:`). Non-empty: `xnsName/routePrefix:route`.
    /// @param xnsName Fully-qualified XNS name.
    /// @param routePrefix Optional route prefix segment.
    /// @param route Route label segment.
    /// @return key Keccak-256 route storage key for `(xnsName, routePrefix, route)`.
    function _routeKey(
        string memory xnsName,
        string memory routePrefix,
        string memory route
    ) private pure returns (bytes32 key) {
        if (bytes(routePrefix).length == 0) {
            return keccak256(abi.encodePacked(xnsName, "/", route));
        }
        return keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route));
    }

    /// @dev Non-empty `routePrefix` and `route` must satisfy XNS label rules so malformed tuples cannot alias canonical keys.
    /// @param routePrefix Optional route prefix segment to validate when non-empty.
    /// @param route Route label segment to validate.
    function _validateRoutePrefixAndRoute(string memory routePrefix, string memory route) private view {
        if (bytes(routePrefix).length != 0 && !_isValidString(routePrefix)) revert InvalidRoutePrefix();
        if (!_isValidString(route)) revert InvalidRoute();
    }

    /// @dev Whether `s` satisfies XNS label/namespace rules (length, charset, hyphen rules).
    /// @param s Candidate label or namespace string.
    /// @return isValid True when `s` passes XNS validation.
    function _isValidString(string memory s) private view returns (bool isValid) {
        return XNS.isValidLabelOrNamespace(s);
    }

}

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
/// @notice Route registry linked to the XNS contract on Ethereum (0x648E4F05aF2b7eB85109A8dc8AE81D8E006457D8).
///
/// Routes are scoped under an XNS name plus optional `routePrefix` and a required `route` label. Human-readable paths look like:
/// `bob.xns/eth:transfer-usdt/to=0x.../amount=100`
/// Prefix-agnostic routes: use empty `routePrefix` — path form `bob.xns/my-wallet/...` (no `:` in the action segment).
/// - xnsName: `bob.xns`
/// - routePrefix: optional disambiguator before `:` (XNS label rules when non-empty; e.g. `eth`, `1-eth`, `137-poly`), or `""` when omitted
/// - route: required action label after `:` when `routePrefix` is set, e.g. `transfer-usdt`
/// With a non-empty `routePrefix`, exactly one `:` appears in the action segment, between `routePrefix` and `route`.
///
/// Storage key: if `routePrefix` is empty, `keccak256(abi.encodePacked(xnsName, "/", route))`; else `keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route))`.
/// `routePrefix` and `route` follow XNS label charset (`a-z`, `0-9`, `-`); `xnsName` is a registered XNS full name (no `/` or `:`).
/// Every public function that takes `routePrefix` and `route` validates them the same way before `_routeKey` so encodings like `routePrefix == ""` with `route == "eth:transfer"` cannot alias a canonical `eth` + `transfer` key.
///
/// A route points to a `target` address; `routeType` is an opaque hint (e.g. how parsers interpret
/// `target` or its calldata output). Meaning of type ids is agreed offchain; the contract stores any `uint32`.
///
/// Ownership model:
/// - only the current address resolved by XNS for `xnsName` may manage routes under that name
///
/// Route state model:
/// - target: address (e.g. builder contract or plain contract depending on `routeType`); must be non-zero.
///   An empty mapping slot has `target == address(0)`; that is the only "route does not exist" state.
/// - routeType: parser hint; semantics are offchain (e.g. 0 = EVM address, 1 = tx calldata builder, …)
/// - isActive: whether wallets/apps should treat the route as usable
/// - isFrozen: whether `target` and `routeType` can still be changed
///
/// Route book freeze model (`_routeBookFrozen` keyed by `keccak256(bytes(xnsName))`):
/// - no new routes may be added under that `xnsName`
/// - no existing route targets under that name may be changed anymore
/// - routes may not be deleted under that name
/// - route activation can still be toggled even after route book freeze
///
/// Semantics:
/// - while the route is not frozen and the route book for that XNS name is not frozen, owner may update `target` and `routeType`
/// - route freeze is irreversible
/// - route book freeze is irreversible
/// - active/inactive can be toggled even after freeze
/// - createRoute / updateRoute for full-record writes (+ optional freeze on create/update)
/// - updateTarget / updateRouteType are narrow updates (same guards as updateRoute for target/type); emit `RouteTargetUpdated` / `RouteTypeUpdated` only on change
/// - deleteRoute clears a route when it is not per-route frozen and the route book is not frozen (`createRoute` may reuse the key afterward)
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
        uint32 routeType
    );

    /// @dev Emitted in `updateRoute`.
    event RouteUpdated(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
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
    /// - `xns_` must not be the zero address (`ZeroAddress`).
    /// - `msg.value` is forwarded to `registerName("routes","xns")` so `routes.xns` resolves to `address(this)`; XNS-side rules
    ///   (payment, exclusivity, name availability, etc.) apply and deployment reverts if registration fails.
    ///
    /// Because the owner of `routes.xns` is this contract, `createRoute` / `updateRoute` with `xnsName == "routes.xns"` require
    /// `msg.sender == address(this)`; use an authorized entrypoint with `this.createRoute` / `this.updateRoute` (or another XNS name owned by the operator).
    ///
    /// @param xns_ XNS registry implementing `IXNSMinimal`.
    constructor(address xns_) payable {
        if (xns_ == address(0)) revert ZeroAddress();
        XNS = IXNSMinimal(xns_);
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
        _requireXnsNameOwner(xnsName);

        _validateRoutePrefixAndRoute(routePrefix, route);
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

        // Emit the `RouteFrozen` event, if the route is frozen
        if (freeze) {
            emit RouteFrozen(xnsName, routePrefix, route);
        }

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
        _requireXnsNameOwner(xnsName);

        // Confirm that the target is not the zero address
        if (target == address(0)) revert InvalidTarget();

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        _validateRoutePrefixAndRoute(routePrefix, route);
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
        _requireXnsNameOwner(xnsName);

        _validateRoutePrefixAndRoute(routePrefix, route);
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
        _requireXnsNameOwner(xnsName);

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        _validateRoutePrefixAndRoute(routePrefix, route);
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
        _requireXnsNameOwner(xnsName);

        // Check if the route book is frozen
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

        _validateRoutePrefixAndRoute(routePrefix, route);
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        // Confirm that the new target is not the zero address
        if (newTarget == address(0)) revert InvalidTarget();

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
        _requireXnsNameOwner(xnsName);
        if (_routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();
        _validateRoutePrefixAndRoute(routePrefix, route);
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

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
        _requireXnsNameOwner(xnsName);

        _validateRoutePrefixAndRoute(routePrefix, route);
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();

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
        _requireXnsNameOwner(xnsName);

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
        _validateRoutePrefixAndRoute(routePrefix, route);
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

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------
    /// @dev XNS `getAddress` returns zero for empty `fullName` and for unregistered names.
    /// @param xnsName Fully-qualified XNS name to authorize against.
    function _requireXnsNameOwner(string calldata xnsName) private view {
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
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) private pure returns (bytes32 key) {
        if (bytes(routePrefix).length == 0) {
            return keccak256(abi.encodePacked(xnsName, "/", route));
        }
        return keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route));
    }

    /// @dev Non-empty `routePrefix` and `route` must satisfy XNS label rules so malformed tuples cannot alias canonical keys.
    /// @param routePrefix Optional route prefix segment to validate when non-empty.
    /// @param route Route label segment to validate.
    function _validateRoutePrefixAndRoute(string calldata routePrefix, string calldata route) private view {
        if (bytes(routePrefix).length != 0 && !_isValidString(routePrefix)) revert InvalidRoutePrefix();
        if (!_isValidString(route)) revert InvalidRoute();
    }

    /// @dev Whether `s` satisfies XNS label/namespace rules (length, charset, hyphen rules).
    /// @param s Candidate label or namespace string.
    /// @return isValid True when `s` passes XNS validation.
    function _isValidString(string calldata s) private view returns (bool isValid) {
        return XNS.isValidLabelOrNamespace(s);
    }

}

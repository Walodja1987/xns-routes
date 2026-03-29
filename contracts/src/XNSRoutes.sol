// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Subset of the XNS registry used by `XNSRoutes` (resolution, label rules, and `registerName` at deploy).
interface IXNS {
    function getAddress(string calldata fullName) external view returns (address addr);
    function isValidLabelOrNamespace(string calldata labelOrNamespace) external pure returns (bool isValid);
    function registerName(string calldata label, string calldata namespace) external payable;
}

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
/// Route book freeze model (`routeBookFrozen` keyed by `keccak256(bytes(xnsName))`):
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
/// - updateTarget / updateRouteType are narrow updates (same guards as updateRoute for target/type); emit `RouteSet` only on change
/// - deleteRoute clears a route when it is not per-route frozen and the route book is not frozen (`createRoute` may reuse the key afterward)
contract XNSRoutes {
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

    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
    }

    IXNS public immutable XNS;

    // keccak256(bytes(xnsName)) => entire route book under that name frozen?
    mapping(bytes32 => bool) public routeBookFrozen;

    // _routeKey(xnsName, routePrefix, route) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    /// @dev Strings are non-indexed so logs carry full values (e.g. subgraphs). `target` is indexed for address filters.
    event RouteSet(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool activate,
        bool freeze,
        uint32 routeType
    );

    event RouteActiveStatusUpdated(string xnsName, string routePrefix, string route, bool isActive);

    event RouteFrozen(string xnsName, string routePrefix, string route);

    event RouteBookFrozenForName(string xnsName);

    event RouteDeleted(string xnsName, string routePrefix, string route);

    /// @param xns_ XNS registry implementing `IXNS`.
    /// @dev Payable: forwards `msg.value` to `registerName("routes","xns")` so `routes.xns` resolves to `address(this)`.
    /// Requirements on XNS side (payment, exclusivity, name availability, etc.) apply — deployment reverts if registration fails.
    /// @dev Because the owner of `routes.xns` is this contract, `createRoute` / `updateRoute` with `xnsName == "routes.xns"` require
    /// `msg.sender == address(this)`. To let an EOA or multisig manage that namespace, add an authorized entrypoint
    /// that performs an external `this.createRoute(...)` / `this.updateRoute(...)` (or use another XNS name owned by the operator).
    constructor(address xns_) payable {
        if (xns_ == address(0)) revert ZeroAddress();
        XNS = IXNS(xns_);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    /// @notice Create a route under `(xnsName, routePrefix, route)`. Reverts if that key already exists.
    /// @dev Enforces owner, XNS label rules on non-empty `routePrefix` and on `route`, non-zero `target`, and route book not frozen before deriving the key.
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action"
    /// @param routePrefix Optional path segment before `:`; non-empty must pass XNS label rules; empty means `xnsName/route/...` only (no `:` in the action segment).
    /// @param route Required action label (XNS label rules), e.g. "transfer-usdt"
    /// @param target Build address for `routeType`; must be non-zero (`address(0)` is reserved for "missing route").
    /// @param routeType Opaque hint for parsers (semantics offchain)
    /// @param activate Initial value for stored `isActive`
    /// @param freeze If true, set stored `isFrozen` in this same tx (irreversible for that route)
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

        // Validate input parameters
        if (bytes(routePrefix).length != 0 && !_isValidString(routePrefix)) revert InvalidRoutePrefix();
        if (!_isValidString(route)) revert InvalidRoute();
        if (target == address(0)) revert InvalidTarget();

        // Check if the route book is frozen
        if (routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

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

        // Emit the `RouteSet` event
        emit RouteSet(xnsName, routePrefix, route, target, activate, freeze, routeType);
    }

    /// @notice Update an existing route (target, routeType, activate, optional freeze in one tx).
    /// @dev Enforces owner, non-zero `target`, route book not frozen, then derives the key. Does not re-validate `routePrefix`/`route` against XNS label rules (saves gas); wrong or invalid strings usually revert `RouteNotFound`.
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action"
    /// @param routePrefix Same as at create time (may be empty).
    /// @param route Same as at create time
    /// @param target Must be non-zero; use a burn address if an unusable target is required.
    /// @param routeType Opaque hint for parsers (semantics offchain)
    /// @param activate New value for stored `isActive`
    /// @param freeze If true, set stored `isFrozen` in this same tx (irreversible for that route)
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
        if (routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();

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

        // Emit the `RouteSet` event
        emit RouteSet(xnsName, routePrefix, route, target, activate, freeze, routeType);
    }

    /// @notice Mark an existing route as active.
    /// @dev Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    function activateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, true);
    }

    /// @notice Mark an existing route as inactive.
    /// @dev Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.
    function deactivateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        _updateRouteActiveStatus(xnsName, routePrefix, route, false);
    }

    /// @dev Allowed after route or route book freeze. Emits `RouteActiveStatusUpdated` only when `isActive` changes.
    function _updateRouteActiveStatus(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        bool active
    ) private {
        // Check if the caller is authorized to update the route active status (must be the XNS name owner)
        _requireXnsNameOwner(xnsName);

        // Derive the route key and check if the route exists
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();
        
        // Update the route active status
        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(xnsName, routePrefix, route, active);
        }
    }

    /// @notice Remove a route so `createRoute` may register the same key again.
    /// @dev Reverts if the route is frozen (`CannotDeleteFrozenRoute`) or the route book is frozen (`RouteBookFrozen`).
    /// Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.
    function deleteRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external {
        _requireXnsNameOwner(xnsName);
        if (routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();
        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotDeleteFrozenRoute();
        delete _routes[routeKey];
        emit RouteDeleted(xnsName, routePrefix, route);
    }

    /// @notice Update the build `target` for an existing route.
    /// @dev Same constraints as `updateRoute` for target changes: not route-frozen, not route-book frozen.
    /// Emits `RouteSet` only when `newTarget` differs from the stored target.
    function updateTarget(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address newTarget
    ) external {
        _requireXnsNameOwner(xnsName);
        if (routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        if (newTarget == address(0)) revert InvalidTarget();

        if (record.target != newTarget) {
            record.target = newTarget;
            emit RouteSet(xnsName, routePrefix, route, newTarget, record.isActive, record.isFrozen, record.routeType);
        }
    }

    /// @notice Update `routeType` for an existing route.
    /// @dev Same constraints as `updateRoute` for type changes: not route-frozen, not route-book frozen.
    /// Emits `RouteSet` only when `newRouteType` differs from the stored value.
    function updateRouteType(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        uint32 newRouteType
    ) external {
        _requireXnsNameOwner(xnsName);
        if (routeBookFrozen[keccak256(bytes(xnsName))]) revert RouteBookFrozen();
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();
        if (record.isFrozen) revert CannotUpdateFrozenRoute();

        if (record.routeType != newRouteType) {
            record.routeType = newRouteType;
            emit RouteSet(xnsName, routePrefix, route, record.target, record.isActive, record.isFrozen, newRouteType);
        }
    }

    /// @notice Freeze a single route forever.
    /// @dev After freezing, `target` and `routeType` can never be changed again.
    /// Active/inactive can still be toggled.
    function freezeRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external {
        _requireXnsNameOwner(xnsName);

        bytes32 routeKey = _routeKey(xnsName, routePrefix, route);
        RouteRecord storage record = _routes[routeKey];
        if (record.target == address(0)) revert RouteNotFound();

        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(xnsName, routePrefix, route);
        }
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    /// @dev After this:
    /// - no new routes may be added under `xnsName`
    /// - no existing route targets may be changed under `xnsName`
    /// - routes may not be deleted under `xnsName`
    /// - route activation can still be toggled
    function freezeRouteBook(string calldata xnsName) external {
        _requireXnsNameOwner(xnsName);

        bytes32 xnsNameKey = keccak256(bytes(xnsName));
        if (!routeBookFrozen[xnsNameKey]) {
            routeBookFrozen[xnsNameKey] = true;
            emit RouteBookFrozenForName(xnsName);
        }
    }

    /// @notice Return full route metadata. Reverts if not found.
    function getRouteInfo(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    )
        external
        view
        returns (address target, bool isActive, bool isFrozen, uint32 routeType)
    {
        RouteRecord storage record = _routes[_routeKey(xnsName, routePrefix, route)];
        if (record.target == address(0)) revert RouteNotFound();

        return (record.target, record.isActive, record.isFrozen, record.routeType);
    }

    /// @notice Returns whether a route exists (`target` was ever set via `createRoute`; zero `target` is never stored).
    function routeExists(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external view returns (bool) {
        return _routes[_routeKey(xnsName, routePrefix, route)].target != address(0);
    }

    /// @dev XNS `getAddress` returns zero for empty `fullName` and for unregistered names.
    function _requireXnsNameOwner(string calldata xnsName) private view {
        address xnsNameOwner = XNS.getAddress(xnsName);
        if (xnsNameOwner == address(0)) revert InvalidXnsName();
        if (msg.sender != xnsNameOwner) revert NotXnsNameOwner();
    }

    /// @dev Empty `routePrefix`: packed `xnsName/route` (matches human path without `:`). Non-empty: `xnsName/routePrefix:route`.
    function _routeKey(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) private pure returns (bytes32) {
        if (bytes(routePrefix).length == 0) {
            return keccak256(abi.encodePacked(xnsName, "/", route));
        }
        return keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route));
    }

    /// @dev Whether `s` satisfies XNS label/namespace rules (length, charset, hyphen rules).
    /// Used only for `createRoute`.
    function _isValidString(string calldata s) private view returns (bool) {
        return XNS.isValidLabelOrNamespace(s);
    }

}

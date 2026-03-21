// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IXNSMinimal {
    function getAddress(string calldata fullName) external view returns (address addr);
    function isValidLabelOrNamespace(string calldata labelOrNamespace) external pure returns (bool isValid);
}

/// @title XNSRoutes
/// @author Wladimir Weinbender (DIVA Technologies AG)
/// @notice Route registry linked to an already deployed XNS contract.
///
/// Routes are scoped under an existing XNS name, e.g.:
/// - baseName: "xns.action"
/// - route:    "register-name"
///
/// A route points to a build contract that returns tx calldata.
///
/// Ownership model:
/// - only the current address resolved by XNS for `baseName` may manage routes under that name
///
/// Route state model:
/// - target: build contract address
/// - isActive: whether wallets/apps should treat the route as usable
/// - isFrozen: whether the target pointer can still be changed
///
/// Base freeze model:
/// - baseRoutesFrozen[baseName] means no new routes may be added under that name
/// - and no existing route targets under that name may be changed anymore
/// - route activation can still be toggled even after base freeze
///
/// Semantics:
/// - while neither the route nor the base name is frozen, owner may update the target
/// - route freeze is irreversible
/// - base freeze is irreversible
/// - active/inactive can be toggled even after freeze
/// - setRoute supports create/update + optional immediate freeze in one tx
contract XNSRoutes {
    error ZeroXNS();
    error InvalidBaseName();
    error InvalidRoute();
    error InvalidTarget();
    error NotBaseNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error BaseRoutesFrozen();

    struct RouteRecord {
        address target;
        bool isActive;
        bool isFrozen;
        bool exists;
    }

    IXNSMinimal public immutable XNS;

    // keccak256(baseName) => all routes under this base name frozen?
    mapping(bytes32 => bool) public baseRoutesFrozen;

    // keccak256(baseName, "/", route) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    event RouteSet(
        string indexed baseName,
        string indexed route,
        address indexed target,
        bool isActive,
        bool isFrozen
    );

    event RouteActivationSet(
        string indexed baseName,
        string indexed route,
        bool isActive
    );

    event RouteFrozen(
        string indexed baseName,
        string indexed route
    );

    event BaseRoutesFrozenForName(
        string indexed baseName
    );

    constructor(address xns_) {
        if (xns_ == address(0)) revert ZeroXNS();
        XNS = IXNSMinimal(xns_);
    }

    /// @notice Create or update a route under `baseName`.
    ///
    /// @param baseName The XNS name that owns the route space, e.g. "xns.action"
    /// @param route The route label, e.g. "register-name"
    /// @param target The build contract address
    /// @param isActive Initial or updated active flag
    /// @param freezeImmediately If true, the route is frozen as part of this same tx
    ///
    /// Behavior:
    /// - new route:
    ///   - created with the provided target and isActive
    ///   - frozen immediately if `freezeImmediately == true`
    ///
    /// - existing mutable route:
    ///   - target updated
    ///   - isActive updated
    ///   - frozen immediately if `freezeImmediately == true`
    ///
    /// Requirements:
    /// - caller must be current owner/resolved address of `baseName`
    /// - route must be valid
    /// - target must not be zero
    /// - base name must not be base-frozen
    /// - route must not already be route-frozen
    function setRoute(
        string calldata baseName,
        string calldata route,
        address target,
        bool isActive,
        bool freezeImmediately
    ) external {
        _requireBaseNameOwner(baseName);

        if (!_isValidRoute(route)) revert InvalidRoute();
        if (target == address(0)) revert InvalidTarget();

        bytes32 baseKey = keccak256(bytes(baseName));
        if (baseRoutesFrozen[baseKey]) revert BaseRoutesFrozen();

        bytes32 routeKey = _routeKey(baseName, route);
        RouteRecord storage record = _routes[routeKey];

        if (record.exists) {
            if (record.isFrozen) revert CannotUpdateFrozenRoute();

            record.target = target;
            record.isActive = isActive;

            if (freezeImmediately) {
                record.isFrozen = true;
                emit RouteFrozen(baseName, route);
            }

            emit RouteSet(baseName, route, target, record.isActive, record.isFrozen);
        } else {
            bool frozen = freezeImmediately;

            _routes[routeKey] = RouteRecord({
                target: target,
                isActive: isActive,
                isFrozen: frozen,
                exists: true
            });

            if (frozen) {
                emit RouteFrozen(baseName, route);
            }

            emit RouteSet(baseName, route, target, isActive, frozen);
        }
    }

    /// @notice Activate or deactivate a route.
    /// @dev Can be called even after route freeze or base freeze.
    function setRouteActive(
        string calldata baseName,
        string calldata route,
        bool isActive
    ) external {
        _requireBaseNameOwner(baseName);

        bytes32 routeKey = _routeKey(baseName, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        record.isActive = isActive;

        emit RouteActivationSet(baseName, route, isActive);
    }

    /// @notice Freeze a single route forever.
    /// @dev After freezing, the route target can never be changed again.
    /// Active/inactive can still be toggled.
    function freezeRoute(
        string calldata baseName,
        string calldata route
    ) external {
        _requireBaseNameOwner(baseName);

        bytes32 routeKey = _routeKey(baseName, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(baseName, route);
        }
    }

    /// @notice Freeze the entire route book under a base name forever.
    /// @dev After this:
    /// - no new routes may be added under `baseName`
    /// - no existing route targets may be changed under `baseName`
    /// - route activation can still be toggled
    function freezeRoutes(
        string calldata baseName
    ) external {
        _requireBaseNameOwner(baseName);

        bytes32 baseKey = keccak256(bytes(baseName));
        if (!baseRoutesFrozen[baseKey]) {
            baseRoutesFrozen[baseKey] = true;
            emit BaseRoutesFrozenForName(baseName);
        }
    }

    /// @notice Return route target only. Reverts if not found.
    function getRoute(
        string calldata baseName,
        string calldata route
    ) external view returns (address target) {
        RouteRecord storage record = _routes[_routeKey(baseName, route)];
        if (!record.exists) revert RouteNotFound();
        return record.target;
    }

    /// @notice Return full route metadata. Reverts if not found.
    function getRouteInfo(
        string calldata baseName,
        string calldata route
    )
        external
        view
        returns (
            address target,
            bool isActive,
            bool isFrozen
        )
    {
        RouteRecord storage record = _routes[_routeKey(baseName, route)];
        if (!record.exists) revert RouteNotFound();

        return (record.target, record.isActive, record.isFrozen);
    }

    /// @notice Returns whether a route exists.
    function routeExists(
        string calldata baseName,
        string calldata route
    ) external view returns (bool) {
        return _routes[_routeKey(baseName, route)].exists;
    }

    function _requireBaseNameOwner(string calldata baseName) internal view {
        if (bytes(baseName).length == 0) revert InvalidBaseName();

        address baseNameOwner = XNS.getAddress(baseName);
        if (baseNameOwner == address(0)) revert InvalidBaseName();
        if (msg.sender != baseNameOwner) revert NotBaseNameOwner();
    }

    function _routeKey(
        string calldata baseName,
        string calldata route
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(baseName, "/", route));
    }

    function _isValidRoute(string calldata route) internal view returns (bool) {
        // Reuse XNS label validation rules:
        // 1–20 chars, [a-z0-9-], no leading/trailing '-', no consecutive '--'
        return XNS.isValidLabelOrNamespace(route);
    }
}
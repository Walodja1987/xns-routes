// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Subset of the XNS registry used by `XNSRoutes` (resolution, label rules, and `registerName` at deploy).
interface IXNS {
    function getAddress(string calldata fullName) external view returns (address addr);
    function isValidLabelOrNamespace(string calldata labelOrNamespace) external pure returns (bool isValid);
    /// @dev Assigns `label.namespace` to `msg.sender` (at deploy, the new `XNSRoutes` instance).
    function registerName(string calldata label, string calldata namespace) external payable;
}

/// @title XNSRoutes
/// @author Wladimir Weinbender (DIVA Technologies AG)
/// @notice Route registry linked to the XNS contract on Ethereum (0x648E4F05aF2b7eB85109A8dc8AE81D8E006457D8).
///
/// Routes are scoped under an XNS name plus a chain key and route label. Human-readable paths look like:
/// `bob.xns/eth:transfer-usdt/to=0x.../amount=100`
/// - baseName: `bob.xns`
/// - chain: `eth` (one label token; use hyphens for compound ids, e.g. `1-eth`, `137-poly`)
/// - route: `transfer-usdt`
/// Only a single `:` appears in the action segment, between `chain` and `route`.
///
/// Storage key: `keccak256(abi.encode(baseName, chain, route))`.
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
    error ZeroAddress();
    error InvalidBaseName();
    error InvalidChain();
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

    IXNS public immutable XNS;

    // keccak256(baseName) => all routes under this base name frozen?
    mapping(bytes32 => bool) public baseRoutesFrozen;

    // keccak256(abi.encode(baseName, chain, route)) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    /// @dev At most three `indexed` fields (EVM limit). `route` is non-indexed for filtering via calldata/logs.
    event RouteSet(
        string indexed baseName,
        string indexed chain,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen
    );

    event RouteActivationSet(
        string indexed baseName,
        string indexed chain,
        string route,
        bool isActive
    );

    event RouteFrozen(string indexed baseName, string indexed chain, string route);

    event BaseRoutesFrozenForName(string indexed baseName);

    /// @param xns_ XNS registry implementing `IXNS`.
    /// @dev Payable: forwards `msg.value` to `registerName("routes","xns")` so `routes.xns` resolves to `address(this)`.
    /// Requirements on XNS side (payment, exclusivity, name availability, etc.) apply — deployment reverts if registration fails.
    /// @dev Because the owner of `routes.xns` is this contract, `setRoute` with `baseName == "routes.xns"` requires
    /// `msg.sender == address(this)`. To let an EOA or multisig manage that namespace, add an authorized entrypoint
    /// that performs an external `this.setRoute(...)` (or use another XNS name owned by the operator for routes).
    constructor(address xns_) payable {
        if (xns_ == address(0)) revert ZeroAddress();
        XNS = IXNS(xns_);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    /// @notice Create or update a route under `(baseName, chain, route)`.
    ///
    /// @param baseName The XNS name that owns the route space, e.g. "xns.action"
    /// @param chain Chain key (XNS label rules), e.g. "eth" or "137-poly"
    /// @param route Action label (XNS label rules), e.g. "transfer-usdt"
    /// @param target The build contract address
    /// @param isActive Initial or updated active flag
    /// @param freezeImmediately If true, the route is frozen as part of this same tx
    function setRoute(
        string calldata baseName,
        string calldata chain,
        string calldata route,
        address target,
        bool isActive,
        bool freezeImmediately
    ) external {
        _requireBaseNameOwner(baseName);

        if (!_isValidChain(chain)) revert InvalidChain();
        if (!_isValidRoute(route)) revert InvalidRoute();
        if (target == address(0)) revert InvalidTarget();

        bytes32 baseKey = keccak256(bytes(baseName));
        if (baseRoutesFrozen[baseKey]) revert BaseRoutesFrozen();

        bytes32 routeKey = _routeKey(baseName, chain, route);
        RouteRecord storage record = _routes[routeKey];

        if (record.exists) {
            if (record.isFrozen) revert CannotUpdateFrozenRoute();

            record.target = target;
            record.isActive = isActive;

            if (freezeImmediately) {
                record.isFrozen = true;
                emit RouteFrozen(baseName, chain, route);
            }

            emit RouteSet(baseName, chain, route, target, record.isActive, record.isFrozen);
        } else {
            bool frozen = freezeImmediately;

            _routes[routeKey] = RouteRecord({
                target: target,
                isActive: isActive,
                isFrozen: frozen,
                exists: true
            });

            if (frozen) {
                emit RouteFrozen(baseName, chain, route);
            }

            emit RouteSet(baseName, chain, route, target, isActive, frozen);
        }
    }

    /// @notice Activate or deactivate a route.
    /// @dev Can be called even after route freeze or base freeze.
    function setRouteActive(
        string calldata baseName,
        string calldata chain,
        string calldata route,
        bool isActive
    ) external {
        _requireBaseNameOwner(baseName);

        bytes32 routeKey = _routeKey(baseName, chain, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        record.isActive = isActive;

        emit RouteActivationSet(baseName, chain, route, isActive);
    }

    /// @notice Freeze a single route forever.
    /// @dev After freezing, the route target can never be changed again.
    /// Active/inactive can still be toggled.
    function freezeRoute(
        string calldata baseName,
        string calldata chain,
        string calldata route
    ) external {
        _requireBaseNameOwner(baseName);

        bytes32 routeKey = _routeKey(baseName, chain, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(baseName, chain, route);
        }
    }

    /// @notice Freeze the entire route book under a base name forever.
    /// @dev After this:
    /// - no new routes may be added under `baseName`
    /// - no existing route targets may be changed under `baseName`
    /// - route activation can still be toggled
    function freezeRoutes(string calldata baseName) external {
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
        string calldata chain,
        string calldata route
    ) external view returns (address target) {
        RouteRecord storage record = _routes[_routeKey(baseName, chain, route)];
        if (!record.exists) revert RouteNotFound();
        return record.target;
    }

    /// @notice Return full route metadata. Reverts if not found.
    function getRouteInfo(
        string calldata baseName,
        string calldata chain,
        string calldata route
    )
        external
        view
        returns (address target, bool isActive, bool isFrozen)
    {
        RouteRecord storage record = _routes[_routeKey(baseName, chain, route)];
        if (!record.exists) revert RouteNotFound();

        return (record.target, record.isActive, record.isFrozen);
    }

    /// @notice Returns whether a route exists.
    function routeExists(
        string calldata baseName,
        string calldata chain,
        string calldata route
    ) external view returns (bool) {
        return _routes[_routeKey(baseName, chain, route)].exists;
    }

    function _requireBaseNameOwner(string calldata baseName) internal view {
        if (bytes(baseName).length == 0) revert InvalidBaseName();

        address baseNameOwner = XNS.getAddress(baseName);
        if (baseNameOwner == address(0)) revert InvalidBaseName();
        if (msg.sender != baseNameOwner) revert NotBaseNameOwner();
    }

    function _routeKey(
        string calldata baseName,
        string calldata chain,
        string calldata route
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(baseName, chain, route));
    }

    function _isValidChain(string calldata chain) internal view returns (bool) {
        return XNS.isValidLabelOrNamespace(chain);
    }

    function _isValidRoute(string calldata route) internal view returns (bool) {
        return XNS.isValidLabelOrNamespace(route);
    }
}

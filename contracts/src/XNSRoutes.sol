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
/// - xnsName: `bob.xns`
/// - chain: `eth` (one label token; use hyphens for compound ids, e.g. `1-eth`, `137-poly`)
/// - route: `transfer-usdt`
/// Only a single `:` appears in the action segment, between `chain` and `route`.
///
/// Storage key: `keccak256(abi.encode(xnsName, chain, route))`.
///
/// A route points to a build contract that returns tx calldata.
///
/// Ownership model:
/// - only the current address resolved by XNS for `xnsName` may manage routes under that name
///
/// Route state model:
/// - target: build contract address
/// - isActive: whether wallets/apps should treat the route as usable
/// - isFrozen: whether the target pointer can still be changed
///
/// Route book freeze model (`routeBookFrozen` keyed by `keccak256(bytes(xnsName))`):
/// - no new routes may be added under that `xnsName`
/// - no existing route targets under that name may be changed anymore
/// - route activation can still be toggled even after route book freeze
///
/// Semantics:
/// - while the route is not frozen and the route book for that XNS name is not frozen, owner may update the target
/// - route freeze is irreversible
/// - route book freeze is irreversible
/// - active/inactive can be toggled even after freeze
/// - setRoute supports create/update + optional immediate freeze in one tx
contract XNSRoutes {
    error ZeroAddress();
    error InvalidXnsName();
    error InvalidChain();
    error InvalidRoute();
    error InvalidTarget();
    error NotXnsNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error RouteBookFrozen();

    struct RouteRecord {
        address target;
        bool isActive;
        bool isFrozen;
        bool exists;
    }

    IXNS public immutable XNS;

    // keccak256(bytes(xnsName)) => entire route book under that name frozen?
    mapping(bytes32 => bool) public routeBookFrozen;

    // keccak256(abi.encode(xnsName, chain, route)) => route record
    mapping(bytes32 => RouteRecord) private _routes;

    /// @dev At most three `indexed` fields (EVM limit). `route` is non-indexed for filtering via calldata/logs.
    event RouteSet(
        string indexed xnsName,
        string indexed chain,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen
    );

    event RouteActivationSet(
        string indexed xnsName,
        string indexed chain,
        string route,
        bool isActive
    );

    event RouteFrozen(string indexed xnsName, string indexed chain, string route);

    event RouteBookFrozenForName(string indexed xnsName);

    /// @param xns_ XNS registry implementing `IXNS`.
    /// @dev Payable: forwards `msg.value` to `registerName("routes","xns")` so `routes.xns` resolves to `address(this)`.
    /// Requirements on XNS side (payment, exclusivity, name availability, etc.) apply — deployment reverts if registration fails.
    /// @dev Because the owner of `routes.xns` is this contract, `setRoute` with `xnsName == "routes.xns"` requires
    /// `msg.sender == address(this)`. To let an EOA or multisig manage that namespace, add an authorized entrypoint
    /// that performs an external `this.setRoute(...)` (or use another XNS name owned by the operator for routes).
    constructor(address xns_) payable {
        if (xns_ == address(0)) revert ZeroAddress();
        XNS = IXNS(xns_);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    /// @notice Create or update a route under `(xnsName, chain, route)`.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action"
    /// @param chain Chain key (XNS label rules), e.g. "eth" or "137-poly"
    /// @param route Action label (XNS label rules), e.g. "transfer-usdt"
    /// @param target The build contract address
    /// @param isActive Initial or updated active flag
    /// @param freezeImmediately If true, the route is frozen as part of this same tx
    function setRoute(
        string calldata xnsName,
        string calldata chain,
        string calldata route,
        address target,
        bool isActive,
        bool freezeImmediately
    ) external {
        _requireXnsNameOwner(xnsName);

        if (!_isValidString(chain)) revert InvalidChain();
        if (!_isValidString(route)) revert InvalidRoute();
        if (target == address(0)) revert InvalidTarget();

        bytes32 xnsNameKey = keccak256(bytes(xnsName));
        if (routeBookFrozen[xnsNameKey]) revert RouteBookFrozen();

        bytes32 routeKey = _routeKey(xnsName, chain, route);
        RouteRecord storage record = _routes[routeKey];

        if (record.exists) {
            if (record.isFrozen) revert CannotUpdateFrozenRoute();

            record.target = target;
            record.isActive = isActive;

            if (freezeImmediately) {
                record.isFrozen = true;
                emit RouteFrozen(xnsName, chain, route);
            }

            emit RouteSet(xnsName, chain, route, target, record.isActive, record.isFrozen);
        } else {
            bool frozen = freezeImmediately;

            _routes[routeKey] = RouteRecord({
                target: target,
                isActive: isActive,
                isFrozen: frozen,
                exists: true
            });

            if (frozen) {
                emit RouteFrozen(xnsName, chain, route);
            }

            emit RouteSet(xnsName, chain, route, target, isActive, frozen);
        }
    }

    /// @notice Activate or deactivate a route.
    /// @dev Can be called even after route freeze or route book freeze.
    function setRouteActive(
        string calldata xnsName,
        string calldata chain,
        string calldata route,
        bool isActive
    ) external {
        _requireXnsNameOwner(xnsName);

        bytes32 routeKey = _routeKey(xnsName, chain, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        record.isActive = isActive;

        emit RouteActivationSet(xnsName, chain, route, isActive);
    }

    /// @notice Freeze a single route forever.
    /// @dev After freezing, the route target can never be changed again.
    /// Active/inactive can still be toggled.
    function freezeRoute(
        string calldata xnsName,
        string calldata chain,
        string calldata route
    ) external {
        _requireXnsNameOwner(xnsName);

        bytes32 routeKey = _routeKey(xnsName, chain, route);
        RouteRecord storage record = _routes[routeKey];
        if (!record.exists) revert RouteNotFound();

        if (!record.isFrozen) {
            record.isFrozen = true;
            emit RouteFrozen(xnsName, chain, route);
        }
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    /// @dev After this:
    /// - no new routes may be added under `xnsName`
    /// - no existing route targets may be changed under `xnsName`
    /// - route activation can still be toggled
    function freezeRoutes(string calldata xnsName) external {
        _requireXnsNameOwner(xnsName);

        bytes32 xnsNameKey = keccak256(bytes(xnsName));
        if (!routeBookFrozen[xnsNameKey]) {
            routeBookFrozen[xnsNameKey] = true;
            emit RouteBookFrozenForName(xnsName);
        }
    }

    /// @notice Return route target only. Reverts if not found.
    function getRoute(
        string calldata xnsName,
        string calldata chain,
        string calldata route
    ) external view returns (address target) {
        RouteRecord storage record = _routes[_routeKey(xnsName, chain, route)];
        if (!record.exists) revert RouteNotFound();
        return record.target;
    }

    /// @notice Return full route metadata. Reverts if not found.
    function getRouteInfo(
        string calldata xnsName,
        string calldata chain,
        string calldata route
    )
        external
        view
        returns (address target, bool isActive, bool isFrozen)
    {
        RouteRecord storage record = _routes[_routeKey(xnsName, chain, route)];
        if (!record.exists) revert RouteNotFound();

        return (record.target, record.isActive, record.isFrozen);
    }

    /// @notice Returns whether a route exists.
    function routeExists(
        string calldata xnsName,
        string calldata chain,
        string calldata route
    ) external view returns (bool) {
        return _routes[_routeKey(xnsName, chain, route)].exists;
    }

    function _requireXnsNameOwner(string calldata xnsName) internal view {
        if (bytes(xnsName).length == 0) revert InvalidXnsName();

        address xnsNameOwner = XNS.getAddress(xnsName);
        if (xnsNameOwner == address(0)) revert InvalidXnsName();
        if (msg.sender != xnsNameOwner) revert NotXnsNameOwner();
    }

    function _routeKey(
        string calldata xnsName,
        string calldata chain,
        string calldata route
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(xnsName, chain, route));
    }

    /// @dev Whether `s` satisfies XNS label/namespace rules (length, charset, hyphen rules).
    /// Used for both `chain` and `route` arguments; callers choose `InvalidChain` vs `InvalidRoute`.
    function _isValidString(string calldata s) internal view returns (bool) {
        return XNS.isValidLabelOrNamespace(s);
    }
}

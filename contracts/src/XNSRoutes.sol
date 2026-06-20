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
/// Routes are addressed with **route** and **parametrized route** strings.
///
/// - **route** — `xnsName/[routeScope:]routeLabel` (on-chain identity; no params).
/// - **parametrized route** — route plus optional `/params…` tail (off-chain parsers only).
///
/// - **xnsName** — XNS name that owns the route book (e.g. `bob.xns`).
/// - **routeScope** — optional segment before `:` (1–20 chars if present).
/// - **routeLabel** — required slug (1–32 chars).
/// - **route identifier** — `[routeScope:]routeLabel` within an `xnsName`.
/// - **params** — optional parameters for off-chain route parsers; not stored or
///   validated on-chain.
///
/// Examples:
/// - route: `alice.og/my-sub-wallet` (without routeScope)
/// - route: `contracts.aave/eth:v3-pool-contract` (with routeScope)
/// - parametrized route: `bob.xns/uniswap:approve-usdt/amount=10` (with routeScope and params)
///
/// `routeScope` and `routeLabel` must follow the same character and hyphenation rules as XNS names:
/// - Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
/// - Cannot start or end with '-'
/// - Cannot contain consecutive hyphens ('--')
///
/// Each route points to a `target`. Once created, `target` and `routeType` are immutable.
///
/// Route metadata and controls:
///
/// **Route type**
/// - Off-chain hint for route parsers on how to interpret `target`.
/// - Examples: 
///   - `0` = `target` is the answer (EOA/smart contract)
///   - `1` = `target` must be queried (e.g. for a Bitcoin or Solana address)
///   - `2` = `target` returns executable calldata
///   - ...
///
/// **Immutable routes**
/// - `target` and `routeType` cannot change after creation; routes cannot be deleted.
/// - Gives users a guarantee that the binding will not change.
///
/// **Active status & activeController**
/// - Routes can be active or inactive (`isActive`).
/// - `activeController` may call `activateRoute` / `deactivateRoute`, start or cancel a
///   two-step transfer (`initiateActiveControllerTransfer` / `acceptActiveController`), or
///   `renounceActiveControl` (irreversible).
/// - Useful to tell off-chain parsers not to resolve a route (e.g. deprecated or paused).
/// - Set at create (`createRoute` defaults to the XNS name owner and isActive = true;
///   `createRouteWithController` for explicit choice).
/// - `activeController` must not be `address(0)`.
/// - At create, `activeController` may be `RENOUNCED_ACTIVE_CONTROLLER` to lock `isActive`
///   permanently; after create use `renounceActiveControl` for the same effect.
///
/// **Route book freeze**
/// - The XNS name owner can freeze the entire route book for an XNS name (`freezeRouteBook`).
/// - Prevents adding new routes under that name. Existing routes are unchanged.
/// - Existing routes can still be activated or deactivated by their `activeController`.
/// - Use `isRouteBookFrozen` to check whether new routes can still be added.
///
/// **Other**
/// - Routes are owned by the XNS name owner; registration is free and unlimited.
/// - Route record: `target`, `routeType`, `isActive`, `activeController`.
/// - Forward resolution: route -> `target`. Use `resolveRouteIfActive` for safe reads
///   or `resolveRoute` for raw resolution. Reverse lookup is not supported because many routes
///   may point to the same `target`.
/// - Bare names like `bob` are stored as `bob.x`.
/// - `routeKey` = hash of canonical route.
/// - List routes on-chain with `getRouteKeyCount` and `getRouteKeys`.
contract XNSRoutes {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Sentinel stored in `activeController` after `renounceActiveControl`.
    /// That account cannot toggle, transfer, or accept; `isActive` is forced false.
    address public constant RENOUNCED_ACTIVE_CONTROLLER =
        address(0x000000000000000000000000000000000000dEaD);

    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @dev Data structure to store route metadata.
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
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

    // keccak256(bytes(canonical xnsName)) => route keys created under that XNS name
    mapping(bytes32 => bytes32[]) private _routeKeysByXNSName;

    // _routeKey(...) => pending `acceptActiveController` recipient (0 = none)
    mapping(bytes32 => address) private _pendingActiveController;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted in `createRoute` and `createRouteWithController`.
    event RouteCreated(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed target,
        uint32 routeType,
        bool isActive,
        address activeController
    );

    /// @dev Emitted in `activateRoute` and `deactivateRoute` when `isActive` changes.
    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        bool isActive
    );

    /// @dev Emitted in `freezeRouteBook` when the route book is frozen for an XNS name.
    event RouteBookFrozen(bytes32 indexed xnsNameHash, string canonicalXNSName);

    /// @dev Emitted in `initiateActiveControllerTransfer`.
    event ActiveControllerTransferInitiated(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed pendingActiveController
    );

    /// @dev Emitted in `acceptActiveController`.
    event ActiveControllerTransferAccepted(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address previousActiveController,
        address indexed newActiveController
    );

    /// @dev Emitted in `cancelActiveControllerTransfer`.
    event ActiveControllerTransferCancelled(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed cancelledPendingActiveController
    );

    /// @dev Emitted in `renounceActiveControl`.
    event ActiveControllerRenounced(
        bytes32 indexed xnsNameHash,
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

    /// @notice Create a route `[xnsName]/[routeScope:][routeLabel]` with `isActive = true` and
    /// `activeController` set to the current XNS name owner.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner for `xnsName`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy local character rules.
    /// - `routeLabel` must be a non-empty string.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - The route key must not already exist.
    ///
    /// On success, adds the route key to `_routeKeysByXNSName` for `xnsName`, queryable via
    /// `getRouteKeys`.
    /// Note: Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
    ///
    /// @param xnsName The XNS name that owns the route space, e.g. "xns.action".
    /// @param routeScope Optional path segment before `:`; non-empty must pass local route scope
    /// rules ([a-z0-9-], max length 20); empty means `xnsName/routeLabel` only (no `:` in the route).
    /// @param routeLabel Required route label ([a-z0-9-], max length 32).
    /// @param target Target address for `routeType`; must be non-zero (`address(0)` is reserved
    /// for non-existent route).
    /// @param routeType Parser hint for how to interpret `target` (off-chain semantics).
    function createRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);
        _createRoute(
            canonicalXNSName,
            routeScope,
            routeLabel,
            target,
            routeType,
            true, // isActive
            XNS.getAddress(canonicalXNSName) // activeController
        );
    }

    /// @notice Same as `createRoute` but with explicit `isActive` and `activeController`.
    /// Use when toggling `isActive` should be delegated to another account.
    ///
    /// Same requirements as `createRoute`, plus:
    /// - `activeController` must not be `address(0)`.
    ///
    /// @param isActive Initial value for stored `isActive`.
    /// @param activeController Account that may toggle `isActive` via `activateRoute` / `deactivateRoute`.
    function createRouteWithController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool isActive,
        address activeController
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);
        _createRoute(
            canonicalXNSName,
            routeScope,
            routeLabel,
            target,
            routeType,
            isActive,
            activeController
        );
    }

    /// @dev Shared implementation for `createRoute` and `createRouteWithController`.
    function _createRoute(
        string memory canonicalXNSName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool isActive,
        address activeController
    ) private {
        _validateRouteScopeAndLabel(routeScope, routeLabel);

        require(target != address(0), "XNSRoutes: invalid target");
        require(activeController != address(0), "XNSRoutes: invalid active controller");

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        require(!_routeBookFrozen[nameKey], "XNSRoutes: route book frozen");

        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        require(_routes[routeKey].target == address(0), "XNSRoutes: route already exists");

        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: isActive,
            activeController: activeController
        });

        _routeKeysByXNSName[nameKey].push(routeKey);

        emit RouteCreated(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            target,
            routeType,
            isActive,
            activeController
        );
    }

    /// @notice Mark an existing route as active.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be `record.activeController`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    /// - The route must exist.
    ///
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes.
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
    /// Emits `RouteActiveStatusUpdated` only when `isActive` changes.
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
    function _updateRouteActiveStatus(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        bool active
    ) private {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);

        _validateRouteScopeAndLabel(routeScope, routeLabel);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != RENOUNCED_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                active
            );
        }
    }

    /// @notice Start a two-step transfer of `activeController` to `newActiveController`.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current `activeController`.
    /// - The route must exist and active control must not be renounced.
    /// - `newActiveController` must not be zero, the current controller, or
    ///   `RENOUNCED_ACTIVE_CONTROLLER` (use `renounceActiveControl` instead).
    ///
    /// Replaces any existing pending transfer for this route.
    ///
    /// @param newActiveController Account that must call `acceptActiveController` to complete the transfer.
    function initiateActiveControllerTransfer(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address newActiveController
    ) external {
        (
            string memory canonicalXNSName,
            bytes32 nameKey,
            bytes32 routeKey,
            RouteRecord storage record
        ) = _requireMutableActiveControllerRoute(xnsName, routeScope, routeLabel);

        require(newActiveController != address(0), "XNSRoutes: invalid active controller");
        require(
            newActiveController != RENOUNCED_ACTIVE_CONTROLLER,
            "XNSRoutes: use renounceActiveControl"
        );
        require(newActiveController != record.activeController, "XNSRoutes: same active controller");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        _pendingActiveController[routeKey] = newActiveController;

        emit ActiveControllerTransferInitiated(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            newActiveController
        );
    }

    /// @notice Complete a pending `activeController` transfer.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the pending `newActiveController` from `initiateActiveControllerTransfer`.
    /// - The route must exist and active control must not be renounced.
    function acceptActiveController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        (
            string memory canonicalXNSName,
            bytes32 nameKey,
            bytes32 routeKey,
            RouteRecord storage record
        ) = _requireMutableActiveControllerRoute(xnsName, routeScope, routeLabel);

        address pending = _pendingActiveController[routeKey];
        require(pending != address(0), "XNSRoutes: no pending transfer");
        require(msg.sender == pending, "XNSRoutes: not pending active controller");

        address previous = record.activeController;
        record.activeController = pending;
        delete _pendingActiveController[routeKey];

        emit ActiveControllerTransferAccepted(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            previous,
            pending
        );
    }

    /// @notice Cancel a pending `activeController` transfer.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current `activeController`.
    /// - A pending transfer must exist.
    function cancelActiveControllerTransfer(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        (
            string memory canonicalXNSName,
            bytes32 nameKey,
            bytes32 routeKey,
            RouteRecord storage record
        ) = _requireMutableActiveControllerRoute(xnsName, routeScope, routeLabel);

        address pending = _pendingActiveController[routeKey];
        require(pending != address(0), "XNSRoutes: no pending transfer");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        delete _pendingActiveController[routeKey];

        emit ActiveControllerTransferCancelled(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            pending
        );
    }

    /// @notice Permanently renounce active control: sets `activeController` to
    /// `RENOUNCED_ACTIVE_CONTROLLER` and `isActive` to false.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current `activeController`.
    /// - Active control must not already be renounced.
    ///
    /// Clears any pending transfer. Emits `RouteActiveStatusUpdated` if `isActive` changes.
    function renounceActiveControl(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        (
            string memory canonicalXNSName,
            bytes32 nameKey,
            bytes32 routeKey,
            RouteRecord storage record
        ) = _requireMutableActiveControllerRoute(xnsName, routeScope, routeLabel);

        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        delete _pendingActiveController[routeKey];

        if (record.isActive) {
            record.isActive = false;
            emit RouteActiveStatusUpdated(
                nameKey,
                routeKey,
                canonicalXNSName,
                routeScope,
                routeLabel,
                false
            );
        }

        record.activeController = RENOUNCED_ACTIVE_CONTROLLER;

        emit ActiveControllerRenounced(
            nameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel
        );
    }

    /// @notice Freeze the entire route book under an XNS name forever.
    ///
    /// **Effects (irreversible):**
    /// - No new routes may be added under `xnsName`.
    /// - Existing routes are unchanged; `activeController` can still toggle `isActive`.
    ///
    /// Requires `msg.sender` to be the XNS name owner of `xnsName`.
    ///
    /// Emits `RouteBookFrozen` only if the route book was not already frozen.
    ///
    /// @param xnsName The XNS name whose route book to freeze.
    function freezeRouteBook(string calldata xnsName) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);

        bytes32 nameKey = _xnsNameKey(canonicalXNSName);
        if (!_routeBookFrozen[nameKey]) {
            _routeBookFrozen[nameKey] = true;
            emit RouteBookFrozen(nameKey, canonicalXNSName);
        }
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Reads stored route record data by `routeKey`.
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param routeKey Canonical route storage key.
    /// @return record The route record (target, routeType, isActive, activeController).
    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record) {
        RouteRecord storage s = _routes[routeKey];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
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
    /// @return record The route record (target, routeType, isActive, activeController).
    function getRouteRecord(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record) {
        return _getRouteRecord(xnsName, routeScope, routeLabel);
    }

    /// @notice Reads stored route record data by route string (`splitRoute`).
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param route Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail.
    /// @return record The route record (target, routeType, isActive, activeController).
    function getRouteRecord(string calldata route) external view returns (RouteRecord memory record) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRoute(route);
        return _getRouteRecord(xnsName, routeScope, routeLabel);
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
        return _resolveRouteIfActive(xnsName, routeScope, routeLabel);
    }

    /// @notice Resolves an active route to `(target, routeType)` by route string (`splitRoute`).
    ///
    /// **Requirements:** same as `resolveRouteIfActive(xnsName, routeScope, routeLabel)`.
    ///
    /// @param route Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail.
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRouteIfActive(
        string calldata route
    ) external view returns (address target, uint32 routeType) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRoute(route);
        return _resolveRouteIfActive(xnsName, routeScope, routeLabel);
    }

    /// @notice Resolves a route to `(target, routeType)` regardless of `isActive`.
    ///
    /// **Requirements:**
    /// - The route must exist (`target != address(0)`).
    /// - Non-empty `routeScope` and `routeLabel` must satisfy character rules.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope (may be empty).
    /// @param routeLabel Route label.
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType) {
        return _resolveRoute(xnsName, routeScope, routeLabel);
    }

    /// @notice Resolves a route to `(target, routeType)` by route string (`splitRoute`).
    ///
    /// **Requirements:** same as `resolveRoute(xnsName, routeScope, routeLabel)`.
    ///
    /// @param route Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail.
    /// @return target Resolved target address.
    /// @return routeType Parser hint for how to interpret `target`.
    function resolveRoute(
        string calldata route
    ) external view returns (address target, uint32 routeType) {
        (string memory xnsName, string memory routeScope, string memory routeLabel) =
            _splitRoute(route);
        return _resolveRoute(xnsName, routeScope, routeLabel);
    }

    /// @notice Returns whether the entire route book under `xnsName` is frozen.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @return frozen True if the route book is frozen.
    function isRouteBookFrozen(string calldata xnsName) external view returns (bool frozen) {
        return _routeBookFrozen[_xnsNameKey(xnsName)];
    }

    /// @notice Pending `acceptActiveController` recipient for a route, or `address(0)` if none.
    function pendingActiveController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address pending) {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        _validateRouteScopeAndLabel(routeScope, routeLabel);
        return _pendingActiveController[_routeKey(canonicalXNSName, routeScope, routeLabel)];
    }

    /// @notice Number of route keys registered under `xnsName`.
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

    /// @notice Parses a route into `(xnsName, routeScope, routeLabel)`.
    /// Example: `bro.xns/eth:my-wallet` -> `(bro.xns, eth, my-wallet)`.
    /// Useful when calling tuple-based mutating functions (`createRoute`, etc.).
    ///
    /// A route is `xnsName "/" routeIdentifier` — not a parametrized route (no `/params…` tail).
    /// Does not validate segments; malformed input may still parse but fail downstream.
    ///
    /// Requires `route` to contain at least one `/`.
    ///
    /// @param route Route (not a parametrized route), e.g. `bob.xns/eth:transfer-usdt`.
    /// @return xnsName Segment before the first `/`.
    /// @return routeScope Segment before the first `:` in the route identifier, or empty if there is no `:`.
    /// @return routeLabel Segment after `:` if `routeScope` is present, else the whole route identifier after `/`.
    function splitRoute(
        string calldata route
    )
        external
        pure
        returns (string memory xnsName, string memory routeScope, string memory routeLabel)
    {
        return _splitRoute(route);
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

    /// @dev Validates scope/label, loads an existing route with mutable active control.
    function _requireMutableActiveControllerRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    )
        private
        view
        returns (
            string memory canonicalXNSName,
            bytes32 nameKey,
            bytes32 routeKey,
            RouteRecord storage record
        )
    {
        canonicalXNSName = _canonicalizeXNSName(xnsName);
        _validateRouteScopeAndLabel(routeScope, routeLabel);
        nameKey = _xnsNameKey(canonicalXNSName);
        routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        record = _routes[routeKey];
        require(record.target != address(0), "XNSRoutes: route not found");
        require(
            record.activeController != RENOUNCED_ACTIVE_CONTROLLER,
            "XNSRoutes: active control renounced"
        );
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
            activeController: s.activeController
        });
    }

    function _resolveRouteIfActive(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel
    ) private view returns (address target, uint32 routeType) {
        RouteRecord memory record = _getRouteRecord(xnsName, routeScope, routeLabel);
        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.isActive, "XNSRoutes: route inactive");
        return (record.target, record.routeType);
    }

    function _resolveRoute(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel
    ) private view returns (address target, uint32 routeType) {
        RouteRecord memory record = _getRouteRecord(xnsName, routeScope, routeLabel);
        require(record.target != address(0), "XNSRoutes: route not found");
        return (record.target, record.routeType);
    }

    /// @dev Splits `route` at the first `/`, then at the first `:` in the route identifier.
    function _splitRoute(
        string calldata route
    ) private pure returns (string memory xnsName, string memory routeScope, string memory routeLabel) {
        bytes calldata b = bytes(route);
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
        require(foundSlash, "XNSRoutes: invalid route");

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
        require(end >= start, "XNSRoutes: invalid route");
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

    /// @dev Returns keccak256 of canonical route: `{canonicalXNSName}/{routeLabel}` when
    /// `routeScope` is empty, else `{canonicalXNSName}/{routeScope}:{routeLabel}`.
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

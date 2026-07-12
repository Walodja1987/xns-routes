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
/// identifiers, so-called **routes**, to any Ethereum address. Routes may point to EOAs and
/// smart contracts, including helper/view contracts returning arbitrary data, such as Bitcoin
/// or Solana addresses, calldata, or other information. Registration is free and reserved for
/// the XNS name owner only.
///
/// Route format: `xnsName/[routeScope:]routeLabel`
///
/// - **xnsName** – XNS name that owns the route book (e.g. `bob.xns`, `contracts.aave`).
/// - **routeScope** – optional segment before `:` (1–20 chars if present).
/// - **routeLabel** – required slug (1–32 chars).
///
/// `routeScope` and `routeLabel` must follow the same character and hyphenation rules as XNS names:
/// - Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
/// - Cannot start or end with '-'
/// - Cannot contain consecutive hyphens ('--')
///
/// Routes may include an optional `/params...` suffix, intended for use by off-chain parsers.
/// String helpers (`splitRoute`, `getRouteRecord(string)`, `resolveRoute(string)`,
/// `resolveRouteIfActive(string)`) strip at the second `/` and ignore that tail. Params are
/// neither stored nor processed on-chain.
///
/// Examples:
/// - `alice.og/my-sub-wallet` (route without routeScope)
/// - `contracts.aave/eth:v3-pool-contract` (route with routeScope)
/// - `safe.uni/uniswap:approve-usdt/amount=10` (route with routeScope and params)
///
/// **Route record**
/// Each route is represented as a structured route record with the following fields:
/// - `target` — EOA or contract the route resolves to.
/// - `routeType` — off-chain parser hint (semantics agreed off-chain; examples below).
/// - `isActive` — whether parsers should treat the route as usable.
/// - `activeController` — account that may toggle `isActive`.
/// - `routeScope` and `routeLabel` — immutable route path segments stored at creation.
///
/// `target` and `routeType` are fixed at creation; routes cannot be deleted.
/// but can be deactivated.
///
/// **Route type examples**
/// - `0` = `target` is the answer (EOA/smart contract)
/// - `1` = `target` must be queried (e.g. for a Bitcoin or Solana address)
/// - `2` = `target` returns executable calldata
/// 
/// The exact semantics of `routeType` are agreed off-chain and are not enforced by the contract.
///
/// **Active status & activeController**
/// - The `activeController` is the account that controls whether a route is active or not.
/// - The `activeController` can change the route's active status, transfer this control to someone else,
///   or give up control permanently (which locks the route's status).
/// - Inactive routes (e.g. deprecated or paused) should not be resolved by off-chain parsers;
///   use `resolveRouteIfActive` to resolve active routes only.
/// - At create: `createRoute` sets `activeController` to the XNS name owner;
///   `createRouteWithController` accepts an explicit controller; both default to `isActive = true`.
/// - `activeController` must not be `address(0)`.
/// - The `isActive` status may be locked by setting `activeController` equal to `NO_ACTIVE_CONTROLLER`
///   address. This will permanently lock the route's `isActive` status.
///
/// **Route book freeze**
/// - The XNS name owner may freeze the route book permanently by calling `freezeRouteBook`
/// - Freezing a route book is irreversible
/// - Under a frozen route book, no new routes can be created; existing routes remain unchanged;
///   `activeController` can still toggle `isActive` on existing routes unless renounced.
///
/// **Resolution & indexing**
/// - Forward: route -> `target` via `resolveRouteIfActive` (requires `isActive`) or
///   `resolveRoute` (ignores `isActive`). No reverse lookup because many routes may point to the same `target`.
/// - Bare names like `bob` normalize to `bob.x` (canonical XNS name). `routeKey` = hash of canonical route.
/// - The route list can be queried with `getRouteKeyCount`, `getRouteKeys`, and `getRouteEntries`.
///   `getRouteEntries` returns each route's key plus stored `routeScope`, `routeLabel`, and metadata.
contract XNSRoutes {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    /// @dev Data structure to store route metadata.
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        address activeController;
        string routeScope;
        string routeLabel;
    }

    /// @notice Paginated route listing entry: storage key plus full stored route metadata.
    struct RouteEntry {
        bytes32 routeKey;
        RouteRecord record;
    }

    // -------------------------------------------------------------------------
    // Constants and storage variables
    // -------------------------------------------------------------------------

    /// @notice Special sentinel value for `activeController` indicating permanent
    /// renouncement of control. When a route's `activeController` is set to this address,
    /// its `isActive` status is locked and cannot be changed.
    ///
    /// Uses 0x…dEaD rather than `address(0)` so `address(0)` can stay reserved as an
    /// invalid / unset controller (guards against accidentally passing Solidity's default
    /// `address` value at create or transfer).
    address public constant NO_ACTIVE_CONTROLLER =
        address(0x000000000000000000000000000000000000dEaD);

    /// @notice XNS registry this contract calls for name resolution.
    IXNSMinimal public immutable XNS;

    /// keccak256(bytes(canonical xnsName)) => true if the route book for an XNS name is frozen
    mapping(bytes32 => bool) private _routeBookFrozen;

    /// route key => route record
    mapping(bytes32 => RouteRecord) private _routes;

    /// keccak256(bytes(canonical xnsName)) => route keys created under that XNS name
    mapping(bytes32 => bytes32[]) private _routeKeysByXNSName;

    /// route key => pending new `activeController` or `address(0)` if none
    mapping(bytes32 => address) private _pendingActiveController;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted in `createRoute` and `createRouteWithController`.
    event RouteCreated(
        bytes32 indexed xnsNameKey,
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
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        bool isActive
    );

    /// @dev Emitted in `freezeRouteBook` when the route book is frozen for an XNS name.
    event RouteBookFrozen(bytes32 indexed xnsNameKey, string canonicalXNSName);

    /// @dev Emitted in `initiateActiveControllerTransfer`.
    event ActiveControllerTransferInitiated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed pendingActiveController
    );

    /// @dev Emitted in `acceptActiveController`.
    event ActiveControllerTransferAccepted(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address previousActiveController,
        address indexed newActiveController
    );

    /// @dev Emitted in `cancelActiveControllerTransfer`.
    event ActiveControllerTransferCancelled(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed cancelledPendingActiveController
    );

    /// @dev Emitted in `renounceActiveControl`.
    event ActiveControllerRenounced(
        bytes32 indexed xnsNameKey,
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
    /// - `xnsContract` must not be the zero address.
    /// - `msg.value` must be exactly 0.001 ETH for the registration of `routes.xns`.
    ///
    /// @param xnsContract XNS registry address.
    constructor(address xnsContract) payable {
        require(xnsContract != address(0), "XNSRoutes: 0x XNS address");
        XNS = IXNSMinimal(xnsContract);
        XNS.registerName{value: msg.value}("routes", "xns");
    }

    // -------------------------------------------------------------------------
    // State-modifying functions
    // -------------------------------------------------------------------------

    /// @notice Create a route `xnsName/[routeScope:]routeLabel`. `isActive` is set to true and
    /// `activeController` to the current XNS name owner.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner of `xnsName`.
    /// - Non-empty `routeScope` and `routeLabel` must satisfy local character rules.
    /// - `routeLabel` must be a non-empty string.
    /// - `target` must not be the zero address.
    /// - The route book for `xnsName` must not be frozen.
    /// - The route key must not already exist.
    ///
    /// On success:
    /// - Adds the route key to `_routeKeysByXNSName` for `xnsName`, queryable via
    ///   `getRouteKeys` and `getRouteEntries`.
    /// - Emits `RouteCreated`.
    ///
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

    /// @notice Same as `createRoute` but with an explicit `activeController`.
    /// Use when toggling `isActive` should be delegated to another account.
    ///
    /// Same requirements as `createRoute`, plus:
    /// - `activeController` must not be `address(0)`.
    ///
    /// Note: If `activeController` is set to `NO_ACTIVE_CONTROLLER`, the route's `isActive` status is locked
    /// and cannot be changed after creation.
    ///
    /// @param activeController Account that may toggle `isActive` via `activateRoute` / `deactivateRoute`.
    function createRouteWithController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        address activeController
    ) external {
        string memory canonicalXNSName = _requireXNSNameOwner(xnsName);
        _createRoute(
            canonicalXNSName,
            routeScope,
            routeLabel,
            target,
            routeType,
            true, // isActive
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

        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        require(!_routeBookFrozen[xnsNameKey], "XNSRoutes: route book frozen");

        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        require(_routes[routeKey].target == address(0), "XNSRoutes: route already exists");

        _routes[routeKey] = RouteRecord({
            target: target,
            routeType: routeType,
            isActive: isActive,
            activeController: activeController,
            routeScope: routeScope,
            routeLabel: routeLabel
        });

        _routeKeysByXNSName[xnsNameKey].push(routeKey);

        emit RouteCreated(
            xnsNameKey,
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
    /// - `msg.sender` must be the current `activeController`.
    /// - The route must exist and active control must not be renounced.
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
    /// - `msg.sender` must be the current `activeController`.
    /// - The route must exist and active control must not be renounced.
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
        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != NO_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        if (record.isActive != active) {
            record.isActive = active;
            emit RouteActiveStatusUpdated(
                xnsNameKey,
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
    ///   `NO_ACTIVE_CONTROLLER` (use `renounceActiveControl` instead).
    ///
    /// Replaces any existing pending transfer for this route.
    ///
    /// Emits `ActiveControllerTransferInitiated`.
    ///
    /// @param newActiveController Account that must call `acceptActiveController` to complete the transfer.
    function initiateActiveControllerTransfer(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address newActiveController
    ) external {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != NO_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(newActiveController != address(0), "XNSRoutes: invalid active controller");
        require(newActiveController != NO_ACTIVE_CONTROLLER, "XNSRoutes: use renounceActiveControl");
        require(newActiveController != record.activeController, "XNSRoutes: same active controller");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        _pendingActiveController[routeKey] = newActiveController;

        emit ActiveControllerTransferInitiated(
            xnsNameKey,
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
    /// - A pending transfer must exist.
    ///
    /// Emits `ActiveControllerTransferAccepted`.
    ///
    function acceptActiveController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        address pending = _pendingActiveController[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != NO_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(pending != address(0), "XNSRoutes: no pending transfer");
        require(msg.sender == pending, "XNSRoutes: not pending active controller");

        address previous = record.activeController;
        record.activeController = pending;
        delete _pendingActiveController[routeKey];

        emit ActiveControllerTransferAccepted(
            xnsNameKey,
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
    /// - The route must exist and active control must not be renounced.
    /// - A pending transfer must exist.
    ///
    /// Emits `ActiveControllerTransferCancelled`.
    ///
    function cancelActiveControllerTransfer(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];
        address pending = _pendingActiveController[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != NO_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(pending != address(0), "XNSRoutes: no pending transfer");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        delete _pendingActiveController[routeKey];

        emit ActiveControllerTransferCancelled(
            xnsNameKey,
            routeKey,
            canonicalXNSName,
            routeScope,
            routeLabel,
            pending
        );
    }

    /// @notice Permanently renounce active control: sets `activeController` to
    /// `NO_ACTIVE_CONTROLLER`. `isActive` is left unchanged and can no longer be toggled.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the current `activeController`.
    /// - The route must exist and active control must not be renounced.
    ///
    /// Clears any pending transfer.
    ///
    /// Emits `ActiveControllerRenounced`.
    function renounceActiveControl(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external {
        string memory canonicalXNSName = _canonicalizeXNSName(xnsName);
        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        bytes32 routeKey = _routeKey(canonicalXNSName, routeScope, routeLabel);
        RouteRecord storage record = _routes[routeKey];

        require(record.target != address(0), "XNSRoutes: route not found");
        require(record.activeController != NO_ACTIVE_CONTROLLER, "XNSRoutes: active control renounced");
        require(msg.sender == record.activeController, "XNSRoutes: not active controller");

        delete _pendingActiveController[routeKey];

        record.activeController = NO_ACTIVE_CONTROLLER;

        emit ActiveControllerRenounced(
            xnsNameKey,
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

        bytes32 xnsNameKey = _xnsNameKey(canonicalXNSName);
        if (!_routeBookFrozen[xnsNameKey]) {
            _routeBookFrozen[xnsNameKey] = true;
            emit RouteBookFrozen(xnsNameKey, canonicalXNSName);
        }
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Reads stored route record data by `routeKey`.
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param routeKey Canonical route storage key.
    /// @return record The route record (target, routeType, isActive, activeController, routeScope, routeLabel).
    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record) {
        RouteRecord storage s = _routes[routeKey];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            activeController: s.activeController,
            routeScope: s.routeScope,
            routeLabel: s.routeLabel
        });
    }

    /// @notice Reads stored route record data by `(xnsName, routeScope, routeLabel)`.
    /// `record.target == address(0)` means that record does not exist.
    ///
    /// @param xnsName The XNS name that owns the route space.
    /// @param routeScope Route scope (may be empty).
    /// @param routeLabel Route label.
    /// @return record The route record (target, routeType, isActive, activeController, routeScope, routeLabel).
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
    /// @param route Route or parametrized route, e.g. `bob.xns/eth:my-wallet` or
    /// `bob.xns/eth:my-wallet/amount=10` (tail after the second `/` is ignored).
    /// @return record The route record (target, routeType, isActive, activeController, routeScope, routeLabel).
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
    /// @param route Route or parametrized route, e.g. `bob.xns/eth:my-wallet` or
    /// `bob.xns/eth:my-wallet/amount=10` (tail after the second `/` is ignored).
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
    /// Requires that the route exists (`target != address(0)`).
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
    /// @param route Route or parametrized route, e.g. `bob.xns/eth:my-wallet` or
    /// `bob.xns/eth:my-wallet/amount=10` (tail after the second `/` is ignored).
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
        return _pendingActiveController[_routeKey(xnsName, routeScope, routeLabel)];
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
        return _sliceRouteKeys(_routeKeysByXNSName[_xnsNameKey(xnsName)], start, end);
    }

    /// @notice Returns `entries[start:end]` for routes registered under `xnsName` (`end` is
    /// exclusive). Each entry includes the route key plus stored `routeScope`, `routeLabel`, and
    /// metadata. Pagination rules match `getRouteKeys`.
    ///
    /// Requires `start <= end`.
    ///
    /// @param xnsName The XNS name to list routes for.
    /// @param start The start index (inclusive).
    /// @param end The end index (exclusive); may exceed array length.
    /// @return entries The route entries.
    function getRouteEntries(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries) {
        bytes32[] memory keys = _sliceRouteKeys(_routeKeysByXNSName[_xnsNameKey(xnsName)], start, end);
        uint256 n = keys.length;
        entries = new RouteEntry[](n);
        for (uint256 i = 0; i < n; ++i) {
            bytes32 routeKey = keys[i];
            RouteRecord storage s = _routes[routeKey];
            entries[i] = RouteEntry({
                routeKey: routeKey,
                record: RouteRecord({
                    target: s.target,
                    routeType: s.routeType,
                    isActive: s.isActive,
                    activeController: s.activeController,
                    routeScope: s.routeScope,
                    routeLabel: s.routeLabel
                })
            });
        }
    }

    /// @notice Parses a route into `(xnsName, routeScope, routeLabel)`.
    /// Example: `bro.xns/eth:my-wallet` -> `(bro.xns, eth, my-wallet)`.
    /// Useful when calling tuple-based mutating functions (e.g. `resolveRoute`, `activateRoute`).
    ///
    /// A route is `xnsName/[routeScope:]routeLabel`. An optional `/params...` tail after a second
    /// `/` is stripped and ignored (not validated or returned).
    /// Does not validate segments; malformed input may still parse but fail downstream.
    ///
    /// Requires `route` to contain at least one `/`.
    ///
    /// @param route Route or parametrized route, e.g. `bob.xns/eth:transfer-usdt` or
    /// `bob.xns/eth:transfer-usdt/amount=10`.
    /// @return xnsName Segment before the first `/`.
    /// @return routeScope Segment before the first `:` in the path after the first `/` (before any
    /// params `/`), or empty if there is no `:`.
    /// @return routeLabel Segment after `:` if `routeScope` is present, else the whole path segment
    /// after the first `/` (before any params `/`).
    function splitRoute(
        string calldata route
    )
        external
        pure
        returns (string memory xnsName, string memory routeScope, string memory routeLabel)
    {
        return _splitRoute(route);
    }

    /// @dev Splits `route` at the first `/`, truncates any `/params...` tail at the second `/`,
    /// then splits the remaining path at the first `:`.
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

        // Truncate at the second `/` (start of optional params tail).
        uint256 routePathEnd = n;
        for (uint256 i = routePathStart; i < n; ++i) {
            if (b[i] == 0x2f) {
                routePathEnd = i;
                break;
            }
        }

        if (routePathStart >= routePathEnd) {
            return (xnsName, "", "");
        }

        bytes calldata routePath = b[routePathStart:routePathEnd];

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

    /// @dev Derives key and returns the route record (no scope/label validation).
    function _getRouteRecord(
        string memory xnsName,
        string memory routeScope,
        string memory routeLabel
    ) private view returns (RouteRecord memory record) {
        RouteRecord storage s = _routes[_routeKey(xnsName, routeScope, routeLabel)];
        record = RouteRecord({
            target: s.target,
            routeType: s.routeType,
            isActive: s.isActive,
            activeController: s.activeController,
            routeScope: s.routeScope,
            routeLabel: s.routeLabel
        });
    }

    /// @dev Returns `arr[start:end]` with the same clamping rules as `getRouteKeys`.
    function _sliceRouteKeys(
        bytes32[] storage arr,
        uint256 start,
        uint256 end
    ) private view returns (bytes32[] memory keys) {
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

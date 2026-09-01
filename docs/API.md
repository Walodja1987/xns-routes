# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


A simple immutable named-address endpoint registry attached to XNS names.

XNS name owners can create named routes under their XNS name which resolve to Ethereum
addresses. Routes may point to EOAs or smart contracts.

Route format:

    label AT namespace/route

Examples:
- `alice AT pay/treasury`
- `alice AT pay/treasury-eth`
- `alice AT pay/treasury-arb`
- `aave AT defi/v3-pool`

The route portion must:
- Be 1–32 characters long.
- Consist only of [a-z0-9-].
- Not start or end with '-'.
- Not contain consecutive hyphens ('--').

Routes may optionally include an application-layer `/params...` suffix when using the
string-based view functions. Anything after the second `/` is ignored by this contract.

Example:

    alice AT pay/payment/amount=10

resolves the stored route:

    alice AT pay/payment

Params are not validated, stored, interpreted, or processed on-chain.

### Route record

Each route stores:
- `target` — immutable Ethereum address the route points to.
- `routeType` — generic off-chain interpretation hint.
- `isActive` — whether applications should currently treat the route as usable.
- `activeController` — account authorized to toggle `isActive`.
- `routeLabel` — immutable route label.

`target`, `routeType`, and `routeLabel` are immutable after route creation.

The exact semantics of `routeType` are intentionally not enforced by this contract.
Applications may define their own interpretation conventions.

Example route types:
- `0` = target address is the endpoint.
- `1` = target is a resolver/view contract.
- `2` = target is interpreted according to another application-level convention.

### Active status

A route starts active by default.

Its `activeController` may:
- Activate or deactivate the route.
- Transfer active control using a two-step process.
- Permanently renounce active control.

Renouncing active control sets `activeController` to `NO_ACTIVE_CONTROLLER` and permanently
locks the current `isActive` state.

### Route-book freeze

The XNS name owner may permanently freeze the entire route book belonging to their XNS name.

After freezing:
- No new routes may be created.
- Existing routes remain unchanged.
- Existing active controllers may continue toggling their routes unless active control
  has separately been renounced.

### Resolution

Efficient contract integrations should use the separate:

    (label, namespace, routeLabel)

parameters.

Convenience view functions additionally support complete strings such as:

    alice AT pay/treasury

No reverse lookup is provided because multiple routes may point to the same target.

**Resolution & indexing**
- Forward: route -> `target` via `resolveRouteIfActive` (requires `isActive`) or
  `resolveRoute` (ignores `isActive`).
- XNS name key: `keccak256(abi.encodePacked(label, " AT ", namespace))`.
- Route key: `keccak256(abi.encode(xnsNameKey, keccak256(bytes(routeLabel))))`.
- The route list can be queried with `getRouteKeyCount`, `getRouteKeys`, and `getRouteEntries`.
  `getRouteEntries` returns each route's key plus stored `routeLabel` and metadata.






## Functions

### createRoute


Creates an immutable route under an XNS name.

The route starts active and `activeController` is set to the current XNS name owner.

Example:

    createRoute("alice", "pay", "treasury", target, 0)

creates:

    alice AT pay/treasury

Requirements:
- `msg.sender` must own `label AT namespace`.
- `routeLabel` must be valid.
- `target` must not be address(0).
- The route book must not be frozen.
- The route must not already exist.

Emits `RouteCreated`.

```solidity
function createRoute(string label, string namespace, string routeLabel, address target, uint32 routeType) external
```




### createRouteWithController


Creates an immutable route with an explicitly specified active controller.

Same requirements as `createRoute`, plus:
- `activeController` must not be `address(0)`.

Note: If `activeController` is set to `NO_ACTIVE_CONTROLLER`, the route's `isActive` status is
locked and cannot be changed after creation.

Emits `RouteCreated`.

```solidity
function createRouteWithController(string label, string namespace, string routeLabel, address target, uint32 routeType, address activeController) external
```




### activateRoute


Activates an existing route.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function activateRoute(string label, string namespace, string routeLabel) external
```




### deactivateRoute


Deactivates an existing route.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function deactivateRoute(string label, string namespace, string routeLabel) external
```




### initiateActiveControllerTransfer


Starts a two-step active-controller transfer.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.
- `newActiveController` must not be zero, the current controller, or
  `NO_ACTIVE_CONTROLLER` (use `renounceActiveControl` instead).

Replaces any existing pending transfer for this route.

Emits `ActiveControllerTransferInitiated`.

```solidity
function initiateActiveControllerTransfer(string label, string namespace, string routeLabel, address newActiveController) external
```




### acceptActiveController


Accepts a pending active-controller transfer.

**Requirements:**
- `msg.sender` must be the pending `newActiveController` from `initiateActiveControllerTransfer`.
- The route must exist and active control must not be renounced.
- A pending transfer must exist.

Emits `ActiveControllerTransferAccepted`.

```solidity
function acceptActiveController(string label, string namespace, string routeLabel) external
```




### cancelActiveControllerTransfer


Cancels a pending active-controller transfer.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.
- A pending transfer must exist.

Emits `ActiveControllerTransferCancelled`.

```solidity
function cancelActiveControllerTransfer(string label, string namespace, string routeLabel) external
```




### renounceActiveControl


Permanently renounces active control for a route.

The current `isActive` status remains unchanged and becomes permanently locked.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.

Clears any pending transfer.

Emits `ActiveControllerRenounced`.

```solidity
function renounceActiveControl(string label, string namespace, string routeLabel) external
```




### freezeRouteBook


Permanently freezes the route book associated with an XNS name.

After freezing no additional routes may be created.

Existing routes and their active-controller mechanics remain unchanged.

Requires `msg.sender` to own `label AT namespace`.

Emits `RouteBookFrozen` only if the route book was not already frozen.

```solidity
function freezeRouteBook(string label, string namespace) external
```




### freezeRouteBook


Permanently freezes the route book for `label AT namespace`.

Same requirements and effects as `freezeRouteBook(label, namespace)`.

Emits `RouteBookFrozen` only if the route book was not already frozen.

```solidity
function freezeRouteBook(string xnsName) external
```




### getRouteRecord


Returns a route record directly by route key.

`record.target == address(0)` means the route does not exist.

```solidity
function getRouteRecord(bytes32 routeKey) external view returns (struct XNSRoutes.RouteRecord record)
```




### getRouteRecord


Returns a route record using separate XNS components.

```solidity
function getRouteRecord(string label, string namespace, string routeLabel) external view returns (struct XNSRoutes.RouteRecord record)
```




### getRouteRecord


Returns a route record using a complete route string.

Example:

    alice AT pay/treasury

An optional suffix after the second `/` is ignored.

```solidity
function getRouteRecord(string route) external view returns (struct XNSRoutes.RouteRecord record)
```




### resolveRouteIfActive


Resolves an active route using separate XNS components.

```solidity
function resolveRouteIfActive(string label, string namespace, string routeLabel) external view returns (address target, uint32 routeType)
```




### resolveRouteIfActive


Resolves an active route using a complete route string.

Example:

    resolveRouteIfActive("alice AT pay/treasury")

```solidity
function resolveRouteIfActive(string route) external view returns (address target, uint32 routeType)
```




### resolveRoute


Resolves a route regardless of its active status.

```solidity
function resolveRoute(string label, string namespace, string routeLabel) external view returns (address target, uint32 routeType)
```




### resolveRoute


Resolves a route regardless of active status using a complete route string.

Example:

    resolveRoute("alice AT pay/treasury")

```solidity
function resolveRoute(string route) external view returns (address target, uint32 routeType)
```




### isRouteBookFrozen


Returns whether the route book belonging to an XNS name is frozen.

```solidity
function isRouteBookFrozen(string label, string namespace) external view returns (bool frozen)
```




### isRouteBookFrozen


Convenience overload accepting a complete XNS name.

Example:

    isRouteBookFrozen("alice AT pay")

```solidity
function isRouteBookFrozen(string xnsName) external view returns (bool frozen)
```




### pendingActiveController


Returns a route's pending active controller, or address(0) if none.

```solidity
function pendingActiveController(string label, string namespace, string routeLabel) external view returns (address pending)
```




### getRouteKeyCount


Returns the number of routes ever created under an XNS name.

```solidity
function getRouteKeyCount(string label, string namespace) external view returns (uint256 count)
```




### getRouteKeyCount


Convenience overload accepting `label AT namespace`.

```solidity
function getRouteKeyCount(string xnsName) external view returns (uint256 count)
```




### getRouteKeys


Returns route keys `[start:end]` for an XNS name.

`end` is exclusive and is clamped to the array length.

```solidity
function getRouteKeys(string label, string namespace, uint256 start, uint256 end) external view returns (bytes32[] keys)
```




### getRouteKeys


Convenience overload accepting `label AT namespace`.

```solidity
function getRouteKeys(string xnsName, uint256 start, uint256 end) external view returns (bytes32[] keys)
```




### getRouteEntries


Returns full route entries `[start:end]` for an XNS name.

```solidity
function getRouteEntries(string label, string namespace, uint256 start, uint256 end) external view returns (struct XNSRoutes.RouteEntry[] entries)
```




### getRouteEntries


Convenience overload accepting `label AT namespace`.

```solidity
function getRouteEntries(string xnsName, uint256 start, uint256 end) external view returns (struct XNSRoutes.RouteEntry[] entries)
```




### splitRoute


Parses a complete route string into:

    (label, namespace, routeLabel)

Example:

    alice AT pay/treasury

becomes:

    ("alice", "pay", "treasury")

An optional `/params...` suffix is ignored:

    alice AT pay/payment/amount=10

also returns:

    ("alice", "pay", "payment")

```solidity
function splitRoute(string route) external pure returns (string label, string namespace, string routeLabel)
```




### splitXNSName


Parses `label AT namespace`.

```solidity
function splitXNSName(string xnsName) external pure returns (string label, string namespace)
```




### isValidRouteLabel


Returns whether a route label satisfies the XNS Routes label rules.

```solidity
function isValidRouteLabel(string routeLabel) external pure returns (bool valid)
```





## Events

### RouteCreated




```solidity
event RouteCreated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, address target, uint32 routeType, bool isActive, address activeController)
```





### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, bool isActive)
```





### RouteBookFrozen




```solidity
event RouteBookFrozen(bytes32 xnsNameKey, string label, string namespace)
```





### ActiveControllerTransferInitiated




```solidity
event ActiveControllerTransferInitiated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, address pendingActiveController)
```





### ActiveControllerTransferAccepted




```solidity
event ActiveControllerTransferAccepted(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, address previousActiveController, address newActiveController)
```





### ActiveControllerTransferCancelled




```solidity
event ActiveControllerTransferCancelled(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, address cancelledPendingActiveController)
```





### ActiveControllerRenounced




```solidity
event ActiveControllerRenounced(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel)
```








## State Variables

### NO_ACTIVE_CONTROLLER


Sentinel indicating that active control has been permanently renounced.

`address(0)` remains reserved for invalid/unset controller values.

```solidity
address NO_ACTIVE_CONTROLLER
```





### XNS


XNSv2 registry used for name ownership resolution.

```solidity
contract IXNSMinimal XNS
```






## Types

### RouteRecord

```solidity
struct RouteRecord {
  address target;
  uint32 routeType;
  bool isActive;
  address activeController;
  string routeLabel;
```

Metadata associated with a route.






### RouteEntry

```solidity
struct RouteEntry {
  bytes32 routeKey;
  struct XNSRoutes.RouteRecord record;
```

Paginated route listing entry.








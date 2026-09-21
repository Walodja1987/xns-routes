# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


A simple named-endpoint registry attached to XNS names.

XNS name owners can create named routes under their XNS name which resolve to opaque
endpoint payloads (`bytes`). Routes may represent EVM addresses, other-chain addresses,
identifiers, or other application-defined data — interpreted via `routeType`.

Route format:

    label AT namespace/routeLabel

Examples:
- `alice AT pay/treasury`
- `alice AT pay/treasury-eth`
- `alice AT pay/treasury-arb`
- `aave AT defi/v3-pool`

The route label must:
- Be 1–32 characters long.
- Consist only of [a-z0-9-].
- Not start or end with '-'.
- Not contain consecutive hyphens ('--').

Application-layer parameters (e.g. `/amount=10`) are not part of the on-chain route format.
Callers must strip any such suffix before using string-based helpers.

### Route record

Each route stores:
- `target` — opaque endpoint payload (mutable until frozen); 1–256 bytes.
- `routeType` — generic off-chain interpretation hint (mutable until frozen).
- `isActive` — whether applications should currently treat the route as usable
  (toggled by the XNS name owner).
- `isFrozen` — whether this route's `target` / `routeType` are permanently locked.
- `routeLabel` — immutable route label.

`routeLabel` is immutable after route creation. `target` and `routeType` may be updated by
the XNS name owner until that route is frozen (`isFrozen`).

The exact semantics of `routeType` are intentionally not enforced by this contract.
Applications may define their own interpretation conventions.

Example route types:
- `0` = `target` is a 20-byte EVM address.
- `1` = `target` is a resolver/view contract address (20 bytes).
- `2` = `target` is interpreted according to another application-level convention
  (e.g. Bitcoin address UTF-8, Solana pubkey, etc.).

This contract does not validate `target` contents beyond non-empty and max length.

### Active status

A route starts active by default.

The XNS name owner may activate or deactivate the route at any time, including after the
route has been frozen. Freezing a route does **not** lock `isActive`.

### Route freezing

The XNS name owner may permanently freeze an individual route (`freezeRoute`).

Once `isFrozen` is true:
- `target` and `routeType` can never change again.
- The XNS name owner may continue toggling `isActive`.

### Route-book closing

The XNS name owner may permanently close the route book (`closeRouteBook`).

After closing:
- No new routes may be created under that name.
- Existing routes are unchanged (not frozen by the close).
- Per-route freeze and `isActive` controls remain independent.

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


Creates a route under an XNS name.

The route starts active and unfrozen.
`target` and `routeType` remain mutable until the route is frozen.

Example:

    createRoute("alice", "pay", "treasury", target, 0)

creates:

    alice AT pay/treasury

Requirements:
- `msg.sender` must own `label AT namespace`.
- `routeLabel` must be valid.
- `target` must be non-empty and at most `MAX_TARGET_LENGTH` bytes.
- The route book must not be closed.
- The route must not already exist.

Emits `RouteCreated`.

```solidity
function createRoute(string label, string namespace, string routeLabel, bytes target, uint32 routeType) external
```




### activateRoute


Activates an existing route.

Allowed even if the route is frozen — freeze does not lock `isActive`.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function activateRoute(string label, string namespace, string routeLabel) external
```




### deactivateRoute


Deactivates an existing route.

Allowed even if the route is frozen — freeze does not lock `isActive`.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function deactivateRoute(string label, string namespace, string routeLabel) external
```




### updateRoute


Updates `target` and `routeType` for an existing route.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- The route must exist.
- The route must not be frozen (`isFrozen`).
- `newTarget` must be non-empty and at most `MAX_TARGET_LENGTH` bytes.

Emits `RouteUpdated` only when `target` or `routeType` actually changes.

```solidity
function updateRoute(string label, string namespace, string routeLabel, bytes newTarget, uint32 newRouteType) external
```




### freezeRoute


Permanently freezes an individual route so `target` and `routeType` cannot change.

Freezing is irreversible. `isActive` remains independently controllable by the XNS name owner.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- The route must exist.

Emits `RouteFrozen` only if the route was not already frozen.

```solidity
function freezeRoute(string label, string namespace, string routeLabel) external
```




### batchFreezeRoutes


Permanently freezes multiple routes under one XNS name.

Same per-route semantics as `freezeRoute`. Already-frozen routes are skipped
(no event). Missing routes cause the entire call to revert.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- Every `routeLabels[i]` must refer to an existing route.

Emits `RouteFrozen` for each route that newly becomes frozen.

```solidity
function batchFreezeRoutes(string label, string namespace, string[] routeLabels) external
```




### closeRouteBook


Permanently closes the route book associated with an XNS name.

After closing, no additional routes may be created under that name.
Existing routes are unchanged: they are not frozen, and `isActive` remains
controllable by the XNS name owner.

Requires `msg.sender` to own `label AT namespace`.

Emits `RouteBookClosed` only if the route book was not already closed.

```solidity
function closeRouteBook(string label, string namespace) external
```




### closeRouteBook


Permanently closes the route book for `label AT namespace`.

Same requirements and effects as `closeRouteBook(label, namespace)`.

Emits `RouteBookClosed` only if the route book was not already closed.

```solidity
function closeRouteBook(string xnsName) external
```




### getRouteRecord


Returns a route record directly by route key.

`record.target.length == 0` means the route does not exist.

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

The string must be exactly `label AT namespace/routeLabel` (no extra `/` segments).

```solidity
function getRouteRecord(string route) external view returns (struct XNSRoutes.RouteRecord record)
```




### resolveRouteIfActive


Resolves an active route using separate XNS components.

```solidity
function resolveRouteIfActive(string label, string namespace, string routeLabel) external view returns (bytes target, uint32 routeType)
```




### resolveRouteIfActive


Resolves an active route using a complete route string.

Example:

    resolveRouteIfActive("alice AT pay/treasury")

The string must be exactly `label AT namespace/routeLabel` (no extra `/` segments).

```solidity
function resolveRouteIfActive(string route) external view returns (bytes target, uint32 routeType)
```




### resolveRoute


Resolves a route regardless of its active status.

```solidity
function resolveRoute(string label, string namespace, string routeLabel) external view returns (bytes target, uint32 routeType)
```




### resolveRoute


Resolves a route regardless of active status using a complete route string.

Example:

    resolveRoute("alice AT pay/treasury")

The string must be exactly `label AT namespace/routeLabel` (no extra `/` segments).

```solidity
function resolveRoute(string route) external view returns (bytes target, uint32 routeType)
```




### isRouteBookClosed


Returns whether the route book belonging to an XNS name is closed.

```solidity
function isRouteBookClosed(string label, string namespace) external view returns (bool closed)
```




### isRouteBookClosed


Convenience overload accepting a complete XNS name.

Example:

    isRouteBookClosed("alice AT pay")

```solidity
function isRouteBookClosed(string xnsName) external view returns (bool closed)
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

The input must contain exactly one `/` separating the XNS name from the route label.

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




### isValidTarget


Returns whether a target payload is non-empty and within `MAX_TARGET_LENGTH`.

```solidity
function isValidTarget(bytes target) external pure returns (bool valid)
```





## Events

### RouteCreated




```solidity
event RouteCreated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, bytes target, uint32 routeType, bool isActive)
```





### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, bool isActive)
```





### RouteUpdated




```solidity
event RouteUpdated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, bytes target, uint32 routeType)
```





### RouteFrozen




```solidity
event RouteFrozen(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel)
```





### RouteBookClosed




```solidity
event RouteBookClosed(bytes32 xnsNameKey, string label, string namespace)
```








## State Variables

### MAX_TARGET_LENGTH


Maximum allowed `target` payload length (bytes).

```solidity
uint256 MAX_TARGET_LENGTH
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
  bytes target;
  uint32 routeType;
  bool isActive;
  bool isFrozen;
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








# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


A simple immutable named-endpoint registry attached to XNS names.

XNS name owners can create named routes under their XNS name which resolve to opaque
endpoint payloads (`bytes`). Routes may represent EVM addresses, other-chain addresses,
identifiers, or other application-defined data — interpreted via `routeType`.

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
- `target` — opaque endpoint payload (mutable until frozen); 1–256 bytes.
- `routeType` — generic off-chain interpretation hint (mutable until frozen).
- `isActive` — whether applications should currently treat the route as usable
  (toggled by the XNS name owner).
- `isFrozen` — whether this route's `target` / `routeType` are permanently locked.
- `routeLabel` — immutable route label.

`routeLabel` is immutable after route creation. `target` and `routeType` may be updated by
the XNS name owner until the route is effectively frozen (`isFrozen` or route-book freeze).

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

The XNS name owner may activate or deactivate the route at any time (including after freeze).

### Route freezing

The XNS name owner may permanently freeze an individual route (`freezeRoute`) or the entire
route book (`freezeRouteBook`).

A route is effectively frozen when `isFrozen` is true **or** its route book is frozen:

    effectiveRouteFrozen = record.isFrozen || routeBookFrozen

After effective freeze:
- `target` and `routeType` can no longer be updated.
- The XNS name owner may continue toggling `isActive`.

After route-book freeze:
- No new routes may be created under that name.
- All existing routes under that name are treated as effectively frozen for updates.

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
`target` and `routeType` remain mutable until the route or route book is frozen.

Example:

    createRoute("alice", "pay", "treasury", target, 0)

creates:

    alice AT pay/treasury

Requirements:
- `msg.sender` must own `label AT namespace`.
- `routeLabel` must be valid.
- `target` must be non-empty and at most `MAX_TARGET_LENGTH` bytes.
- The route book must not be frozen.
- The route must not already exist.

Emits `RouteCreated`.

```solidity
function createRoute(string label, string namespace, string routeLabel, bytes target, uint32 routeType) external
```




### activateRoute


Activates an existing route.

**Requirements:**
- `msg.sender` must own `label AT namespace`.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function activateRoute(string label, string namespace, string routeLabel) external
```




### deactivateRoute


Deactivates an existing route.

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
- The route must not be effectively frozen (`isFrozen` or route-book freeze).
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




### freezeRouteBook


Permanently freezes the route book associated with an XNS name.

After freezing:
- No additional routes may be created.
- All existing routes under the name are treated as effectively frozen for
  `target` / `routeType` updates (without iterating or writing each route).
- The XNS name owner may continue toggling `isActive` on existing routes.

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

An optional suffix after the second `/` is ignored.

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

```solidity
function resolveRoute(string route) external view returns (bytes target, uint32 routeType)
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




### isRouteFrozen


Returns whether a route is effectively frozen for `target` / `routeType` updates.

True when the route's `isFrozen` flag is set or its route book is frozen.
Returns false when the route does not exist.

```solidity
function isRouteFrozen(string label, string namespace, string routeLabel) external view returns (bool frozen)
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





### RouteBookFrozen




```solidity
event RouteBookFrozen(bytes32 xnsNameKey, string label, string namespace)
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








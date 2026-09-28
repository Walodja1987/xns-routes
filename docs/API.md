# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


A simple named-endpoint registry attached to XNS names.

The ERC-173-compatible `owner()` is an identity/administrative pointer for external
integrations only. It has no authority over routes. Route mutations are authorized
exclusively through current XNS name ownership.

XNS name owners can create named routes under their XNS name which resolve to opaque
endpoint payloads (`bytes`). Routes may represent EVM addresses, other-chain addresses,
identifiers, or other application-defined data — interpreted via `routeType`.

### Route format

label@namespace/routeLabel

Examples:
- `alice@pay/treasury`
- `alice@pay/treasury-eth`
- `alice@pay/treasury-arb`
- `aave@defi/v3-pool`

The route label must:
- Be 1–32 characters long.
- Consist only of [a-z0-9-].
- Not start or end with '-'.
- Not contain consecutive hyphens ('--').

Application-layer parameters use URL query syntax (e.g. `?amount=10&to=0x…`) and are
not part of the on-chain route format. Callers must strip any `?...` suffix before using
string-based helpers.

### Route record

Each route stores:
- `target` — opaque endpoint payload (mutable until frozen); must be non-empty.
- `routeType` — generic off-chain interpretation hint (mutable until frozen).
- `isActive` — whether applications should currently treat the route as usable
  (toggled by the XNS name owner).
- `isFrozen` — whether this route's `target` / `routeType` are permanently locked.
- `routeLabel` — immutable route label.

`routeLabel` is immutable after route creation. `target` and `routeType` may be updated by
the XNS name owner until that route is frozen (`isFrozen`).

The exact semantics of `routeType` are intentionally not enforced by this contract.
Applications may define their own interpretation conventions.

Example route types (illustrative; see `routeTypes/`):
- `0` = EVM address
- `1` = Bitcoin address
- `2` = Solana pubkey
- `3` = EVM calldata
- `4` = URI
- `5` = EVM route builder
- etc.

This contract does not validate `target` contents beyond requiring non-empty.

### Active status

A route starts active by default.

The XNS name owner may activate or deactivate the route at any time, including after the
route has been frozen. Freezing a route does **not** lock `isActive`.

### Route freezing

The XNS name owner may permanently freeze an individual route (`freezeRoute`), or create
it already frozen (`createRouteAndFreeze`).

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

`resolveRoute` returns the `target` only when the route is frozen and active.
Integrations that need mutable or inactive routes can inspect `getRouteRecord` directly.

Efficient contract integrations should use the separate:

    (label, namespace, routeLabel)

parameters.

Convenience view functions additionally support complete strings such as:

    alice@pay/treasury

No reverse lookup is provided because multiple routes may point to the same target.

### Keys and indexing

- XNS name key: `keccak256(abi.encodePacked(label, "@", namespace))`.
- Route key: `keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel))`
  (the hash of the canonical route string `label@namespace/routeLabel`).
  Unambiguous because XNSv2 forbids the at-sign and `/` in `label` and `namespace`,
  and a route label cannot contain `/`.
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

    alice@pay/treasury

**Requirements:**
- `msg.sender` must own `label@namespace`.
- `routeLabel` must be valid.
- `target` must be non-empty.
- The route book must not be closed.
- The route must not already exist.

Emits `RouteCreated`.

```solidity
function createRoute(string label, string namespace, string routeLabel, bytes target, uint32 routeType) external
```




### createRouteAndFreeze


Creates a route and permanently freezes it in the same transaction.

The route starts active and frozen, so it is immediately returned by `resolveRoute`.
Use only with a verified `target` and `routeType`: a mistaken route can never be
corrected or removed, only deactivated.

**Requirements:**
- Same as `createRoute`.

Emits `RouteCreated` followed by `RouteFrozen`.

```solidity
function createRouteAndFreeze(string label, string namespace, string routeLabel, bytes target, uint32 routeType) external
```




### activateRoute


Activates an existing route.

Allowed even if the route is frozen — freeze does not lock `isActive`.

**Requirements:**
- `msg.sender` must own `label@namespace`.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function activateRoute(string label, string namespace, string routeLabel) external
```




### deactivateRoute


Deactivates an existing route.

Allowed even if the route is frozen — freeze does not lock `isActive`.

**Requirements:**
- `msg.sender` must own `label@namespace`.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function deactivateRoute(string label, string namespace, string routeLabel) external
```




### updateRoute


Updates `target` and `routeType` for an existing route.

**Requirements:**
- `msg.sender` must own `label@namespace`.
- The route must exist.
- The route must not be frozen (`isFrozen`).
- `newTarget` must be non-empty.

Emits `RouteUpdated` only when `target` or `routeType` actually changes.

```solidity
function updateRoute(string label, string namespace, string routeLabel, bytes newTarget, uint32 newRouteType) external
```




### freezeRoute


Permanently freezes an individual route so `target` and `routeType` cannot change.

Freezing is irreversible. `isActive` remains independently controllable by the XNS name owner.

**Requirements:**
- `msg.sender` must own `label@namespace`.
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
- `msg.sender` must own `label@namespace`.
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

**Requirements:**
- `msg.sender` must own `label@namespace`.

Emits `RouteBookClosed` only if the route book was not already closed.

```solidity
function closeRouteBook(string label, string namespace) external
```




### closeRouteBook


Permanently closes the route book for `label@namespace`.

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

    alice@pay/treasury

Parsed like `splitRoute` (no component validation). Returns an empty record if no
route matches.

```solidity
function getRouteRecord(string route) external view returns (struct XNSRoutes.RouteRecord record)
```




### getXNSNameKey


Returns the canonical XNS name key for separate name components.

Equal to the hash of the UTF-8 string `label@namespace`.

```solidity
function getXNSNameKey(string label, string namespace) external pure returns (bytes32 xnsNameKey)
```




### getXNSNameKey


Returns the canonical XNS name key for a complete XNS name.

Parsed like `splitXNSName` (no component validation).

```solidity
function getXNSNameKey(string xnsName) external pure returns (bytes32 xnsNameKey)
```




### getRouteKey


Returns the canonical route key for separate XNS components.

Equal to the hash of the UTF-8 string `label@namespace/routeLabel`.

```solidity
function getRouteKey(string label, string namespace, string routeLabel) external pure returns (bytes32 routeKey)
```




### getRouteKey


Returns the canonical route key for a complete route string.

Example:

    getRouteKey("alice@pay/treasury")

Parsed like `splitRoute` (no component validation), so an invalid route string still
yields a key; no created route can have it.

```solidity
function getRouteKey(string route) external pure returns (bytes32 routeKey)
```




### resolveRoute


Resolves a frozen and active route using separate XNS components.

Reverts if the route does not exist, is not frozen, or is inactive.

```solidity
function resolveRoute(string label, string namespace, string routeLabel) external view returns (bytes target, uint32 routeType)
```




### resolveRoute


Resolves a frozen and active route using a complete route string.

Example:

    resolveRoute("alice@pay/treasury")

Parsed like `splitRoute` (no component validation). Reverts if the string cannot be split
(missing delimiter or empty component), or if the route does not exist, is not frozen,
or is inactive.

```solidity
function resolveRoute(string route) external view returns (bytes target, uint32 routeType)
```




### isRouteBookClosed


Returns whether the route book belonging to an XNS name is closed.

```solidity
function isRouteBookClosed(string label, string namespace) external view returns (bool closed)
```




### isRouteBookClosed


Convenience overload accepting `label@namespace`.

Example:

    isRouteBookClosed("alice@pay")

```solidity
function isRouteBookClosed(string xnsName) external view returns (bool closed)
```




### getRouteKeyCount


Returns the number of routes ever created under an XNS name.

```solidity
function getRouteKeyCount(string label, string namespace) external view returns (uint256 count)
```




### getRouteKeyCount


Convenience overload accepting `label@namespace`.

```solidity
function getRouteKeyCount(string xnsName) external view returns (uint256 count)
```




### getRouteKeys


Returns route keys `[start:end]` for an XNS name.

`end` is exclusive and is clamped to the array length. Returns an empty array if
`start` is at or beyond the clamped `end`. Reverts if `start > end`.

```solidity
function getRouteKeys(string label, string namespace, uint256 start, uint256 end) external view returns (bytes32[] keys)
```




### getRouteKeys


Convenience overload accepting `label@namespace`.

Same pagination rules as `getRouteKeys(label, namespace, start, end)`.

```solidity
function getRouteKeys(string xnsName, uint256 start, uint256 end) external view returns (bytes32[] keys)
```




### getRouteEntries


Returns full route entries `[start:end]` for an XNS name.

Same pagination rules as `getRouteKeys(label, namespace, start, end)`.

```solidity
function getRouteEntries(string label, string namespace, uint256 start, uint256 end) external view returns (struct XNSRoutes.RouteEntry[] entries)
```




### getRouteEntries


Convenience overload accepting `label@namespace`.

Same pagination rules as `getRouteKeys(label, namespace, start, end)`.

```solidity
function getRouteEntries(string xnsName, uint256 start, uint256 end) external view returns (struct XNSRoutes.RouteEntry[] entries)
```




### splitRoute


Parses a complete route string into:

    (label, namespace, routeLabel)

Example:

    alice@pay/treasury

becomes:

    ("alice", "pay", "treasury")

Splits at the first `/` and the first at-sign before it. Components are not validated:
for example, `alice@pay/foo/bar` becomes `("alice", "pay", "foo/bar")`.
Reverts only if a delimiter is missing or a component is empty.

```solidity
function splitRoute(string route) external pure returns (string label, string namespace, string routeLabel)
```




### splitXNSName


Parses `label@namespace`.

Splits at the first at-sign. Components are not validated.
Reverts only if the at-sign is missing or a component is empty.

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
event RouteCreated(bytes32 xnsNameKey, bytes32 routeKey, bytes32 targetHash, string label, string namespace, string routeLabel, uint32 routeType)
```

_Emitted by `createRoute` and `createRouteAndFreeze`._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel, bool isActive)
```

_Emitted by `activateRoute` and `deactivateRoute` (only when `isActive` changes)._




### RouteUpdated




```solidity
event RouteUpdated(bytes32 xnsNameKey, bytes32 routeKey, bytes32 targetHash, string label, string namespace, string routeLabel, uint32 routeType)
```

_Emitted by `updateRoute`._




### RouteFrozen




```solidity
event RouteFrozen(bytes32 xnsNameKey, bytes32 routeKey, string label, string namespace, string routeLabel)
```

_Emitted by `freezeRoute`, `batchFreezeRoutes`, and `createRouteAndFreeze`._




### RouteBookClosed




```solidity
event RouteBookClosed(bytes32 xnsNameKey, string label, string namespace)
```

_Emitted by `closeRouteBook`._







## State Variables

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








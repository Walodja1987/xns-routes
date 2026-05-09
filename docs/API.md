# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry for XNS names which enables XNS name owners to map URL-style
identifiers to any Ethereum address. Mappings are free and may point to EOAs and smart
contracts including helper/view contracts returning arbitrary data, such as Bitcoin or Solana
addresses, calldata, or other information.

Route format: `[xnsName]/[routePrefix:][route]` with `routePrefix` being optional.

Examples:
- `alice.og/my-sub-wallet`
- `contracts.aave/eth:v3-pool-contract`
- `bob.xns/eth:approve-usdt`

`routePrefix` and `route` must follow the same character and hyphenation rules as `xnsName`:
- Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
- Cannot start or end with '-'
- Cannot contain consecutive hyphens ('--')

`routePrefix` is optional; if provided, it must be 1-20 characters long.
`route` is required and must be 1-32 characters long.

Key points:
- Routes are owned and managed by the XNS name owner.
- An XNS name owner can register unlimited routes for free.
- A route stores `target`, `routeType`, `isActive`, and `isFrozen`.
- Route freeze and route book freeze are irreversible.
- Active status can still be toggled after freeze.
- `routeType` is a `uint32` tag whose meaning and interpretation are defined off-chain by route parsers.
  For example, `routeType = 0` may suggest that the `target` is an EOA.
  `routeType = 1` may suggest that the `target` is a smart contract.
  `routeType = 2` may suggest that the `target` is a special contract that returns parametrized calldata.
  `routeType = 3` may suggest that the `target` returns a Bitcoin address.
- Forward resolution is direct (`xnsName`, `routePrefix`, `route` → `target`). A global reverse
  lookup from `target` to all names/routes is not stored on-chain.
- For one known `xnsName`, on-chain enumeration is available without an indexer via the append-only
  route-key log (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecordByRouteKey` / batch overload).






## Functions

### createRoute


Create a route under `(xnsName, routePrefix, route)`. Reverts if that key already exists.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- The route key must not already exist.

On success, appends the route storage key to the per-name append-only log
(`getRouteKeyCount` / `getRouteKeys`).

```solidity
function createRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action" |
| routePrefix | string | Optional path segment before `:`; non-empty must pass local route-prefix        rules (same charset/hyphen constraints as XNS labels, max length 20);        empty means `xnsName/route/...` only (no `:` in the routePath). |
| route | string | Required route label (same charset/hyphen constraints as XNS labels, max        length 32). |
| target | address | Build address for `routeType`; must be non-zero (`address(0)` is reserved        for "missing route"). |
| routeType | uint32 | Opaque hint for parsers (semantics offchain) |
| activate | bool | Initial value for stored `isActive`. |
| freeze | bool | If true, set stored `isFrozen` in this same tx (irreversible for that route). |


### updateRoute


Update an existing route (target, routeType, activate, optional freeze in one tx).

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist and must not already be per-route frozen.

```solidity
function updateRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action" |
| routePrefix | string | Same as at create time (may be empty). |
| route | string | Same as at create time |
| target | address | Must be non-zero; use a burn address if an unusable target is required. |
| routeType | uint32 | Opaque hint for parsers (semantics offchain) |
| activate | bool | New value for stored `isActive`. |
| freeze | bool | If true, set stored `isFrozen` in this same tx (irreversible for that route). |


### activateRoute


Mark an existing route as active.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function activateRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |


### deactivateRoute


Mark an existing route as inactive.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function deactivateRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |


### deleteRoute


Remove a route so `createRoute` may register the same key again.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist and must not be per-route frozen.

Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.

```solidity
function deleteRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |


### updateTarget


Update the build `target` for an existing route.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist and must not be per-route frozen.
- `newTarget` must not be the zero address.

Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.

```solidity
function updateTarget(string xnsName, string routePrefix, string route, address newTarget) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |
| newTarget | address | New build target; must be non-zero. |


### updateRouteType


Update `routeType` for an existing route.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist and must not be per-route frozen.

Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.

```solidity
function updateRouteType(string xnsName, string routePrefix, string route, uint32 newRouteType) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |
| newRouteType | uint32 | New opaque parser hint. |


### freezeRoute


Freeze a single route forever.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy local route-segment rules.
- The route must exist.

After freezing, `target` and `routeType` can never be changed again; active/inactive can
still be toggled.

```solidity
function freezeRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |


### freezeRouteBook


Freeze the entire route book under an XNS name forever.

**Requirements:**
- `msg.sender` must be the current XNS owner for `xnsName`.

**Effects (irreversible):**
- No new routes may be added under `xnsName`.
- No existing route targets may be changed under `xnsName`.
- Routes may not be deleted under `xnsName`.
- `freezeRoute` may not be called for routes under `xnsName`.
- Route activation can still be toggled.

```solidity
function freezeRouteBook(string xnsName) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | Fully-qualified XNS name whose route book to freeze. |


### getRouteInfo


Return full route metadata. Applies the same `routePrefix`/`route` validation as
mutating functions, then reads storage. Reverts when no route exists for the key.

```solidity
function getRouteInfo(string xnsName, string routePrefix, string route) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Stored build target address. |
| isActive | bool | Whether the route is active. |
| isFrozen | bool | Whether the route is frozen per-route. |
| routeType | uint32 | Opaque parser hint. |

### getRouteInfoFromPath


Same as `getRouteInfo` with `fullRoutePath` parsed by `splitFullPath`.

**Requirements:**
- `fullRoutePath` must contain at least one `/`.
- Further requirements match `getRouteInfo` for the parsed components.

```solidity
function getRouteInfoFromPath(string fullRoutePath) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType)
```




### routeExists


Returns whether a route exists (`target` was ever set via `createRoute`; zero
`target` is never stored). Applies the same `routePrefix`/`route` validation as mutating
functions before reading storage.

```solidity
function routeExists(string xnsName, string routePrefix, string route) external view returns (bool exists)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Optional route prefix segment (empty means no prefix). |
| route | string | Route label segment. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| exists | bool | True if a route record exists for the key. |

### routeExistsFromPath


Same as `routeExists` with `fullRoutePath` parsed by `splitFullPath`.

**Requirements:**
- `fullRoutePath` must contain at least one `/`.
- Further requirements match `routeExists` for the parsed components.

```solidity
function routeExistsFromPath(string fullRoutePath) external view returns (bool exists)
```




### isRouteBookFrozen


Returns whether the entire route book under `xnsName` is frozen
(reads `_routeBookFrozen[keccak256(bytes(xnsName))]`).

```solidity
function isRouteBookFrozen(string xnsName) external view returns (bool frozen)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | Fully-qualified XNS name. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| frozen | bool | True if the route book is frozen. |

### getRouteKeyCount


Number of entries in the append-only route-key log for `xnsName` (not the count of live routes;
deletes do not shrink this).

```solidity
function getRouteKeyCount(string xnsName) external view returns (uint256 count)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name to get the route key count for. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| count | uint256 | The number of route keys. |

### getRouteKeys


Returns `keys[start:end]` from the append-only log for `xnsName` (`end` is exclusive).
Reverts if `start > end` or `end` exceeds length.

```solidity
function getRouteKeys(string xnsName, uint256 start, uint256 end) external view returns (bytes32[] keys)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name to get the route keys for. |
| start | uint256 | The start index (inclusive). |
| end | uint256 | The end index (exclusive). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| keys | bytes32[] | The route keys. |

### getRouteRecordByRouteKey


Read stored metadata by canonical route storage key. Does not validate strings;
`record.target == address(0)` means no record (never created or deleted).

```solidity
function getRouteRecordByRouteKey(bytes32 routeKey) external view returns (struct XNSRoutes.RouteRecord record)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeKey | bytes32 | The route key to read. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| record | struct XNSRoutes.RouteRecord | The route record (same shape as each element of the batch overload). |

### getRouteRecordByRouteKey


Batch read of `RouteRecord` for each `routeKey`. Same semantics as
`getRouteRecordByRouteKey(bytes32)` per element.

```solidity
function getRouteRecordByRouteKey(bytes32[] routeKeys) external view returns (struct XNSRoutes.RouteRecord[] records)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeKeys | bytes32[] | The route keys to read. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| records | struct XNSRoutes.RouteRecord[] | The route records. |

### splitFullPath


Parse `fullRoutePath` into `(xnsName, routePrefix, route)`
(first `/`, then first `:` in the routePath).

**Requirements:**
- `fullRoutePath` must contain at least one `/`.

Does not apply XNS label validation; pass the returned tuple into tuple-based functions,
which validate `routePrefix` and `route`.

```solidity
function splitFullPath(string fullRoutePath) external pure returns (string xnsName, string routePrefix, string route)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| fullRoutePath | string | Full path, e.g. `bob.xns/eth:transfer-usdt` or `bob.xns/my-wallet`. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | Segment before the first `/`. |
| routePrefix | string | Segment before the first `:` in the routePath, or empty if there is no `:`. |
| route | string | Remainder of the routePath after `routePrefix` and `:`, or the whole         routePath if there is no `:`. |


### isValidRoutePrefix

Returns whether `routePrefix` satisfies local prefix rules. Empty string is valid (no prefix); non-empty values must match the same slug rules as non-empty prefixes in `createRoute` (1–20 characters).

```solidity
function isValidRoutePrefix(string routePrefix) external pure returns (bool valid)
```

### isValidRoute

Returns whether `route` satisfies local route rules (1–32 characters, slug charset and hyphen placement).

```solidity
function isValidRoute(string route) external pure returns (bool valid)
```

### isValidRoutePrefixAndRoute

Returns whether the pair `(routePrefix, route)` would pass validation used by mutating functions and tuple-based reads (`getRouteInfo`, `routeExists`, etc.).

```solidity
function isValidRoutePrefixAndRoute(string routePrefix, string route) external pure returns (bool valid)
```


## Events

### RouteCreated




```solidity
event RouteCreated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, address target, bool isActive, bool isFrozen, uint32 routeType)
```

_Emitted in `createRoute`._




### RouteUpdated




```solidity
event RouteUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, address target, bool isActive, bool isFrozen, uint32 routeType)
```

_Emitted in `updateRoute`._




### RouteTargetUpdated




```solidity
event RouteTargetUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, address newTarget)
```

_Emitted in `updateTarget` when target changes._




### RouteTypeUpdated




```solidity
event RouteTypeUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, uint32 newRouteType)
```

_Emitted in `updateRouteType` when route type changes._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, bool isActive)
```

_Emitted in `activateRoute` and `deactivateRoute` when active status changes._




### RouteFrozen




```solidity
event RouteFrozen(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route)
```

_Emitted in `createRoute`, `updateRoute`, and `freezeRoute` when route freeze is applied._




### RouteBookFrozenForName




```solidity
event RouteBookFrozenForName(bytes32 nameHash, string xnsName)
```

_Emitted in `freezeRouteBook` when the route book is frozen for an XNS name._




### RouteDeleted




```solidity
event RouteDeleted(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route)
```

_Emitted in `deleteRoute`._







## State Variables

### XNS


XNS registry this contract calls for name resolution and label validation.

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
  bool isFrozen;
```




_Data structure to store route metadata._






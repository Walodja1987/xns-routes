# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Examples XRLs:
- `alice.og/my-sub-wallet`
- `contracts.aave/eth:v3-pool-contract`
- `bob.xns/uniswap:approve-usdt/amount=10`

`routeScope` and `routeLabel` must follow the same character and hyphenation rules as `xnsName`:
- Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
- Cannot start or end with '-'
- Cannot contain consecutive hyphens ('--')

Key points:
- Routes are owned and managed by the XNS name owner.
- An XNS name owner can register unlimited routes for free.
- A route record stores `target`, `routeType`, `isActive`, `isFrozen`, and `activeController`.
- Route freeze and route book freeze are irreversible.
- Only `activeController` may toggle `isActive` via `activateRoute` / `deactivateRoute`.
- `activeController` is set at `createRoute` (XNS name owner) or `createRouteWithController`
  and cannot be changed afterward.
- `activeController == address(0)` locks `isActive` at its create-time value forever.
- `activeController` may still toggle `isActive` after route or route-book freeze.
- `routeType` is a `uint32` tag whose meaning and interpretation are defined off-chain by route parsers.
  For example, `routeType = 0` may suggest that the `target` is an EOA.
  `routeType = 1` may suggest that the `target` is a smart contract.
  `routeType = 2` may suggest that the `target` is a special contract that returns parametrized calldata.
  `routeType = 3` may suggest that the `target` returns a Bitcoin address.
- Forward resolution is direct: registry XRL -> `target`. Use `resolveRouteIfActive` or
  `resolveRouteIfActiveAndFrozen` for strict resolution; `getRouteRecord` returns raw storage.
  Reverse lookup is not supported because many routes may point to the same `target`.
- Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.
- `routeKey` is `keccak256` of canonical registry XRL (`xnsName/route`; params excluded).
- For one known `xnsName`, on-chain enumeration is available without an indexer via the append-only
  route-key log (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecord`).






## Functions

### createRoute


Create a route `[xnsName]/[routeScope:][route]` with `activeController` set to the
current XNS name owner.

**Requirements:**
- `msg.sender` must be the owner for `xnsName`.
- Non-empty `routeScope` and `routeLabel` must satisfy local character rules.
- `routeLabel` must be a non-empty string.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- The route key must not already exist.

On success, appends the route key to the append-only array `_routeKeysByXNSName` associated
with `xnsName`, querieable via `getRouteKeys`.
Note: Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.

```solidity
function createRoute(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType, bool activate, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routeScope | string | Optional path segment before `:`; non-empty must pass local route scope rules ([a-z0-9-], max length 20); empty means `xnsName/routeLabel` only (no `:` in the route). |
| routeLabel | string | Required route label ([a-z0-9-], max length 32). |
| target | address | Target address for `routeType`; must be non-zero (`address(0)` is reserved for non-existent route). |
| routeType | uint32 | Parser hint for how to interpret `target` (off-chain semantics), e.g. 0 = plain address, 2 = Bitcoin address, 3 = address exposing a html, etc. |
| activate | bool | Initial value for stored `isActive`. |
| freeze | bool | If true, renders the route immutable. |


### createRouteWithController


Same as `createRoute` but with an explicit `activeController`.
Use when toggling `isActive` should be delegated to another account or locked at create time.

Same requirements as `createRoute`, plus:
- Only active routes can be locked at create time via `activeController == address(0)`.

```solidity
function createRouteWithController(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType, bool activate, bool freeze, address activeController) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routeScope | string | Optional path segment before `:`; non-empty must pass local route scope rules ([a-z0-9-], max length 20); empty means `xnsName/routeLabel` only (no `:` in the route). |
| routeLabel | string | Required route label ([a-z0-9-], max length 32). |
| target | address | Target address for `routeType`; must be non-zero (`address(0)` is reserved for non-existent route). |
| routeType | uint32 | Parser hint for how to interpret `target` (off-chain semantics), e.g. 0 = plain address, 2 = Bitcoin address, 3 = address exposing a html, etc. |
| activate | bool | Initial value for stored `isActive`. |
| freeze | bool | If true, renders the route immutable. |
| activeController | address | Account that may toggle `isActive`; `address(0)` locks `isActive` status forever (requires `activate == true`). |


### updateRoute


Update an existing route (target, routeType, freeze in one tx).

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist and must not already be frozen.

```solidity
function updateRoute(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routeScope | string | Route scope of the route path to be updated (may be empty). |
| routeLabel | string | Route label of the route path to be updated. |
| target | address | New target address. Must be non-zero. |
| routeType | uint32 | New route type integer. |
| freeze | bool | If true, renders the route immutable. Does not change `isActive`; use `activateRoute` / `deactivateRoute` as `activeController`. Emits `RouteTargetUpdated` and/or `RouteTypeUpdated` only when the corresponding stored field changes; emits `RouteFrozen` when `freeze` is true. |


### activateRoute


Mark an existing route as active.

**Requirements:**
- `msg.sender` must be `record.activeController`.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function activateRoute(string xnsName, string routeScope, string routeLabel) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be activated (may be empty). |
| routeLabel | string | Route label of the route path to be activated. |


### deactivateRoute


Mark an existing route as inactive.

**Requirements:**
- `msg.sender` must be `record.activeController`.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function deactivateRoute(string xnsName, string routeScope, string routeLabel) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be deactivated (may be empty). |
| routeLabel | string | Route label of the route path to be deactivated. |


### deleteRoute


Remove a routeLabel so `createRoute` may register the same key again.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist and must not already be frozen.

Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.

Emits `RouteDeleted` only when the route is deleted.

```solidity
function deleteRoute(string xnsName, string routeScope, string routeLabel) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be deleted (may be empty). |
| routeLabel | string | Route label of the route path to be deleted. |


### updateTarget


Update the `target` address for an existing route.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist and must not already be frozen.
- `newTarget` must not be the zero address.

Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.

```solidity
function updateTarget(string xnsName, string routeScope, string routeLabel, address newTarget) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be updated (may be empty). |
| routeLabel | string | Route label of the route path to be updated. |
| newTarget | address | New target address; must be non-zero. |


### updateRouteType


Update `routeType` for an existing route.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist and must not already be frozen.

Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.

```solidity
function updateRouteType(string xnsName, string routeScope, string routeLabel, uint32 newRouteType) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be updated (may be empty). |
| routeLabel | string | Route label of the route path to be updated. |
| newRouteType | uint32 | New route type integer. |


### freezeRoute


Freeze a single routeLabel forever.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist.

After freezing, `target` and `routeType` can never be changed again; `activeController`
can still toggle `isActive`.

Emits `RouteFrozen` only if the route was not already frozen.

```solidity
function freezeRoute(string xnsName, string routeScope, string routeLabel) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be frozen (may be empty). |
| routeLabel | string | Route label of the route path to be frozen. |


### freezeRouteBook


Freeze the entire route book under an XNS name forever.

**Effects (irreversible):**
- No new routes may be added under `xnsName`.
- No existing route targets may be changed under `xnsName`.
- Routes may not be deleted under `xnsName`.
- `freezeRoute` may not be called for routes under `xnsName`.
- `activeController` can still toggle `isActive` for existing routes.

Requires `msg.sender` to be the XNS name owner of `xnsName`.

Emits `RouteBookFrozen` only if the route book was not already frozen.

```solidity
function freezeRouteBook(string xnsName) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name whose route book to freeze. |


### getRouteRecord


Reads stored route record data by `routeKey`.
`record.target == address(0)` means that record does not exist.

```solidity
function getRouteRecord(bytes32 routeKey) external view returns (struct XNSRoutes.RouteRecord record)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeKey | bytes32 | Canonical route storage key. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, isFrozen, activeController). |

### getRouteRecord


Reads stored route record data by `(xnsName, routeScope, routeLabel)`.
`record.target == address(0)` means that record does not exist.

Returns stored route fields only. For route-book freeze status in the same call,
use `getRouteRecordWithBookStatus`.

Requires that `routeScope` and `routeLabel` are valid strings.

```solidity
function getRouteRecord(string xnsName, string routeScope, string routeLabel) external view returns (struct XNSRoutes.RouteRecord record)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope (may be empty). |
| routeLabel | string | Route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, isFrozen, activeController). |

### getRouteRecord


Reads stored route record data by registry XRL (`splitRegistryXRL`).
`record.target == address(0)` means that record does not exist.

Returns stored route fields only. For route-book freeze status in the same call,
use `getRouteRecordWithBookStatus`.

```solidity
function getRouteRecord(string registryXRL) external view returns (struct XNSRoutes.RouteRecord record)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| registryXRL | string | Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, isFrozen, activeController). |

### getRouteRecordWithBookStatus


Reads stored route record data and route-book freeze status by
`(xnsName, routeScope, routeLabel)`.

`details.record.target == address(0)` means that record does not exist.
Route-book freeze is name-scoped and not stored in `RouteRecord`.
For structural immutability (`target` / `routeType` / delete locked):
`details.record.isFrozen || details.isRouteBookFrozen`. `isActive` may still be toggled
by `activeController` when structurally frozen.

Requires that `routeScope` and `routeLabel` are valid strings.

```solidity
function getRouteRecordWithBookStatus(string xnsName, string routeScope, string routeLabel) external view returns (struct XNSRoutes.RouteRecordWithBookStatus details)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope (may be empty). |
| routeLabel | string | Route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| details | struct XNSRoutes.RouteRecordWithBookStatus | Stored route record and route-book freeze flag for `xnsName`. |

### getRouteRecordWithBookStatus


Reads stored route record data and route-book freeze status by registry XRL
(`splitRegistryXRL`).

Same semantics as `getRouteRecordWithBookStatus(xnsName, routeScope, routeLabel)`.

```solidity
function getRouteRecordWithBookStatus(string registryXRL) external view returns (struct XNSRoutes.RouteRecordWithBookStatus details)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| registryXRL | string | Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| details | struct XNSRoutes.RouteRecordWithBookStatus | Stored route record and route-book freeze flag for the parsed `xnsName`. |

### resolveRouteIfActive


Resolves an active route to `(target, routeType)`.

**Requirements:**
- The route must exist (`target != address(0)`).
- `isActive` must be true.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.

```solidity
function resolveRouteIfActive(string xnsName, string routeScope, string routeLabel) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope (may be empty). |
| routeLabel | string | Route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Resolved target address. |
| routeType | uint32 | Parser hint for how to interpret `target`. |

### resolveRouteIfActive


Resolves an active route to `(target, routeType)` by registry XRL (`splitRegistryXRL`).

**Requirements:** same as `resolveRouteIfActive(xnsName, routeScope, routeLabel)`.

```solidity
function resolveRouteIfActive(string registryXRL) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| registryXRL | string | Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Resolved target address. |
| routeType | uint32 | Parser hint for how to interpret `target`. |

### resolveRouteIfActiveAndFrozen


Resolves an active and frozen route to `(target, routeType)`.

**Requirements:**
- The route must exist (`target != address(0)`).
- `isActive` must be true.
- `record.isFrozen` must be true or the route book for `xnsName` must be frozen.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.

```solidity
function resolveRouteIfActiveAndFrozen(string xnsName, string routeScope, string routeLabel) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope (may be empty). |
| routeLabel | string | Route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Resolved target address. |
| routeType | uint32 | Parser hint for how to interpret `target`. |

### resolveRouteIfActiveAndFrozen


Resolves an active and frozen route to `(target, routeType)` by registry XRL
(`splitRegistryXRL`).

**Requirements:** same as `resolveRouteIfActiveAndFrozen(xnsName, routeScope, routeLabel)`.

```solidity
function resolveRouteIfActiveAndFrozen(string registryXRL) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| registryXRL | string | Registry XRL, e.g. `bob.xns/eth:my-wallet`, without trailing parameters (if any). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Resolved target address. |
| routeType | uint32 | Parser hint for how to interpret `target`. |

### isRouteBookFrozen


Returns whether the entire route book under `xnsName` is frozen.

```solidity
function isRouteBookFrozen(string xnsName) external view returns (bool frozen)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| frozen | bool | True if the route book is frozen. |

### getRouteKeyCount


Number of entries in the append-only routeLabel-key log for `xnsName`
(not the count of live routes; deletes do not shrink this).

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


Returns `keys[start:end]` from the route keys array associated with
`xnsName` (`end` is exclusive). If `end` is greater than the array length, behaves
like `end == length` (caller may pass any large upper bound to fetch "the rest"
without needing to know the exact array length). If `start` lies past the end of
the array, returns an empty array.

Requires `start <= end`.

```solidity
function getRouteKeys(string xnsName, uint256 start, uint256 end) external view returns (bytes32[] keys)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name to get the route keys for. |
| start | uint256 | The start index (inclusive). |
| end | uint256 | The end index (exclusive); may exceed array length. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| keys | bytes32[] | The route keys. |

### splitRegistryXRL


Parses a registry XRL into `(xnsName, routeScope, routeLabel)`.
Example: `bro.xns/eth:my-wallet` -> `(bro.xns, eth, my-wallet)`.
Useful when calling tuple-based mutating functions (`updateRoute`, `createRoute`, etc.).

A registry XRL is `xnsName "/" route` — the on-chain subset of a full XRL (no `/params…` tail).
Does not validate segments; malformed input may still parse but fail downstream.

Requires `registryXRL` to contain at least one `/`.

```solidity
function splitRegistryXRL(string registryXRL) external pure returns (string xnsName, string routeScope, string routeLabel)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| registryXRL | string | Registry XRL (not a full XRL with params), e.g. `bob.xns/eth:transfer-usdt`. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | Segment before the first `/`. |
| routeScope | string | Segment before the first `:` in `route`, or empty if there is no `:`. |
| routeLabel | string | Segment after `:` if `routeScope` is present, else the whole `route` after `/`. |

### isValidRouteScope


Returns whether `routeScope` satisfies local scope rules. Empty string is valid;
non-empty must be 1–20 chars and match the slug charset/hyphen rules.

```solidity
function isValidRouteScope(string routeScope) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeScope | string | Candidate route scope (may be empty). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True if empty or a valid slug (1–20 chars). |

### isValidRouteLabel


Returns whether `routeLabel` satisfies local label rules (1–32 chars, slug rules).

```solidity
function isValidRouteLabel(string routeLabel) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeLabel | string | Candidate route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True if a valid slug (1–32 chars). |

### isValidRouteScopeAndLabel


Returns whether `routeScope` and `routeLabel` pass validation rules.

```solidity
function isValidRouteScopeAndLabel(string routeScope, string routeLabel) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routeScope | string | Candidate route scope (may be empty). |
| routeLabel | string | Candidate route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True if both inputs are valid slugs. |


## Events

### RouteCreated




```solidity
event RouteCreated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address target, bool isActive, bool isFrozen, uint32 routeType, address activeController)
```

_Emitted in `createRoute`._




### RouteTargetUpdated




```solidity
event RouteTargetUpdated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address previousTarget, address newTarget)
```

_Emitted in `updateTarget` and `updateRoute` when `target` changes._




### RouteTypeUpdated




```solidity
event RouteTypeUpdated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, uint32 previousRouteType, uint32 newRouteType)
```

_Emitted in `updateRouteType` and `updateRoute` when `routeType` changes._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, bool isActive)
```

_Emitted in `activateRoute` and `deactivateRoute` when `isActive` changes._




### RouteFrozen




```solidity
event RouteFrozen(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel)
```

_Emitted in `updateRoute` and `freezeRoute` when an existing route becomes frozen.
Initial freeze-at-create is reflected only in `RouteCreated` (`isFrozen`)._




### RouteBookFrozen




```solidity
event RouteBookFrozen(bytes32 nameHash, string canonicalXNSName)
```

_Emitted in `freezeRouteBook` when the route book is frozen for an XNS name._




### RouteDeleted




```solidity
event RouteDeleted(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel)
```

_Emitted in `deleteRoute`._







## State Variables

### XNS


XNS registry this contract calls for name resolution.

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
  address activeController;
```




_Data structure to store route metadata._




### RouteRecordWithBookStatus

```solidity
struct RouteRecordWithBookStatus {
  struct XNSRoutes.RouteRecord record;
  bool isRouteBookFrozen;
```




_Stored route record plus route-book freeze status for UI reads._






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
- Forward resolution is direct: `[xnsName]/[routePrefix:][route]` → `target`. Reverse lookup is not
  supported because many routes may point to the same `target`.
- For one known `xnsName`, on-chain enumeration is available without an indexer via the append-only
  route-key log (`getRouteKeyCount`, `getRouteKeys`, `getRouteRecordByRouteKey` / batch overload).
- Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.






## Functions

### createRoute


Create a route `[xnsName]/[routePrefix:][route]`. Reverts if the route already exists.

**Requirements:**
- `msg.sender` must be the owner for `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy local character set, hyphenation, and length rules.
- `route` must be a non-empty string.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- The route key must not already exist.

On success, appends the route key to the append-only array `_routeKeysByXNSName` associated with `xnsName`.

Note: Bare names like `bob` are normalized/canonicalized to `bob.x` for storage.

```solidity
function createRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routePrefix | string | Optional path segment before `:`; non-empty must pass local route-prefix rules ([a-z0-9-], max length 20). empty means `xnsName/route` only (no `:` in the routePath). |
| route | string | Required route label ([a-z0-9-], max length 32). |
| target | address | Target address for `routeType`; must be non-zero (`address(0)` is reserved for non-existent route). |
| routeType | uint32 | Parser hint for how to interpret `target` (off-chain semantics), e.g. 0 = plain address, 2 = Bitcoin address, 3 = html, etc. |
| activate | bool | Initial value for stored `isActive`. |
| freeze | bool | If true, renders the route immutable. |


### updateRoute


Update an existing route (target, routeType, activate, freeze in one tx).

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist and must not already be frozen.

```solidity
function updateRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routePrefix | string | Route prefix of the route path to be updated (may be empty). |
| route | string | Route label of the route path to be updated. |
| target | address | New target address. Must be non-zero. |
| routeType | uint32 | New route type integer. |
| activate | bool | New value for stored `isActive`. |
| freeze | bool | If true, renders the route immutable. Emits `RouteTargetUpdated`, `RouteTypeUpdated`, and/or `RouteActiveStatusUpdated` only when the corresponding stored field changes; emits `RouteFrozen` when `freeze` is true. |


### activateRoute


Mark an existing route as active.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function activateRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Route prefix of the route path to be activated (may be empty). |
| route | string | Route label of the route path to be activated. |


### deactivateRoute


Mark an existing route as inactive.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze.

```solidity
function deactivateRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Route prefix of the route path to be deactivated (may be empty). |
| route | string | Route label of the route path to be deactivated. |


### deleteRoute


Remove a route so `createRoute` may register the same key again.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist and must not already be frozen.

Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting.

```solidity
function deleteRoute(string xnsName, string routePrefix, string route) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Route prefix of the route path to be deleted (may be empty). |
| route | string | Route label of the route path to be deleted. |


### updateTarget


Update the `target` address for an existing route.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist and must not already be frozen.
- `newTarget` must not be the zero address.

Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target.

```solidity
function updateTarget(string xnsName, string routePrefix, string route, address newTarget) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Route prefix of the route path to be updated (may be empty). |
| route | string | Route label of the route path to be updated. |
| newTarget | address | New target address; must be non-zero. |


### updateRouteType


Update `routeType` for an existing route.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy character rules.
- The route must exist and must not already be frozen.

Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value.

```solidity
function updateRouteType(string xnsName, string routePrefix, string route, uint32 newRouteType) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routePrefix | string | Route prefix of the route path to be updated (may be empty). |
| route | string | Route label of the route path to be updated. |
| newRouteType | uint32 | New route type integer. |


### freezeRoute


Freeze a single route forever.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.
- The route book for `xnsName` must not be frozen.
- Non-empty `routePrefix` and `route` must satisfy character rules.
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
| routePrefix | string | Route prefix of the route path to be frozen (may be empty). |
| route | string | Route label of the route path to be frozen. |


### freezeRouteBook


Freeze the entire route book under an XNS name forever.

**Effects (irreversible):**
- No new routes may be added under `xnsName`.
- No existing route targets may be changed under `xnsName`.
- Routes may not be deleted under `xnsName`.
- `freezeRoute` may not be called for routes under `xnsName`.
- Route activation can still be toggled.

**Requirements:**
- `msg.sender` must be the XNS name owner of `xnsName`.

```solidity
function freezeRouteBook(string xnsName) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name whose route book to freeze. |


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
| routePrefix | string | Route prefix of the route path to be queried (may be empty). |
| route | string | Route label of the route path to be queried. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Stored target address for the route. |
| isActive | bool | Whether the route is active. |
| isFrozen | bool | Whether the route is frozen. |
| routeType | uint32 | Route type integer. |

### getRouteInfoFromPath


Same as `getRouteInfo` with `fullRoutePath` parsed by `splitFullPath`.

**Requirements:**
- `fullRoutePath` must contain at least one `/`.
- Further requirements match `getRouteInfo` for the parsed components.

```solidity
function getRouteInfoFromPath(string fullRoutePath) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| fullRoutePath | string | The full route path to get the route info for. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Stored target address for the route. |
| isActive | bool | Whether the route is active. |
| isFrozen | bool | Whether the route is frozen. |
| routeType | uint32 | Route type integer. |

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
| routePrefix | string | Route prefix of the route path to be queried (may be empty). |
| route | string | Route label of the route path to be queried. |

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


Number of entries in the append-only route-key log for `xnsName`
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
the array, returns an empty array. Reverts only when `start > end`.

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


Utility function to parse `fullRoutePath` into `(xnsName, routePrefix, route)`.

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
| route | string | Remainder of the routePath after `routePrefix` and `:`, or the whole routePath if there is no `:`. |

### isValidRoutePrefix


Returns whether `routePrefix` satisfies local prefix rules. Empty string is valid
(no prefix); non-empty must be 1–20 chars and match the slug charset/hyphen rules.

```solidity
function isValidRoutePrefix(string routePrefix) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routePrefix | string | Candidate route-prefix segment (may be empty). |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True when `routePrefix` is empty or passes `_isValidRoutePrefix`. |

### isValidRoute


Returns whether `route` satisfies local route rules (1–32 chars, slug charset/hyphen rules).

```solidity
function isValidRoute(string route) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| route | string | Candidate route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True when `route` passes `_isValidRoute`. |

### isValidRoutePrefixAndRoute


Returns whether `(routePrefix, route)` would pass validation used by mutating and tuple-based view functions.

```solidity
function isValidRoutePrefixAndRoute(string routePrefix, string route) external pure returns (bool valid)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| routePrefix | string | Candidate route-prefix segment (may be empty). |
| route | string | Candidate route label. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| valid | bool | True when the tuple passes `_validateRoutePrefixAndRoute` rules. |


## Events

### RouteCreated




```solidity
event RouteCreated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, address target, bool isActive, bool isFrozen, uint32 routeType)
```

_Emitted in `createRoute`._




### RouteTargetUpdated




```solidity
event RouteTargetUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, address previousTarget, address newTarget)
```

_Emitted in `updateTarget` when target changes, and in `updateRoute` when `target` changes._




### RouteTypeUpdated




```solidity
event RouteTypeUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, uint32 previousRouteType, uint32 newRouteType)
```

_Emitted in `updateRouteType` when route type changes, and in `updateRoute` when `routeType` changes._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route, bool isActive)
```

_Emitted in `activateRoute`, `deactivateRoute`, and `updateRoute` when `isActive` changes._




### RouteFrozen




```solidity
event RouteFrozen(bytes32 nameHash, bytes32 routeKey, string xnsName, string routePrefix, string route)
```

_Emitted in `updateRoute` and `freezeRoute` when an existing route becomes frozen.
Initial freeze-at-create is reflected only in `RouteCreated` (`isFrozen`)._




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
```




_Data structure to store route metadata._






# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry for XNS names which enables XNS name owners to map URL-style
identifiers to any Ethereum address. Routes may point to EOAs and smart contracts,
including helper/view contracts returning arbitrary data, such as Bitcoin or
Solana addresses, calldata, or other information.

Routes are addressed with XRL (XNS Route Link) strings. The format is:

XRL = `xnsName/[routeScope:]routeLabel[/params]`

- **xnsName** — XNS name that owns the route book (e.g. `bob.xns`).
- **routeScope** — optional segment before `:` (1–20 chars if present).
- **routeLabel** — required slug (1–32 chars).
- **params** — optional parameters for off-chain route parsers; not stored or validated on-chain.
- The segment `[routeScope:]routeLabel` is referred to as **route**.
- The segment `xnsName/[routeScope:]routeLabel` (XRL without the params tail) is referred to as **Registry XRL**.

Examples XRLs:
- `alice.og/my-sub-wallet` (without routeScope)
- `contracts.aave/eth:v3-pool-contract` (with routeScope)
- `bob.xns/uniswap:approve-usdt/amount=10` (with routeScope and params)

`routeScope` and `routeLabel` must follow the same character and hyphenation rules as XNS names:
- Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
- Cannot start or end with '-'
- Cannot contain consecutive hyphens ('--')

Each registry XRL points to a `target`. Once created, `target` and `routeType` are immutable.

Route metadata and controls:

**Route type**
- Off-chain hint for route parsers on how to interpret `target`.
- Examples: `0` = EOA, `1` = smart contract, `2` = calldata builder, `3` = Bitcoin address,
  `4` = Solana address, etc.

**Immutable routes**
- `target` and `routeType` cannot change after creation; routes cannot be deleted.
- Gives users a guarantee that the binding will not change.

**Active status & activeController**
- Routes can be active or inactive (`isActive`).
- `activeController` is the only account that may call `activateRoute` / `deactivateRoute`.
- Useful to tell off-chain parsers not to resolve a route (e.g. deprecated or paused).
- Set at create (`createRoute` defaults to the XNS name owner; `createRouteWithController` for explicit choice).
- `activeController` must not be `address(0)`.

**Route book freeze**
- The XNS name owner can freeze the entire route book for an XNS name (`freezeRouteBook`).
- Prevents adding new routes under that name. Existing routes are unchanged.
- Existing routes can still be activated or deactivated by their `activeController`.
- Use `getRouteRecordWithBookStatus` to read `record` and `isRouteBookFrozen` in one call.

**Other**
- Routes are owned by the XNS name owner; registration is free and unlimited.
- Route record: `target`, `routeType`, `isActive`, `activeController`.
- Forward resolution: registry XRL -> `target`. Use `resolveRouteIfActive` for safe reads
  or `resolveRoute` for raw resolution. Reverse lookup is not supported because many routes
  may point to the same `target`.
- Bare names like `bob` are stored as `bob.x`.
- `routeKey` = hash of canonical registry XRL.
- List routes on-chain with `getRouteKeyCount` and `getRouteKeys`.






## Functions

### createRoute


Create a route `[xnsName]/[routeScope:][routeLabel]` with `isActive = true` and
`activeController` set to the current XNS name owner.

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
function createRoute(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action". |
| routeScope | string | Optional path segment before `:`; non-empty must pass local route scope rules ([a-z0-9-], max length 20); empty means `xnsName/routeLabel` only (no `:` in the route). |
| routeLabel | string | Required route label ([a-z0-9-], max length 32). |
| target | address | Target address for `routeType`; must be non-zero (`address(0)` is reserved for non-existent route). |
| routeType | uint32 | Parser hint for how to interpret `target` (off-chain semantics), e.g. 0 = plain address, 2 = Bitcoin address, 3 = address exposing a html, etc. |


### createRouteWithController


Same as `createRoute` but with explicit `isActive` and `activeController`.
Use when toggling `isActive` should be delegated to another account.

Same requirements as `createRoute`, plus:
- `activeController` must not be `address(0)`.

```solidity
function createRouteWithController(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType, bool isActive, address activeController) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string |  |
| routeScope | string |  |
| routeLabel | string |  |
| target | address |  |
| routeType | uint32 |  |
| isActive | bool | Initial value for stored `isActive`. |
| activeController | address | Account that may toggle `isActive` via `activateRoute` / `deactivateRoute`. |


### activateRoute


Mark an existing route as active.

**Requirements:**
- `msg.sender` must be `record.activeController`.
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.
- The route must exist.

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

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

Emits `RouteActiveStatusUpdated` only when `isActive` changes.

```solidity
function deactivateRoute(string xnsName, string routeScope, string routeLabel) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space. |
| routeScope | string | Route scope of the route path to be deactivated (may be empty). |
| routeLabel | string | Route label of the route path to be deactivated. |


### freezeRouteBook


Freeze the entire route book under an XNS name forever.

**Effects (irreversible):**
- No new routes may be added under `xnsName`.
- Existing routes are unchanged; `activeController` can still toggle `isActive`.

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
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, activeController). |

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
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, activeController). |

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
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, activeController). |

### getRouteRecordWithBookStatus


Reads stored route record data and route-book freeze status by
`(xnsName, routeScope, routeLabel)`.

`details.record.target == address(0)` means that record does not exist.
Route-book freeze is name-scoped and not stored in `RouteRecord`.

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

### resolveRoute


Resolves a route to `(target, routeType)` regardless of `isActive`.

**Requirements:**
- The route must exist (`target != address(0)`).
- Non-empty `routeScope` and `routeLabel` must satisfy character rules.

```solidity
function resolveRoute(string xnsName, string routeScope, string routeLabel) external view returns (address target, uint32 routeType)
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

### resolveRoute


Resolves a route to `(target, routeType)` by registry XRL (`splitRegistryXRL`).

**Requirements:** same as `resolveRoute(xnsName, routeScope, routeLabel)`.

```solidity
function resolveRoute(string registryXRL) external view returns (address target, uint32 routeType)
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


Number of entries in the append-only route-key log for `xnsName`.

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
Useful when calling tuple-based mutating functions (`createRoute`, etc.).

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
event RouteCreated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address target, uint32 routeType, bool isActive, address activeController)
```

_Emitted in `createRoute` and `createRouteWithController`._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 nameHash, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, bool isActive)
```

_Emitted in `activateRoute` and `deactivateRoute` when `isActive` changes._




### RouteBookFrozen




```solidity
event RouteBookFrozen(bytes32 nameHash, string canonicalXNSName)
```

_Emitted in `freezeRouteBook` when the route book is frozen for an XNS name._







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






# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry for XNS names which enables XNS name owners to map URL-style
identifiers, so-called **routes**, to any Ethereum address. Routes may point to EOAs and
smart contracts, including helper/view contracts returning arbitrary data, such as Bitcoin
or Solana addresses, calldata, or other information. Registration is free and reserved for
the XNS name owner only.

Route format: `xnsName/[routeScope:]routeLabel`

- **xnsName** – XNS name that owns the route book (e.g. `bob.xns`, `contracts.aave`).
- **routeScope** – optional segment before `:` (1–20 chars if present).
- **routeLabel** – required slug (1–32 chars).

`routeScope` and `routeLabel` must follow the same character and hyphenation rules as XNS names:
- Must consist only of [a-z0-9-] (lowercase letters, digits, and hyphens)
- Cannot start or end with '-'
- Cannot contain consecutive hyphens ('--')

Routes may include an optional `/params…` suffix, intended for use by off-chain parsers.
These parameters are ignored by the contract and are neither stored nor processed on-chain.

Examples:
- `alice.og/my-sub-wallet` (route without routeScope)
- `contracts.aave/eth:v3-pool-contract` (route with routeScope)
- `safe.uni/uniswap:approve-usdt/amount=10` (route with routeScope and params)

**Route record**
- `target` — EOA or contract the route resolves to.
- `routeType` — off-chain parser hint (semantics agreed off-chain; examples below).
- `isActive` — whether parsers should treat the route as usable.
- `activeController` — account that may toggle `isActive`.

`target` and `routeType` are fixed at creation; routes cannot be deleted.

**Route type examples**
- `0` = `target` is the answer (EOA/smart contract)
- `1` = `target` must be queried (e.g. for a Bitcoin or Solana address)
- `2` = `target` returns executable calldata

The exact semantics of `routeType` are agreed off-chain and are not enforced by the contract.

**Active status & activeController**
- The `activeController` is the account that controls whether a route is active or not.
- The `activeController` can change the route's active status, transfer this control to someone else,
  or give up control permanently (which locks the route's status).
- Inactive routes (e.g. deprecated or paused) should not be resolved by off-chain parsers;
  use `resolveRouteIfActive` to resolve active routes only.
- At create: `createRoute` sets `activeController` to the XNS name owner;
  `createRouteWithController` accepts an explicit controller; both default to `isActive = true`.
- `activeController` must not be `address(0)`.
- The `isActive` status may be locked by setting `activeController` equal to `NO_ACTIVE_CONTROLLER`
  address.

**Route book freeze**
- The XNS name owner may freeze the route book permanently by calling `freezeRouteBook`
- Freezing a route book is irreversible
- Under a frozen route book, no new routes can be created; existing routes remain unchanged;
  `activeController` can still toggle `isActive` on existing routes.

**Resolution & indexing**
- Forward: route -> `target` via `resolveRouteIfActive` (requires `isActive`) or
  `resolveRoute` (ignores `isActive`). No reverse lookup because many routes may share a `target`.
- Bare names like `bob` normalize to `bob.x` (canonical XNS name). `routeKey` = hash of canonical route.
- The route list can be queried with `getRouteKeyCount` and `getRouteKeys`.






## Functions

### createRoute


Create a route `[xnsName]/[routeScope:][routeLabel]`. `isActive` is set to true and
`activeController` to the current XNS name owner.

**Requirements:**
- `msg.sender` must be the owner for `xnsName`.
- Non-empty `routeScope` and `routeLabel` must satisfy local character rules.
- `routeLabel` must be a non-empty string.
- `target` must not be the zero address.
- The route book for `xnsName` must not be frozen.
- The route key must not already exist.

On success, adds the route key to `_routeKeysByXNSName` for `xnsName`, queryable via
`getRouteKeys`.
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
| routeType | uint32 | Parser hint for how to interpret `target` (off-chain semantics). |


### createRouteWithController


Same as `createRoute` but with an explicit `activeController`.
Use when toggling `isActive` should be delegated to another account.

Same requirements as `createRoute`, plus:
- `activeController` must not be `address(0)`.

Note: If `activeController` is set to `NO_ACTIVE_CONTROLLER`, the route's `isActive` status is locked
and cannot be changed after creation.

```solidity
function createRouteWithController(string xnsName, string routeScope, string routeLabel, address target, uint32 routeType, address activeController) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string |  |
| routeScope | string |  |
| routeLabel | string |  |
| target | address |  |
| routeType | uint32 |  |
| activeController | address | Account that may toggle `isActive` via `activateRoute` / `deactivateRoute`. |


### activateRoute


Mark an existing route as active.

**Requirements:**
- `msg.sender` must be `record.activeController`.
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


### initiateActiveControllerTransfer


Start a two-step transfer of `activeController` to `newActiveController`.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- The route must exist and active control must not be renounced.
- `newActiveController` must not be zero, the current controller, or
  `NO_ACTIVE_CONTROLLER` (use `renounceActiveControl` instead).

Replaces any existing pending transfer for this route.

```solidity
function initiateActiveControllerTransfer(string xnsName, string routeScope, string routeLabel, address newActiveController) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string |  |
| routeScope | string |  |
| routeLabel | string |  |
| newActiveController | address | Account that must call `acceptActiveController` to complete the transfer. |


### acceptActiveController


Complete a pending `activeController` transfer.

**Requirements:**
- `msg.sender` must be the pending `newActiveController` from `initiateActiveControllerTransfer`.
- The route must exist and active control must not be renounced.

```solidity
function acceptActiveController(string xnsName, string routeScope, string routeLabel) external
```




### cancelActiveControllerTransfer


Cancel a pending `activeController` transfer.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- A pending transfer must exist.

```solidity
function cancelActiveControllerTransfer(string xnsName, string routeScope, string routeLabel) external
```




### renounceActiveControl


Permanently renounce active control: sets `activeController` to
`NO_ACTIVE_CONTROLLER`. `isActive` is left unchanged and can no longer be toggled.

**Requirements:**
- `msg.sender` must be the current `activeController`.
- Active control must not already be renounced.

Clears any pending transfer.

```solidity
function renounceActiveControl(string xnsName, string routeScope, string routeLabel) external
```




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


Reads stored route record data by route string (`splitRoute`).
`record.target == address(0)` means that record does not exist.

```solidity
function getRouteRecord(string route) external view returns (struct XNSRoutes.RouteRecord record)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| route | string | Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| record | struct XNSRoutes.RouteRecord | The route record (target, routeType, isActive, activeController). |

### resolveRouteIfActive


Resolves an active route to `(target, routeType)`.

**Requirements:**
- The route must exist (`target != address(0)`).
- `isActive` must be true.

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


Resolves an active route to `(target, routeType)` by route string (`splitRoute`).

**Requirements:** same as `resolveRouteIfActive(xnsName, routeScope, routeLabel)`.

```solidity
function resolveRouteIfActive(string route) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| route | string | Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| target | address | Resolved target address. |
| routeType | uint32 | Parser hint for how to interpret `target`. |

### resolveRoute


Resolves a route to `(target, routeType)` regardless of `isActive`.

**Requirements:**
- The route must exist (`target != address(0)`).

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


Resolves a route to `(target, routeType)` by route string (`splitRoute`).

**Requirements:** same as `resolveRoute(xnsName, routeScope, routeLabel)`.

```solidity
function resolveRoute(string route) external view returns (address target, uint32 routeType)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| route | string | Route, e.g. `bob.xns/eth:my-wallet`, without a parametrized `/params…` tail. |

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

### pendingActiveController


Pending `acceptActiveController` recipient for a route, or `address(0)` if none.

```solidity
function pendingActiveController(string xnsName, string routeScope, string routeLabel) external view returns (address pending)
```




### getRouteKeyCount


Number of route keys registered under `xnsName`.

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

### splitRoute


Parses a route into `(xnsName, routeScope, routeLabel)`.
Example: `bro.xns/eth:my-wallet` -> `(bro.xns, eth, my-wallet)`.
Useful when calling tuple-based mutating functions (`createRoute`, etc.).

A route is `xnsName/[routeScope:]routeLabel` — not a parametrized route (no `/params…` tail).
Does not validate segments; malformed input may still parse but fail downstream.

Requires `route` to contain at least one `/`.

```solidity
function splitRoute(string route) external pure returns (string xnsName, string routeScope, string routeLabel)
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| route | string | Route (not a parametrized route), e.g. `bob.xns/eth:transfer-usdt`. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | Segment before the first `/`. |
| routeScope | string | Segment before the first `:` in the segment after `/`, or empty if there is no `:`. |
| routeLabel | string | Segment after `:` if `routeScope` is present, else the whole segment after `/`. |

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
event RouteCreated(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address target, uint32 routeType, bool isActive, address activeController)
```

_Emitted in `createRoute` and `createRouteWithController`._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, bool isActive)
```

_Emitted in `activateRoute` and `deactivateRoute` when `isActive` changes._




### RouteBookFrozen




```solidity
event RouteBookFrozen(bytes32 xnsNameKey, string canonicalXNSName)
```

_Emitted in `freezeRouteBook` when the route book is frozen for an XNS name._




### ActiveControllerTransferInitiated




```solidity
event ActiveControllerTransferInitiated(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address pendingActiveController)
```

_Emitted in `initiateActiveControllerTransfer`._




### ActiveControllerTransferAccepted




```solidity
event ActiveControllerTransferAccepted(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address previousActiveController, address newActiveController)
```

_Emitted in `acceptActiveController`._




### ActiveControllerTransferCancelled




```solidity
event ActiveControllerTransferCancelled(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel, address cancelledPendingActiveController)
```

_Emitted in `cancelActiveControllerTransfer`._




### ActiveControllerRenounced




```solidity
event ActiveControllerRenounced(bytes32 xnsNameKey, bytes32 routeKey, string canonicalXNSName, string routeScope, string routeLabel)
```

_Emitted in `renounceActiveControl`._







## State Variables

### NO_ACTIVE_CONTROLLER


Special sentinel value for `activeController` indicating permanent
renouncement of control. When a route's `activeController` is set to this address,
its `isActive` status is locked and cannot be changed.

Uses 0x…dEaD rather than `address(0)` because `address(0)` is rejected as an invalid
`activeController` at create.

```solidity
address NO_ACTIVE_CONTROLLER
```





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






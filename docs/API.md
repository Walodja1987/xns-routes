# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry linked to the XNS contract on Ethereum (0x648E4F05aF2b7eB85109A8dc8AE81D8E006457D8).

Routes are scoped under an XNS name plus optional `routePrefix` and a required `route` label. Human-readable paths look like:
`bob.xns/eth:transfer-usdt/to=0x.../amount=100`
Prefix-agnostic routes: use empty `routePrefix` — path form `bob.xns/my-wallet/...` (no `:` in the action segment).
- xnsName: `bob.xns`
- routePrefix: optional disambiguator before `:` (XNS label rules when non-empty; e.g. `eth`, `1-eth`, `137-poly`), or `""` when omitted
- route: required action label after `:` when `routePrefix` is set, e.g. `transfer-usdt`
With a non-empty `routePrefix`, exactly one `:` appears in the action segment, between `routePrefix` and `route`.

Storage key: if `routePrefix` is empty, `keccak256(abi.encodePacked(xnsName, "/", route))`; else `keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route))`.
`routePrefix` and `route` follow XNS label charset (`a-z`, `0-9`, `-`); `xnsName` is a registered XNS full name (no `/` or `:`).

A route points to a `target` address; `routeType` is an opaque hint (e.g. how parsers interpret
`target` or its calldata output). Meaning of type ids is agreed offchain; the contract stores any `uint32`.

Ownership model:
- only the current address resolved by XNS for `xnsName` may manage routes under that name

Route state model:
- target: address (e.g. builder contract or plain contract depending on `routeType`); must be non-zero.
  An empty mapping slot has `target == address(0)`; that is the only "route does not exist" state.
- routeType: parser hint; semantics are offchain (e.g. 0 = EVM address, 1 = tx calldata builder, …)
- isActive: whether wallets/apps should treat the route as usable
- isFrozen: whether `target` and `routeType` can still be changed

Route book freeze model (`routeBookFrozen` keyed by `keccak256(bytes(xnsName))`):
- no new routes may be added under that `xnsName`
- no existing route targets under that name may be changed anymore
- routes may not be deleted under that name
- route activation can still be toggled even after route book freeze

Semantics:
- while the route is not frozen and the route book for that XNS name is not frozen, owner may update `target` and `routeType`
- route freeze is irreversible
- route book freeze is irreversible
- active/inactive can be toggled even after freeze
- createRoute / updateRoute for full-record writes (+ optional freeze on create/update)
- updateTarget / updateRouteType are narrow updates (same guards as updateRoute for target/type); emit `RouteTargetUpdated` / `RouteTypeUpdated` only on change
- deleteRoute clears a route when it is not per-route frozen and the route book is not frozen (`createRoute` may reuse the key afterward)






## Functions

### createRoute


Create a route under `(xnsName, routePrefix, route)`. Reverts if that key already exists.

```solidity
function createRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```

_Enforces owner, XNS label rules on non-empty `routePrefix` and on `route`, non-zero `target`, and route book not frozen before deriving the key._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action" |
| routePrefix | string | Optional path segment before `:`; non-empty must pass XNS label rules; empty means `xnsName/route/...` only (no `:` in the action segment). |
| route | string | Required action label (XNS label rules), e.g. "transfer-usdt" |
| target | address | Build address for `routeType`; must be non-zero (`address(0)` is reserved for "missing route"). |
| routeType | uint32 | Opaque hint for parsers (semantics offchain) |
| activate | bool | Initial value for stored `isActive` |
| freeze | bool | If true, set stored `isFrozen` in this same tx (irreversible for that route) |


### updateRoute


Update an existing route (target, routeType, activate, optional freeze in one tx).

```solidity
function updateRoute(string xnsName, string routePrefix, string route, address target, uint32 routeType, bool activate, bool freeze) external
```

_Enforces owner, non-zero `target`, route book not frozen, then derives the key. Does not re-validate `routePrefix`/`route` against XNS label rules (saves gas); wrong or invalid strings usually revert `RouteNotFound`._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action" |
| routePrefix | string | Same as at create time (may be empty). |
| route | string | Same as at create time |
| target | address | Must be non-zero; use a burn address if an unusable target is required. |
| routeType | uint32 | Opaque hint for parsers (semantics offchain) |
| activate | bool | New value for stored `isActive` |
| freeze | bool | If true, set stored `isFrozen` in this same tx (irreversible for that route) |


### activateRoute


Mark an existing route as active.

```solidity
function activateRoute(string xnsName, string routePrefix, string route) external
```

_Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze._



### deactivateRoute


Mark an existing route as inactive.

```solidity
function deactivateRoute(string xnsName, string routePrefix, string route) external
```

_Emits `RouteActiveStatusUpdated` only when `isActive` changes. Allowed after route or route book freeze._



### deleteRoute


Remove a route so `createRoute` may register the same key again.

```solidity
function deleteRoute(string xnsName, string routePrefix, string route) external
```

_Reverts if the route is frozen (`CannotDeleteFrozenRoute`) or the route book is frozen (`RouteBookFrozen`).
Does not check `isActive`; use `deactivateRoute` for a soft disable without deleting._



### updateTarget


Update the build `target` for an existing route.

```solidity
function updateTarget(string xnsName, string routePrefix, string route, address newTarget) external
```

_Same constraints as `updateRoute` for target changes: not route-frozen, not route-book frozen.
Emits `RouteTargetUpdated` only when `newTarget` differs from the stored target._



### updateRouteType


Update `routeType` for an existing route.

```solidity
function updateRouteType(string xnsName, string routePrefix, string route, uint32 newRouteType) external
```

_Same constraints as `updateRoute` for type changes: not route-frozen, not route-book frozen.
Emits `RouteTypeUpdated` only when `newRouteType` differs from the stored value._



### freezeRoute


Freeze a single route forever.

```solidity
function freezeRoute(string xnsName, string routePrefix, string route) external
```

_After freezing, `target` and `routeType` can never be changed again.
Active/inactive can still be toggled._



### freezeRouteBook


Freeze the entire route book under an XNS name forever.

```solidity
function freezeRouteBook(string xnsName) external
```

_After this:
- no new routes may be added under `xnsName`
- no existing route targets may be changed under `xnsName`
- routes may not be deleted under `xnsName`
- route activation can still be toggled_



### getRouteInfo


Return full route metadata. Reverts if not found.

```solidity
function getRouteInfo(string xnsName, string routePrefix, string route) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType)
```




### routeExists


Returns whether a route exists (`target` was ever set via `createRoute`; zero `target` is never stored).

```solidity
function routeExists(string xnsName, string routePrefix, string route) external view returns (bool)
```





## Events

### RouteCreated




```solidity
event RouteCreated(string xnsName, string routePrefix, string route, address target, bool isActive, bool isFrozen, uint32 routeType)
```

_Strings are non-indexed so logs carry full values (e.g. subgraphs). `target` is indexed for address filters._




### RouteUpdated




```solidity
event RouteUpdated(string xnsName, string routePrefix, string route, address target, bool isActive, bool isFrozen, uint32 routeType)
```





### RouteTargetUpdated




```solidity
event RouteTargetUpdated(string xnsName, string routePrefix, string route, address newTarget)
```

_Narrow `updateTarget`; `newTarget` indexed for address filters._




### RouteTypeUpdated




```solidity
event RouteTypeUpdated(string xnsName, string routePrefix, string route, uint32 newRouteType)
```

_Narrow `updateRouteType`._




### RouteActiveStatusUpdated




```solidity
event RouteActiveStatusUpdated(string xnsName, string routePrefix, string route, bool isActive)
```





### RouteFrozen




```solidity
event RouteFrozen(string xnsName, string routePrefix, string route)
```





### RouteBookFrozenForName




```solidity
event RouteBookFrozenForName(string xnsName)
```





### RouteDeleted




```solidity
event RouteDeleted(string xnsName, string routePrefix, string route)
```







## Errors

### ZeroAddress




```solidity
error ZeroAddress()
```





### InvalidXnsName




```solidity
error InvalidXnsName()
```





### InvalidRoutePrefix




```solidity
error InvalidRoutePrefix()
```





### InvalidRoute




```solidity
error InvalidRoute()
```





### InvalidTarget




```solidity
error InvalidTarget()
```





### NotXnsNameOwner




```solidity
error NotXnsNameOwner()
```





### RouteNotFound




```solidity
error RouteNotFound()
```





### CannotUpdateFrozenRoute




```solidity
error CannotUpdateFrozenRoute()
```





### RouteBookFrozen




```solidity
error RouteBookFrozen()
```





### RouteAlreadyExists




```solidity
error RouteAlreadyExists()
```





### CannotDeleteFrozenRoute




```solidity
error CannotDeleteFrozenRoute()
```






## State Variables

### XNS




```solidity
contract IXNSMinimal XNS
```





### routeBookFrozen




```solidity
mapping(bytes32 => bool) routeBookFrozen
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










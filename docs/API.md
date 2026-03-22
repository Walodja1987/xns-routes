# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry linked to the XNS contract on Ethereum (0x648E4F05aF2b7eB85109A8dc8AE81D8E006457D8).

Routes are scoped under an XNS name plus a chain key and route label. Human-readable paths look like:
`bob.xns/eth:transfer-usdt/to=0x.../amount=100`
- xnsName: `bob.xns`
- chain: `eth` (one label token; use hyphens for compound ids, e.g. `1-eth`, `137-poly`)
- route: `transfer-usdt`
Only a single `:` appears in the action segment, between `chain` and `route`.

Storage key: `keccak256(abi.encode(xnsName, chain, route))`.

A route points to a build contract that returns tx calldata.

Ownership model:
- only the current address resolved by XNS for `xnsName` may manage routes under that name

Route state model:
- target: build contract address
- isActive: whether wallets/apps should treat the route as usable
- isFrozen: whether the target pointer can still be changed

Route book freeze model (`routeBookFrozen` keyed by `keccak256(bytes(xnsName))`):
- no new routes may be added under that `xnsName`
- no existing route targets under that name may be changed anymore
- route activation can still be toggled even after route book freeze

Semantics:
- while the route is not frozen and the route book for that XNS name is not frozen, owner may update the target
- route freeze is irreversible
- route book freeze is irreversible
- active/inactive can be toggled even after freeze
- setRoute supports create/update + optional immediate freeze in one tx






## Functions

### setRoute


Create or update a route under `(xnsName, chain, route)`.

```solidity
function setRoute(string xnsName, string chain, string route, address target, bool isActive, bool freezeImmediately) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| xnsName | string | The XNS name that owns the route space, e.g. "xns.action" |
| chain | string | Chain key (XNS label rules), e.g. "eth" or "137-poly" |
| route | string | Action label (XNS label rules), e.g. "transfer-usdt" |
| target | address | The build contract address |
| isActive | bool | Initial or updated active flag |
| freezeImmediately | bool | If true, the route is frozen as part of this same tx |


### setRouteActive


Activate or deactivate a route.

```solidity
function setRouteActive(string xnsName, string chain, string route, bool isActive) external
```

_Can be called even after route freeze or route book freeze._



### freezeRoute


Freeze a single route forever.

```solidity
function freezeRoute(string xnsName, string chain, string route) external
```

_After freezing, the route target can never be changed again.
Active/inactive can still be toggled._



### freezeRoutes


Freeze the entire route book under an XNS name forever.

```solidity
function freezeRoutes(string xnsName) external
```

_After this:
- no new routes may be added under `xnsName`
- no existing route targets may be changed under `xnsName`
- route activation can still be toggled_



### getRoute


Return route target only. Reverts if not found.

```solidity
function getRoute(string xnsName, string chain, string route) external view returns (address target)
```




### getRouteInfo


Return full route metadata. Reverts if not found.

```solidity
function getRouteInfo(string xnsName, string chain, string route) external view returns (address target, bool isActive, bool isFrozen)
```




### routeExists


Returns whether a route exists.

```solidity
function routeExists(string xnsName, string chain, string route) external view returns (bool)
```




### _requireXnsNameOwner




```solidity
function _requireXnsNameOwner(string xnsName) internal view
```




### _routeKey




```solidity
function _routeKey(string xnsName, string chain, string route) internal pure returns (bytes32)
```




### _isValidString




```solidity
function _isValidString(string s) internal view returns (bool)
```

_Whether `s` satisfies XNS label/namespace rules (length, charset, hyphen rules).
Used for both `chain` and `route` arguments; callers choose `InvalidChain` vs `InvalidRoute`._




## Events

### RouteSet




```solidity
event RouteSet(string xnsName, string chain, string route, address target, bool isActive, bool isFrozen)
```

_At most three `indexed` fields (EVM limit). `route` is non-indexed for filtering via calldata/logs._




### RouteActivationSet




```solidity
event RouteActivationSet(string xnsName, string chain, string route, bool isActive)
```





### RouteFrozen




```solidity
event RouteFrozen(string xnsName, string chain, string route)
```





### RouteBookFrozenForName




```solidity
event RouteBookFrozenForName(string xnsName)
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





### InvalidChain




```solidity
error InvalidChain()
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






## State Variables

### XNS




```solidity
contract IXNS XNS
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
  bool isActive;
  bool isFrozen;
  bool exists;
```










# XNS Routes Contract Documentation

This is an automatically generated documentation (using `solidity-docgen` package) for the XNS Routes contract based on the NatSpec comments in the code.

## XNSRoutes


Route registry linked to an already deployed XNS contract.

Routes are scoped under an existing XNS name, e.g.:
- baseName: "xns.action"
- route:    "register-name"

A route points to a build contract that returns tx calldata.

Ownership model:
- only the current address resolved by XNS for `baseName` may manage routes under that name

Route state model:
- target: build contract address
- isActive: whether wallets/apps should treat the route as usable
- isFrozen: whether the target pointer can still be changed

Base freeze model:
- baseRoutesFrozen[baseName] means no new routes may be added under that name
- and no existing route targets under that name may be changed anymore
- route activation can still be toggled even after base freeze

Semantics:
- while neither the route nor the base name is frozen, owner may update the target
- route freeze is irreversible
- base freeze is irreversible
- active/inactive can be toggled even after freeze
- setRoute supports create/update + optional immediate freeze in one tx






## Functions

### setRoute


Create or update a route under `baseName`.

```solidity
function setRoute(string baseName, string route, address target, bool isActive, bool freezeImmediately) external
```


#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| baseName | string | The XNS name that owns the route space, e.g. "xns.action" |
| route | string | The route label, e.g. "register-name" |
| target | address | The build contract address |
| isActive | bool | Initial or updated active flag |
| freezeImmediately | bool | If true, the route is frozen as part of this same tx Behavior: - new route:   - created with the provided target and isActive   - frozen immediately if `freezeImmediately == true` - existing mutable route:   - target updated   - isActive updated   - frozen immediately if `freezeImmediately == true` Requirements: - caller must be current owner/resolved address of `baseName` - route must be valid - target must not be zero - base name must not be base-frozen - route must not already be route-frozen |


### setRouteActive


Activate or deactivate a route.

```solidity
function setRouteActive(string baseName, string route, bool isActive) external
```

_Can be called even after route freeze or base freeze._



### freezeRoute


Freeze a single route forever.

```solidity
function freezeRoute(string baseName, string route) external
```

_After freezing, the route target can never be changed again.
Active/inactive can still be toggled._



### freezeRoutes


Freeze the entire route book under a base name forever.

```solidity
function freezeRoutes(string baseName) external
```

_After this:
- no new routes may be added under `baseName`
- no existing route targets may be changed under `baseName`
- route activation can still be toggled_



### getRoute


Return route target only. Reverts if not found.

```solidity
function getRoute(string baseName, string route) external view returns (address target)
```




### getRouteInfo


Return full route metadata. Reverts if not found.

```solidity
function getRouteInfo(string baseName, string route) external view returns (address target, bool isActive, bool isFrozen)
```




### routeExists


Returns whether a route exists.

```solidity
function routeExists(string baseName, string route) external view returns (bool)
```




### _requireBaseNameOwner




```solidity
function _requireBaseNameOwner(string baseName) internal view
```




### _routeKey




```solidity
function _routeKey(string baseName, string route) internal pure returns (bytes32)
```




### _isValidRoute




```solidity
function _isValidRoute(string route) internal view returns (bool)
```





## Events

### RouteSet




```solidity
event RouteSet(string baseName, string route, address target, bool isActive, bool isFrozen)
```





### RouteActivationSet




```solidity
event RouteActivationSet(string baseName, string route, bool isActive)
```





### RouteFrozen




```solidity
event RouteFrozen(string baseName, string route)
```





### BaseRoutesFrozenForName




```solidity
event BaseRoutesFrozenForName(string baseName)
```







## Errors

### ZeroXNS




```solidity
error ZeroXNS()
```





### InvalidBaseName




```solidity
error InvalidBaseName()
```





### InvalidRoute




```solidity
error InvalidRoute()
```





### InvalidTarget




```solidity
error InvalidTarget()
```





### NotBaseNameOwner




```solidity
error NotBaseNameOwner()
```





### RouteNotFound




```solidity
error RouteNotFound()
```





### CannotUpdateFrozenRoute




```solidity
error CannotUpdateFrozenRoute()
```





### BaseRoutesFrozen




```solidity
error BaseRoutesFrozen()
```






## State Variables

### XNS




```solidity
contract IXNSMinimal XNS
```





### baseRoutesFrozen




```solidity
mapping(bytes32 => bool) baseRoutesFrozen
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










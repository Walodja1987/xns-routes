# SponsoredRoutes tests

Contract: [`contracts/src/examples/SponsoredRoutes.sol`](../contracts/src/examples/SponsoredRoutes.sol)
Tests: [`test/SponsoredRoutes.test.ts`](SponsoredRoutes.test.ts)
Mocks: [`contracts/src/mocks/MockXNS.sol`](../contracts/src/mocks/MockXNS.sol), deployed together with `XNSRoutes`.

`SponsoredRoutes` owns an XNS name and can only create frozen routes under it. It has no path to update or deactivate a route, so every sponsored route stays resolvable forever.

---

## Constructor

#### Functionality

- Registers `label@namespace` on XNS for the contract itself (forwarding `msg.value`).
- Stores `owner`, `XNS_ROUTES`, `xnsLabel` and `xnsNamespace`.

#### Reverts

- `"SponsoredRoutes: 0x XNS address"` when `xnsContract` is the zero address.
- `"SponsoredRoutes: 0x XNSRoutes"` when `xnsRoutesContract` is the zero address.
- `OwnableInvalidOwner(address(0))` when `initialOwner` is the zero address.

---

## `sponsorRoute`

#### Functionality

- Calls `XNSRoutes.createRouteAndFreeze` for `label@namespace/routeLabel`.
- The route is frozen and active, and `resolveRoute` returns it immediately.

#### Events

- `XNSRoutes` emits `RouteCreated` followed by `RouteFrozen`.

#### Reverts

- `OwnableUnauthorizedAccount(caller)` when the caller is not the owner.
- `XNSRoutes` errors bubble up: `"XNSRoutes: invalid route label"`, `"XNSRoutes: invalid target"`, `"XNSRoutes: route book closed"`, `"XNSRoutes: route already exists"`.

---

## `closeRouteBook`

#### Functionality

- Calls `XNSRoutes.closeRouteBook(label, namespace)`; further `sponsorRoute` calls revert with `"XNSRoutes: route book closed"`.
- Existing routes keep resolving.

#### Events

- `XNSRoutes` emits `RouteBookClosed`.

#### Reverts

- `OwnableUnauthorizedAccount(caller)` when the caller is not the owner.

---

## Permanence guarantee

- The ABI exposes only `sponsorRoute`, `closeRouteBook`, the three getters (`XNS_ROUTES`, `xnsLabel`, `xnsNamespace`) and the `Ownable2Step` functions; nothing can update, deactivate or forward calls.
- The contract owner cannot manage routes directly on `XNSRoutes` (`"XNSRoutes: not XNS name owner"`).
- After `renounceOwnership`, no new routes can be sponsored and existing routes keep resolving.

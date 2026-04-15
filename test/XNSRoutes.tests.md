# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

Failures use Solidity `require` revert strings prefixed with `XNSRoutes: ` (same style as `XNS: ...` in the XNS registry).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `xnsName → owner` via `setResolution`. Route segment validation is local to `XNSRoutes` (not delegated to XNS): `routePrefix` allows 1–20 chars (or empty), while `route` allows 1–48 chars; both share lowercase/number/hyphen and hyphen-placement rules.
- **Canonical on-chain XNS** addresses for deploy/scripts/fork work live in [`constants/addresses.ts`](../constants/addresses.ts) as `XNS_ADDRESS` (they are not used by the default local test suite).

---

## Constructor

#### Functionality

- Stores the non-zero XNS registry address and exposes it via `XNS()`.
- Calls XNS `registerName("routes","xns")` with the constructor’s `msg.value`, so `routes.xns` resolves to the new registry (`address(this)`).
- On the mock, `getAddress("routes.xns")` returns the deployed `XNSRoutes` address after deployment.

#### Reverts

- Should revert with `"XNSRoutes: 0x XNS address"` when `_xns` is `address(0)`.
- Reverts if XNS rejects registration (e.g. insufficient `msg.value`, name taken, exclusivity rules on the real contract).

---

## `createRoute`

#### Functionality

- Name owner can **create** a route for `(xnsName, routePrefix, route)` with the given `target`, `routeType`, stored `isActive` from `activate`, and stored `isFrozen` from `freeze`.
- Second `createRoute` for the same key should revert with `"XNSRoutes: route already exists"`.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteCreated`).

#### Events

- Should emit `RouteCreated` with indexed `nameHash` (`keccak256(bytes(xnsName))`), `routeKey` (same as `_routeKey`), and `target`, then `xnsName`, `routePrefix`, `route`, `isActive`, `isFrozen`, and `routeType` (non-indexed, full values in log data).
- Should emit `RouteFrozen` with indexed `nameHash` / `routeKey` and full `xnsName`, `routePrefix`, `route` when `freeze` is true on create.

#### Reverts

- Owner, local route-segment rules on non-empty `routePrefix` and on `route` (prefix 1–20; route 1–48), non-zero `target`, `"XNSRoutes: route book frozen"`, plus `"XNSRoutes: route already exists"` if the route key already exists.

---

## `updateRoute`

#### Functionality

- Name owner can **update** `target`, `routeType`, and `isActive` (via `activate`) on an **existing** route while the entry is not frozen and the route book for that XNS name is not frozen.
- Should revert with `"XNSRoutes: route not found"` if no route exists for the key.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteUpdated`).

#### Events

- Should emit `RouteUpdated` with the same indexed `nameHash` / `routeKey` / `target` layout as `RouteCreated`, plus full strings and `isActive` / `isFrozen` / `routeType` in data.
- Should emit `RouteFrozen` (indexed `nameHash` / `routeKey` + strings) when `freeze` is true on update.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when `msg.sender` is not `XNS.getAddress(xnsName)`.
- Should revert with `"XNSRoutes: invalid XNS name"` when `XNS.getAddress(xnsName)` is zero (empty `xnsName` is included: XNS returns zero for `len == 0`).
- Should revert with `"XNSRoutes: invalid route prefix"` / `"XNSRoutes: invalid route"` when `routePrefix` or `route` fails local route-segment rules (same as `createRoute`), including empty `routePrefix` with a `route` containing `:` (prevents aliasing the canonical `prefix:route` key).
- Should revert with `"XNSRoutes: invalid target"` when `target` is zero.
- Should revert with `"XNSRoutes: route book frozen"` when `freezeRouteBook` has already been called for that `xnsName`.
- Should revert with `"XNSRoutes: cannot update frozen route"` when updating a route that is already frozen (including changing only `routeType` or only `target`).
- Should revert with `"XNSRoutes: route not found"` when the route does not exist.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- Name owner can set `isActive` to true / false for an existing `(xnsName, routePrefix, route)`.
- Should still succeed when the **route** is frozen or the **route book** is frozen (only target updates are blocked).
- Like `freezeRoute`, should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second `deactivateRoute` or `activateRoute` when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with indexed `nameHash` / `routeKey`, then `xnsName`, `routePrefix`, `route`, and `isActive` when transitioning.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the resolved owner.
- Should revert with `"XNSRoutes: route not found"` when no route exists for `(xnsName, routePrefix, route)`.

---

## `deleteRoute`

#### Functionality

- Name owner can clear a route slot (`routeExists` false); `createRoute` may register the same `(xnsName, routePrefix, route)` again afterward.
- Reverts with `"XNSRoutes: cannot delete frozen route"` if the route is per-route frozen.
- Reverts with `"XNSRoutes: route book frozen"` if the route book for `xnsName` is frozen (same as `updateRoute`).
- Independent of `isActive`; use `deactivateRoute` for a soft disable without removing the record.

#### Events

- Should emit `RouteDeleted` with indexed `nameHash` / `routeKey` and `xnsName`, `routePrefix`, `route`.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: cannot delete frozen route"`, `"XNSRoutes: route book frozen"` as above.

---

## `updateTarget` / `updateRouteType`

#### Functionality

- Name owner can change `target` or `routeType` on an existing route (not for create).
- Same freeze rules as `updateRoute` for those fields: reverts with `"XNSRoutes: cannot update frozen route"` if the route is frozen, `"XNSRoutes: route book frozen"` if the route book for `xnsName` is frozen.
- Should emit `RouteTargetUpdated` / `RouteTypeUpdated` **only when** the value actually changes (no-op otherwise).

#### Events

- `RouteTargetUpdated` with indexed `nameHash` / `routeKey` / `newTarget`, then `xnsName`, `routePrefix`, and `route`.
- `RouteTypeUpdated` with indexed `nameHash` / `routeKey`, then strings and non-indexed `newRouteType`.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: cannot update frozen route"`, `"XNSRoutes: route book frozen"` as above.
- `"XNSRoutes: invalid route prefix"` / `"XNSRoutes: invalid route"` when `routePrefix` / `route` fail local route-segment rules (same as `createRoute`).
- `updateTarget`: `"XNSRoutes: invalid target"` when `newTarget` is zero.

---

## `freezeRoute`

#### Functionality

- Name owner can set `isFrozen` permanently for an existing route.
- Second call when already frozen should **not** emit `RouteFrozen` again (no-op on storage already frozen).

#### Events

- Should emit `RouteFrozen` (indexed `nameHash` / `routeKey` + strings) the first time the route transitions to frozen.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the resolved owner.
- Should revert with `"XNSRoutes: route book frozen"` when `freezeRouteBook` has already been called for that `xnsName`.
- Should revert with `"XNSRoutes: route not found"` when the route does not exist.

---

## `freezeRouteBook`

#### Functionality

- Name owner can set `isRouteBookFrozen(xnsName)` permanently.
- After route book freeze, `createRoute`, `updateRoute`, `deleteRoute`, `updateTarget`, `updateRouteType`, and `freezeRoute` must revert for that `xnsName`, while `activateRoute` / `deactivateRoute` may still run.

#### Events

- Should emit `RouteBookFrozenForName` with indexed `nameHash` and full `xnsName` the first time the route book is frozen.
- Second call should not emit again (idempotent).

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the resolved owner.

---

## `getRouteInfo` / `routeExists`

#### Functionality

- `routeExists` returns `false` before a route is created and `true` after.
- `getRouteInfo` returns `(target, isActive, isFrozen, routeType)` consistent with `createRoute` / `updateRoute` / `updateTarget` / `updateRouteType` / `activateRoute` / `deactivateRoute` / `freezeRoute` (until `deleteRoute` clears the slot).
- Both apply the same local `routePrefix` / `route` validation as mutating functions before deriving the key.

#### Reverts

- `getRouteInfo` should revert with `"XNSRoutes: route not found"` when the route does not exist.
- Should revert with `"XNSRoutes: invalid route prefix"` / `"XNSRoutes: invalid route"` for malformed `routePrefix` / `route` (e.g. `:` in `route` when `routePrefix` is empty).

---

## `isRouteBookFrozen`

#### Functionality

- For a given `xnsName`, `isRouteBookFrozen(xnsName)` matches whether `freezeRouteBook` was applied.

---

## Route keying (regression)

#### Functionality

- Routes under different `xnsName`, `routePrefix`, or `route` are independent: key is `keccak256(abi.encodePacked(xnsName, "/", route))` if `routePrefix` is empty, else `keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route))` (empty `routePrefix` is distinct from any non-empty `routePrefix` for the same `route` given XNS label rules).

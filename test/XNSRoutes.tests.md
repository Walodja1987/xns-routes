# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `xnsName → owner` via `setResolution`, and optionally mark labels invalid via `setLabelInvalid` for `InvalidRoutePrefix` / `InvalidRoute` cases.
- **Canonical on-chain XNS** addresses for deploy/scripts/fork work live in [`constants/addresses.ts`](../constants/addresses.ts) as `XNS_ADDRESS` (they are not used by the default local test suite).

---

## Constructor

#### Functionality

- Stores the non-zero XNS registry address and exposes it via `XNS()`.
- Calls XNS `registerName("routes","xns")` with the constructor’s `msg.value`, so `routes.xns` resolves to the new registry (`address(this)`).
- On the mock, `getAddress("routes.xns")` returns the deployed `XNSRoutes` address after deployment.

#### Reverts

- Should revert with `ZeroAddress` when `xns_` is `address(0)`.
- Reverts if XNS rejects registration (e.g. insufficient `msg.value`, name taken, exclusivity rules on the real contract).

---

## `createRoute`

#### Functionality

- Name owner can **create** a route for `(xnsName, routePrefix, route)` with the given `target`, `routeType`, stored `isActive` from `activate`, and stored `isFrozen` from `freeze`.
- Second `createRoute` for the same key should revert with `RouteAlreadyExists`.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteCreated`).

#### Events

- Should emit `RouteCreated` with `xnsName`, `routePrefix`, `route`, `target`, `isActive`, `isFrozen`, and `routeType`. String parameters are non-indexed (full values in log data); `target` is indexed.
- Should emit `RouteFrozen` with `xnsName`, `routePrefix`, `route` when `freeze` is true on create.

#### Reverts

- Owner, XNS label rules on non-empty `routePrefix` and on `route`, non-zero `target`, and `RouteBookFrozen`, plus `RouteAlreadyExists` if the route key already exists.

---

## `updateRoute`

#### Functionality

- Name owner can **update** `target`, `routeType`, and `isActive` (via `activate`) on an **existing** route while the entry is not frozen and the route book for that XNS name is not frozen.
- Should revert with `RouteNotFound` if no route exists for the key.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteUpdated`).

#### Events

- Should emit `RouteUpdated` with final `record.isActive` / `record.isFrozen` / `record.routeType` after the write.
- Should emit `RouteFrozen` when `freeze` is true on update.

#### Reverts

- Should revert with `NotXnsNameOwner` when `msg.sender` is not `XNS.getAddress(xnsName)`.
- Should revert with `InvalidXnsName` when `XNS.getAddress(xnsName)` is zero (empty `xnsName` is included: XNS returns zero for `len == 0`).
- Does **not** revert with `InvalidRoutePrefix` / `InvalidRoute` for bad `routePrefix`/`route` (no XNS label check on this path for gas); mismatched keys typically yield `RouteNotFound`.
- Should revert with `InvalidTarget` when `target` is zero.
- Should revert with `RouteBookFrozen` when `freezeRouteBook` has already been called for that `xnsName`.
- Should revert with `CannotUpdateFrozenRoute` when updating a route that is already frozen (including changing only `routeType` or only `target`).
- Should revert with `RouteNotFound` when the route does not exist.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- Name owner can set `isActive` to true / false for an existing `(xnsName, routePrefix, route)`.
- Should still succeed when the **route** is frozen or the **route book** is frozen (only target updates are blocked).
- Like `freezeRoute`, should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second `deactivateRoute` or `activateRoute` when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with `xnsName`, `routePrefix`, `route`, and `isActive` when transitioning.

#### Reverts

- Should revert with `NotXnsNameOwner` when the caller is not the resolved owner.
- Should revert with `RouteNotFound` when no route exists for `(xnsName, routePrefix, route)`.

---

## `deleteRoute`

#### Functionality

- Name owner can clear a route slot (`routeExists` false); `createRoute` may register the same `(xnsName, routePrefix, route)` again afterward.
- Reverts with `CannotDeleteFrozenRoute` if the route is per-route frozen.
- Reverts with `RouteBookFrozen` if the route book for `xnsName` is frozen (same as `updateRoute`).
- Independent of `isActive`; use `deactivateRoute` for a soft disable without removing the record.

#### Events

- Should emit `RouteDeleted` with `xnsName`, `routePrefix`, `route`.

#### Reverts

- `NotXnsNameOwner`, `RouteNotFound`, `CannotDeleteFrozenRoute`, `RouteBookFrozen` as above.

---

## `updateTarget` / `updateRouteType`

#### Functionality

- Name owner can change `target` or `routeType` on an existing route (not for create).
- Same freeze rules as `updateRoute` for those fields: reverts with `CannotUpdateFrozenRoute` if the route is frozen, `RouteBookFrozen` if the route book for `xnsName` is frozen.
- Should emit `RouteTargetUpdated` / `RouteTypeUpdated` **only when** the value actually changes (no-op otherwise).

#### Events

- `RouteTargetUpdated` with `xnsName`, `routePrefix`, `route`, and `newTarget` (indexed).
- `RouteTypeUpdated` with `xnsName`, `routePrefix`, `route`, and `newRouteType` (indexed).

#### Reverts

- `NotXnsNameOwner`, `RouteNotFound`, `CannotUpdateFrozenRoute`, `RouteBookFrozen` as above.
- `updateTarget`: `InvalidTarget` when `newTarget` is zero.

---

## `freezeRoute`

#### Functionality

- Name owner can set `isFrozen` permanently for an existing route.
- Second call when already frozen should **not** emit `RouteFrozen` again (no-op on storage already frozen).

#### Events

- Should emit `RouteFrozen` the first time the route transitions to frozen.

#### Reverts

- Should revert with `NotXnsNameOwner` when the caller is not the resolved owner.
- Should revert with `RouteNotFound` when the route does not exist.

---

## `freezeRouteBook`

#### Functionality

- Name owner can set `routeBookFrozen[keccak256(bytes(xnsName))]` permanently.
- After route book freeze, `createRoute`, `updateRoute`, `deleteRoute`, `updateTarget`, and `updateRouteType` must revert for that `xnsName`, while `activateRoute` / `deactivateRoute` may still run.

#### Events

- Should emit `RouteBookFrozenForName` with `xnsName` the first time the route book is frozen.
- Second call should not emit again (idempotent).

#### Reverts

- Should revert with `NotXnsNameOwner` when the caller is not the resolved owner.

---

## `getRouteInfo` / `routeExists`

#### Functionality

- `routeExists` returns `false` before a route is created and `true` after.
- `getRouteInfo` returns `(target, isActive, isFrozen, routeType)` consistent with `createRoute` / `updateRoute` / `updateTarget` / `updateRouteType` / `activateRoute` / `deactivateRoute` / `freezeRoute` (until `deleteRoute` clears the slot).

#### Reverts

- `getRouteInfo` should revert with `RouteNotFound` when the route does not exist.

---

## `routeBookFrozen`

#### Functionality

- For a given `xnsName`, `routeBookFrozen(keccak256(bytes(xnsName)))` matches whether `freezeRouteBook` was applied.

---

## Route keying (regression)

#### Functionality

- Routes under different `xnsName`, `routePrefix`, or `route` are independent: key is `keccak256(abi.encodePacked(xnsName, "/", route))` if `routePrefix` is empty, else `keccak256(abi.encodePacked(xnsName, "/", routePrefix, ":", route))` (empty `routePrefix` is distinct from any non-empty `routePrefix` for the same `route` given XNS label rules).

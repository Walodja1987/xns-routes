# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `xnsName → owner` via `setResolution`, and optionally mark labels invalid via `setLabelInvalid` for `InvalidChain` / `InvalidRoute` cases.
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

- Name owner can **create** a route for `(xnsName, chain, route)` with the given `target`, `routeType`, stored `isActive` from `activate`, and stored `isFrozen` from `freeze`.
- Second `createRoute` for the same key should revert with `RouteAlreadyExists`.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteSet`).

#### Events

- Should emit `RouteSet` with `xnsName`, `chain`, `route`, `target`, `activate`, `freeze`, and `routeType`. Three indexed fields max: `xnsName`, `chain`, `target`; `route` and `routeType` are non-indexed.
- Should emit `RouteFrozen` with `xnsName`, `chain`, `route` when `freeze` is true on create.

#### Reverts

- Same validation as `updateRoute` for owner, labels, non-zero `target`, and `RouteBookFrozen` (see below), plus `RouteAlreadyExists` if the route key already exists.

---

## `updateRoute`

#### Functionality

- Name owner can **update** `target`, `routeType`, and `isActive` (via `activate`) on an **existing** route while the entry is not frozen and the route book for that XNS name is not frozen.
- Should revert with `RouteNotFound` if no route exists for the key.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteSet`).

#### Events

- Should emit `RouteSet` with final `record.isActive` / `record.isFrozen` after the write.
- Should emit `RouteFrozen` when `freeze` is true on update.

#### Reverts

- Should revert with `NotXnsNameOwner` when `msg.sender` is not `XNS.getAddress(xnsName)`.
- Should revert with `InvalidXnsName` when `XNS.getAddress(xnsName)` is zero (empty `xnsName` is included: XNS returns zero for `len == 0`).
- Should revert with `InvalidChain` when non-empty `chain` fails XNS label rules (`_isValidString` → `isValidLabelOrNamespace`).
- Empty `chain` is allowed (chain-agnostic route; human path `xnsName/route/...`) and does not run the chain label check.
- Should revert with `InvalidRoute` when `route` fails the same rules.
- Should revert with `InvalidTarget` when `target` is zero.
- Should revert with `RouteBookFrozen` when `freezeRouteBook` has already been called for that `xnsName`.
- Should revert with `CannotUpdateFrozenRoute` when updating a route that is already frozen (including changing only `routeType` or only `target`).
- Should revert with `RouteNotFound` when the route does not exist.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- Name owner can set `isActive` to true / false for an existing `(xnsName, chain, route)`.
- Should still succeed when the **route** is frozen or the **route book** is frozen (only target updates are blocked).
- Like `freezeRoute`, should emit `RouteActivationSet` **only when `isActive` actually changes** (second `deactivateRoute` or `activateRoute` when already in that state is a no-op for events).

#### Events

- Should emit `RouteActivationSet` with `xnsName`, `chain`, `route`, and `isActive` when transitioning.

#### Reverts

- Should revert with `NotXnsNameOwner` when the caller is not the resolved owner.
- Should revert with `RouteNotFound` when no route exists for `(xnsName, chain, route)`.

---

## `updateTarget` / `updateRouteType`

#### Functionality

- Name owner can change `target` or `routeType` on an existing route (not for create).
- Same freeze rules as `updateRoute` for those fields: reverts with `CannotUpdateFrozenRoute` if the route is frozen, `RouteBookFrozen` if the route book for `xnsName` is frozen.
- Should emit `RouteSet` **only when** the value actually changes (no-op otherwise).

#### Events

- `RouteSet` with current `activate` / `freeze` (stored `isActive` / `isFrozen`) and updated `target` or `routeType`.

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
- After route book freeze, `createRoute`, `updateRoute`, `updateTarget`, and `updateRouteType` must revert for that `xnsName`, while `activateRoute` / `deactivateRoute` may still run.

#### Events

- Should emit `RouteBookFrozenForName` with `xnsName` the first time the route book is frozen.
- Second call should not emit again (idempotent).

#### Reverts

- Should revert with `NotXnsNameOwner` when the caller is not the resolved owner.

---

## `getRoute` / `getRouteInfo` / `routeExists`

#### Functionality

- `routeExists` returns `false` before a route is created and `true` after.
- `getRoute` returns the stored `target` when the route exists.
- `getRouteInfo` returns `(target, isActive, isFrozen, routeType)` consistent with `createRoute` / `updateRoute` / `updateTarget` / `updateRouteType` / `activateRoute` / `deactivateRoute` / `freezeRoute`.

#### Reverts

- `getRoute` and `getRouteInfo` should revert with `RouteNotFound` when the route does not exist.

---

## `routeBookFrozen`

#### Functionality

- For a given `xnsName`, `routeBookFrozen(keccak256(bytes(xnsName)))` matches whether `freezeRouteBook` was applied.

---

## Route keying (regression)

#### Functionality

- Routes under different `xnsName`, `chain`, or `route` are independent: key is `keccak256(abi.encodePacked(xnsName, "/", route))` if `chain` is empty, else `keccak256(abi.encodePacked(xnsName, "/", chain, ":", route))` (empty `chain` is distinct from any non-empty `chain` for the same `route` given XNS label rules).

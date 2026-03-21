# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `baseName → owner` via `setResolution`, and optionally mark labels invalid via `setLabelInvalid` for `InvalidChain` / `InvalidRoute` cases.
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

## `setRoute`

#### Functionality

- Name owner can **create** a route for `(baseName, chain, route)` with the given `target`, `isActive`, and `isFrozen` implied by `freezeImmediately`.
- Name owner can **update** `target` and `isActive` while the entry is not frozen and the base name is not base-frozen.
- With `freezeImmediately == true`, should set `isFrozen` and emit `RouteFrozen` (in addition to `RouteSet`).

#### Events

- Should emit `RouteSet` with `baseName`, `chain`, `route`, `target`, `isActive`, and final `isFrozen` (three indexed fields max: `baseName`, `chain`, `target`; `route` is non-indexed).
- Should emit `RouteFrozen` with `baseName`, `chain`, `route` when the route becomes frozen in that transaction.

#### Reverts

- Should revert with `NotBaseNameOwner` when `msg.sender` is not `XNS.getAddress(baseName)`.
- Should revert with `InvalidBaseName` when `baseName` is empty.
- Should revert with `InvalidBaseName` when `XNS.getAddress(baseName)` is zero.
- Should revert with `InvalidChain` when `XNS.isValidLabelOrNamespace(chain)` is false.
- Should revert with `InvalidRoute` when `XNS.isValidLabelOrNamespace(route)` is false.
- Should revert with `InvalidTarget` when `target` is zero.
- Should revert with `BaseRoutesFrozen` when `freezeRoutes` has already been called for that `baseName`.
- Should revert with `CannotUpdateFrozenRoute` when updating a route that is already frozen.

---

## `setRouteActive`

#### Functionality

- Name owner can toggle `isActive` for an existing `(baseName, chain, route)`.
- Should still succeed when the **route** is frozen or the **base** is base-frozen (only target updates are blocked).

#### Events

- Should emit `RouteActivationSet` with `baseName`, `chain`, `route`, and `isActive`.

#### Reverts

- Should revert with `NotBaseNameOwner` when the caller is not the resolved owner.
- Should revert with `RouteNotFound` when no route exists for `(baseName, chain, route)`.

---

## `freezeRoute`

#### Functionality

- Name owner can set `isFrozen` permanently for an existing route.
- Second call when already frozen should **not** emit `RouteFrozen` again (no-op on storage already frozen).

#### Events

- Should emit `RouteFrozen` the first time the route transitions to frozen.

#### Reverts

- Should revert with `NotBaseNameOwner` when the caller is not the resolved owner.
- Should revert with `RouteNotFound` when the route does not exist.

---

## `freezeRoutes`

#### Functionality

- Name owner can set `baseRoutesFrozen[keccak256(bytes(baseName))]` permanently.
- After base freeze, `setRoute` must revert for that `baseName` (new routes and target changes), while `setRouteActive` may still run.

#### Events

- Should emit `BaseRoutesFrozenForName` with `baseName` the first time the base is frozen.
- Second call should not emit again (idempotent).

#### Reverts

- Should revert with `NotBaseNameOwner` when the caller is not the resolved owner.

---

## `getRoute` / `getRouteInfo` / `routeExists`

#### Functionality

- `routeExists` returns `false` before a route is created and `true` after.
- `getRoute` returns the stored `target` when the route exists.
- `getRouteInfo` returns `(target, isActive, isFrozen)` consistent with `setRoute` / `setRouteActive` / `freezeRoute`.

#### Reverts

- `getRoute` and `getRouteInfo` should revert with `RouteNotFound` when the route does not exist.

---

## `baseRoutesFrozen`

#### Functionality

- For a given `baseName`, `baseRoutesFrozen(keccak256(bytes(baseName)))` matches whether `freezeRoutes` was applied.

---

## Route keying (regression)

#### Functionality

- Routes under different `baseName`, `chain`, or `route` are independent (storage key `keccak256(abi.encode(baseName, chain, route))`).

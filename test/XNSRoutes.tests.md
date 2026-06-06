# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

Failures use Solidity `require` revert strings prefixed with `XNSRoutes: ` (same style as `XNS: ...` in the XNS registry).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `xnsName → owner` via `setResolution`. Route segment validation is local to `XNSRoutes` (not delegated to XNS): `routeScope` allows 1–20 chars (or empty), while routeLabel allows 1–32 chars; both share lowercase/number/hyphen and hyphen-placement rules.
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

- Name owner can **create** a route for `(xnsName, routeScope, route)` with the given `target`, `routeType`, stored `isActive` from `activate`, and stored `isFrozen` from `freeze`.
- Second `createRoute` for the same key should revert with `"XNSRoutes: route already exists"`.
- With `freeze == true`, should set `isFrozen` and emit `RouteCreated` with `isFrozen == true` (does **not** emit `RouteFrozen`; use `RouteFrozen` only when an existing route freezes later).

#### Events

- Should emit `RouteCreated` with indexed `nameHash` (`keccak256(bytes(xnsName))`), `routeKey` (same as `_routeKey`), and `target`, then `xnsName`, `routeScope`, routeLabel, `isActive`, `isFrozen`, and `routeType` (non-indexed, full values in log data).
- Should **not** emit `RouteFrozen` on create (even when `freeze` is true).

#### Reverts

- Owner, local route-segment rules on non-empty `routeScope` and on routeLabel (prefix 1–20; route 1–32), non-zero `target`, `"XNSRoutes: route book frozen"`, plus `"XNSRoutes: route already exists"` if the route key already exists.

---

## `updateRoute`

#### Functionality

- Name owner can **update** `target`, `routeType`, and `isActive` (via `activate`) on an **existing** route while the entry is not frozen and the route book for that XNS name is not frozen.
- Should revert with `"XNSRoutes: route not found"` if no route exists for the key.
- With `freeze == true`, should set `isFrozen` and emit `RouteFrozen`.

#### Events

- Emits `RouteTargetUpdated`, `RouteTypeUpdated`, and/or `RouteActiveStatusUpdated` only when the corresponding stored field changes (same shapes as `updateTarget` / `updateRouteType` / `activateRoute`).
- Should emit `RouteFrozen` (indexed `nameHash` / `routeKey` + strings) when `freeze` is true on update.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when `msg.sender` is not `XNS.getAddress(xnsName)` (includes unregistered names where XNS returns `address(0)`).
- Should revert with `"XNSRoutes: invalid XNS name"` when `xnsName` is empty (in `_canonicalizeXNSName`, before the owner check).
- Should revert with `"XNSRoutes: invalid route scope"` / `"XNSRoutes: invalid route label"` when `routeScope` or routeLabel fails local route-segment rules (same as `createRoute`), including empty `routeScope` with a routeLabel containing `:` (prevents aliasing the canonical `prefix:route` key).
- Should revert with `"XNSRoutes: invalid target"` when `target` is zero.
- Should revert with `"XNSRoutes: route book frozen"` when `freezeRouteBook` has already been called for that `xnsName`.
- Should revert with `"XNSRoutes: cannot update frozen route"` when updating a route that is already frozen (including changing only `routeType` or only `target`).
- Should revert with `"XNSRoutes: route not found"` when the route does not exist.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- Name owner can set `isActive` to true / false for an existing `(xnsName, routeScope, route)`.
- Should still succeed when the **route** is frozen or the **route book** is frozen (only target updates are blocked).
- Like `freezeRoute`, should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second `deactivateRoute` or `activateRoute` when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with indexed `nameHash` / `routeKey`, then `xnsName`, `routeScope`, routeLabel, and `isActive` when transitioning.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the resolved owner.
- Should revert with `"XNSRoutes: route not found"` when no route exists for `(xnsName, routeScope, route)`.

---

## `deleteRoute`

#### Functionality

- Name owner can clear a route slot (`getRouteRecord(...).target == address(0)`); `createRoute` may register the same `(xnsName, routeScope, route)` again afterward.
- Reverts with `"XNSRoutes: cannot delete frozen route"` if the route is per-route frozen.
- Reverts with `"XNSRoutes: route book frozen"` if the route book for `xnsName` is frozen (same as `updateRoute`).
- Independent of `isActive`; use `deactivateRoute` for a soft disable without removing the record.

#### Events

- Should emit `RouteDeleted` with indexed `nameHash` / `routeKey` and `xnsName`, `routeScope`, routeLabel.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: cannot delete frozen route"`, `"XNSRoutes: route book frozen"` as above.

---

## `updateTarget` / `updateRouteType`

#### Functionality

- Name owner can change `target` or `routeType` on an existing route (not for create).
- Same freeze rules as `updateRoute` for those fields: reverts with `"XNSRoutes: cannot update frozen route"` if the route is frozen, `"XNSRoutes: route book frozen"` if the route book for `xnsName` is frozen.
- Should emit `RouteTargetUpdated` / `RouteTypeUpdated` **only when** the value actually changes (no-op otherwise).

#### Events

- `RouteTargetUpdated` with indexed `nameHash` / `routeKey` / `newTarget`, then `xnsName`, `routeScope`, routeLabel, and non-indexed `previousTarget`.
- `RouteTypeUpdated` with indexed `nameHash` / `routeKey`, then strings and non-indexed `previousRouteType` / `newRouteType`.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: cannot update frozen route"`, `"XNSRoutes: route book frozen"` as above.
- `"XNSRoutes: invalid route scope"` / `"XNSRoutes: invalid route label"` when `routeScope` / routeLabel fail local route-segment rules (same as `createRoute`).
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

## `getRouteRecord`

#### Functionality

- All overloads return an empty `RouteRecord` (`target == address(0)`) when the route does not exist (soft read).
- `getRouteRecord(xnsName, routeScope, routeLabel)` returns fields consistent with `createRoute` / `updateRoute` / `updateTarget` / `updateRouteType` / `activateRoute` / `deactivateRoute` / `freezeRoute` (until `deleteRoute` clears the slot).
- `getRouteRecord(string registryXRL)` parses a **registry XRL** via `splitRegistryXRL` then reads the same record.
- `getRouteRecord(bytes32 routeKey)` reads storage directly by key.
- Existence: `getRouteRecord(...).target != address(0)`.
- Tuple overload applies the same local `routeScope` / routeLabel validation as mutating functions before deriving the key.

#### Reverts

- Should revert with `"XNSRoutes: invalid route scope"` / `"XNSRoutes: invalid route label"` for malformed `routeScope` / routeLabel (e.g. `:` in routeLabel when `routeScope` is empty).
- `getRouteRecord(string)` should revert with `"XNSRoutes: invalid XRL"` when no `/` is present.

---

## `isValidRouteScope` / `isValidRouteLabel / `isValidRouteScopeAndRoute`

#### Functionality

- Pure views mirror `_isValidRouteScope` / `_isValidRouteLabel / `_validateRoutePrefixAndRoute`: empty `routeScope` is allowed; non-empty prefix and route must satisfy slug length and charset rules.

---

## `isRouteBookFrozen`

#### Functionality

- For a given `xnsName`, `isRouteBookFrozen(xnsName)` matches whether `freezeRouteBook` was applied.

---

## Route keying (regression)

#### Functionality

- Routes under different `xnsName`, `routeScope`, or routeLabel are independent: key is `keccak256(abi.encodePacked(xnsName, "/", route))` if `routeScope` is empty, else `keccak256(abi.encodePacked(xnsName, "/", routeScope, ":", route))` (empty `routeScope` is distinct from any non-empty `routeScope` for the same routeLabel given XNS label rules).

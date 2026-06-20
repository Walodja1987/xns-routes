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

- Name owner can **create** a route for `(xnsName, routeScope, routeLabel)` with the given `target`, `routeType`, `isActive == true`, and `activeController` set to the current XNS name owner.
- Second `createRoute` for the same key should revert with `"XNSRoutes: route already exists"`.
- Routes under different `xnsName`, `routeScope`, or routeLabel are independent.

#### Events

- Should emit `RouteCreated` with indexed `xnsNameHash` (`keccak256(bytes(canonicalXNSName))`), `routeKey` (same as `_routeKey`), and `target`, then `canonicalXNSName`, `routeScope`, routeLabel, `routeType`, `isActive`, and `activeController` (non-indexed, full values in log data).

#### Reverts

- Owner, local route-segment rules on non-empty `routeScope` and on routeLabel (prefix 1–20; route 1–32), non-zero `target`, `"XNSRoutes: route book frozen"`, plus `"XNSRoutes: route already exists"` if the route key already exists.

---

## `createRouteWithController`

#### Functionality

- Same as `createRoute`, but accepts explicit `isActive` and `activeController` (must not be `address(0)`).

#### Reverts

- Same as `createRoute`, plus `"XNSRoutes: invalid active controller"` when `activeController == address(0)`.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- `activeController` can set `isActive` to true / false for an existing `(xnsName, routeScope, routeLabel)`.
- Should still succeed when the **route book** is frozen (only new routes are blocked for the name owner).
- Should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second call when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with indexed `xnsNameHash` / `routeKey`, then `canonicalXNSName`, `routeScope`, routeLabel, and `isActive` when transitioning.

#### Reverts

- Should revert with `"XNSRoutes: not active controller"` when the caller is not `record.activeController`.
- Should revert with `"XNSRoutes: route not found"` when no route exists for `(xnsName, routeScope, routeLabel)`.

---

## `activeController`

#### Functionality

- Set at `createRoute` (XNS name owner) or `createRouteWithController`; never editable afterward.
- Only `activeController` may call `activateRoute` / `deactivateRoute` (name owner has no special toggle rights unless they are the stored controller).

---

## `freezeRouteBook`

#### Functionality

- Name owner can set `isRouteBookFrozen(xnsName)` permanently.
- After route book freeze, `createRoute` must revert for that `xnsName`, while `activeController` may still call `activateRoute` / `deactivateRoute`.

#### Events

- Should emit `RouteBookFrozen` with indexed `xnsNameHash` and full `canonicalXNSName` the first time the route book is frozen.
- Second call should not emit again (idempotent).

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the resolved owner.

---

## `getRouteRecord`

#### Functionality

- All overloads return an empty `RouteRecord` (`target == address(0)`) when the route does not exist (soft read).
- `getRouteRecord(xnsName, routeScope, routeLabel)` returns fields consistent with `createRoute` / `createRouteWithController` / `activateRoute` / `deactivateRoute`.
- `getRouteRecord(string registryXRL)` parses a **registry XRL** via `splitRegistryXRL` then reads the same record.
- `getRouteRecord(bytes32 routeKey)` reads storage directly by key.
- Existence: `getRouteRecord(...).target != address(0)`.
- Tuple overload applies the same local `routeScope` / routeLabel validation as mutating functions before deriving the key.

#### Reverts

- Should revert with `"XNSRoutes: invalid route scope"` / `"XNSRoutes: invalid route label"` for malformed `routeScope` / routeLabel (e.g. `:` in routeLabel when `routeScope` is empty).
- `getRouteRecord(string)` should revert with `"XNSRoutes: invalid XRL"` when no `/` is present.

---

## `resolveRoute` / `resolveRouteIfActive`

#### Functionality

- Tuple and registry-XRL overloads return `(target, routeType)` for forward resolution.
- `resolveRoute`: route exists (`target != address(0)`); ignores `isActive`.
- `resolveRouteIfActive`: route exists and `isActive == true`.
- Both succeed when the route book is frozen (existing routes unchanged).

#### Reverts

- `"XNSRoutes: route not found"` when the route does not exist.
- `"XNSRoutes: route inactive"` for `resolveRouteIfActive` when `isActive == false`.
- `"XNSRoutes: invalid route scope"` / `"XNSRoutes: invalid route label"` for malformed tuple inputs.
- `"XNSRoutes: invalid XRL"` for registry-XRL overloads without `/`.

---

## Route key list

#### Functionality

- `getRouteKeyCount` starts at zero for a name; increments by one on each successful `createRoute`.
- `getRouteKeys(xnsName, start, end)` pages through keys (`end` exclusive; clamped to array length).
- Failed `createRoute` (e.g. duplicate key) does not add a key to the list.
- `getRouteKeys` reverts when `start > end`; returns empty when `start` is past the log range.

---

## `isValidRouteScope` / `isValidRouteLabel` / `isValidRouteScopeAndLabel`

#### Functionality

- Pure views mirror `_isValidRouteScope` / `_isValidRouteLabel` / `_validateRoutePrefixAndRoute`: empty `routeScope` is allowed; non-empty prefix and route must satisfy slug length and charset rules.

---

## `isRouteBookFrozen`

#### Functionality

- For a given `xnsName`, `isRouteBookFrozen(xnsName)` matches whether `freezeRouteBook` was applied.

---

## Bare XNS name canonicalization

#### Functionality

- Routes created with a bare label (e.g. `"action"`) resolve when queried with the canonical name (e.g. `"action.xns"`).
- Bare and canonical names share the same route book (second create for the same key reverts).
- Events emit `canonicalXNSName` in the canonical form.

---

## Route keying (regression)

#### Functionality

- Routes under different `xnsName`, `routeScope`, or routeLabel are independent: key is `keccak256(abi.encodePacked(xnsName, "/", route))` if `routeScope` is empty, else `keccak256(abi.encodePacked(xnsName, "/", routeScope, ":", route))` (empty `routeScope` is distinct from any non-empty `routeScope` for the same routeLabel given XNS label rules).

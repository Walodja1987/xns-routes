# XNSRoutes test matrix

This document lists behaviour covered by Hardhat tests for [`XNSRoutes`](../contracts/src/XNSRoutes.sol) in [`XNSRoutes.test.ts`](./XNSRoutes.test.ts).

Failures use Solidity `require` revert strings prefixed with `XNSRoutes: ` (same style as `XNS: ...` in the XNS registry).

## Test setup

- **Unit tests** use [`MockXNS`](../contracts/src/mocks/MockXNS.sol): set `label@namespace → owner` via `setResolution(label, namespace, addr)`. Route label validation is local to `XNSRoutes` (not delegated to XNS): `routeLabel` allows 1–32 chars with lowercase/number/hyphen and hyphen-placement rules.
- **Canonical on-chain XNS** addresses for deploy/scripts/fork work live in [`constants/addresses.ts`](../constants/addresses.ts) as `XNS_ADDRESS` (they are not used by the default local test suite).

---

## Constructor

#### Functionality

- Stores the non-zero XNS registry address and exposes it via `XNS()`.
- Calls XNS `registerName("routes","xns")` with the constructor’s `msg.value`, so `routes@xns` resolves to the new registry (`address(this)`).
- On the mock, `getAddress("routes", "xns")` returns the deployed `XNSRoutes` address after deployment.

#### Reverts

- Should revert with `"XNSRoutes: 0x XNS address"` when `xnsContract` is `address(0)`.
- Reverts if XNS rejects registration (e.g. insufficient `msg.value`, name taken, exclusivity rules on the real contract).

---

## `createRoute`

#### Functionality

- Name owner can **create** a route for `(label, namespace, routeLabel)` with the given `target` (`bytes`, 1–`MAX_TARGET_LENGTH` where `MAX_TARGET_LENGTH = 256`), `routeType`, and `isActive == true`.
- Second `createRoute` for the same key should revert with `"XNSRoutes: route already exists"`.
- Routes under different `label`, `namespace`, or `routeLabel` are independent.
- Missing routes are represented by empty `target` (`target.length == 0`).

#### Events

- Should emit `RouteCreated` with indexed `xnsNameKey` (`keccak256(abi.encodePacked(label, "@", namespace))`), `routeKey`, then `label`, `namespace`, `routeLabel`, `target`, `routeType`, and `isActive` (non-indexed, full values in log data).

#### Reverts

- Owner, local route-label rules (1–32 chars), `"XNSRoutes: invalid target"` when `target` is empty or longer than `MAX_TARGET_LENGTH` (256), `"XNSRoutes: route book frozen"`, plus `"XNSRoutes: route already exists"` if the route key already exists.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- XNS name owner can set `isActive` to true / false for an existing `(label, namespace, routeLabel)`.
- Should still succeed when the **route book** is frozen (only new routes are blocked for the name owner).
- Should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second call when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with indexed `xnsNameKey` / `routeKey`, then `label`, `namespace`, `routeLabel`, and `isActive` when transitioning.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the current XNS name owner.
- Should revert with `"XNSRoutes: route not found"` when no route exists for `(label, namespace, routeLabel)`.

---

## `updateRoute`

#### Functionality

- XNS name owner can update `target` (`bytes`, 1–`MAX_TARGET_LENGTH`) and `routeType` for an existing route while it is not effectively frozen.
- Emits `RouteUpdated` only when values actually change.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: route frozen"`, `"XNSRoutes: invalid target"` (empty or `> MAX_TARGET_LENGTH`).

---

## `freezeRoute`

#### Functionality

- XNS name owner can permanently set `isFrozen` on one route.
- After freeze, `updateRoute` reverts; `activateRoute` / `deactivateRoute` still work.
- Idempotent: second freeze is a no-op (no duplicate event).

#### Events

- Emits `RouteFrozen` the first time the route is frozen.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`.

---

## `freezeRouteBook`

#### Functionality

- Name owner can permanently freeze the route book for `(label, namespace)` or `label@namespace` string overload.
- After freeze, `createRoute` reverts; existing routes are treated as effectively frozen for `updateRoute`; existing routes can still toggle `isActive`.
- Idempotent: second freeze is a no-op (no duplicate event).

#### Events

- Should emit `RouteBookFrozen` with indexed `xnsNameKey` and full `label`, `namespace` the first time the route book is frozen.

#### Reverts

- `"XNSRoutes: not XNS name owner"` when caller is not the XNS name owner.

---

## `getRouteRecord`

#### Functionality

- `getRouteRecord(label, namespace, routeLabel)` returns fields consistent with `createRoute` / `activateRoute` / `deactivateRoute`.
- `getRouteRecord(routeKey)` and `getRouteRecord(route)` overloads behave consistently.
- Malformed `routeLabel` on read paths return an empty record (no validation revert).

---

## `resolveRoute` / `resolveRouteIfActive`

#### Functionality

- `resolveRoute` returns `(target, routeType)` regardless of `isActive`.
- `resolveRouteIfActive` reverts with `"XNSRoutes: route inactive"` when `isActive == false`.
- String overloads accept parametrized routes; params after the second `/` are stripped.

#### Reverts

- `"XNSRoutes: route not found"` when route does not exist.

---

## `splitRoute` / `splitXNSName`

#### Functionality

- `splitRoute` parses `label@namespace/routeLabel` into `(label, namespace, routeLabel)`.
- Parametrized routes: strips `/params…` tail at the second `/`.
- `splitXNSName` parses `label@namespace` into components.

#### Reverts

- `"XNSRoutes: invalid route"` for malformed input.

---

## Route key list (`getRouteKeyCount`, `getRouteKeys`, `getRouteEntries`)

#### Functionality

- Per-name append-only list of route keys on successful `createRoute`.
- Pagination: `start` inclusive, `end` exclusive; clamp `end` to length; empty slice when `start` past end.
- `getRouteEntries` returns `routeKey`, stored `routeLabel`, and full `RouteRecord`.
- `xnsName` string overloads for count/keys/entries match tuple overloads.

#### Reverts

- `"XNSRoutes: invalid route key slice"` when `start > end`.

---

## `isValidRouteLabel`

#### Functionality

- Pure view mirrors `_isValidRouteLabel`: 1–32 chars, charset and hyphen rules.

---

## `isValidTarget` / `MAX_TARGET_LENGTH`

#### Functionality

- `MAX_TARGET_LENGTH = 256`.
- `isValidTarget(target)` is true iff `target.length > 0 && target.length <= MAX_TARGET_LENGTH`.
- Contents are not validated; `routeType` interprets the opaque payload offchain.

---

## Key semantics

- `xnsNameKey = keccak256(abi.encodePacked(label, "@", namespace))`
- `routeKey = keccak256(abi.encode(xnsNameKey, keccak256(bytes(routeLabel))))`
- Routes under different `label`, `namespace`, or `routeLabel` are independent.
- Existence: `getRouteRecord(...).target.length == 0` means the route is not registered.

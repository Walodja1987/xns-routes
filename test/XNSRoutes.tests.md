# XNSRoutes tests

## Constructor

#### Functionality

- Sets the non-zero `initialOwner` as the ERC-173 contract owner.
- Stores the non-zero XNS registry address and exposes it via `XNS()`.
- Calls XNS `registerName("routes","xns")` with the constructor’s `msg.value`, so `routes@xns` resolves to the new registry (`address(this)`).
- On the mock, `getAddress("routes", "xns")` returns the deployed `XNSRoutes` address after deployment.

#### Reverts

- Should revert with OpenZeppelin `OwnableInvalidOwner(address(0))` when `initialOwner` is zero.
- Should revert with `"XNSRoutes: 0x XNS address"` when `xnsContract` is `address(0)`.
- Reverts if XNS rejects registration (e.g. insufficient `msg.value`, name taken, exclusivity rules on the real contract).

---

## Contract ownership

- Ownership transfers use the two-step `transferOwnership` / `acceptOwnership` flow.
- `pendingOwner()` is set until the nominated account accepts.
- Contract ownership grants no route authority; route mutations still require current XNS name ownership.

---

## `createRoute`

#### Functionality

- Name owner can **create** a route for `(label, namespace, routeLabel)` with the given `target` (`bytes`, non-empty; no protocol max length), `routeType`, and `isActive == true`.
- Second `createRoute` for the same key should revert with `"XNSRoutes: route already exists"`.
- Routes under different `label`, `namespace`, or `routeLabel` are independent.
- Missing routes are represented by empty `target` (`target.length == 0`).

#### Events

- Should emit `RouteCreated` with indexed `xnsNameKey`, `routeKey`, and `targetHash` (`keccak256(target)`), then `label`, `namespace`, `routeLabel`, and `routeType` in log data (new routes always start active). Full `target` is not logged — read it from storage via `getRouteRecord` / resolve.

#### Reverts

- Owner, local route-label rules (1–32 chars), `"XNSRoutes: invalid target"` when `target` is empty, `"XNSRoutes: route book closed"`, plus `"XNSRoutes: route already exists"` if the route key already exists.

---

## `activateRoute` / `deactivateRoute`

#### Functionality

- XNS name owner can set `isActive` to true / false for an existing `(label, namespace, routeLabel)`.
- Should still succeed when the **route book** is closed (only new routes are blocked for the name owner).
- Should emit `RouteActiveStatusUpdated` **only when `isActive` actually changes** (second call when already in that state is a no-op for events).

#### Events

- Should emit `RouteActiveStatusUpdated` with indexed `xnsNameKey` / `routeKey`, then `label`, `namespace`, `routeLabel`, and `isActive` when transitioning.

#### Reverts

- Should revert with `"XNSRoutes: not XNS name owner"` when the caller is not the current XNS name owner.
- Should revert with `"XNSRoutes: route not found"` when no route exists for `(label, namespace, routeLabel)`.

---

## `updateRoute`

#### Functionality

- XNS name owner can update `target` (`bytes`, non-empty; no protocol max length) and `routeType` for an existing route while `record.isFrozen` is false.
- Closing the route book does **not** block `updateRoute`.
- Emits `RouteUpdated` only when values actually change (indexed `targetHash = keccak256(newTarget)`; full `target` is not in the log).

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`, `"XNSRoutes: route frozen"`, `"XNSRoutes: invalid target"` (empty).

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

## `batchFreezeRoutes`

#### Functionality

- XNS name owner can freeze multiple routes under one `(label, namespace)` in a single call.
- Same per-route semantics as `freezeRoute` (already-frozen = no-op / no event).
- Empty `routeLabels` succeeds as a no-op.
- If any label is missing, the entire batch reverts.

#### Events

- Emits `RouteFrozen` for each route that newly becomes frozen.

#### Reverts

- `"XNSRoutes: not XNS name owner"`, `"XNSRoutes: route not found"`.

---

## `closeRouteBook`

#### Functionality

- Name owner can permanently close the route book for `(label, namespace)` or `label@namespace` string overload.
- After close, `createRoute` reverts; existing routes remain updatable until individually frozen; existing routes can still toggle `isActive`.
- Idempotent: second close is a no-op (no duplicate event).

#### Events

- Should emit `RouteBookClosed` with indexed `xnsNameKey` and full `label`, `namespace` the first time the route book is closed.

#### Reverts

- `"XNSRoutes: not XNS name owner"` when caller is not the XNS name owner.

---

## `getRouteRecord`

#### Functionality

- `getRouteRecord(label, namespace, routeLabel)` returns fields consistent with `createRoute` / `activateRoute` / `deactivateRoute`.
- `getRouteRecord(routeKey)` and `getRouteRecord(route)` overloads behave consistently.
- Malformed `routeLabel` on read paths return an empty record (no validation revert).

---

## `resolveRoute`

#### Functionality

- `resolveRoute` returns `(target, routeType)` only when the route is frozen and active.
- Callers that need mutable or inactive routes can inspect `getRouteRecord`.
- String overloads require exactly `label@namespace/routeLabel`; apps must strip `?...` query parameters before calling.

#### Reverts

- `"XNSRoutes: route not found"` when route does not exist.
- `"XNSRoutes: route not frozen"` when `isFrozen == false`.
- `"XNSRoutes: route inactive"` when `isActive == false`.
- `"XNSRoutes: invalid route"` for malformed route strings (including extra `/` segments).

---

## `splitRoute` / `splitXNSName`

#### Functionality

- `splitRoute` parses `label@namespace/routeLabel` into `(label, namespace, routeLabel)`.
- Exactly one `/` is allowed; extra path segments are rejected. Strip `?...` query parameters before calling.
- `splitXNSName` parses `label@namespace` into components.

#### Reverts

- `"XNSRoutes: invalid route"` / `"XNSRoutes: invalid XNS name"` for malformed input.

---

## `getXNSNameKey`

#### Functionality

- `getXNSNameKey(label, namespace)` returns `keccak256(abi.encodePacked(label, "@", namespace))`.
- `getXNSNameKey(xnsName)` parses an exact `label@namespace` string and returns the same key.

#### Reverts

- `"XNSRoutes: invalid XNS name"` for the string overload when the XNS name is malformed.

---

## `getRouteKey`

#### Functionality

- `getRouteKey(label, namespace, routeLabel)` returns `keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel))`.
- `getRouteKey(route)` parses an exact `label@namespace/routeLabel` string and returns the same key.

#### Reverts

- `"XNSRoutes: invalid route"` for the string overload when the route string is malformed.

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

## `isValidTarget` (removed)

Target validation is only `target.length > 0` inline in `createRoute` / `updateRoute`. There is no protocol max length and no `isValidTarget` view. Contents are not validated; `routeType` interprets the opaque payload offchain.

---

## Key semantics

- `xnsNameKey = keccak256(abi.encodePacked(label, "@", namespace))`
- `routeKey = keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel))` (hash of `label@namespace/routeLabel`)
- Routes under different `label`, `namespace`, or `routeLabel` are independent.
- Existence: `getRouteRecord(...).target.length == 0` means the route is not registered.

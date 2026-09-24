# XNS Routes

```
///////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                           //
//   __   __ _   _   _____         ___    _____    ____   _    _  _______  ______   _____    //
//   \ \ / /| \ | | / ____|       /  /   |  __ \  / __ \ | |  | ||__   __||  ____| / ____|   //
//    \ V / |  \| || (___        /  /    | |__) || |  | || |  | |   | |   | |__   | (___     //
//     > <  | . ` | \___ \      /  /     |  _  / | |  | || |  | |   | |   |  __|   \___ \    //
//    / . \ | |\  | ____) |    /  /      | | \ \ | |__| || |__| |   | |   | |____  ____) |   //
//   /_/ \_\|_| \_||_____/    /_ /       |_|  \_\ \____/  \____/    |_|   |______||_____/    //
//                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////
```

## Table of contents

1. [What are XNS Routes?](#-what-are-xns-routes)
2. [Why XNS Routes?](#-why-xns-routes)
3. [How It Works](#-how-it-works) \
   3.1 [Define a Route](#1-define-a-route) \
   3.2 [Resolve a Route](#2-resolve-a-route) \
   3.3 [Interpret the endpoint](#3-interpret-the-endpoint) \
   3.4 [Route type registry](routeTypes/README.md)
4. [Route State Model](#-route-state-model)
5. [Route freeze](#-route-freeze) \
   5.1 [Per-route freeze](#per-route-freeze) \
   5.2 [Route-book close](#route-book-close)
6. [Design Principles](#-design-principles)
7. [Repo Contents](#-repo-contents)
8. [On-chain route discovery](#-on-chain-route-discovery) \
   8.1 [State-modifying](#state-modifying-executable-by-the-xns-name-owner) \
   8.2 [Views](#views)
9. [API reference](#-api-reference)
10. [Contract addresses](#-contract-addresses)
11. [Contract ownership](#-contract-ownership)
12. [Contributing](#-contributing)

---

## ✨ What are XNS Routes?

Routes are typed endpoints underneath an [XNS name](https://github.com/Walodja1987/XNSv2/blob/main/README.md#xns--the-name-layer-on-ethereum). XNS Routes extends an XNS name with a simple path:

```text
route = label@namespace/routeLabel
```

If you own `alice@eth`, you can publish routes under that name such as:

```text
alice@eth/treasury           → 0xdf2…3e7          (EVM address)
alice@eth/my-wallet-2        → 0xabc…901          (another EVM address)
alice@eth/bitcoin-wallet-1   → bc1q…              (Bitcoin address)
alice@eth/solana-main        → 7Ec…               (Solana pubkey)
alice@eth/claim-airdrop      → 0xa9059cbb…        (calldata)
```

Each route points to an opaque **endpoint payload** (`bytes target`) plus a **`routeType`** that tells applications how to interpret it.

Routes can have parameters like URLs (`?key=value&…`). They are not stored on-chain, but can be used to derive return data (e.g. with a type-[`5`](routeTypes/5.md) builder). Strip the query string before calling Routes string helpers.

Example shared link:

```text
usdt@action/transfer-usdt?to=0x1234…abcd&amount=100
```

The character rules for a route label are the same as for XNS names:

- `routeLabel` must be `1-32` chars
- charset: lowercase `a-z`, digits `0-9`, and `-`
- no leading/trailing `-`, and no consecutive `--`

XNS name owners can publish an unlimited number of routes **for free**.

---

## 🚀 Why XNS Routes?

- ✅ One recognizable identity with multiple destinations
- ✅ Shareable, human-readable destinations (links, QR codes, etc.)
- ✅ Support EVM and non-EVM endpoints

---

## 🔧 How It Works

### 1. Define a Route

A route is registered under an XNS name:

```ts
import { getBytes } from "ethers";

await routes.createRoute(
  "alice", // label
  "pay", // namespace
  "treasury", // routeLabel
  getBytes("0xAbc0000000000000000000000000000000000Def"), // target (bytes; e.g. 20-byte EVM address)
  0, // routeType — meanings are defined in routeTypes/, not by the contract
);
```

Newly created routes are `isActive = true` by default. `target` and `routeType` are mutable until the route is [frozen](#-route-state-model).

---

### 2. Resolve a Route

Given:

```text
alice@pay/treasury
```

An application:

1. Calls one of the resolve variants(`resolveRouteIfFrozenAndActive`, `resolveRouteIfActive`, or `resolveRoute`)
2. Receives `(target, routeType)`

XNS Routes only supports forward resolution as multiple routes may point at the same endpoint.

---

### 3. Interpret the endpoint

`routeType` tells the application how to read `target`. Conventions are documented in
[`routeTypes/`](routeTypes/README.md) (not enforced on-chain):

| `routeType` | Meaning          | Spec                   |
| ----------- | ---------------- | ---------------------- |
| `0`         | EVM address      | [routeTypes/0.md](routeTypes/0.md) |
| `1`         | Bitcoin address  | [routeTypes/1.md](routeTypes/1.md) |
| `2`         | Solana pubkey    | [routeTypes/2.md](routeTypes/2.md) |
| `3`         | EVM calldata     | [routeTypes/3.md](routeTypes/3.md) |
| `4`         | URI              | [routeTypes/4.md](routeTypes/4.md) |
| `5`         | EVM route builder | [routeTypes/5.md](routeTypes/5.md) |

New public types can be proposed via a GitHub issue (see [routeTypes/README.md](routeTypes/README.md#propose-a-new-route-type))
without changing the XNS Routes contract. The registry stores the endpoint and its type;
applications decide how to interpret it.

---

## 🔒 Route State Model

Each route has:

- `target` → opaque endpoint payload, non-empty `bytes` with no protocol max length (**mutable** until the route is frozen)
- `routeType` → off-chain interpretation hint (**mutable** until the route is frozen)
- `isActive` → usable or disabled (toggled by the XNS name owner)
- `isFrozen` → permanently locks `target` / `routeType` for that route
- `routeLabel` → immutable slug

The XNS name owner can call `updateRoute` to change `target` and `routeType` until the route's `isFrozen` flag is set.

`isActive` and `isFrozen` are independent: a frozen route can still be deactivated (and reactivated) without changing its endpoint.

`routeLabel` cannot be renamed; create another route instead. Routes are never deleted.

---

## 🧊 Route freeze

XNS Routes has two permanence controls: 
* **Per-route freeze:** lock an individual endpoint.
* **Route book close:** lock the set of available routes under a name.

The former is useful to signal to users that the endpoint is not going to change.
The latter is useful for finalized endpoint sets, audited contract maps, or limited route collections.

### Per-route freeze

```solidity
freezeRoute("alice", "pay", "treasury");
```

or

```solidity
batchFreezeRoutes("alice", "pay", ["treasury", "personal"]);
```

- Permanently locks that route's `target` / `routeType`
- XNS name owner can still toggle `isActive`

### Route-book close

```solidity
closeRouteBook("alice@pay");
```

or

```solidity
closeRouteBook("alice", "pay");
```

- No new routes can be added under that XNS name after the route book is closed
- Existing routes stay updatable until individually frozen
- XNS name owner can still toggle `isActive`

To get the freeze and book closed state of a route, use `record.isFrozen` (via `getRouteRecord`) and `isRouteBookClosed(...)`, respectively.

---

## 🌍 Design Principles

The registry answers one question:

> **What endpoint did the owner of this XNS name publish under this route?**

It does not interpret payment amounts, execute returned data, or decide what an endpoint means.

- **Name-owned** → routes belong to XNS names; no separate route owners or route NFTs
- **Minimal** → registry stops at typed endpoint resolution
- **Generic** → `target` + `routeType`; apps define interpretation
- **Forward-only** → resolve route → endpoint; no reverse index
- **Optionally immutable** → `target` / `routeType` updateable until freeze; then permanent

---

## 📦 Repo Contents

- `XNSRoutes.sol` — named-endpoint registry (includes on-chain enumeration helpers; see below)
- [`routeTypes/`](routeTypes/README.md) — public `routeType` conventions (`0`–`5`, …)
- [`docs/API.md`](docs/API.md) — NatSpec-generated contract API reference
- [`docs/DEV_NOTES.md`](docs/DEV_NOTES.md) — local setup, networks, and development notes
- [`scripts/examples/`](scripts/examples/) — Hardhat scripts for create / resolve / freeze / discovery (see [Example scripts](#-example-scripts))

---

## 📇 On-chain route discovery

The registry stores each route's **`routeLabel` on-chain** and keeps a per-name list so integrators can discover and reconstruct human-readable routes using only `eth_call`s—**no subgraph or indexer required**. Full NatSpec: [docs/API.md](docs/API.md).

### State-modifying (executable by the XNS name owner)

| Function | Description |
| -------- | ----------- |
| `createRoute(label, namespace, routeLabel, target, routeType)` | Register a new route (starts active, unfrozen) |
| `updateRoute(label, namespace, routeLabel, newTarget, newRouteType)` | Change `target` / `routeType` while not frozen |
| `activateRoute` / `deactivateRoute` | Toggle `isActive` (allowed after freeze) |
| `freezeRoute(label, namespace, routeLabel)` | Permanently lock that route's `target` / `routeType` |
| `batchFreezeRoutes(label, namespace, routeLabels)` | Freeze many routes under one name |
| `closeRouteBook(label, namespace)` / `closeRouteBook(xnsName)` | Permanently block new routes under that name |

### Views

| Function | Description |
| -------- | ----------- |
| `getRouteKey(label, namespace, routeLabel)` / `getRouteKey(route)` | Canonical route storage key |
| `getRouteKeyCount(label, namespace)` | Number of routes registered under a name |
| `getRouteEntries(label, namespace, start, end)` | **Preferred** page of keys + full records (`end` exclusive; clamped; empty if `start` past end) |
| `getRouteKeys(label, namespace, start, end)` | Page of storage keys only (same pagination rules) |
| `getRouteRecord(routeKey)` / `(label, namespace, routeLabel)` / `(route)` | Full `RouteRecord` (empty `target` ⇒ not registered) |
| `isRouteBookClosed(label, namespace)` / `(xnsName)` | Whether new routes can still be added |
| `resolveRouteIfFrozenAndActive` | `(target, routeType)` if frozen **and** active (preferred production path) |
| `resolveRouteIfActive` | Same if active (ignores freeze; drafts OK) |
| `resolveRoute` | Same if the route exists (ignores `isActive` / `isFrozen`) |
| `splitRoute` / `splitXNSName` | Parse `label@namespace/routeLabel` or `label@namespace` |
| `isValidRouteLabel` | Whether a label satisfies on-chain rules |

Component and string overloads exist for several views (see [docs/API.md](docs/API.md)). Resolvers revert when the route is missing or fails the relevant flag checks. `getRouteRecord` returns an empty record (`target.length == 0`) when missing.

`target` and `routeType` are mutable until frozen. Route-book close blocks **new** routes only; the XNS name owner can still update existing routes and toggle `isActive`.

**Important semantics**

1. **Route list** — `getRouteKeyCount` is one entry per successful `createRoute`. Routes are never deleted. Use `getRouteEntries` to reconstruct human-readable routes without event history.
2. **Existence** — `getRouteRecord(...).target.length == 0` means not registered.

---

## 📚 API reference

Generated contract documentation (NatSpec / solidity-docgen): [docs/API.md](docs/API.md).

---

## 📍 Contract addresses

| Network | XNS |
| ------- | --- |
| Ethereum | [`0x6e797ba2d3103aF167918e71a7E01DE40D45f74b`](https://etherscan.io/address/0x6e797ba2d3103aF167918e71a7E01DE40D45f74b) |
| Sepolia | [`0x6e797ba2d3103aF167918e71a7E01DE40D45f74b`](https://sepolia.etherscan.io/address/0x6e797ba2d3103aF167918e71a7E01DE40D45f74b) (same address) |

---

## 🔐 Contract ownership

`XNSRoutes` exposes ERC-173-compatible `owner()` with OpenZeppelin's two-step ownership
transfer (`transferOwnership` → `acceptOwnership`). The owner is an external identity /
administrative pointer only and has **no authority over route state**. Creating, updating,
freezing, activating, deactivating, and closing route books remain authorized exclusively
through current XNS name ownership.

---

## 🤝 Contributing

Ideas, improvements, and new endpoint conventions are welcome.

To propose a new public `routeType`, open a **New route type** GitHub issue and follow the
format of the specs in [`routeTypes/`](routeTypes/README.md).

This is an early-stage standard — feedback is highly valuable.

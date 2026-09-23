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
   3.3 [Interpret the endpoint](#3-interpret-the-endpoint)
4. [Route State Model](#-route-state-model)
5. [Route freeze](#-route-freeze) \
   5.1 [Per-route freeze](#per-route-freeze) \
   5.2 [Route-book close](#route-book-close)
6. [Optional: build contracts](#-optional-build-contracts)
7. [Suggested route label](#-suggested-route-label)
8. [Design Principles](#-design-principles)
9. [Vision](#-vision)
10. [Repo Contents](#-repo-contents)
11. [On-chain route discovery](#-on-chain-route-discovery)
12. [API reference](#-api-reference)
13. [Network addresses](#-network-addresses)
14. [Deploy](#-deploy)
15. [Contract ownership](#-contract-ownership)
16. [Example scripts](#-example-scripts)
17. [Notes](#-notes)
18. [Contributing](#-contributing)
19. [Summary](#-summary)

---

## ✨ What are XNS Routes?

Routes are typed endpoints underneath an [XNS name](https://github.com/Walodja1987/XNSv2/blob/main/README.md#xns--the-name-layer-on-ethereum). XNS Routes extends an XNS name with a simple path:

```text
route = label@namespace/routeLabel
```

If you own `alice@eth`, you can publish routes under that name **for free**:

```text
alice@eth/treasury           → 0xdf2…3e7          (EVM address)
alice@eth/my-wallet-2        → 0xabc…901          (another EVM address)
alice@eth/bitcoin-wallet-1   → bc1q…              (Bitcoin address)
alice@eth/solana-main        → 7Ec…               (Solana pubkey)
alice@eth/claim-airdrop      → 0xa9059cbb…        (calldata)
```

Each route points to an opaque **endpoint payload** (`bytes target`) plus a **`routeType`** that tells applications how to interpret it.

Routes can have parameters like URLs. They are not stored on-chain, but can be used to derive the return data.
Example shared link:

```text
usdt@action/transfer-usdt/to=0x1234…abcd/amount=100
```

The character rules for a route label are the same as for XNS names:

- `routeLabel` must be `1-32` chars
- charset: lowercase `a-z`, digits `0-9`, and `-`
- no leading/trailing `-`, and no consecutive `--`

---

## 🚀 Why XNS Routes?

- ✅ One recognizable identity with multiple destinations
- ✅ Shareable, human-readable destinations (links, QR codes, etc.)
- ✅ Support EVM and non-EVM endpoints

---

## 🔧 How It Works

### 1. Define a Route

A route is registered under an XNS name:

```solidity
createRoute(
  "alice",                              // label
  "pay",                                // namespace
  "treasury",                           // routeLabel
  abi.encodePacked(address(0xAbc...)),  // target (bytes; e.g. 20-byte EVM address)
  0                                     // application-defined routeType; meanings are defined outside of the contract
);

```

Newly created routes are `isActive = true` by default. `target` and `routeType` are mutable until the route is frozen.

---

### 2. Resolve a Route

Given:

```text
alice@pay/treasury
```

An application:

1. Calls one of the resolve variants(`resolveRouteIfFrozenAndActive`, `resolveRouteIfActive`, or `resolveRoute`)
2. Receives `(target, routeType)`

XNS Routes only supports forward resolution only as multiple routes may point at the same endpoint.

---

### 3. Interpret the endpoint

`routeType` tells the application how to read `target`. Illustrative conventions (not enforced on-chain):

| `routeType` | Example `target`        | Meaning              |
| ----------- | ----------------------- | -------------------- |
| `0`         | 20-byte EVM address     | Ethereum endpoint    |
| `1`         | Bitcoin address bytes   | Bitcoin endpoint     |
| `2`         | Solana pubkey bytes     | Solana endpoint      |

New route types can be defined without changing the XNS Routes contract. The registry stores the endpoint and its type; applications decide how to interpret it.

---

## 🔒 Route State Model

Each route has:

- `target` → opaque endpoint payload, non-empty `bytes` with no protocol max length (**mutable** until the route is frozen)
- `routeType` → off-chain interpretation hint (**mutable** until the route is frozen)
- `isActive` → usable or disabled (toggled by the XNS name owner)
- `isFrozen` → permanently locks `target` / `routeType` for that route
- `routeLabel` → immutable slug

The XNS name owner can call `updateRoute` to change `target` and `routeType` until the route's `isFrozen` flag is set. Closing the route book does **not** block updates.

`isActive` and `isFrozen` are independent: a frozen route can still be deactivated (and reactivated) without changing its endpoint.

`routeLabel` cannot be renamed; create another route instead. Routes are never deleted.

---

## 🧊 Route freeze

### Per-route freeze

```solidity
freezeRoute("alice", "pay", "treasury");
// or batchFreezeRoutes("alice", "pay", ["treasury", "personal"]);
```

- Permanently locks that route's `target` / `routeType`
- XNS name owner can still toggle `isActive`

### Route-book close

```solidity
closeRouteBook("alice@pay");
// or closeRouteBook("alice", "pay");
```

- No new routes can be added under that name
- Existing routes stay updatable until individually frozen
- XNS name owner can still toggle `isActive`

> Useful for finalized endpoint sets, audited contract maps, or limited route collections.

Use `isRouteBookClosed(...)` for the book flag and `record.isFrozen` (via `getRouteRecord`) for per-route freeze.

**Freeze a route** when its endpoint should become permanent.

**Close the route book** when the set of available routes should become permanent.

---

## 🧱 Optional: build contracts

Some applications may treat `target` as the address of a helper that builds a transaction template (view `build(...)` returning chain, destination, value, and data). That pattern is supported by the generic `(target, routeType)` model but is **not** the primary use case of Routes.

Example shared link:

```text
usdt@action/transfer-usdt/to=0x1234…abcd/amount=100
```

Only `usdt@action/transfer-usdt` is registered on-chain. The `/to=…/amount=…` params can be
passed to the view contract pointed to by the route’s `target` to generate and return
calldata — e.g. an ERC-20 `transfer(to, amount)` payload.

Example builders in this repo:

- `XNSRegisterNameBuilder` — `xns@action/register-name`
- `USDTTransferEthBuilder` — `usdt@action/transfer-usdt`

Build contracts:

- define how parameters map to a transaction template
- are reusable across routes
- must be audited if widely used; wallets should verify route + builder before execution

---

## 🧭 Suggested route label

Build contracts can suggest the **route label** (the segment after `/` in the path).

```solidity
function suggestedRouteName() external pure returns (string memory);
```

### UX Flow

- User picks builder from library
- App reads suggested route label
- Prefills `label@namespace/routeLabel` in the path
- User accepts or edits

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

## 🔮 Vision

Routes extend XNS from:

> **name resolution → named endpoint resolution**

They enable:

- multiple payment and account destinations under one identity
- protocol-native endpoint directories
- wallets and apps that resolve `label@namespace/routeLabel` without hardcoding addresses

---

## 📦 Repo Contents

- `XNSRoutes.sol` — named-endpoint registry (includes on-chain enumeration helpers; see below)
- optional example build contracts:
  - `XNSRegisterNameBuilder`
  - `USDTTransferEthBuilder`

---

## 📇 On-chain route discovery

The registry stores each route's **`routeLabel` on-chain** and keeps a per-name list so integrators can discover and reconstruct human-readable routes using only `eth_call`s—**no subgraph or indexer required**.

**Views (see NatSpec / [docs/API.md](docs/API.md))**

- `getRouteKey(label, namespace, routeLabel)` — derive the canonical route storage key
- `getRouteKey(route)` — same from an exact route string
- `getRouteKeyCount(label, namespace)` — number of routes for that name
- `getRouteEntries(label, namespace, start, end)` — **preferred**: page through routes with key, `routeLabel`, and full metadata (`end` **exclusive**; clamped to array length; empty slice when `start` is past the end)
- `getRouteKeys(label, namespace, start, end)` — page through storage keys only (same pagination rules as `getRouteEntries`)
- `getRouteRecord(routeKey)` — read one `RouteRecord` by key (includes stored `routeLabel`)
- `getRouteRecord(label, namespace, routeLabel)` — read by components
- `getRouteRecord(route)` — read by exact **route** string (parsed by `splitRoute`)
- `isRouteBookClosed(xnsName)` — whether new routes can still be added under that name
- `resolveRoute` — resolve `(target, routeType)` when the route exists (ignores `isActive` / `isFrozen`)
- `resolveRouteIfActive` — same, but requires `isActive == true` (ignores freeze)
- `resolveRouteIfFrozenAndActive` — requires `isFrozen == true` and `isActive == true` (preferred production path)
- `splitRoute` — parse `label@namespace/routeLabel` into components
- `splitXNSName` — parse `label@namespace` into components

Use **`resolveRouteIfFrozenAndActive`** for production paths that only trust published (frozen), live routes; use **`resolveRouteIfActive`** when unfrozen drafts are acceptable; use **`resolveRoute`** when you need the binding regardless of flags. Use **`getRouteRecord`** for route metadata. Resolver overloads revert when the route is missing, inactive (active-gated), or not frozen (`resolveRouteIfFrozenAndActive`). `getRouteRecord` returns an **empty record** (`target.length == 0`) when the route is missing.

`target` and `routeType` are **mutable until the route is frozen** (`record.isFrozen`). Route book close blocks **new** routes only; the XNS name owner can still update existing routes and toggle `isActive`.

**Important semantics (don’t skip this)**

1. **Route list**  
   `getRouteKeyCount` equals the number of routes registered under a name—one entry per successful `createRoute`. Routes are never deleted on-chain. Use `getRouteEntries` to reconstruct human-readable routes (`routeLabel`) without event history.

2. **Existence check**  
   Treat **`getRouteRecord(...).target.length == 0`** as "route not registered".

---

## 📚 API reference

Generated contract documentation (NatSpec / solidity-docgen): [docs/API.md](docs/API.md).

---

## 📍 Network addresses

On-chain XNS registry and deployed `XNSRoutes` slots live in [constants/addresses.ts](constants/addresses.ts) (`XNS_ADDRESS`, `XNS_ROUTES_ADDRESS`).

---

## 🚢 Deploy

- Script: [scripts/deploy/deployXNSRoutes.ts](scripts/deploy/deployXNSRoutes.ts)
- Shortcuts: `yarn deploy:xns-routes:hh`, `yarn deploy:xns-routes:sepolia`, `yarn deploy:xns-routes:ethMain`

Set `XNS_CONTRACT_ADDRESS` (Hardhat vars or environment) to your XNS registry before deploying.
The initial contract owner defaults to the deployer; optionally set
`XNS_ROUTES_INITIAL_OWNER` to another non-zero address. See
[docs/DEV_NOTES.md](docs/DEV_NOTES.md).

The deploy script reads `getNamespacePrice("xns")` and sends that ETH with the deployment tx: the `XNSRoutes` constructor calls XNS `registerName("routes","xns")` so **`routes@xns` resolves to the new registry contract**. Ensure the deploy account holds enough ETH for the quoted price (XNS refunds overpayment).

---

## 🔐 Contract ownership

`XNSRoutes` exposes ERC-173-compatible `owner()` with OpenZeppelin's two-step ownership
transfer (`transferOwnership` → `acceptOwnership`). The owner is an external identity /
administrative pointer only and has **no authority over route state**. Creating, updating,
freezing, activating, deactivating, and closing route books remain authorized exclusively
through current XNS name ownership.

---

## 🧪 Example scripts

```bash
npx hardhat run scripts/examples/<script_name>.ts --network <network_name>
```

**Read-only**

- [scripts/examples/routeExists.ts](scripts/examples/routeExists.ts) — check if a route is registered (`getRouteRecord(...).target.length != 0`)
- [scripts/examples/getRouteRecord.ts](scripts/examples/getRouteRecord.ts) — read target, `isActive`, `isFrozen`, `routeType`, and route-book close
- [scripts/examples/isRouteBookClosed.ts](scripts/examples/isRouteBookClosed.ts) — route book closed flag for a name

**Write** (signer must be the address XNS currently resolves for the script’s `label@namespace`)

- [scripts/examples/createRoute.ts](scripts/examples/createRoute.ts) — register a new route key (`createRoute`)
- [scripts/examples/activateRoute.ts](scripts/examples/activateRoute.ts) — set `isActive` true as XNS name owner (emit only on change)
- [scripts/examples/deactivateRoute.ts](scripts/examples/deactivateRoute.ts) — set `isActive` false as XNS name owner (emit only on change)
- [scripts/examples/closeRouteBook.ts](scripts/examples/closeRouteBook.ts) — route book close for a name

Each script has a `USER INPUTS` section at the top. Fill in [constants/addresses.ts](constants/addresses.ts) for `XNS_ROUTES_ADDRESS` on your network before running.

---

## ⚠️ Notes

- Routes store typed endpoints; applications interpret `target` via `routeType`
- Prefer frozen + active routes for production resolution (`resolveRouteIfFrozenAndActive`)
- If using optional build contracts: audit them, and verify route + builder before execution

---

## 🤝 Contributing

Ideas, improvements, and new endpoint conventions are welcome.

This is an early-stage standard — feedback is highly valuable.

---

## 🧩 Summary

> **XNS provides the permanent identity. XNS Routes gives that identity named endpoints.**

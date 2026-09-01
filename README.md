# XNS Routes

**Routes turn XNS names into onchain actions.**

Instead of sharing raw calldata or relying on a single frontend, protocols and users can publish **human-readable, verifiable commands** that build transactions.

---

## ✨ What are Routes?

Routes are registered under an XNSv2 name using **route** and **parametrized route** strings.

**Grammar:**

```text
route               = label "@" namespace "/" routeLabel
parametrized route  = route [ "/" params… ]
```

- **params** (e.g. `/label=bro/namespace=og`) are off-chain; registration stores only the **route**.
  String helpers (`splitRoute`, `getRouteRecord(string)`, `resolveRoute*`) strip at the second `/`
  and ignore that tail.

```
xns@action/register-name/label=bro/namespace=og
usdt@action/transfer-usdt/to=0x.../amount=100
```

Each route:

- belongs to an **XNS name** (`label@namespace`, e.g. `xns@action`)
- has a required **route label** (e.g. `transfer-usdt`)
- points to a **build contract** (`target`)
- produces transaction calldata off-chain

Validation rules:

- `routeLabel` must be `1-32` chars
- charset: lowercase `a-z`, digits `0-9`, and `-`
- no leading/trailing `-`, and no consecutive `--`

---

## 📖 Route vocabulary

| Term | Example | Notes |
|------|---------|--------|
| **route** | `alice@pay/treasury` | On-chain identity: `label@namespace/routeLabel` (no params). Used by `splitRoute`, `routeKey`, and registry lookups |
| **parametrized route** | `alice@pay/treasury/amount=10` | Off-chain link: route plus optional `/params…` tail. String helpers strip the tail at the second `/` |
| **label** | `alice` | XNSv2 name label |
| **namespace** | `pay` | XNSv2 namespace |
| **route label** | `treasury` | Required slug after `/` |
| **route key** | `bytes32` | `keccak256(abi.encode(xnsNameKey, keccak256(bytes(routeLabel))))`; params never included |

Contract tuple APIs use `(label, namespace, routeLabel)` — equivalent to parsing a route. String helpers: `splitRoute`, `splitXNSName`, `getRouteRecord(string route)` (accept a route or parametrized route; params after the second `/` are ignored).

---

## 🧠 Mental Model

| Component      | Meaning                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------ |
| XNS name       | Identity / publisher (`label@namespace`)                                                   |
| Route label    | Action slug (e.g. `transfer-usdt`); 1-32 chars                                             |
| Build contract | How the transaction is built (`target`)                                                    |

> **XNS names resolve identities. Routes resolve actions.**

---

## 🚀 Why Routes?

### For Users

- ✅ Human-readable transaction actions
- ✅ No need to understand calldata or ABI
- ✅ Safer transaction signing (wallet can verify)
- ✅ Reusable commands (links, QR codes, etc.)

---

### For Developers / Protocols

- ✅ Publish canonical actions (e.g. `borrow`, `swap`, `transfer`)
- ✅ Reduce wallet integration complexity
- ✅ Make actions portable across apps
- ✅ Enable verifiable transaction generation

---

## 🔧 How It Works

### 1. Define a Route

A route is registered under an XNS name:

```solidity
createRoute(
  "xns",           // label
  "action",        // namespace
  "register-name", // routeLabel
  address(builder),
  0                // routeType (offchain-defined parser hint)
);
// Sets isActive = true and activeController = current XNS name owner.
// target and routeType are immutable after creation.
// Use createRouteWithController(...) to set activeController explicitly (isActive=true by default).
```

---

### 2. Build Contract

Each route points to a build contract that returns a transaction template:

```solidity
function build(...)
    external
    view
    returns (
        uint256 targetChainId,
        address target,
        uint256 value,
        bytes memory data
    );
```

---

### 3. Wallet Flow

Given:

```
xns@action/register-name/label=bro/namespace=og
```

A wallet:

1. Resolves `xns@action` via XNSv2
2. Parses `register-name` from the route path
3. Resolves `(label, namespace, routeLabel)` via `resolveRouteIfActive`
4. Calls `build(...)`
5. Gets:
   - target chain
   - contract address
   - value
   - calldata

6. Verifies and executes the transaction

---

## 🔒 Route State Model

Each route has:

- `target` → build contract (**immutable** after create)
- `routeType` → off-chain parser hint (**immutable** after create)
- `isActive` → usable or disabled (toggled by `activeController`)
- `activeController` → sole account that may call `activateRoute` / `deactivateRoute`, start a two-step transfer, or `renounceActiveControl` (must not be `address(0)`; see `NO_ACTIVE_CONTROLLER`)

Routes cannot be updated or deleted. The binding from route to `target` is permanent.

---

## 🧊 Route book freeze

The XNS name owner can close the route book permanently:

```solidity
freezeRouteBook("xns@action");
// or freezeRouteBook("xns", "action");
```

- No new routes can be added under that name
- Existing routes are unchanged; `activeController` can still toggle `isActive`

> Useful for finalized app registries, audited contract maps, or limited route collections.

Use `isRouteBookFrozen(xnsName)` or `isRouteBookFrozen(label, namespace)` to check whether the book is closed.

---

## 🧱 Build Contracts

Build contracts:

- define how parameters map to calldata
- return a transaction template
- are reusable across routes

### Example: XNS Name Registration

```
xns@action/register-name/label=bro/namespace=og
```

---

### Example: USDT Transfer

```
usdt@action/transfer-usdt/to=0x.../amount=100
```

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

- **Name-owned** → routes belong to XNS names
- **Composable** → builders are reusable
- **Verifiable** → wallets can independently rebuild tx
- **Human-readable** → no opaque calldata
- **Immutable by design** → `target` and `routeType` never change after create

---

## 🔮 Vision

Routes extend XNS from:

> **name resolution → action resolution**

They enable:

- protocol-native action APIs
- wallet-native transaction building
- shareable onchain commands

---

## 📦 Repo Contents

- `XNSRoutes.sol` — route registry contract (includes on-chain enumeration helpers; see below)
- example build contracts:
  - `XNSRegisterNameBuilder`
  - `USDTTransferEthBuilder`

---

## 📇 On-chain route discovery

The registry stores each route's **`routeLabel` on-chain** and keeps a per-name list so integrators can discover and reconstruct human-readable routes using only `eth_call`s—**no subgraph or indexer required**.

**Views (see NatSpec / [docs/API.md](docs/API.md))**

- `getRouteKeyCount(label, namespace)` — number of routes for that name
- `getRouteEntries(label, namespace, start, end)` — **preferred**: page through routes with key, `routeLabel`, and full metadata (`end` **exclusive**; clamped to array length; empty slice when `start` is past the end)
- `getRouteKeys(label, namespace, start, end)` — page through storage keys only (same pagination rules as `getRouteEntries`)
- `getRouteRecord(routeKey)` — read one `RouteRecord` by key (includes stored `routeLabel`)
- `getRouteRecord(label, namespace, routeLabel)` — read by components
- `getRouteRecord(route)` — read by **route** or parametrized route string (parsed by `splitRoute`; params stripped)
- `isRouteBookFrozen(xnsName)` — whether new routes can still be added under that name
- `resolveRoute` — resolve `(target, routeType)` when the route exists (ignores `isActive`)
- `resolveRouteIfActive` — same, but requires `isActive == true`
- `splitRoute` — parse a route (or parametrized route) into `(label, namespace, routeLabel)`
- `splitXNSName` — parse `label@namespace` into components

Use **`resolveRouteIfActive`** for execution paths that must skip inactive routes; use **`resolveRoute`** when you need the binding regardless of active status. Use **`getRouteRecord`** for route metadata. Resolver overloads revert when the route is missing or (for `resolveRouteIfActive`) inactive. `getRouteRecord` returns an **empty record** (`target == address(0)`) when the route is missing.

`target` and `routeType` are **immutable** after create. Route book freeze blocks **new** routes only; `activeController` can still toggle `isActive` on existing routes.

**Important semantics (don’t skip this)**

1. **Route list**  
   `getRouteKeyCount` equals the number of routes registered under a name—one entry per successful `createRoute`. Routes are never deleted on-chain. Use `getRouteEntries` to reconstruct human-readable routes (`routeLabel`) without event history.

2. **Existence check**  
   Treat **`getRouteRecord(...).target == address(0)`** as "route not registered".

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

Set `XNS_CONTRACT_ADDRESS` (Hardhat vars or environment) to your XNS registry before deploying. See [docs/DEV_NOTES.md](docs/DEV_NOTES.md).

The deploy script reads `getNamespacePrice("xns")` and sends that ETH with the deployment tx: the `XNSRoutes` constructor calls XNS `registerName("routes","xns")` so **`routes@xns` resolves to the new registry contract**. Ensure the deploy account holds enough ETH for the quoted price (XNS refunds overpayment).

---

## 🧪 Example scripts

```bash
npx hardhat run scripts/examples/<script_name>.ts --network <network_name>
```

**Read-only**

- [scripts/examples/routeExists.ts](scripts/examples/routeExists.ts) — check if a route is registered (`getRouteRecord(...).target != 0`)
- [scripts/examples/getRouteRecord.ts](scripts/examples/getRouteRecord.ts) — read target, `isActive`, `routeType`, `activeController`, and route-book freeze
- [scripts/examples/isRouteBookFrozen.ts](scripts/examples/isRouteBookFrozen.ts) — route book freeze flag for a name

**Write** (signer must be the address XNS currently resolves for the script’s `label@namespace`, except activate/deactivate which require `activeController`)

- [scripts/examples/createRoute.ts](scripts/examples/createRoute.ts) — register a new route key (`createRoute` or `createRouteWithController`)
- [scripts/examples/activateRoute.ts](scripts/examples/activateRoute.ts) — set `isActive` true as `activeController` (emit only on change)
- [scripts/examples/deactivateRoute.ts](scripts/examples/deactivateRoute.ts) — set `isActive` false as `activeController` (emit only on change)
- [scripts/examples/freezeRouteBook.ts](scripts/examples/freezeRouteBook.ts) — route book freeze for a name

Each script has a `USER INPUTS` section at the top. Fill in [constants/addresses.ts](constants/addresses.ts) for `XNS_ROUTES_ADDRESS` on your network before running.

---

## ⚠️ Notes

- Build contracts must be audited if widely used
- Always verify route + builder before execution
- Wallets should clearly display:
  - route
  - target contract
  - calldata summary

---

## 🤝 Contributing

Ideas, improvements, and new builders are welcome.

This is an early-stage standard — feedback is highly valuable.

---

## 🧩 Summary

> **Routes make blockchain actions human-readable, shareable, and verifiable.**

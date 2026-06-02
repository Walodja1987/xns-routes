# XNS Routes

**Routes turn XNS names into onchain actions.**

Instead of sharing raw calldata or relying on a single frontend, protocols and users can publish **human-readable, verifiable commands** that build transactions.

---

## ✨ What are Routes?

Routes are registered under an XNS name using **XRL** (XNS Route Locator) strings.

**Grammar:**

```text
XRL           = xnsName "/" route [ "/" params… ]
registry XRL  = xnsName "/" route          (no params; on-chain subset)
```

- **route** = `routeLabel` or `routeScope ":" routeLabel` (e.g. `eth:register-name` or `my-wallet`)
- **params** (e.g. `/label=bro/namespace=og`) are off-chain; the contract only accepts **registry XRL**

```
xns.action/eth:register-name/label=bro/namespace=og
usdt.action/eth:transfer-usdt/to=0x.../amount=100
```

Each route:

- belongs to an **xnsName** (e.g. `xns.action`)
- has an optional **route scope** (e.g. `eth`, `137-poly`) and a required **route label** (e.g. `transfer-usdt`)
- points to a **build contract** (`target`)
- produces transaction calldata off-chain

Validation rules:

- `routeScope` may be empty, or `1-20` chars if provided
- `routeLabel` must be `1-32` chars
- charset for both: lowercase `a-z`, digits `0-9`, and `-`
- no leading/trailing `-`, and no consecutive `--`

---

## 📖 XRL vocabulary

| Term | Example | Notes |
|------|---------|--------|
| **XRL** | `ai.xns/eth:123/label=bro` | Full locator; optional param path after the route |
| **Registry XRL** | `ai.xns/eth:123` | On-chain subset of XRL: `xnsName "/" route` only (no params). Used by `splitXRL`, `routeKey`, and registry lookups |
| **xnsName** | `ai.xns` | Host / owner scope |
| **route** | `eth:123` | Part after `/` in a registry XRL |
| **route scope** | `eth` | Optional; before `:` |
| **route label** | `123` | Required slug |
| **route key** | `bytes32` | `keccak256(canonical registry XRL)`; params never included |

Contract tuple APIs use `(xnsName, routeScope, routeLabel)` — equivalent to parsing a registry XRL. Path helpers: `splitXRL`, `getRouteInfoFromXRL`, `routeExistsFromXRL` (input must be a registry XRL).

---

## 🧠 Mental Model

| Component      | Meaning                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------ |
| XNS name       | Identity / publisher (`xnsName`)                                                           |
| Route scope    | Optional disambiguator before `:` (e.g. `eth`); 0 or 1-20 chars                            |
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
  "xns.action",
  "eth",           // routeScope
  "register-name", // routeLabel
  address(builder),
  0,      // routeType (offchain-defined parser hint)
  true,   // activate → stored isActive
  true    // freeze → set isFrozen in this tx
);
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
xns.action/eth:register-name/label=bro/namespace=og
```

A wallet:

1. Resolves `xns.action`
2. Parses `eth` and `register-name` from `eth:register-name`
3. Looks up `(xnsName, routeScope, routeLabel)` on the registry (`routeScope` may be empty)
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

- `target` → build contract
- `isActive` → usable or disabled
- `isFrozen` → immutable or editable

### States

| State               | Meaning                 |
| ------------------- | ----------------------- |
| Active + Editable   | Live, but can change    |
| Inactive + Editable | Draft / paused          |
| Active + Frozen     | Live and immutable      |
| Inactive + Frozen   | Disabled, but immutable |

---

## 🧊 Freezing

### Route Freeze

Locks a route forever:

```solidity
freezeRoute("xns.action", "eth", "register-name");
```

- Target can never change again and the route cannot be deleted
- Active flag can still be toggled (`activateRoute` / `deactivateRoute`)

---

### Route book freeze

Locks the entire route book under a name:

```solidity
freezeRouteBook("xns.action");
```

- No new routes can be added
- No route targets can be changed
- Routes cannot be deleted (`deleteRoute` reverts)
- Activation still allowed (`activateRoute` / `deactivateRoute`)

> This is useful for publishers who want to finalize their entire action set.

---

## 🧱 Build Contracts

Build contracts:

- define how parameters map to calldata
- return a transaction template
- are reusable across routes

### Example: XNS Name Registration

```
xns.action/eth:register-name/label=bro/namespace=og
```

---

### Example: USDT Transfer

```
usdt.action/eth:transfer-usdt/to=0x.../amount=100
```

---

## 🧭 Suggested route label (and scope)

Build contracts can suggest the **route label** (the part after `routeScope:` in the path). The **route scope** (e.g. `eth`) often comes from the builder’s target network or app defaults.

```solidity
function suggestedRouteName() external pure returns (string memory);
```

### UX Flow

- User picks builder from library
- App reads suggested **route** label and sets **route scope** (e.g. from `TARGET_CHAIN_ID` or user choice)
- Prefills `routeScope:routeLabel` in the path
- User accepts or edits

---

## 🌍 Design Principles

- **Name-owned** → routes belong to XNS names
- **Composable** → builders are reusable
- **Verifiable** → wallets can independently rebuild tx
- **Human-readable** → no opaque calldata
- **Immutable when needed** → freeze for trust

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

## 📇 On-chain route discovery (no indexer)

The registry keeps an **append-only log** of **route storage keys** (`bytes32`) per XNS name so integrators can discover “what was ever created here” using only `eth_call`s—**no subgraph or indexer required** for that workflow.

**Views (see NatSpec / [docs/API.md](docs/API.md))**

- `getRouteKeyCount(xnsName)` — length of the log for that name
- `getRouteKeys(xnsName, start, end)` — page through keys (`end` **exclusive**; if `end` &gt; log length, it is clamped to the log length; if `start` is past that range, returns an empty array)
- `getRouteRecordByRouteKey(bytes32)` — read one `RouteRecord` by key (no string tuple needed)
- `getRouteRecordByRouteKey(bytes32[])` — same, batch; returns `RouteRecord[]` (ABI overload—some clients must pick the function by full signature, e.g. ethers: `getFunction("getRouteRecordByRouteKey(bytes32[])")`)
- `splitXRL`, `getRouteInfoFromXRL`, `routeExistsFromXRL` — accept **registry XRL** only (not full XRL with params)

**Important semantics (don’t skip this)**

1. **Log length ≠ number of live routes**  
   `getRouteKeyCount` counts **append-only log entries**, not routes that still exist. After `deleteRoute`, the key **stays in the log**; storage for that key is cleared, so `getRouteRecordByRouteKey` returns **`target == address(0)`** for that slot. Treat **zero `target` as deleted / empty** and filter those out off-chain (or in your UI) when you only want **live** routes.

2. **Duplicate keys in the log**  
   If a route is **deleted and later recreated** with the same `(xnsName, routeScope, routeLabel)`, **`createRoute` appends the same `bytes32` again**. That is **intentional**: duplicates hint at **churn** (tear-down and re-registration). If you only care about unique keys, **dedupe by hash** off-chain.

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

The deploy script reads `getNamespacePrice("xns")` and sends that ETH with the deployment tx: the `XNSRoutes` constructor calls XNS `registerName("routes","xns")` so **`routes.xns` resolves to the new registry contract**. Ensure the deploy account holds enough ETH for the quoted price (XNS refunds overpayment).

---

## 🧪 Example scripts

```bash
npx hardhat run scripts/examples/<script_name>.ts --network <network_name>
```

**Read-only**

- [scripts/examples/routeExists.ts](scripts/examples/routeExists.ts) — check if a route is registered
- [scripts/examples/getRouteInfo.ts](scripts/examples/getRouteInfo.ts) — read target, `isActive`, `isFrozen`, `routeType`
- [scripts/examples/isRouteBookFrozen.ts](scripts/examples/isRouteBookFrozen.ts) — route book freeze flag for a name

**Write** (signer must be the address XNS currently resolves for the script’s `xnsName`)

- [scripts/examples/createRoute.ts](scripts/examples/createRoute.ts) — register a new route key
- [scripts/examples/updateRoute.ts](scripts/examples/updateRoute.ts) — full update of an existing route
- [scripts/examples/activateRoute.ts](scripts/examples/activateRoute.ts) — set `isActive` true (emit only on change)
- [scripts/examples/deactivateRoute.ts](scripts/examples/deactivateRoute.ts) — set `isActive` false (emit only on change)
- [scripts/examples/deleteRoute.ts](scripts/examples/deleteRoute.ts) — remove route if not frozen / route book open
- [scripts/examples/updateTarget.ts](scripts/examples/updateTarget.ts) — change build `target` (emit only on change)
- [scripts/examples/updateRouteType.ts](scripts/examples/updateRouteType.ts) — change `routeType` (emit only on change)
- [scripts/examples/freezeRoute.ts](scripts/examples/freezeRoute.ts) — freeze one route forever
- [scripts/examples/freezeRouteBook.ts](scripts/examples/freezeRouteBook.ts) — route book freeze for a name

Each script has a `USER INPUTS` section at the top. Fill in [constants/addresses.ts](constants/addresses.ts) for `XNS_ROUTES_ADDRESS` on your network before running.

---

## ⚠️ Notes

- Build contracts must be audited if widely used
- Always verify route + builder before execution
- Wallets should clearly display:
  - route
  - route scope (if any)
  - target contract
  - calldata summary

---

## 🤝 Contributing

Ideas, improvements, and new builders are welcome.

This is an early-stage standard — feedback is highly valuable.

---

## 🧩 Summary

> **Routes make blockchain actions human-readable, shareable, and verifiable.**

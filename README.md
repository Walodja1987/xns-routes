# XNS Routes

**Routes turn XNS names into onchain actions.**

Instead of sharing raw calldata or relying on a single frontend, protocols and users can publish **human-readable, verifiable commands** that build transactions.

---

## ✨ What are Routes?

An XNS route is a **named action** under an XNS name, scoped to a **chain key** and **route** label. Paths look like `xnsName/chain:route/params…` when a chain is set (one `:` in the action segment). For **chain-agnostic** routes (e.g. same EOA everywhere), use an empty chain in the registry and a path like `xnsName/route/params…` (no `:` in that segment).

```
xns.action/eth:register-name/label=bro/namespace=og
usdt.action/eth:transfer-usdt/to=0x.../amount=100
```

Each route:

* belongs to an XNS name (e.g. `xns.action`)
* has a **chain** key (e.g. `eth`, `137-poly`) or **empty** for chain-agnostic routes, plus a **route** label (e.g. `transfer-usdt`)
* points to a **build contract**
* produces transaction calldata

---

## 🧠 Mental Model

| Component      | Meaning                                      |
| -------------- | -------------------------------------------- |
| XNS name       | Identity / publisher                         |
| Chain key      | Where the action runs (label, e.g. `eth`)   |
| Route          | Action / intent (label, e.g. `transfer-usdt`) |
| Build contract | How the transaction is built                 |

> **XNS names resolve identities. Routes resolve actions.**

---

## 🚀 Why Routes?

### For Users

* ✅ Human-readable transaction actions
* ✅ No need to understand calldata or ABI
* ✅ Safer transaction signing (wallet can verify)
* ✅ Reusable commands (links, QR codes, etc.)

---

### For Developers / Protocols

* ✅ Publish canonical actions (e.g. `borrow`, `swap`, `transfer`)
* ✅ Reduce wallet integration complexity
* ✅ Make actions portable across apps
* ✅ Enable verifiable transaction generation

---

## 🔧 How It Works

### 1. Define a Route

A route is registered under an XNS name:

```solidity
createRoute(
  "xns.action",
  "eth",           // chain
  "register-name", // route
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
3. Looks up `(xnsName, chain, route)` on the registry (`chain` may be empty for chain-agnostic routes)
4. Calls `build(...)`
5. Gets:

   * target chain
   * contract address
   * value
   * calldata
6. Verifies and executes the transaction

---

## 🔒 Route State Model

Each route has:

* `target` → build contract
* `isActive` → usable or disabled
* `isFrozen` → immutable or editable

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

* Target can never change again
* Active flag can still be toggled (`activateRoute` / `deactivateRoute`)

---

### Route book freeze

Locks the entire route book under a name:

```solidity
freezeRouteBook("xns.action");
```

* No new routes can be added
* No route targets can be changed
* Activation still allowed (`activateRoute` / `deactivateRoute`)

> This is useful for publishers who want to finalize their entire action set.

---

## 🧱 Build Contracts

Build contracts:

* define how parameters map to calldata
* return a transaction template
* are reusable across routes

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

## 🧭 Suggested route label (and chain)

Build contracts can suggest the **route** label (the part after `chain:` in the path). The **chain** key (e.g. `eth`) usually comes from the builder’s target network or app defaults.

```solidity
function suggestedRouteName() external pure returns (string memory);
```

### UX Flow

* User picks builder from library
* App reads suggested **route** label and sets **chain** (e.g. from `TARGET_CHAIN_ID` or user choice)
* Prefills `chain:route` in the path
* User accepts or edits

---

## 🌍 Design Principles

* **Name-owned** → routes belong to XNS names
* **Composable** → builders are reusable
* **Verifiable** → wallets can independently rebuild tx
* **Human-readable** → no opaque calldata
* **Immutable when needed** → freeze for trust

---

## 🔮 Vision

Routes extend XNS from:

> **name resolution → action resolution**

They enable:

* protocol-native action APIs
* wallet-native transaction building
* shareable onchain commands

---

## 📦 Repo Contents

* `XNSRoutes.sol` — route registry contract
* example build contracts:

  * `XNSRegisterNameBuilder`
  * `USDTTransferEthBuilder`

---

## 📚 API reference

Generated contract documentation (NatSpec / solidity-docgen): [docs/API.md](docs/API.md).

---

## 📍 Network addresses

On-chain XNS registry and deployed `XNSRoutes` slots live in [constants/addresses.ts](constants/addresses.ts) (`XNS_ADDRESS`, `XNS_ROUTES_ADDRESS`).

---

## 🚢 Deploy

* Script: [scripts/deploy/deployXNSRoutes.ts](scripts/deploy/deployXNSRoutes.ts)
* Shortcuts: `yarn deploy:xns-routes:hh`, `yarn deploy:xns-routes:sepolia`, `yarn deploy:xns-routes:ethMain`

Set `XNS_CONTRACT_ADDRESS` (Hardhat vars or environment) to your XNS registry before deploying. See [docs/DEV_NOTES.md](docs/DEV_NOTES.md).

The deploy script reads `getNamespacePrice("xns")` and sends that ETH with the deployment tx: the `XNSRoutes` constructor calls XNS `registerName("routes","xns")` so **`routes.xns` resolves to the new registry contract**. Ensure the deploy account holds enough ETH for the quoted price (XNS refunds overpayment).

---

## 🧪 Example scripts

```bash
npx hardhat run scripts/examples/<script_name>.ts --network <network_name>
```

**Read-only**

* [scripts/examples/routeExists.ts](scripts/examples/routeExists.ts) — check if a route is registered
* [scripts/examples/getRouteInfo.ts](scripts/examples/getRouteInfo.ts) — read target, `isActive`, `isFrozen`, `routeType`
* [scripts/examples/isRouteBookFrozen.ts](scripts/examples/isRouteBookFrozen.ts) — route book freeze flag for a name

**Write** (signer must be the address XNS currently resolves for the script’s `xnsName`)

* [scripts/examples/createRoute.ts](scripts/examples/createRoute.ts) — register a new route key
* [scripts/examples/updateRoute.ts](scripts/examples/updateRoute.ts) — full update of an existing route
* [scripts/examples/activateRoute.ts](scripts/examples/activateRoute.ts) — set `isActive` true (emit only on change)
* [scripts/examples/deactivateRoute.ts](scripts/examples/deactivateRoute.ts) — set `isActive` false (emit only on change)
* [scripts/examples/updateTarget.ts](scripts/examples/updateTarget.ts) — change build `target` (emit only on change)
* [scripts/examples/updateRouteType.ts](scripts/examples/updateRouteType.ts) — change `routeType` (emit only on change)
* [scripts/examples/freezeRoute.ts](scripts/examples/freezeRoute.ts) — freeze one route forever
* [scripts/examples/freezeRouteBook.ts](scripts/examples/freezeRouteBook.ts) — route book freeze for a name

Each script has a `USER INPUTS` section at the top. Fill in [constants/addresses.ts](constants/addresses.ts) for `XNS_ROUTES_ADDRESS` on your network before running.

---

## ⚠️ Notes

* Build contracts must be audited if widely used
* Always verify route + builder before execution
* Wallets should clearly display:

  * route
  * chain
  * target contract
  * calldata summary

---

## 🤝 Contributing

Ideas, improvements, and new builders are welcome.

This is an early-stage standard — feedback is highly valuable.

---

## 🧩 Summary

> **Routes make blockchain actions human-readable, shareable, and verifiable.**
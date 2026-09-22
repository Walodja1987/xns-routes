# XNS Routes

**Routes turn XNS names into onchain actions.**

Instead of sharing raw calldata or relying on a single frontend, protocols and users can publish **human-readable, verifiable commands** that build transactions.

---

## ✨ What are Routes?

Routes are registered under an XNSv2 name using **route** strings.

**Grammar:**

```text
route = label "@" namespace "/" routeLabel
```

Application-layer params (e.g. `/amount=10`) are **not** part of the on-chain format.
Apps must strip them before calling string helpers (`splitRoute`, `getRouteRecord(string)`, `resolveRoute*`).

```
xns@action/register-name
usdt@action/transfer-usdt
```

Each route:

- belongs to an **XNS name** (`label@namespace`, e.g. `xns@action`)
- has a required **route label** (e.g. `transfer-usdt`)
- points to an opaque **endpoint payload** (`bytes target`, interpreted via `routeType`)
- produces transaction calldata off-chain

Validation rules:

- `routeLabel` must be `1-32` chars
- charset: lowercase `a-z`, digits `0-9`, and `-`
- no leading/trailing `-`, and no consecutive `--`

---

## 📖 Route vocabulary

| Term            | Example              | Notes                                                                                                        |
| --------------- | -------------------- | ------------------------------------------------------------------------------------------------------------ |
| **route**       | `alice@pay/treasury` | On-chain identity: `label@namespace/routeLabel`. Used by `splitRoute`, `routeKey`, and registry lookups      |
| **label**       | `alice`              | XNSv2 name label                                                                                             |
| **namespace**   | `pay`                | XNSv2 namespace                                                                                              |
| **route label** | `treasury`           | Required slug after `/`                                                                                      |
| **route key**   | `bytes32`            | `keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel))` — hash of `label@namespace/routeLabel` |

Contract tuple APIs use `(label, namespace, routeLabel)` — equivalent to parsing a route. String helpers: `splitRoute`, `splitXNSName`, `getRouteRecord(string route)` (exact route string only; no params suffix).

---

## 🧠 Mental Model

| Component      | Meaning                                        |
| -------------- | ---------------------------------------------- |
| XNS name       | Identity / publisher (`label@namespace`)       |
| Route label    | Action slug (e.g. `transfer-usdt`); 1-32 chars |
| Build contract | How the transaction is built (`target`)        |

> **XNS names resolve identities. Routes resolve actions.**

### Contract ownership

`XNSRoutes` exposes ERC-173-compatible `owner()` with OpenZeppelin's two-step ownership
transfer (`transferOwnership` → `acceptOwnership`). The owner is an external identity /
administrative pointer only and has **no authority over route state**. Creating, updating,
freezing, activating, deactivating, and closing route books remain authorized exclusively
through current XNS name ownership.

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
  abi.encodePacked(address(builder)), // target (bytes; e.g. 20-byte EVM address)
  0                // application-defined routeType; meanings are not standardized
);
// Sets isActive = true.
// target and routeType are mutable until the route is frozen.
```

---

### 2. Build Contract

For EVM builder-style routes, `target` is typically a 20-byte contract address under an application-defined `routeType`. That contract can return a transaction template:

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

Non-EVM endpoints (e.g. Bitcoin) can store the destination directly in `bytes target` under another `routeType`. Large payloads (e.g. calldata) are allowed; owners pay the gas/storage cost.

---

### 3. Wallet Flow

Given:

```
xns@action/register-name
```

(with optional off-chain params like `/label=bro/namespace=og` stripped by the app before calling Routes)

A wallet:

1. Strips any application-layer params from the shared link
2. Resolves `xns@action` via XNSv2
3. Resolves `(label, namespace, routeLabel)` via `resolveRouteIfFrozenAndActive` (or `resolveRouteIfActive` when unfrozen drafts are acceptable)
4. Calls `build(...)` using the off-chain params
5. Gets:
   - target chain
   - contract address
   - value
   - calldata

6. Verifies and executes the transaction

---

## 🔒 Route State Model

Each route has:

- `target` → opaque endpoint payload, non-empty `bytes` with no protocol max length (**mutable** until the route is frozen; e.g. a 20-byte EVM address under an application-defined `routeType`)
- `routeType` → off-chain interpretation hint (**mutable** until the route is frozen)
- `isActive` → usable or disabled (toggled by the XNS name owner)
- `isFrozen` → permanently locks `target` / `routeType` for that route
- `routeLabel` → immutable slug

The XNS name owner can call `updateRoute` to change `target` and `routeType` until the route's `isFrozen` flag is set. Closing the route book does **not** block updates.

`routeLabel` cannot be renamed; create another route instead. Routes are never deleted.

---

## 🧊 Route freeze

### Per-route freeze

```solidity
freezeRoute("xns", "action", "register-name");
// or batchFreezeRoutes("xns", "action", ["register-name", "treasury"]);
```

- Permanently locks that route's `target` / `routeType`
- XNS name owner can still toggle `isActive`

### Route-book close

```solidity
closeRouteBook("xns@action");
// or closeRouteBook("xns", "action");
```

- No new routes can be added under that name
- Existing routes stay updatable until individually frozen
- XNS name owner can still toggle `isActive`

> Useful for finalized app registries, audited contract maps, or limited route collections.

Use `isRouteBookClosed(...)` for the book flag and `record.isFrozen` (via `getRouteRecord`) for per-route freeze.

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
- **Optionally immutable** → `target` / `routeType` updateable until freeze; then permanent

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

Use **`resolveRouteIfFrozenAndActive`** for production execution paths that only trust published (frozen), live routes; use **`resolveRouteIfActive`** when unfrozen drafts are acceptable; use **`resolveRoute`** when you need the binding regardless of flags. Use **`getRouteRecord`** for route metadata. Resolver overloads revert when the route is missing, inactive (active-gated), or not frozen (`resolveRouteIfFrozenAndActive`). `getRouteRecord` returns an **empty record** (`target.length == 0`) when the route is missing.

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

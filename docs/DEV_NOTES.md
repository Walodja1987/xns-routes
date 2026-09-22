# 🎡 Installation

```bash
yarn install
```

## Environment Variables Setup

Set variables via Hardhat `vars`:

```bash
# Network-independent
npx hardhat vars set MNEMONIC
npx hardhat vars set ETHERSCAN_API_KEY

# Network-specific
npx hardhat vars set ETH_SEPOLIA_TESTNET_URL
npx hardhat vars set ETH_MAINNET_URL
```

## Compile and Test

```bash
yarn compile:hh
yarn test:hh
```

## Contract

- `contracts/src/XNSRoutes.sol` — route registry (linked to a deployed XNS contract)

## Deploy Scripts

Set `XNS_CONTRACT_ADDRESS` (Hardhat var or env) only when overriding the default. For Ethereum mainnet and Sepolia, the deploy script uses `XNS_ADDRESS` in `constants/addresses.ts` (`0x6e797ba2d3103aF167918e71a7E01DE40D45f74b`). The deployment tx sends `getNamespacePrice("xns")` as value so the constructor can call XNS `registerName("routes","xns")` (see `XNSRoutes` NatSpec).

The initial ERC-173 contract owner defaults to the deployer. To use a different non-zero
address, set `XNS_ROUTES_INITIAL_OWNER` as a Hardhat var or environment variable. Ownership
uses a two-step transfer and grants no authority over route state.

```bash
yarn deploy:xns-routes:hh
```

For live networks:

```bash
yarn deploy:xns-routes:sepolia
yarn deploy:xns-routes:ethMain
```

or:

```bash
npx hardhat run scripts/deploy/deployXNSRoutes.ts --network sepolia
```

## Example Scripts

Run any example with:

```bash
npx hardhat run scripts/examples/<script_name>.ts --network <network_name>
```

### XNSRoutes (read)

- [resolveRoute.ts](../scripts/examples/resolveRoute.ts) — demonstrates frozen+active, active-only, and raw resolution policies
- [listRoutes.ts](../scripts/examples/listRoutes.ts) — paginates through `getRouteEntries`
- [routeExists.ts](../scripts/examples/routeExists.ts) — uses `getRouteRecord(...).target != 0`
- [getRouteRecord.ts](../scripts/examples/getRouteRecord.ts)
- [getRouteKey.ts](../scripts/examples/getRouteKey.ts) — compares tuple, string, and local key derivation
- [isRouteBookClosed.ts](../scripts/examples/isRouteBookClosed.ts)
- [parseRoute.ts](../scripts/examples/parseRoute.ts) — demonstrates `splitRoute` and `splitXNSName`
- [isValidRouteLabel.ts](../scripts/examples/isValidRouteLabel.ts)

### XNSRoutes (write — caller must be XNS-resolved owner of `xnsName`)

- [createRoute.ts](../scripts/examples/createRoute.ts)
- [updateRoute.ts](../scripts/examples/updateRoute.ts)
- [activateRoute.ts](../scripts/examples/activateRoute.ts)
- [deactivateRoute.ts](../scripts/examples/deactivateRoute.ts)
- [freezeRoute.ts](../scripts/examples/freezeRoute.ts)
- [batchFreezeRoutes.ts](../scripts/examples/batchFreezeRoutes.ts)
- [closeRouteBook.ts](../scripts/examples/closeRouteBook.ts)

### Contract identity ownership (does not grant route authority)

- [transferOwnership.ts](../scripts/examples/transferOwnership.ts) — starts a two-step transfer
- [acceptOwnership.ts](../scripts/examples/acceptOwnership.ts) — pending owner accepts

> Note: each script has a `USER INPUTS` section at the top.

## Address Configuration

Before running examples, set deployed addresses in `constants/addresses.ts`:

- `XNS_ADDRESS` — XNSv2 registry (`ethMain` / `sepolia`: `0x6e797ba2d3103aF167918e71a7E01DE40D45f74b`)
- `XNS_ROUTES_ADDRESS.hardhat` / `localhost` / `ethMain` / `sepolia`

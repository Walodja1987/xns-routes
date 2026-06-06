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

Set `XNS_CONTRACT_ADDRESS` (Hardhat var or env) to your XNS registry. The deploy script sends `getNamespacePrice("xns")` as the deployment tx value so the constructor can call XNS `registerName("routes","xns")` (see `XNSRoutes` NatSpec).

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

- [routeExists.ts](../scripts/examples/routeExists.ts) — uses `getRouteRecord(...).target != 0`
- [getRouteRecord.ts](../scripts/examples/getRouteRecord.ts)
- [isRouteBookFrozen.ts](../scripts/examples/isRouteBookFrozen.ts)

### XNSRoutes (write — caller must be XNS-resolved owner of `xnsName`)

- [createRoute.ts](../scripts/examples/createRoute.ts)
- [updateRoute.ts](../scripts/examples/updateRoute.ts)
- [activateRoute.ts](../scripts/examples/activateRoute.ts)
- [deactivateRoute.ts](../scripts/examples/deactivateRoute.ts)
- [deleteRoute.ts](../scripts/examples/deleteRoute.ts)
- [updateTarget.ts](../scripts/examples/updateTarget.ts)
- [updateRouteType.ts](../scripts/examples/updateRouteType.ts)
- [freezeRoute.ts](../scripts/examples/freezeRoute.ts)
- [freezeRouteBook.ts](../scripts/examples/freezeRouteBook.ts)

> Note: each script has a `USER INPUTS` section at the top.

## Address Configuration

Before running examples, set deployed addresses in `constants/addresses.ts`:

- `XNS_ROUTES_ADDRESS.hardhat` / `localhost` / `ethMain` / `sepolia`

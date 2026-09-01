# XNSRoutes Simple Indexer

Compact SQLite-based indexer for `XNSRoutes` events (XNSv2). No TheGraph, no extra services.

## What it does

- Reads logs from an RPC endpoint
- Reconstructs latest route state per `(label, namespace, routeLabel)`
- Stores state + checkpoint in a local SQLite file
- Lets you list or export routes

On-chain events index `xnsNameKey` and `routeKey` (see `XNSRoutes.sol`) so external indexers or
custom `eth_getLogs` queries can filter by XNS name hash and/or canonical route key; this tool
decodes full event payloads from the ABI and does not rely on topic layout beyond what `web3.py`
provides.

## Requirements

- Python 3.10+
- `pip install web3`

## Quick start

From repository root:

```bash
pip install web3
python indexer/indexer.py --rpc-url "$RPC_URL" --contract "$XNS_ROUTES" sync --from-block 12345678 --once
python indexer/indexer.py --rpc-url "$RPC_URL" --contract "$XNS_ROUTES" list --xns-name xns@action
```

## Commands

All commands require `--rpc-url` and `--contract`.

### 1) Sync

```bash
python indexer/indexer.py \
  --rpc-url "$RPC_URL" \
  --contract "$XNS_ROUTES" \
  sync \
  --from-block 12345678 \
  --once
```

Options:

- `--from-block` (required): contract deployment block
- `--once`: catch up and exit
- `--chunk-size` (default `4000`): block range per request
- `--poll-interval` (default `5`): seconds between polls (follow mode)
- `--finality` (default `6`): ignore latest N blocks (reorg safety)

Without `--once`, sync runs continuously.

### 2) List routes

```bash
python indexer/indexer.py \
  --rpc-url "$RPC_URL" \
  --contract "$XNS_ROUTES" \
  list \
  --xns-name xns@action
```

### 3) Export routes (JSON)

```bash
python indexer/indexer.py \
  --rpc-url "$RPC_URL" \
  --contract "$XNS_ROUTES" \
  export \
  --out routes.json
```

Filter by name:

```bash
python indexer/indexer.py \
  --rpc-url "$RPC_URL" \
  --contract "$XNS_ROUTES" \
  export \
  --xns-name xns@action \
  --out xns-action-routes.json
```

## Storage

Default DB path:

`indexer/xns_routes_indexer.sqlite`

Override with:

```bash
--db /custom/path/index.sqlite
```

## ABI source

By default, the script reads:

`artifacts/contracts/src/XNSRoutes.sol/XNSRoutes.json`

Override with:

```bash
--abi /path/to/XNSRoutes.json
```

## Notes

- Run `sync` first before `list` or `export`.
- If you re-deploy to a new contract address, use the new address and deployment block.
- Indexed rows are keyed by `(chainId, contract, label, namespace, routeLabel)`.
- `--xns-name` uses XNSv2 format: `label@namespace` (e.g. `xns@action`).

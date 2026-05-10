#!/usr/bin/env python3
"""Simple SQLite indexer for XNSRoutes events.

Route-scoped events (`RouteCreated`, `RouteTargetUpdated`, etc.) include indexed `nameHash`
(`keccak256(bytes(xnsName))`) and `routeKey` (same as on-chain `_routeKey`) as log topics.
`RouteCreated` indexes `target`; `RouteTargetUpdated` indexes `newTarget` (previous target is non-indexed in log data).
Remaining fields are non-indexed (strings, flags, types) in log data. Use topics for narrow
`eth_getLogs` filters; decoded `args` expose the same fields by name.

Usage examples:
  python indexer/indexer.py sync --rpc-url https://... --contract 0x... --from-block 12345678
  python indexer/indexer.py list --rpc-url https://... --contract 0x... --xns-name bob.xns
  python indexer/indexer.py export --rpc-url https://... --contract 0x... --xns-name bob.xns --out routes.json
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from web3 import Web3


EVENT_NAMES = (
    "RouteCreated",
    "RouteTargetUpdated",
    "RouteTypeUpdated",
    "RouteActiveStatusUpdated",
    "RouteFrozen",
    "RouteDeleted",
)


@dataclass(frozen=True)
class Context:
    db_path: Path
    abi_path: Path
    rpc_url: str
    contract: str
    chunk_size: int
    poll_interval: int


def load_abi(abi_path: Path) -> list[dict[str, Any]]:
    artifact = json.loads(abi_path.read_text(encoding="utf-8"))
    if "abi" not in artifact:
        raise ValueError(f"Artifact missing 'abi': {abi_path}")
    return artifact["abi"]


def get_web3(rpc_url: str) -> Web3:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 30}))
    if not w3.is_connected():
        raise RuntimeError(f"Cannot connect to RPC: {rpc_url}")
    return w3


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;

        CREATE TABLE IF NOT EXISTS checkpoints (
            chain_id INTEGER NOT NULL,
            contract TEXT NOT NULL,
            last_block INTEGER NOT NULL,
            PRIMARY KEY (chain_id, contract)
        );

        CREATE TABLE IF NOT EXISTS routes (
            chain_id INTEGER NOT NULL,
            contract TEXT NOT NULL,
            xns_name TEXT NOT NULL,
            route_prefix TEXT NOT NULL,
            route TEXT NOT NULL,
            target TEXT,
            route_type INTEGER,
            is_active INTEGER,
            is_frozen INTEGER,
            deleted INTEGER NOT NULL DEFAULT 0,
            updated_block INTEGER NOT NULL,
            updated_tx_hash TEXT NOT NULL,
            updated_log_index INTEGER NOT NULL,
            PRIMARY KEY (chain_id, contract, xns_name, route_prefix, route)
        );

        CREATE INDEX IF NOT EXISTS idx_routes_lookup
        ON routes(chain_id, contract, xns_name, deleted, route_prefix, route);
        """
    )
    conn.commit()


def get_checkpoint(conn: sqlite3.Connection, chain_id: int, contract: str, start_block: int) -> int:
    row = conn.execute(
        "SELECT last_block FROM checkpoints WHERE chain_id = ? AND contract = ?",
        (chain_id, contract),
    ).fetchone()
    return int(row[0]) if row else start_block - 1


def set_checkpoint(conn: sqlite3.Connection, chain_id: int, contract: str, last_block: int) -> None:
    conn.execute(
        """
        INSERT INTO checkpoints(chain_id, contract, last_block)
        VALUES (?, ?, ?)
        ON CONFLICT(chain_id, contract) DO UPDATE SET last_block = excluded.last_block
        """,
        (chain_id, contract, last_block),
    )


def upsert_route(
    conn: sqlite3.Connection,
    chain_id: int,
    contract: str,
    xns_name: str,
    route_prefix: str,
    route: str,
    *,
    target: str | None = None,
    route_type: int | None = None,
    is_active: int | None = None,
    is_frozen: int | None = None,
    deleted: int | None = None,
    block_number: int,
    tx_hash: str,
    log_index: int,
) -> None:
    conn.execute(
        """
        INSERT INTO routes(
            chain_id, contract, xns_name, route_prefix, route,
            target, route_type, is_active, is_frozen, deleted,
            updated_block, updated_tx_hash, updated_log_index
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(chain_id, contract, xns_name, route_prefix, route)
        DO UPDATE SET
            target = COALESCE(excluded.target, routes.target),
            route_type = COALESCE(excluded.route_type, routes.route_type),
            is_active = COALESCE(excluded.is_active, routes.is_active),
            is_frozen = COALESCE(excluded.is_frozen, routes.is_frozen),
            deleted = COALESCE(excluded.deleted, routes.deleted),
            updated_block = excluded.updated_block,
            updated_tx_hash = excluded.updated_tx_hash,
            updated_log_index = excluded.updated_log_index
        """,
        (
            chain_id,
            contract,
            xns_name,
            route_prefix,
            route,
            target,
            route_type,
            is_active,
            is_frozen,
            deleted,
            block_number,
            tx_hash,
            log_index,
        ),
    )


def decode_logs(contract: Any, logs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    decoded: list[dict[str, Any]] = []
    for log in logs:
        for event_name in EVENT_NAMES:
            event_cls = getattr(contract.events, event_name)
            try:
                e = event_cls().process_log(log)
                decoded.append(
                    {
                        "name": event_name,
                        "args": dict(e["args"]),
                        "blockNumber": int(e["blockNumber"]),
                        "transactionHash": e["transactionHash"].hex(),
                        "logIndex": int(e["logIndex"]),
                    }
                )
                break
            except Exception:
                continue
    decoded.sort(key=lambda x: (x["blockNumber"], x["logIndex"]))
    return decoded


def apply_event(conn: sqlite3.Connection, chain_id: int, contract: str, evt: dict[str, Any]) -> None:
    a = evt["args"]
    common = {
        "chain_id": chain_id,
        "contract": contract,
        "xns_name": a["xnsName"],
        "route_prefix": a["routePrefix"],
        "route": a["route"],
        "block_number": evt["blockNumber"],
        "tx_hash": evt["transactionHash"],
        "log_index": evt["logIndex"],
    }

    name = evt["name"]
    if name == "RouteCreated":
        upsert_route(
            conn,
            **common,
            target=Web3.to_checksum_address(a["target"]),
            route_type=int(a["routeType"]),
            is_active=1 if a["isActive"] else 0,
            is_frozen=1 if a["isFrozen"] else 0,
            deleted=0,
        )
    elif name == "RouteTargetUpdated":
        upsert_route(conn, **common, target=Web3.to_checksum_address(a["newTarget"]), deleted=0)
    elif name == "RouteTypeUpdated":
        upsert_route(conn, **common, route_type=int(a["newRouteType"]), deleted=0)
    elif name == "RouteActiveStatusUpdated":
        upsert_route(conn, **common, is_active=1 if a["isActive"] else 0, deleted=0)
    elif name == "RouteFrozen":
        upsert_route(conn, **common, is_frozen=1, deleted=0)
    elif name == "RouteDeleted":
        upsert_route(conn, **common, deleted=1)


def run_sync(ctx: Context, from_block: int, once: bool, finality: int) -> None:
    w3 = get_web3(ctx.rpc_url)
    abi = load_abi(ctx.abi_path)
    chain_id = int(w3.eth.chain_id)
    contract_addr = Web3.to_checksum_address(ctx.contract)
    contract = w3.eth.contract(address=contract_addr, abi=abi)
    conn = sqlite3.connect(ctx.db_path)
    init_db(conn)

    last_block = get_checkpoint(conn, chain_id, contract_addr, from_block)
    print(f"[sync] chain={chain_id} contract={contract_addr} start_from={last_block + 1}")

    while True:
        head = int(w3.eth.block_number)
        target = max(from_block - 1, head - max(0, finality))
        if last_block >= target:
            if once:
                break
            time.sleep(ctx.poll_interval)
            continue

        start = last_block + 1
        end = min(target, start + ctx.chunk_size - 1)
        logs = w3.eth.get_logs({"fromBlock": start, "toBlock": end, "address": contract_addr})
        events = decode_logs(contract, logs)

        with conn:
            for evt in events:
                apply_event(conn, chain_id, contract_addr, evt)
            set_checkpoint(conn, chain_id, contract_addr, end)
        last_block = end
        print(f"[sync] blocks {start}-{end} logs={len(logs)} events={len(events)}")

    conn.close()


def print_routes(ctx: Context, xns_name: str) -> None:
    w3 = get_web3(ctx.rpc_url)
    chain_id = int(w3.eth.chain_id)
    contract_addr = Web3.to_checksum_address(ctx.contract)
    conn = sqlite3.connect(ctx.db_path)
    init_db(conn)

    rows = conn.execute(
        """
        SELECT route_prefix, route, target, route_type, is_active, is_frozen, deleted,
               updated_block, updated_tx_hash
        FROM routes
        WHERE chain_id = ? AND contract = ? AND xns_name = ?
        ORDER BY route_prefix, route
        """,
        (chain_id, contract_addr, xns_name),
    ).fetchall()
    conn.close()

    if not rows:
        print("No indexed routes found. Run sync first.")
        return

    for r in rows:
        prefix, route, target, route_type, is_active, is_frozen, deleted, blk, tx = r
        marker = "DELETED" if deleted else "ACTIVE"
        print(
            f"{marker:7}  {xns_name}/{(prefix + ':') if prefix else ''}{route}  "
            f"target={target} type={route_type} active={bool(is_active)} frozen={bool(is_frozen)} "
            f"@block={blk} tx={tx[:10]}..."
        )


def export_routes(ctx: Context, xns_name: str | None, out_path: Path) -> None:
    w3 = get_web3(ctx.rpc_url)
    chain_id = int(w3.eth.chain_id)
    contract_addr = Web3.to_checksum_address(ctx.contract)
    conn = sqlite3.connect(ctx.db_path)
    init_db(conn)

    if xns_name:
        rows = conn.execute(
            """
            SELECT xns_name, route_prefix, route, target, route_type, is_active, is_frozen, deleted,
                   updated_block, updated_tx_hash, updated_log_index
            FROM routes
            WHERE chain_id = ? AND contract = ? AND xns_name = ?
            ORDER BY xns_name, route_prefix, route
            """,
            (chain_id, contract_addr, xns_name),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT xns_name, route_prefix, route, target, route_type, is_active, is_frozen, deleted,
                   updated_block, updated_tx_hash, updated_log_index
            FROM routes
            WHERE chain_id = ? AND contract = ?
            ORDER BY xns_name, route_prefix, route
            """,
            (chain_id, contract_addr),
        ).fetchall()

    cp = conn.execute(
        "SELECT last_block FROM checkpoints WHERE chain_id = ? AND contract = ?",
        (chain_id, contract_addr),
    ).fetchone()
    conn.close()

    payload = {
        "chainId": chain_id,
        "contract": contract_addr,
        "lastProcessedBlock": int(cp[0]) if cp else None,
        "routes": [
            {
                "xnsName": r[0],
                "routePrefix": r[1],
                "route": r[2],
                "target": r[3],
                "routeType": r[4],
                "isActive": bool(r[5]) if r[5] is not None else None,
                "isFrozen": bool(r[6]) if r[6] is not None else None,
                "deleted": bool(r[7]),
                "updatedBlock": r[8],
                "updatedTxHash": r[9],
                "updatedLogIndex": r[10],
            }
            for r in rows
        ],
    }
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {len(rows)} rows to {out_path}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compact XNSRoutes SQLite indexer")
    parser.add_argument("--rpc-url", required=True, help="RPC URL (HTTP)")
    parser.add_argument("--contract", required=True, help="XNSRoutes contract address")
    parser.add_argument(
        "--db",
        default="indexer/xns_routes_indexer.sqlite",
        help="SQLite file path (default: indexer/xns_routes_indexer.sqlite)",
    )
    parser.add_argument(
        "--abi",
        default="artifacts/contracts/src/XNSRoutes.sol/XNSRoutes.json",
        help="Hardhat artifact JSON path containing `abi`",
    )

    sub = parser.add_subparsers(dest="cmd", required=True)

    p_sync = sub.add_parser("sync", help="Sync events into SQLite")
    p_sync.add_argument("--from-block", type=int, required=True, help="Contract deployment block")
    p_sync.add_argument("--chunk-size", type=int, default=4000, help="Block chunk size")
    p_sync.add_argument("--poll-interval", type=int, default=5, help="Polling seconds for follow mode")
    p_sync.add_argument("--finality", type=int, default=6, help="Ignore latest N blocks")
    p_sync.add_argument("--once", action="store_true", help="Run one catch-up pass and exit")

    p_list = sub.add_parser("list", help="List indexed routes for one xnsName")
    p_list.add_argument("--xns-name", required=True, help="e.g. bob.xns")

    p_export = sub.add_parser("export", help="Export indexed routes as JSON")
    p_export.add_argument("--out", required=True, help="Output JSON file path")
    p_export.add_argument("--xns-name", help="Optional xnsName filter")

    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    ctx = Context(
        db_path=Path(args.db),
        abi_path=Path(args.abi),
        rpc_url=args.rpc_url,
        contract=args.contract,
        chunk_size=getattr(args, "chunk_size", 4000),
        poll_interval=getattr(args, "poll_interval", 5),
    )
    ctx.db_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        if args.cmd == "sync":
            run_sync(ctx, from_block=args.from_block, once=args.once, finality=args.finality)
        elif args.cmd == "list":
            print_routes(ctx, xns_name=args.xns_name)
        elif args.cmd == "export":
            export_routes(ctx, xns_name=args.xns_name, out_path=Path(args.out))
        else:
            raise RuntimeError(f"Unsupported command: {args.cmd}")
        return 0
    except KeyboardInterrupt:
        print("\nInterrupted.")
        return 130
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

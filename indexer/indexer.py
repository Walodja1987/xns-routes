#!/usr/bin/env python3
"""Simple SQLite indexer for XNSRoutes events (XNSv2).

Route-scoped events include indexed `xnsNameKey`
(`keccak256(abi.encodePacked(label, "@", namespace))`) and `routeKey` as log topics.
`RouteCreated` / `RouteUpdated` also index `targetHash` (`keccak256(target)`); the full
`target` bytes are not in the log — resolve via `getRouteRecord` / eth_call when needed.

Usage examples:
  python indexer/indexer.py sync --rpc-url https://... --contract 0x... --from-block 12345678
  python indexer/indexer.py list --rpc-url https://... --contract 0x... --xns-name xns@action
  python indexer/indexer.py export --rpc-url https://... --contract 0x... --xns-name xns@action --out routes.json
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
    "RouteActiveStatusUpdated",
    "RouteUpdated",
    "RouteFrozen",
    "RouteBookClosed",
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


def xns_name_from_parts(label: str, namespace: str) -> str:
    return f"{label}@{namespace}"


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
            label TEXT NOT NULL,
            namespace TEXT NOT NULL,
            route_label TEXT NOT NULL,
            target TEXT,
            target_hash TEXT,
            route_type INTEGER,
            is_active INTEGER,
            is_frozen INTEGER NOT NULL DEFAULT 0,
            updated_block INTEGER NOT NULL,
            updated_tx_hash TEXT NOT NULL,
            updated_log_index INTEGER NOT NULL,
            PRIMARY KEY (chain_id, contract, label, namespace, route_label)
        );

        CREATE TABLE IF NOT EXISTS route_books (
            chain_id INTEGER NOT NULL,
            contract TEXT NOT NULL,
            label TEXT NOT NULL,
            namespace TEXT NOT NULL,
            is_closed INTEGER NOT NULL DEFAULT 0,
            updated_block INTEGER NOT NULL,
            updated_tx_hash TEXT NOT NULL,
            updated_log_index INTEGER NOT NULL,
            PRIMARY KEY (chain_id, contract, label, namespace)
        );

        CREATE INDEX IF NOT EXISTS idx_routes_lookup
        ON routes(chain_id, contract, label, namespace, route_label);
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
    label: str,
    namespace: str,
    route_label: str,
    *,
    target: str | None = None,
    target_hash: str | None = None,
    route_type: int | None = None,
    is_active: int | None = None,
    is_frozen: int | None = None,
    block_number: int,
    tx_hash: str,
    log_index: int,
) -> None:
    conn.execute(
        """
        INSERT INTO routes(
            chain_id, contract, label, namespace, route_label,
            target, target_hash, route_type, is_active, is_frozen,
            updated_block, updated_tx_hash, updated_log_index
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, 0), ?, ?, ?)
        ON CONFLICT(chain_id, contract, label, namespace, route_label)
        DO UPDATE SET
            target = COALESCE(excluded.target, routes.target),
            target_hash = COALESCE(excluded.target_hash, routes.target_hash),
            route_type = COALESCE(excluded.route_type, routes.route_type),
            is_active = COALESCE(excluded.is_active, routes.is_active),
            is_frozen = COALESCE(excluded.is_frozen, routes.is_frozen),
            updated_block = excluded.updated_block,
            updated_tx_hash = excluded.updated_tx_hash,
            updated_log_index = excluded.updated_log_index
        """,
        (
            chain_id,
            contract,
            label,
            namespace,
            route_label,
            target,
            target_hash,
            route_type,
            is_active,
            is_frozen,
            block_number,
            tx_hash,
            log_index,
        ),
    )


def upsert_route_book_closed(
    conn: sqlite3.Connection,
    chain_id: int,
    contract: str,
    label: str,
    namespace: str,
    *,
    block_number: int,
    tx_hash: str,
    log_index: int,
) -> None:
    conn.execute(
        """
        INSERT INTO route_books(
            chain_id, contract, label, namespace, is_closed,
            updated_block, updated_tx_hash, updated_log_index
        ) VALUES (?, ?, ?, ?, 1, ?, ?, ?)
        ON CONFLICT(chain_id, contract, label, namespace)
        DO UPDATE SET
            is_closed = 1,
            updated_block = excluded.updated_block,
            updated_tx_hash = excluded.updated_tx_hash,
            updated_log_index = excluded.updated_log_index
        """,
        (chain_id, contract, label, namespace, block_number, tx_hash, log_index),
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
    name = evt["name"]
    block_number = evt["blockNumber"]
    tx_hash = evt["transactionHash"]
    log_index = evt["logIndex"]

    if name == "RouteBookClosed":
        upsert_route_book_closed(
            conn,
            chain_id=chain_id,
            contract=contract,
            label=a["label"],
            namespace=a["namespace"],
            block_number=block_number,
            tx_hash=tx_hash,
            log_index=log_index,
        )
        return

    common = {
        "chain_id": chain_id,
        "contract": contract,
        "label": a["label"],
        "namespace": a["namespace"],
        "route_label": a["routeLabel"],
        "block_number": block_number,
        "tx_hash": tx_hash,
        "log_index": log_index,
    }

    if name == "RouteCreated":
        upsert_route(
            conn,
            **common,
            target_hash=Web3.to_hex(a["targetHash"])
            if not isinstance(a["targetHash"], str)
            else a["targetHash"],
            route_type=int(a["routeType"]),
            is_active=1,
            is_frozen=0,
        )
    elif name == "RouteActiveStatusUpdated":
        upsert_route(conn, **common, is_active=1 if a["isActive"] else 0)
    elif name == "RouteUpdated":
        upsert_route(
            conn,
            **common,
            target_hash=Web3.to_hex(a["targetHash"])
            if not isinstance(a["targetHash"], str)
            else a["targetHash"],
            route_type=int(a["routeType"]),
        )
    elif name == "RouteFrozen":
        upsert_route(conn, **common, is_frozen=1)


def parse_xns_name(xns_name: str) -> tuple[str, str]:
    if "@" not in xns_name:
        raise ValueError(f"Expected label@namespace, got: {xns_name}")
    label, namespace = xns_name.split("@", 1)
    if not label or not namespace:
        raise ValueError(f"Invalid XNS name: {xns_name}")
    return label, namespace


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
    label, namespace = parse_xns_name(xns_name)
    conn = sqlite3.connect(ctx.db_path)
    init_db(conn)

    book = conn.execute(
        """
        SELECT is_closed FROM route_books
        WHERE chain_id = ? AND contract = ? AND label = ? AND namespace = ?
        """,
        (chain_id, contract_addr, label, namespace),
    ).fetchone()
    book_closed = bool(book[0]) if book else False

    rows = conn.execute(
        """
        SELECT route_label, target, target_hash, route_type, is_active,
               updated_block, updated_tx_hash
        FROM routes
        WHERE chain_id = ? AND contract = ? AND label = ? AND namespace = ?
        ORDER BY route_label
        """,
        (chain_id, contract_addr, label, namespace),
    ).fetchall()
    conn.close()

    if not rows:
        print("No indexed routes found. Run sync first.")
        return

    print(f"routeBookClosed={book_closed}")
    for r in rows:
        route_label, target, target_hash, route_type, is_active, blk, tx = r
        print(
            f"  {xns_name_from_parts(label, namespace)}/{route_label}  "
            f"target={target} targetHash={target_hash} type={route_type} "
            f"active={bool(is_active)} @block={blk} tx={tx[:10]}..."
        )


def export_routes(ctx: Context, xns_name: str | None, out_path: Path) -> None:
    w3 = get_web3(ctx.rpc_url)
    chain_id = int(w3.eth.chain_id)
    contract_addr = Web3.to_checksum_address(ctx.contract)
    conn = sqlite3.connect(ctx.db_path)
    init_db(conn)

    if xns_name:
        label, namespace = parse_xns_name(xns_name)
        rows = conn.execute(
            """
            SELECT label, namespace, route_label, target, target_hash, route_type, is_active,
                   updated_block, updated_tx_hash, updated_log_index
            FROM routes
            WHERE chain_id = ? AND contract = ? AND label = ? AND namespace = ?
            ORDER BY label, namespace, route_label
            """,
            (chain_id, contract_addr, label, namespace),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT label, namespace, route_label, target, target_hash, route_type, is_active,
                   updated_block, updated_tx_hash, updated_log_index
            FROM routes
            WHERE chain_id = ? AND contract = ?
            ORDER BY label, namespace, route_label
            """,
            (chain_id, contract_addr),
        ).fetchall()

    books = conn.execute(
        """
        SELECT label, namespace, is_closed, updated_block, updated_tx_hash, updated_log_index
        FROM route_books
        WHERE chain_id = ? AND contract = ?
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
        "routeBooks": [
            {
                "xnsName": xns_name_from_parts(b[0], b[1]),
                "label": b[0],
                "namespace": b[1],
                "isRouteBookClosed": bool(b[2]),
                "updatedBlock": b[3],
                "updatedTxHash": b[4],
                "updatedLogIndex": b[5],
            }
            for b in books
        ],
        "routes": [
            {
                "xnsName": xns_name_from_parts(r[0], r[1]),
                "label": r[0],
                "namespace": r[1],
                "routeLabel": r[2],
                "target": r[3],
                "targetHash": r[4],
                "routeType": r[5],
                "isActive": bool(r[6]) if r[6] is not None else None,
                "updatedBlock": r[7],
                "updatedTxHash": r[8],
                "updatedLogIndex": r[9],
            }
            for r in rows
        ],
    }
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {len(rows)} routes to {out_path}")


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
    p_list.add_argument("--xns-name", required=True, help="e.g. xns@action")

    p_export = sub.add_parser("export", help="Export indexed routes as JSON")
    p_export.add_argument("--out", required=True, help="Output JSON file path")
    p_export.add_argument("--xns-name", help="Optional xnsName filter (label@namespace)")

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

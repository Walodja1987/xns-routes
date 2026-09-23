# XNS Routes — route type registry

Community conventions for interpreting `routeType` + `bytes target` returned by
[`XNSRoutes`](../contracts/src/XNSRoutes.sol).

These definitions are **not** enforced on-chain. The contract only requires
`target.length > 0`. Applications and wallets decide which types they support.

## Index

| `routeType` | Name           | Spec                         |
| ----------- | -------------- | ---------------------------- |
| `0`         | EVM address    | [0.md](./0.md)               |
| `1`         | Bitcoin address | [1.md](./1.md)              |
| `2`         | Solana pubkey  | [2.md](./2.md)               |

## Id ranges

| Range              | Purpose                                      |
| ------------------ | -------------------------------------------- |
| `0` – `999_999`    | Public / shared conventions (this registry)  |
| `1_000_000`+       | Application-private / experimental types     |

Do not reuse assigned public ids. New public ids are assigned when a proposal is accepted.

## Propose a new route type

1. Open a GitHub issue with the **New route type** template.
2. Follow the same sections as existing specs (`Summary`, `Encoding`, `Decoding`, `Non-goals`).
3. Explain why an existing type is insufficient.
4. Leave the numeric id blank unless you are requesting a specific unused id in the public range.

After review, a maintainer assigns an id and adds `routeTypes/<id>.md` to this folder.

See also the main [README](../README.md#3-interpret-the-endpoint) and
[Contributing](../README.md#-contributing).

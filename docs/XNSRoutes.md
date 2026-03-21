# Inbound Block Registry

## Overview

The **Inbound Block Registry** is a minimal Ethereum mainnet contract that allows any address to irreversibly declare:

> “Do not send funds to this address anymore.”

It is designed to reduce loss from:

* compromised wallets
* deprecated / migrated addresses
* accidental salary or payment misdirection

The registry enables wallets and applications to prevent unsafe transfers **before a transaction is signed**.

> **Note:** This registry cannot prevent a hack from occurring or recover lost funds. Its primary purpose is to minimize further loss—such as stopping additional transfers (e.g., salary from an employer) to a compromised or deprecated address—by signaling to wallets and applications to block future sends.

---

## Contract Address

* **Ethereum:** [TODO](https://sepolia.etherscan.io/address/TODO)
* **Sepolia (testnet):** [0x6bE791d53b0a9cafC1547Bf70a971b95Df50387f](https://sepolia.etherscan.io/address/0x6bE791d53b0a9cafC1547Bf70a971b95Df50387f)

This is the **only canonical registry**.
All integrations should reference this address on Ethereum mainnet.

---

## Contract Interface

```solidity
interface IInboundBlockRegistry {
    event InboundBlockedForever(address indexed account);
    event GuardianSet(address indexed account, address indexed guardian);

    function blockInboundForever() external;
    function setGuardian(address guardian) external;
    function blockInboundForeverFor(address account) external;

    function isInboundBlocked(address account) external view returns (bool);
    function getGuardianOf(address account) external view returns (address);
}
```

---

## Behavior

### blockInboundForever()

* Can only be called by `msg.sender`
* Irreversibly marks the address as inbound-blocked
* Emits `InboundBlockedForever(account)`
* Cannot be undone

Once blocked, the address is **permanently** marked as unsafe to receive funds.

---

### setGuardian(address guardian)

* Lets an account configure a guardian that can trigger an inbound block on its behalf
* Reverts if the account is already blocked
* Reverts if `guardian` is zero address or equal to `msg.sender`
* Emits `GuardianSet(account, guardian)`

---

### blockInboundForeverFor(address account)

* Callable only by the configured guardian of `account`
* Irreversibly marks `account` as inbound-blocked
* Emits `InboundBlockedForever(account)`
* Reverts with `NotGuardian(account)` if caller is not the configured guardian

---

### isInboundBlocked(address account)

Returns:

* `true` → The address has permanently deactivated inbound transfers
* `false` → No block has been declared

---

## Intended Integration Model

### Wallets / dApps (Soft Enforcement)

Before sending funds:

1. Query `isInboundBlocked(recipient)` via `eth_call` on Ethereum mainnet.
2. If `true`, block the UI flow.

This prevents accidental transfers to compromised addresses.  
For **hard enforcement**, token contracts can also enforce this on-chain by checking the registry during transfer execution.

### Script Examples

Scripts are available in `scripts/examples/`:

- [routeExists.ts][script-routeExists] — check if a route is registered
- [getRouteInfo.ts][script-getRouteInfo] — read target / active / frozen
- [isBaseRoutesFrozen.ts][script-isBaseRoutesFrozen] — base freeze flag for a name
- [setRoute.ts][script-setRoute] — create or update a route (owner only)
- [setRouteActive.ts][script-setRouteActive] — toggle active (owner only)
- [freezeRoute.ts][script-freezeRoute] — freeze one route forever (owner only)
- [freezeRoutes.ts][script-freezeRoutes] — base-freeze the whole name (owner only)

---

### Token Contracts (Optional Hard Enforcement)

Future ERC20/ERC721/ERC1155 contracts may optionally enforce:

```solidity
if (registry.isInboundBlocked(to)) revert();
```

This enables onchain enforcement for tokens that adopt the standard.

---

## Security Model

* This registry does not prevent receiving ETH or tokens that do not integrate the check.
* It enables ecosystem-level prevention via wallet and application enforcement.
* Irreversibility prevents trivial attacker bypass.

Users must understand that calling `blockInboundForever()` cannot be undone.

---

## License

MIT

<!-- Reference-style link definitions -->
[script-routeExists]: ../scripts/examples/routeExists.ts
[script-getRouteInfo]: ../scripts/examples/getRouteInfo.ts
[script-isBaseRoutesFrozen]: ../scripts/examples/isBaseRoutesFrozen.ts
[script-setRoute]: ../scripts/examples/setRoute.ts
[script-setRouteActive]: ../scripts/examples/setRouteActive.ts
[script-freezeRoute]: ../scripts/examples/freezeRoute.ts
[script-freezeRoutes]: ../scripts/examples/freezeRoutes.ts
# Test cases

The following test cases are implemented in [InboundBlockRegistry.test.ts](./InboundBlockRegistry.test.ts) file.

## InboundBlockRegistry

### isInboundBlocked

#### Functionality

- Should return `false` for addresses that have not blocked inbound transfers.
- Should return `true` only for the account that called `blockInboundForever`.

---

### blockInboundForever

#### Functionality

- Should mark `msg.sender` as blocked forever.
- Should allow multiple different accounts to block themselves independently.

#### Events

- Should emit `InboundBlockedForever` event with `msg.sender`.

#### Reverts

- Should revert with `AlreadyBlocked` when calling `blockInboundForever` twice.

---

### setGuardian

#### Functionality

- Should set guardian and persist it in storage.
- Should allow changing guardian.

#### Events

- Should emit `GuardianSet` with the expected account and guardian.

#### Reverts

- Should revert with `InvalidGuardian` for zero-address guardian.
- Should revert with `InvalidGuardian` for self guardian (`guardian == msg.sender`).
- Should revert with `BlockedAccount` when a blocked account tries to set guardian.

---

### getGuardianOf

#### Functionality

- Should return `address(0)` when no guardian is configured.
- Should return the latest configured guardian.

---

### blockInboundForeverFor

#### Functionality

- Should allow the configured guardian to block inbound transfers for the target account.

#### Events

- Should emit `InboundBlockedForever` for the target account.

#### Reverts

- Should revert with `NotGuardian` when caller is not the configured guardian.
- Should revert with `AlreadyBlocked` when attempting to block the same account twice.

---

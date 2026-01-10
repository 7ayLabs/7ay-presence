# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.28-blue)](https://docs.soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://book.getfoundry.sh/)

This repository contains the public specification and reference materials for the 7ay Presence Protocol, originally designed by Zaid Arath.

The protocol is source-available under the Business Source License (BSL 1.1).
Non-commercial use, research, and integration are permitted.
Commercial use requires a separate license from 7ayLabs.

## Current Version

The protocol is currently at **v0.5**, which adds the Ephemeral Data Governance Layer with epoch capabilities and policy commitments.

| Version | Status | Scope |
|---------|--------|-------|
| v0.1 | Complete | Presence finalization (None → Finalized) |
| v0.2 | Complete | Epoch lifecycle (Scheduled → Active → Closed → Finalized) |
| v0.3 | Complete | Declaration layer (declarePresence, Declared state) |
| v0.4 | Complete | Validators, quorum validation, disputes, slashing |
| v0.5 | Complete | Ephemeral Data Governance (EpochCapability, EpochDataPolicy) |

## Usage

### Reading the Specification

The canonical protocol documents are organized by version:

**v0.5 (Current)**
- [specs/v0.5/ephemeral.md](specs/v0.5/ephemeral.md) — Ephemeral Data Governance Layer
- [specs/v0.5/policy-definition.md](specs/v0.5/policy-definition.md) — EpochDataPolicy formal definition
- [specs/v0.5/policy-commitment.md](specs/v0.5/policy-commitment.md) — Policy commitment semantics
- [specs/v0.5/capability-immutability.md](specs/v0.5/capability-immutability.md) — EpochCapability immutability
- [specs/v0.5/actor-scope.md](specs/v0.5/actor-scope.md) — Actor scope rules
- [specs/v0.5/non-addressability.md](specs/v0.5/non-addressability.md) — Non-addressability of ephemeral data
- [specs/v0.5/presence-causality.md](specs/v0.5/presence-causality.md) — Presence-data causality
- [specs/v0.5/compliance-hooks.md](specs/v0.5/compliance-hooks.md) — Compliance and audit hooks

**v0.4**
- [specs/v0.4/presence.md](specs/v0.4/presence.md) — Presence lifecycle with validation, disputes, slashing
- [specs/v0.4/validator.md](specs/v0.4/validator.md) — Validator management and quorum mechanics
- [specs/v0.4/errors.md](specs/v0.4/errors.md) — Error catalog with priority ordering

**Foundation**
- [specs/v0.2/epoch.md](specs/v0.2/epoch.md) — Epoch lifecycle specification
- [specs/model.md](specs/model.md) — Conceptual model and definitions

### Running the Reference Implementation

```bash
# Clone the repository
git clone https://github.com/7aylabs/7ay-pop-ref.git
cd 7ay-pop-ref

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test suite
forge test --match-contract ValidatorRegistryUnitTests
```


## Core Concepts

**Presence** — A protocol-level assertion that an actor participated in a defined context during a specific epoch. In v0.4, presences must be validated by a quorum of validators before finalization.

**Actor** — An identifiable participant (address). An actor declares their own presence and can have at most one finalized presence per epoch.

**Epoch** — A discrete, bounded time window during which presence can be declared and validated. Epochs transition through states: `None → Scheduled → Active → Closed → Finalized`.

**Validator** — An authorized address that votes on presence validation and disputes. Validators are managed by a validator authority and must meet quorum requirements.

**Quorum** — The minimum number of validator votes required for consensus. Calculated as `ceil(activeValidatorCount * quorumThreshold / 100)` with a default threshold of 67%.

**Dispute** — A challenge mechanism allowing any party to contest a presence claim. Disputes are resolved by validator voting, with upheld disputes resulting in slashing.

**Slashing** — The permanent invalidation of a presence due to a successful dispute. Slashed is a terminal state that cannot be reversed.

**EpochCapability** — Defines what an epoch supports: `PresenceOnly` (default), `PresenceWithSignals`, or `PresenceWithEphemeralData`. Immutable once set at epoch creation.

**EpochDataPolicy** — A bytes32 hash representing governance rules for ephemeral data. Required for epochs with `PresenceWithEphemeralData` capability. The hash references an off-chain JSON policy document.

**Ephemeral Data** — Temporary, non-addressable data that exists only during an epoch's Active state. Cannot be persisted, referenced externally, or influence presence state.

## Invariants

### Presence Invariants
1. An actor MUST NOT have more than one finalized presence per epoch
2. Terminal states (Finalized, Slashed) MUST NOT be modified
3. Presence state transitions MUST be deterministic and idempotent
4. Only the actor itself MAY declare its own presence
5. Presence finalization requires validator quorum validation
6. A pending dispute blocks presence finalization

### Validator Invariants
7. Active validator count MUST NOT drop below minimum (3)
8. Removed validators MUST NOT return to Active state
9. Quorum size MUST be achievable with current validators
10. Only validator authority MAY add/remove validators

### Epoch Invariants
11. Epoch states are derived from `block.timestamp` (no storage writes)
12. Declaration and validation only during Active epochs
13. Finalization only after epoch is Closed

### Ephemeral Data Invariants (v0.5)
14. Ephemeral Data MUST NOT exist outside Active epoch
15. Ephemeral Data MUST NOT be readable after epoch termination
16. Actors leaving epoch MUST immediately lose Ephemeral Data access
17. Ephemeral Data MUST NOT influence presence state (orthogonality)
18. Ephemeral Data MUST NOT be persisted or finalized

## Versions

Protocol versions are available in the `specs/` directory:

- `specs/v0.1/` — MVP presence specification
- `specs/v0.2/` — Epoch lifecycle specification
- `specs/v0.3/` — Declaration layer specification
- `specs/v0.4/` — Validators, disputes, slashing
- `specs/v0.5/` — Ephemeral Data Governance (current)

## License

This project is licensed under the **Business Source License 1.1**.

- **Non-commercial use**: Permitted without restriction
- **Research & education**: Permitted
- **Commercial use**: Requires explicit license from 7ayLabs

On **January 8, 2030**, the license automatically converts to **Apache License 2.0**.

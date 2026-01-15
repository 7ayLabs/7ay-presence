# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.28-blue)](https://docs.soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://book.getfoundry.sh/)

This repository contains the public specification and reference materials for the 7ay Presence Protocol, originally designed by Zaid Arath.

The protocol is source-available under the Business Source License (BSL 1.1).
Non-commercial use, research, and integration are permitted.
Commercial use requires a separate license from 7ayLabs.

## Current Version

The protocol is currently at **v0.6.7**, which completes the Semantic Protocol Extension with advanced features for media, routing, automation, and scaling.

| Version | Status | Scope |
|---------|--------|-------|
| v0.1 | Complete | Presence finalization (None → Finalized) |
| v0.2 | Complete | Epoch lifecycle (Scheduled → Active → Closed → Finalized) |
| v0.3 | Complete | Declaration layer (declarePresence, Declared state) |
| v0.4 | Complete | Validators, quorum validation, disputes, slashing |
| v0.5 | Complete | Ephemeral Data Governance (EpochCapability, EpochDataPolicy) |
| v0.6.0-0.3 | Complete | Semantic Protocol Extension (Node Discovery, Messaging, State Sync) |
| v0.6.4 | Complete | Ephemeral Media (images/audio within epochs) |
| v0.6.5 | Complete | Boomerang Routing (return path verification) |
| v0.6.6 | Complete | Autonomous Transactions (pattern-based execution) |
| v0.6.7 | Complete | Octopus Scaling (dynamic node division) |

## Usage

### Reading the Specification

The canonical protocol documents are organized by version:

**v0.6 (Current)**
- [specs/v0.6/node-model.md](specs/v0.6/node-model.md) — Logical node structure and identity
- [specs/v0.6/message-catalog.md](specs/v0.6/message-catalog.md) — Protocol message types (0x01-0x65)
- [specs/v0.6/discovery.md](specs/v0.6/discovery.md) — Node discovery semantics
- [specs/v0.6/state-sync.md](specs/v0.6/state-sync.md) — State synchronization and reconciliation
- [specs/v0.6/ephemeral-media.md](specs/v0.6/ephemeral-media.md) — Ephemeral media (v0.6.4)
- [specs/v0.6/boomerang.md](specs/v0.6/boomerang.md) — Boomerang routing (v0.6.5)
- [specs/v0.6/autonomous.md](specs/v0.6/autonomous.md) — Autonomous transactions (v0.6.6)
- [specs/v0.6/octopus.md](specs/v0.6/octopus.md) — Octopus scaling (v0.6.7)
- [specs/v0.6/invariants.md](specs/v0.6/invariants.md) — Protocol invariants (INV19-42)
- [specs/v0.6/errors.md](specs/v0.6/errors.md) — Error catalog

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

**Node** — A logical abstraction over on-chain actors. Nodes are identified by their Ethereum address and have a role (Participant or Validator) and capabilities (Discovery, Messaging, StateSync).

**Message Envelope** — A signed protocol message containing version, type, sender identity, epoch context, timestamp, nonce (for replay protection), signature, and payload.

**Discovery** — The process by which nodes find and connect with peers within an epoch. Discovery is epoch-scoped and presence-gated.

**State Synchronization** — The process by which nodes maintain consistent views of protocol state. Uses deterministic reconciliation to ensure identical state roots.

**Ephemeral Media** — Images (JPEG, PNG, WebP) and audio (MP3, AAC, Opus) that exist only within an epoch's Active state. Bound by media policy constraints (size, type, TTL).

**Boomerang Routing** — A message routing pattern with return path verification. Messages travel forward to a destination, then return via a divergent path for confirmation.

**Autonomous Transactions** — Pattern-based automatic transactions for frequent users. Requires validated presence, pattern threshold, and validator quorum finalization.

**Octopus Scaling** — Dynamic node division based on throughput. Nodes divide into up to 4 sub-nodes when throughput exceeds 45%, and merge when below 20% for sustained periods.


## License

This project is licensed under the **Business Source License 1.1**.

- **Non-commercial use**: Permitted without restriction
- **Research & education**: Permitted
- **Commercial use**: Requires explicit license from 7ayLabs

On **January 8, 2030**, the license automatically converts to **Apache License 2.0**.

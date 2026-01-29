# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Version](https://img.shields.io/badge/Version-0.6.7-green.svg)](specs/v0.6/)

Canonical specification for the 7ay Proof of Presence (PoP) Protocol.

This repository contains protocol specifications, governance processes, and reference materials. The protocol enables on-chain actor presence certification through epoch-bound, validator-quorum finalization.

## Current Version

**v0.6.7** — Consolidated Protocol Specification

| Layer | Versions | Scope |
|-------|----------|-------|
| Presence | v0.1, v0.3, v0.4 | State machine, declaration, validation, disputes |
| Epoch | v0.2 | Lifecycle, temporal boundaries |
| Governance | v0.5 | Ephemeral data, capabilities, policies |
| Semantic | v0.6.0-0.3 | Node discovery, messaging, state sync |
| Extensions | v0.6.4-0.6.7 | Media, boomerang, autonomous, octopus |

## Specification Index

### Core Protocol

| Document | Scope |
|----------|-------|
| [overview.md](specs/v0.6/overview.md) | Protocol vision and architecture |
| [model.md](specs/v0.6/model.md) | Core protocol model |
| [presence.md](specs/v0.6/presence.md) | Presence state machine and validation |
| [epochs.md](specs/v0.6/epochs.md) | Epoch lifecycle and temporal boundaries |
| [actors.md](specs/v0.6/actors.md) | Actor identity and scope |
| [validators.md](specs/v0.6/validators.md) | Validator management and quorum |
| [disputes.md](specs/v0.6/disputes.md) | Dispute resolution and slashing |

### Ephemeral Layer

| Document | Scope |
|----------|-------|
| [ephemeral.md](specs/v0.6/ephemeral.md) | Ephemeral data governance |
| [capabilities.md](specs/v0.6/capabilities.md) | Epoch capability system |
| [policies.md](specs/v0.6/policies.md) | Data policy constraints |

### Semantic Layer

| Document | Scope |
|----------|-------|
| [node-model.md](specs/v0.6/node-model.md) | Logical node structure |
| [message-catalog.md](specs/v0.6/message-catalog.md) | Protocol message types (0x01-0x65) |
| [discovery.md](specs/v0.6/discovery.md) | Node discovery semantics |
| [state-sync.md](specs/v0.6/state-sync.md) | State synchronization |

### Extensions

| Document | Version | Scope |
|----------|---------|-------|
| [ephemeral-media.md](specs/v0.6/ephemeral-media.md) | v0.6.4 | Media within epochs |
| [boomerang.md](specs/v0.6/boomerang.md) | v0.6.5 | Return path verification |
| [autonomous.md](specs/v0.6/autonomous.md) | v0.6.6 | Pattern-based execution |
| [octopus.md](specs/v0.6/octopus.md) | v0.6.7 | Dynamic node scaling |

### Reference

| Document | Scope |
|----------|-------|
| [state-machine.md](specs/v0.6/state-machine.md) | Unified state transitions |
| [invariants.md](specs/v0.6/invariants.md) | Protocol invariants (INV1-42) |
| [errors.md](specs/v0.6/errors.md) | Error catalog |
| [substrate.md](specs/v0.6/substrate.md) | Substrate implementation notes |

## Protocol Invariants

The protocol defines 42 invariants across six categories:

| Category | Range | Scope |
|----------|-------|-------|
| Presence | INV1-13 | State transitions, validation, disputes |
| Ephemeral | INV14-18 | Temporal boundaries, non-persistence |
| Semantic | INV19-26 | Node identity, discovery, messaging |
| Media | INV27-29 | Epoch binding, policy compliance |
| Boomerang | INV30-33 | Path divergence, verification chain |
| Autonomous | INV34-37 | Intent presence, pattern threshold |
| Octopus | INV38-42 | Activation threshold, sub-node limits |

## Implementation

Reference implementation: [github.com/7ayLabs/7ay-chain](https://github.com/7ayLabs/7ay-chain) (Rust/Substrate)

Solidity reference implementation preserved at tag `v0.6.7-solidity-final` and branch `archive/v0.6.7-solidity-reference`.

## Governance

Protocol modifications follow the [RFC Process](rfcs/README.md).

Changes requiring RFC:
- Invariant modifications (INV1-42+)
- State machine changes
- New epoch capabilities
- New message types
- Breaking changes

## License

**Business Source License 1.1**

- Non-commercial use: Permitted
- Research and education: Permitted
- Commercial use: Requires license from 7ayLabs

Converts to **Apache License 2.0** on January 8, 2030.

See [LICENSE.md](LICENSE.md) for full terms.

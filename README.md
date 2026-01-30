# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Version](https://img.shields.io/badge/Version-0.6.9-green.svg)](specs/README.md)

Canonical specification for the 7ay Proof of Presence (PoP) Protocol.

This repository contains protocol specifications, governance processes, and reference materials. The protocol enables on-chain actor presence certification through epoch-bound, validator-quorum finalization.

## Current Version

**v0.6.9** — Security Hardening Release

| Layer | Versions | Scope |
|-------|----------|-------|
| Presence | v0.1, v0.3, v0.4 | State machine, declaration, validation, disputes |
| Epoch | v0.2 | Lifecycle, temporal boundaries |
| Governance | v0.5, v0.6.9 | Ephemeral data, capabilities, policies, key management |
| Semantic | v0.6.0-0.3, v0.6.9 | Node discovery, messaging, state sync, rate limiting |
| Extensions | v0.6.4-0.6.9 | Media, boomerang, autonomous, octopus |
| Security | v0.6.9 | Chain binding, key destruction, rate limiting |

## Specification Index

### Core Protocol

| Document | Scope |
|----------|-------|
| [presence.md](specs/core/presence.md) | Presence state machine and validation |
| [epochs.md](specs/core/epochs.md) | Epoch lifecycle and temporal boundaries |
| [actors.md](specs/core/actors.md) | Actor identity and scope |
| [validators.md](specs/core/validators.md) | Validator management and quorum |
| [disputes.md](specs/core/disputes.md) | Dispute resolution and slashing |

### Governance Layer

| Document | Scope |
|----------|-------|
| [ephemeral.md](specs/governance/ephemeral.md) | Ephemeral data governance and key management |
| [capabilities.md](specs/governance/capabilities.md) | Epoch capability system |
| [policies.md](specs/governance/policies.md) | Data policy constraints |

### Semantic Layer

| Document | Scope |
|----------|-------|
| [node-model.md](specs/semantic/node-model.md) | Logical node structure |
| [message-catalog.md](specs/semantic/message-catalog.md) | Protocol message types (0x01-0x65) |
| [discovery.md](specs/semantic/discovery.md) | Node discovery semantics |
| [state-sync.md](specs/semantic/state-sync.md) | State synchronization |

### Extensions

| Document | Version | Scope |
|----------|---------|-------|
| [ephemeral-media.md](specs/extensions/ephemeral-media.md) | v0.6.4 | Media within epochs |
| [boomerang.md](specs/extensions/boomerang.md) | v0.6.9 | Return path verification, configurable timeout |
| [autonomous.md](specs/extensions/autonomous.md) | v0.6.6 | Pattern-based execution |
| [octopus.md](specs/extensions/octopus.md) | v0.6.9 | Dynamic node scaling, VRF identity |

### Reference

| Document | Scope |
|----------|-------|
| [overview.md](specs/reference/overview.md) | Protocol vision and architecture |
| [model.md](specs/reference/model.md) | Core protocol model |
| [state-machine.md](specs/reference/state-machine.md) | Unified state transitions |
| [invariants.md](specs/reference/invariants.md) | Protocol invariants (INV1-45) |
| [errors.md](specs/reference/errors.md) | Error catalog |
| [substrate.md](specs/reference/substrate.md) | Substrate implementation notes |

## Protocol Invariants

The protocol defines 45 invariants across eight categories:

| Category | Range | Scope |
|----------|-------|-------|
| Presence | INV1-13 | State transitions, validation, disputes |
| Ephemeral | INV14-18 | Temporal boundaries, non-persistence |
| Semantic | INV19-26 | Node identity, discovery, messaging |
| Media | INV27-29 | Epoch binding, policy compliance |
| Boomerang | INV30-33 | Path divergence, verification chain |
| Autonomous | INV34-37 | Intent presence, pattern threshold |
| Octopus | INV38-42 | Activation threshold, sub-node limits |
| Security | INV43-45 | Chain binding, key destruction, rate limiting |

## Implementation

Reference implementation: [github.com/7ayLabs/7ay-chain](https://github.com/7ayLabs/7ay-chain) (Rust/Substrate)

Solidity reference implementation preserved at tag `v0.6.7-solidity-final` and branch `archive/v0.6.7-solidity-reference`.

## Governance

Protocol modifications follow the [RFC Process](rfcs/README.md).

Changes requiring RFC:
- Invariant modifications (INV1-45+)
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

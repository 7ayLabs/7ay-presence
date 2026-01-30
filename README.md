# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Version](https://img.shields.io/badge/Version-0.7.0-green.svg)](specs/README.md)

Canonical specification for the 7ay Proof of Presence (PoP) Protocol.

This repository contains protocol specifications, governance processes, and reference materials. The protocol enables on-chain actor presence certification through epoch-bound, validator-quorum finalization.

## Current Version

**v0.7.0** — Production Readiness Release

| Layer | Versions | Scope |
|-------|----------|-------|
| Presence | v0.1, v0.3, v0.4 | State machine, declaration, validation, disputes |
| Epoch | v0.2 | Lifecycle, temporal boundaries |
| Governance | v0.5, v0.6.9, v0.7.0 | Ephemeral data, capabilities, policies, key management, trust model |
| Semantic | v0.6.0-0.3, v0.6.9 | Node discovery, messaging, state sync, rate limiting |
| Extensions | v0.6.4-v0.7.0 | Media, boomerang, autonomous, octopus, dynamic scaling |
| Security | v0.6.9, v0.7.0 | Chain binding, key destruction, rate limiting |
| Economics | v0.7.0 | Validator staking, slashing, stake concentration |
| Recovery | v0.7.0 | Validator recovery, protocol upgrades |

## Specification Index

### Core Protocol

| Document | Scope |
|----------|-------|
| [presence.md](specs/core/presence.md) | Presence state machine and validation |
| [epochs.md](specs/core/epochs.md) | Epoch lifecycle and temporal boundaries |
| [actors.md](specs/core/actors.md) | Actor identity and scope |
| [validators.md](specs/core/validators.md) | Validator management and quorum |
| [disputes.md](specs/core/disputes.md) | Dispute resolution and slashing |
| [staking.md](specs/core/staking.md) | Validator staking and economics (v0.7.0) |
| [recovery.md](specs/core/recovery.md) | Validator recovery mechanism (v0.7.0) |

### Governance Layer

| Document | Scope |
|----------|-------|
| [ephemeral.md](specs/governance/ephemeral.md) | Ephemeral data governance, key management, trust model |
| [capabilities.md](specs/governance/capabilities.md) | Epoch capability system |
| [policies.md](specs/governance/policies.md) | Data policy constraints |
| [upgrades.md](specs/governance/upgrades.md) | Protocol upgrade mechanism (v0.7.0) |

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
| [boomerang.md](specs/extensions/boomerang.md) | v0.7.0 | Return path verification, small network fallback |
| [autonomous.md](specs/extensions/autonomous.md) | v0.7.0 | Pattern-based execution, progressive reputation |
| [octopus.md](specs/extensions/octopus.md) | v0.7.0 | Dynamic node scaling, dynamic sub-node limits |

### Reference

| Document | Scope |
|----------|-------|
| [overview.md](specs/reference/overview.md) | Protocol vision and architecture |
| [model.md](specs/reference/model.md) | Core protocol model |
| [state-machine.md](specs/reference/state-machine.md) | Unified state transitions |
| [invariants.md](specs/reference/invariants.md) | Protocol invariants (INV1-63) |
| [errors.md](specs/reference/errors.md) | Error catalog |
| [substrate.md](specs/reference/substrate.md) | Substrate implementation notes |

### RFCs

| RFC | Title | Status |
|-----|-------|--------|
| [RFC-0001](rfcs/0001-validator-security-model.md) | Validator Security Model | Draft |
| [RFC-0002](rfcs/0002-autonomous-hardening.md) | Autonomous Hardening | Draft |
| [RFC-0003](rfcs/0003-boomerang-small-network.md) | Boomerang Small Network | Draft |
| [RFC-0004](rfcs/0004-validator-recovery-governance.md) | Recovery & Governance | Draft |

## Protocol Invariants

The protocol defines 63 invariants across twelve categories:

| Category | Range | Scope |
|----------|-------|-------|
| Presence | INV1-13 | State transitions, validation, disputes |
| Ephemeral | INV14-18, INV44 | Temporal boundaries, key destruction |
| Semantic | INV19-26 | Node identity, discovery, messaging |
| Media | INV27-29 | Epoch binding, policy compliance |
| Boomerang | INV30-33, INV54-56 | Path divergence, small network fallback |
| Autonomous | INV34-37, INV50-53 | Intent presence, progressive reputation |
| Octopus | INV38-42, INV63 | Activation threshold, dynamic sub-node limits |
| Security | INV43-45 | Chain binding, key destruction, rate limiting |
| Validator | INV46-49 | Minimum validators, stake concentration, slashing |
| Recovery | INV57-58 | Recovery quorum, cooldowns |
| Governance | INV59-60 | Upgrade delays, emergency quorum |
| Verification | INV61-62 | Invariant violation logging |

## Implementation

Reference implementation: [github.com/7ayLabs/7ay-chain](https://github.com/7ayLabs/7ay-chain) (Rust/Substrate)

Solidity reference implementation preserved at tag `v0.6.7-solidity-final` and branch `archive/v0.6.7-solidity-reference`.

## Governance

Protocol modifications follow the [RFC Process](rfcs/README.md).

Changes requiring RFC:
- Invariant modifications (INV1-63+)
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

# 7ay Protocol Specifications

> Proof of Presence (PoP) — Canonical Protocol Specifications

**Version:** 0.6.x
**Status:** Active
**License:** BSL 1.1 → Apache 2.0 (2030)

---

## Structure

```
specs/
├── core/           # Fundamental protocol primitives
├── governance/     # Data governance layer
├── semantic/       # Network and messaging layer
├── extensions/     # Protocol extensions
├── reference/      # Cross-cutting documentation
├── diagrams/       # Visual documentation
├── schemas/        # JSON schemas for validation
└── test-cases/     # Specification test scenarios
```

---

## Core

Fundamental protocol primitives. Required for any implementation.

| Spec | Description |
|------|-------------|
| [presence.md](core/presence.md) | Presence state machine (None → Declared → Validated → Finalized) |
| [epochs.md](core/epochs.md) | Epoch lifecycle (Scheduled → Active → Closed → Finalized) |
| [validators.md](core/validators.md) | Validator registry and quorum mechanics |
| [disputes.md](core/disputes.md) | Dispute initiation, voting, resolution |
| [actors.md](core/actors.md) | Actor identity and epoch scoping |

---

## Governance

Ephemeral data governance layer. Defines constraints for off-chain data.

| Spec | Description |
|------|-------------|
| [ephemeral.md](governance/ephemeral.md) | Ephemeral data lifecycle and destruction |
| [capabilities.md](governance/capabilities.md) | EpochCapability enumeration |
| [policies.md](governance/policies.md) | EpochDataPolicy commitment and verification |

---

## Semantic

Network layer for node discovery and messaging.

| Spec | Description |
|------|-------------|
| [node-model.md](semantic/node-model.md) | Node identity, roles, capabilities |
| [discovery.md](semantic/discovery.md) | Peer discovery protocol |
| [message-catalog.md](semantic/message-catalog.md) | Message types and envelope format |
| [state-sync.md](semantic/state-sync.md) | State synchronization and reconciliation |

---

## Extensions

Optional protocol extensions. Implementations MAY support these.

| Spec | Description | Invariants |
|------|-------------|------------|
| [ephemeral-media.md](extensions/ephemeral-media.md) | Images/audio within epochs | INV27-29 |
| [boomerang.md](extensions/boomerang.md) | Return path verification | INV30-33 |
| [autonomous.md](extensions/autonomous.md) | Pattern-based execution | INV34-37 |
| [octopus.md](extensions/octopus.md) | Dynamic node division | INV38-42 |

---

## Reference

Cross-cutting documentation and implementation guides.

| Spec | Description |
|------|-------------|
| [overview.md](reference/overview.md) | Protocol vision and principles |
| [model.md](reference/model.md) | Conceptual system model |
| [state-machine.md](reference/state-machine.md) | Consolidated state transitions |
| [invariants.md](reference/invariants.md) | Protocol invariants (INV1-42) |
| [errors.md](reference/errors.md) | Error catalog and priority |
| [substrate.md](reference/substrate.md) | Rust/Substrate implementation notes |

---

## Assets

| Folder | Contents |
|--------|----------|
| [diagrams/](diagrams/) | Flow diagrams (Mermaid/ASCII) |
| [schemas/](schemas/) | JSON Schema definitions |
| [test-cases/](test-cases/) | Specification test scenarios |

---

## Reading Order

**For implementers:**
1. reference/overview.md
2. core/* (presence → epochs → validators → disputes)
3. governance/* (if supporting ephemeral data)
4. semantic/* (if supporting networking)
5. extensions/* (optional features)

**For auditors:**
1. reference/invariants.md
2. reference/state-machine.md
3. reference/errors.md

---

## Versioning

| Tag | Description |
|-----|-------------|
| `v0.6.7` | Legacy reference (archived) |
| `v0.6.8-specs` | Specs-only repository |
| `v0.6.9` | Security hardening release |

History preserved in git. Use `git log --follow <file>` for file history.

---

## Contributing

Protocol changes require RFC process. See [/rfcs/README.md](/rfcs/README.md).

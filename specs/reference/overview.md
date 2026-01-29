# 7ay Presence Protocol — Overview

**Version:** v0.6
**Status:** Active
**Scope:** Protocol specification

---

## What is Proof of Presence?

Cryptographic verification that an actor was physically present within defined spatiotemporal bounds.

The 7ay Presence Protocol provides a deterministic and verifiable mechanism to assert that an actor participated in a given context during a specific temporal window (epoch).

---

## Core Components

| Component | Description |
|-----------|-------------|
| **Actor** | Uniquely identifiable participant in the protocol |
| **Epoch** | Bounded temporal context (location + time window) |
| **Presence** | Proof of participation within an epoch |
| **Validator** | Verifies presence claims |
| **Quorum** | 67% validator agreement for validation |

---

## Protocol Layers

| Layer | Version | Scope |
|-------|---------|-------|
| Core | v0.1 | Actor, Epoch, Presence primitives |
| Declaration | v0.3 | Self-declaration of presence |
| Validation | v0.4 | Quorum-based verification, disputes, slashing |
| Ephemeral | v0.5 | Temporary data governance |
| Semantic | v0.6 | Node discovery, messaging, state sync |

---

## State Machines

### Presence States

```
None → Declared → Validated → Finalized
                      ↓
                   Slashed
```

### Epoch States

```
None → Scheduled → Active → Closed → Finalized
```

### Epoch Capabilities

```
PresenceOnly < PresenceWithSignals < PresenceWithEphemeralData
```

---

## Invariants

42 formal invariants (INV1-42) guarantee protocol correctness.

| Range | Scope |
|-------|-------|
| INV1-6 | Presence state |
| INV7-10 | Validator management |
| INV11-13 | Epoch lifecycle |
| INV14-18 | Ephemeral data |
| INV19-26 | Semantic layer (node, messaging) |
| INV27-29 | Ephemeral media |
| INV30-33 | Boomerang routing |
| INV34-37 | Autonomous transactions |
| INV38-42 | Octopus scaling |

See [invariants.md](invariants.md) for complete definitions.

---

## Implementation

| Target | Repository |
|--------|------------|
| Solidity (archived) | `archive/v0.6.7-solidity-reference` branch |
| Substrate (active) | github.com/7ayLabs/7ay-chain |

---

## References

- [model.md](model.md) — Conceptual system model
- [presence.md](presence.md) — Presence specification
- [epochs.md](epochs.md) — Epoch lifecycle
- [validators.md](validators.md) — Validator mechanics
- [state-machine.md](state-machine.md) — State transitions

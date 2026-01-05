# 7ay Proof of Presence (PoP)
## Conceptual System Model
**Derived from:** Presence Specification v0.1  
**Status:** Draft (MVP)  
**Scope:** Conceptual / Protocol Model (MVP Profile)

---

## 1. Overview

This document defines the conceptual model of the Proof of Presence (PoP) protocol.

It translates the formal rules defined in `presence.md` into:
- conceptual entities
- relationships
- responsibilities
- state behavior

This model is implementation-agnostic and precedes any smart contract or node logic.

This model reflects the MVP implementation on the 7aychain. Advanced protocol roles such as validators, slashing, and quorum are explicitly out of scope for this version.

---

## 2. Core Concepts

---

## 2.1 Actor

### Conceptual Definition

An **Actor** is any uniquely identifiable entity that participates in the protocol.

The protocol does not impose identity semantics beyond uniqueness.

---

### Capabilities

An actor:
- MAY declare presence
- MAY assume additional roles in future protocol versions

---

### Constraints

- An actor MUST NOT have more than one active presence per epoch.
- An actor MAY be associated with multiple epochs over time.
- Actor behavior is subject to protocol invariants.

---

## 2.2 Epoch

### Conceptual Definition

An **Epoch** is a discrete, ordered temporal window during which
presence declarations and validations occur.

Epochs provide temporal determinism to the protocol.

In the MVP, an Epoch is represented as an event-specific temporal window and is not a global on-chain epoch system.

---

### Properties

An epoch:
- Has a unique, monotonically increasing identifier
- Has a defined start and end boundary
- Has a lifecycle state

---

### Constraints

- Epochs MUST NOT overlap.
- Epochs MUST be finalized sequentially.
- A finalized epoch MUST NOT be reopened.

---

## 2.3 Presence

### Conceptual Definition

A **Presence** is a protocol-level assertion that an actor
participated in a given context during a specific epoch,
and that this assertion followed protocol rules.

---

### Properties

A presence is defined by:
- An associated actor
- An associated epoch
- A lifecycle state

Presence metadata is opaque to the protocol
and does not affect protocol determinism.

---

### Presence States

A presence MAY exist in one of the following states:

- None
- Declared
- Validated
- Finalized
- Expired
- Slashed

Note: In the MVP on-chain implementation, only the `Finalized` state is persisted on-chain; all other states are conceptual or off-chain.

---

## 2.4 Future Protocol Extensions (Non-MVP)

Validator roles, quorum-based validation, and slashing mechanisms are part of future versions of the protocol and are intentionally excluded from the MVP to preserve determinism and simplicity.

---

## 3. Presence Lifecycle Model

A presence MUST follow the lifecycle defined below.
No undefined transitions are allowed.

Lifecycle transitions are conceptual; the MVP contract enforces only final presence acceptance or rejection.

---

---

### State Descriptions

#### None
No presence exists for the actor in the given epoch.

#### Declared
The actor has declared presence in an active epoch.

#### Validated
The declared presence has satisfied validation rules.

#### Finalized
The presence is immutable and permanently recorded.

#### Expired
The presence was not validated within the epoch window.

#### Slashed
The presence was invalidated due to protocol violations.

---

## 4. Conceptual Relationships

---

### Entity Relationships

- An Actor MAY have zero or more Presences over time.
- A Presence MUST reference exactly one Actor.
- A Presence MUST reference exactly one Epoch.
- A Validator is an Actor with validation authority.
- The Protocol enforces all rules and invariants.

---

## 5. Conceptual Invariants

The following invariants apply at the conceptual model level
and MUST hold for all implementations:

### MVP Invariants (Enforced)

1. An actor MUST NOT have more than one finalized presence per epoch.
2. A finalized presence MUST NOT be reverted.
3. Presence state transitions MUST be deterministic and idempotent.
4. Only the actor itself MAY finalize its own presence.
5. Finalizing presence for one actor MUST NOT affect any other actor.
6. Finalizing presence in one epoch MUST NOT affect any other epoch.
7. A finalized presence MUST NOT transition back to None.

### Future Invariants (Non-MVP)

8. A slashed presence MUST NOT become valid again.
9. An expired presence MUST NOT be validated retroactively.
10. Epochs MUST be finalized in strict order.  

---

## 6. Determinism Model

Given the same:
- actor set
- epoch state
- presence declarations
- validation inputs

all compliant implementations MUST reach identical results.

No external or non-deterministic data sources are permitted.

---

## 7. Role of This Model

This conceptual model:
- Precedes smart contract design
- Guides interface definition
- Informs invariant testing
- Serves as reference for node and SDK implementations

This model is designed to evolve alongside the 7ay blockchain as Presence expands from MVP to a full protocol.
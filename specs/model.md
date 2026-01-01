# 7ay Proof of Presence (PoP)
## Conceptual System Model
**Derived from:** Presence Specification v0.1  
**Status:** Draft  
**Scope:** Conceptual / Protocol Model

---

## 1. Overview

This document defines the conceptual model of the Proof of Presence (PoP) protocol.

It translates the formal rules defined in `presence.md` into:
- conceptual entities
- relationships
- responsibilities
- state behavior

This model is implementation-agnostic and precedes any smart contract or node logic.

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
- MAY act as a validator
- MAY be penalized by the protocol

An actor MAY assume multiple roles simultaneously.

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

---

### Constraints

- Presence is non-transferable.
- A finalized presence is immutable.
- A slashed presence is irreversible.

---

## 2.4 Validator

### Conceptual Definition

A **Validator** is an actor authorized by the protocol
to validate presence declarations.

Validation authority is protocol-defined and deterministic.

---

### Capabilities

A validator:
- MAY validate declared presences
- MAY be penalized for invalid behavior

---

### Constraints

- A penalized validator MUST NOT participate in validation.
- Validation outcomes MUST be deterministic.
- Validation MAY require quorum as defined by the protocol.

---

## 2.5 Slashing

### Conceptual Definition

**Slashing** is the protocol-level mechanism
for penalizing invalid or malicious behavior.

Slashing is enforced exclusively by the protocol.

---

### Causes

Slashing MAY occur due to:
- Multiple presence declarations in the same epoch
- Invalid validation behavior
- Violation of protocol invariants

---

### Properties

- Slashing is irreversible.
- Slashing outcomes are deterministic.
- Slashing rules are protocol-defined.

---

## 3. Presence Lifecycle Model

A presence MUST follow the lifecycle defined below.
No undefined transitions are allowed.

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

1. An actor MUST NOT have more than one active presence per epoch.
2. Presence state transitions MUST follow the defined lifecycle.
3. A finalized presence MUST NOT transition to another state.
4. A slashed presence MUST NOT become valid.
5. An expired presence MUST NOT be validated retroactively.
6. Epochs MUST be finalized in strict order.
7. All protocol decisions MUST be deterministic.

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

Any implementation deviating from this model is non-compliant.
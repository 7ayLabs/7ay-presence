# 7ay Proof of Presence (PoP)
## Protocol Specification — Presence
**Version:** v0.1  
**Status:** Draft (MVP)  
**Scope:** Protocol-level (canonical, MVP profile)

---

## 1. Purpose

The Proof of Presence (PoP) protocol defines a deterministic and verifiable
mechanism to assert that an actor was present within a given context and time window,
according to protocol rules.

This specification defines the canonical rules for presence declaration,
validation, finalization, and invalidation.

Implementations MUST follow this specification to be considered compliant.

Validator roles, slashing, quorum, and multi-party validation are explicitly out of scope for the MVP.

---

## 2. Definitions

### 2.1 Presence

**Presence** is a protocol-level assertion that an actor participated
in a defined context during a specific temporal window (epoch),
and that this assertion was validated according to protocol rules.

Presence is:
- Time-bound
- Context-bound
- Non-transferable
- Deterministic

---

### 2.2 Actor

An **Actor** is an identifiable participant in the protocol.

An actor:
- MAY declare presence
- MUST be uniquely identifiable
- MUST NOT have more than one finalized presence per epoch

The protocol does not assume actor identity semantics beyond uniqueness.

---

### 2.3 Epoch

An **Epoch** is a discrete, monotonically increasing time window
during which presence can be declared and validated.

Epochs:
- Have a defined start and end
- Are finalized sequentially
- Cannot overlap

In the MVP, an Epoch represents an event-scoped temporal window and does not imply network-level consensus epochs.

---

## 3. Actors and Roles (MVP)

The protocol defines the following logical actors:

### 3.1 Participant

A participant is an actor who declares presence.

### 3.2 Protocol

The protocol itself acts as an impartial arbitrator enforcing all invariants.

---

## 4. Presence Lifecycle

A presence claim MUST follow this lifecycle:
No transitions outside this flow are valid.

Lifecycle stages are conceptual; only final acceptance or rejection is enforced on-chain in the MVP.

---

## 5. Presence States

Note: In the MVP on-chain implementation, only the Finalized state is persisted on-chain.
All other states are conceptual or off-chain and are included for protocol completeness.

### 5.1 None

No presence exists for the actor in the given epoch.

---

### 5.2 Declared

A presence has been declared by an actor.

Conditions:
- The actor has no other active presence in the same epoch.
- The epoch is active.

---

### 5.3 Validated

A declared presence has been validated by the protocol-defined mechanism.

Conditions:
- Validation rules are satisfied.
- Validator quorum (if applicable) is met.

---

### 5.4 Finalized

A validated presence becomes final and immutable.

Conditions:
- The epoch is finalized.
- No pending disputes exist.

---

### 5.5 Expired

A presence that was declared but not validated within the epoch window.

Expired presences are non-final and non-recoverable.

---

### 5.6 Slashed

A presence invalidated due to protocol violations.

Slashed presences:
- Are irreversible
- Imply penalties defined elsewhere in the protocol

---

## 6. Events

The protocol MUST emit canonical events for each lifecycle transition.

At minimum, the following event is defined:

- PresenceFinalized

Other lifecycle events are reserved for future protocol versions.

---

## 7. Invariants

The following invariants MUST NEVER be violated:

### MVP Invariants

1. An actor MUST NOT have more than one active presence per epoch.  
2. A finalized presence MUST NOT be reverted.  
6. Presence state transitions MUST be deterministic.

### Future Invariants (Non-MVP)

3. A slashed presence MUST NOT become valid again.  
4. An expired presence MUST NOT be validated retroactively.  
5. Epochs MUST be finalized in order.

Any implementation violating these invariants is non-compliant.

---

## 8. Determinism

Given the same inputs and state,
all compliant implementations MUST reach the same outcome.

No off-protocol data or non-deterministic sources are allowed.

---

## 9. Extensibility

This specification defines the minimal viable presence protocol.

Future extensions:
- MUST NOT break existing invariants
- MUST be versioned
- MUST be explicitly specified

---

## 10. Compliance

An implementation is considered compliant if and only if:
- All MVP Invariants hold
- All required MVP events are emitted correctly
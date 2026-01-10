# 7ay Proof of Presence (PoP)
## Protocol Specification — Presence–Data Causality
**Version:** v0.5.6
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines the **causal relationship** between presence state
and ephemeral data in the 7ay Presence Protocol.

The core principle is **orthogonality**: presence and ephemeral data
MUST NOT influence each other's state transitions.

This document defines:
- The orthogonality requirement
- Prohibited causal relationships
- State independence guarantees
- Rationale for separation

This document does NOT:
- Define presence logic (see presence.md)
- Define data transport
- Change existing protocol behavior

---

## 2. Orthogonality Principle

### 2.1 Core Statement

**Presence state and ephemeral data are causally independent.**

```
presence_state(actor, epoch) ⊥ ephemeral_data(actor, epoch)
```

Neither can influence the other's state.

### 2.2 Presence-First Design

The 7ay Protocol is **presence-first**:
- Presence is the primary consensus primitive
- Ephemeral data is secondary and optional
- Presence can exist without ephemeral data
- Ephemeral data cannot exist without presence

### 2.3 Dependency Direction

```
┌─────────────────────────────────────────────────────────────┐
│                     DEPENDENCY DIRECTION                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    PRESENCE ────────────────────► EPHEMERAL DATA            │
│    (primary)     depends on       (secondary)               │
│                                                             │
│    Ephemeral data REQUIRES presence.                        │
│    Presence does NOT require ephemeral data.                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Prohibited Relationships

### 3.1 Data Cannot Affect Presence

Ephemeral data MUST NOT influence:

| Presence Aspect | Ephemeral Data Influence |
|-----------------|-------------------------|
| Declaration | PROHIBITED |
| Validation | PROHIBITED |
| Disputes | PROHIBITED |
| Slashing | PROHIBITED |
| Finalization | PROHIBITED |

### 3.2 Specific Prohibitions

**P1: No Data-Based Declaration**
```
❌ PROHIBITED:
  IF received_data(actor) THEN declare_presence(actor)
```

**P2: No Data-Based Validation**
```
❌ PROHIBITED:
  IF data_quality(actor) > threshold THEN validate_presence(actor)
```

**P3: No Data-Based Disputes**
```
❌ PROHIBITED:
  IF bad_data(actor) THEN raise_dispute(actor)
```

**P4: No Data-Based Slashing**
```
❌ PROHIBITED:
  IF spam_data(actor) THEN slash_presence(actor)
```

**P5: No Data-Based Finalization**
```
❌ PROHIBITED:
  IF data_complete(actor) THEN finalize_presence(actor)
```

### 3.3 Presence Cannot Affect Data Content

Presence state MUST NOT influence data content:

```
❌ PROHIBITED:
  data.content = f(presence.state)
  data.priority = presence.validation_count
```

Presence only affects data **access**, not data **content**.

---

## 4. Permitted Relationships

### 4.1 Presence Gates Data Access

Presence state MAY gate ephemeral data access:

```
✓ PERMITTED:
  IF presence.state >= Declared THEN allow_data_access()
```

This is access control, not causal influence.

### 4.2 Data Requires Active Epoch

Ephemeral data MAY require epoch state:

```
✓ PERMITTED:
  IF epoch.state == Active THEN allow_data()
```

This is a precondition, not causal influence.

### 4.3 Co-Temporal Existence

Presence and data MAY exist simultaneously:

```
✓ PERMITTED:
  actor.has_presence(epoch) AND actor.has_data(epoch)
```

Simultaneity is not causation.

---

## 5. State Machine Independence

### 5.1 Presence State Machine

The presence state machine operates independently:

```
None → Declared → Validated → Finalized
           ↓           ↓
        Slashed ←──────┘
```

No transition depends on ephemeral data.

### 5.2 Data Lifecycle

The ephemeral data lifecycle operates independently:

```
∅ → Created → Propagated → Destroyed
```

No transition depends on presence state (except access gating).

### 5.3 Independence Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  PRESENCE STATE MACHINE          DATA LIFECYCLE             │
│  ════════════════════           ═══════════════             │
│                                                             │
│  None ──► Declared              ∅ ──► Created               │
│              │                          │                   │
│              ▼                          ▼                   │
│         Validated               Propagated                  │
│              │                          │                   │
│              ▼                          ▼                   │
│         Finalized               Destroyed                   │
│                                                             │
│         ◄─── NO ARROWS BETWEEN COLUMNS ───►                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Invariants

### 6.1 INV17: State Independence (from v0.5)

```
FOR ALL presence state transitions T:
  T.preconditions ∩ ephemeral_data_state = ∅
```

### 6.2 INV-CAUSE1: No Data-Driven Validation

```
FOR ALL validation events V:
  NOT EXISTS data d: V.cause = d
```

### 6.3 INV-CAUSE2: No Data-Driven Slashing

```
FOR ALL slashing events S:
  NOT EXISTS data d: S.cause = d
```

### 6.4 INV-CAUSE3: Presence Precedence

```
FOR ALL actors a, epochs e:
  has_data(a, e) IMPLIES has_presence(a, e)
```

---

## 7. Rationale

### 7.1 Consensus Integrity

Separating presence from data protects consensus:
- Presence consensus cannot be manipulated via data
- Data content cannot game validation outcomes
- Slashing is based on presence behavior, not data content

### 7.2 v0.4 Invariant Preservation

All v0.4 invariants remain intact:
- INV1-13 are unaffected by ephemeral data
- Presence logic is unchanged
- Validator logic is unchanged

### 7.3 Simplicity

Orthogonality simplifies:
- Presence logic: No data considerations
- Data logic: No presence state machine entanglement
- Testing: Independent verification of each subsystem

---

## 8. Security Analysis

### 8.1 Attack Prevention

Orthogonality prevents:
- **Data spam attacks**: Spamming data cannot trigger slashing of others
- **Data bribery**: Good data cannot buy validation
- **Data extortion**: Threatening bad data cannot affect presence

### 8.2 Isolation Guarantee

If ephemeral data subsystem is compromised:
- Presence consensus remains secure
- Validation continues normally
- Slashing operates correctly

---

## 9. Non-Goals

This specification explicitly does NOT define:
- Presence state machine details (see presence.md)
- Data content validation
- Quality of service metrics
- Reputation systems

---

## 10. Backwards Compatibility

This specification is additive:
- Presence logic unchanged from v0.4
- Data layer is new and separate
- No migration required

---

## 11. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- validator.md v0.4 — Validation rules

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.5.6 | Initial presence-data causality specification |

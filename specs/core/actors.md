# 7ay Proof of Presence (PoP)
## Protocol Specification — Actor Scope Rules
**Version:** v0.5.4
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines **actor scope rules** for ephemeral data access
in the 7ay Presence Protocol.

Actor scope determines which actors may access ephemeral data within an
epoch and under what conditions.

This document defines:
- Actor eligibility requirements
- Scope boundaries
- Access acquisition and revocation
- Exit invalidation semantics

This document does NOT:
- Define access control implementation
- Define authentication mechanisms
- Change existing presence logic

---

## 2. Actor Eligibility

### 2.1 Base Requirement

An actor MAY access ephemeral data IFF:

```
actor.hasPresence(epochId) == true
  AND
epoch.capability == PresenceWithEphemeralData
  AND
epoch.state == Active
```

All three conditions MUST hold simultaneously.

> **Note:** The pseudocode uses conceptual notation. `hasPresence()` represents
> checking that an actor has a presence state other than None for the epoch.
> `PresenceWithEphemeralData` is an `EpochCapability` value defined in
> ephemeral.md v0.5 (forward reference).

### 2.2 Presence Requirement

Ephemeral data access requires **declared presence**:

| Presence State | Ephemeral Data Access |
|----------------|----------------------|
| None | NO |
| Declared | YES (if epoch supports) |
| Validated | YES (if epoch supports) |
| Finalized | NO |
| Slashed | NO |

> **Note:** Access denial in Finalized state follows from the base requirement
> in Section 2.1: ephemeral data access requires `epoch.state == Active`. The
> presence state itself does not determine the epoch state; access is revoked
> when the epoch transitions out of Active.

### 2.3 Actor Types

All actor types with valid presence are eligible:
- Participants
- Validators
- Observers (if presence declared)

Actor type does not affect eligibility, only presence state.

---

## 3. Scope Boundaries

### 3.1 Epoch-Local Scope

Ephemeral data access is **strictly epoch-local**:

```
scope(actor, epochId) ⊆ epoch(epochId)
```

An actor's scope cannot extend beyond their declared epoch.

### 3.2 No Cross-Epoch Access

Actors MUST NOT access ephemeral data from:
- Other epochs (even if active)
- Parent epochs (in hierarchical models)
- Child epochs (in hierarchical models)
- Adjacent epochs (sequential)

### 3.3 Scope Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         EPOCH A                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 EPHEMERAL DATA SCOPE                │    │
│  │                                                     │    │
│  │   Actor 1 ✓    Actor 2 ✓    Actor 3 ✓             │    │
│  │   (declared)   (validated)  (declared)             │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Actor 4 ✗ (no presence in this epoch)                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                         EPOCH B                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 EPHEMERAL DATA SCOPE                │    │
│  │                                                     │    │
│  │   Actor 4 ✓    Actor 5 ✓                           │    │
│  │   (declared)   (validated)                         │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Actor 1 ✗ (no presence in this epoch)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Access Lifecycle

### 4.1 Access Acquisition

Access is acquired when:
1. Actor declares presence in an epoch
2. Epoch has `PresenceWithEphemeralData` capability
3. Epoch state is `Active`

```
acquire_access(actor, epoch):
  REQUIRE: epoch.capability == PresenceWithEphemeralData
  REQUIRE: epoch.state == Active
  REQUIRE: presence(actor, epoch.id).state IN {Declared, Validated}
  GRANT: ephemeral_data_access(actor, epoch.id)
```

### 4.2 Access Maintenance

Access is maintained as long as:
- Epoch remains Active
- Actor presence is not revoked (slashed)
- Actor remains in the epoch context

### 4.3 Access Revocation

Access is revoked when ANY of:
- Epoch transitions from Active (to Closed)
- Actor is slashed
- Actor exits the epoch context

---

## 5. Exit Invalidation

### 5.1 Rule: Exit Invalidation (see INV-SCOPE4)

**Actors leaving an epoch MUST immediately lose ephemeral data access.**

```
ON actor_exit(actor, epoch):
  REVOKE: ephemeral_data_access(actor, epoch.id)
  INVALIDATE: all ephemeral data held by actor for epoch
```

### 5.2 Exit Conditions

An actor "exits" an epoch when:
- Actor is slashed (`presence.state = Slashed`)
- Epoch becomes non-Active
- Actor explicitly withdraws (if supported)

### 5.3 Immediate Effect

Exit invalidation is **immediate**:
- No grace period
- No data retention window
- No delayed cleanup

---

## 6. Invariants

### 6.1 INV-SCOPE1: Presence Required

```
FOR ALL actors a, epochs e:
  has_ephemeral_access(a, e) IMPLIES has_presence(a, e)
```

### 6.2 INV-SCOPE2: Epoch Locality

```
FOR ALL actors a, epochs e1, e2 where e1 ≠ e2:
  ephemeral_data(a, e1) ∩ ephemeral_data(a, e2) = ∅
```

### 6.3 INV-SCOPE3: Active Epoch Required

```
FOR ALL actors a, epochs e:
  has_ephemeral_access(a, e) IMPLIES e.state == Active
```

### 6.4 INV-SCOPE4: Exit Invalidation

```
FOR ALL actors a, epochs e:
  exit(a, e) IMPLIES NOT has_ephemeral_access(a, e) afterward
```

---

## 7. Security Considerations

### 7.1 Scope Isolation

Strict epoch-local scope prevents:
- Data leakage between epochs
- Cross-epoch correlation attacks
- Scope escalation

### 7.2 Presence Binding

Presence requirement ensures:
- Only committed actors access data
- Accountability through presence record
- Audit trail via presence state

### 7.3 Immediate Revocation

Immediate exit invalidation prevents:
- Data exfiltration after exit
- Lingering access after slashing
- Stale access windows

---

## 8. Non-Goals

This specification explicitly does NOT define:
- Access control implementation
- Authentication mechanisms
- Key distribution
- Encryption requirements

---

## 9. Backwards Compatibility

This specification is additive:
- Does not change presence logic
- Does not change epoch logic
- Defines rules for new capability only

---

## 10. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- model.md — Actor definition

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.5.4 | Initial actor scope rules specification |

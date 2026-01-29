# 7ay Proof of Presence (PoP)
## Protocol Specification — EpochCapability Immutability
**Version:** v0.5.3
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines the **immutability guarantees** for EpochCapability
in the 7ay Presence Protocol.

Capability immutability ensures that an epoch's feature set cannot change
after creation, preventing capability escalation attacks and ensuring
predictable governance.

This document defines:
- The immutability requirement for capabilities
- Rationale for immutability
- Invariants that enforce immutability
- Security implications

This document does NOT:
- Define capability values (see EpochCapability enum)
- Implement storage mechanisms
- Change existing protocol behavior

---

## 2. EpochCapability Overview

### 2.1 Capability Values

An epoch's capability declares its feature support:

| Value | Name | Features |
|-------|------|----------|
| 0 | PresenceOnly | Basic presence tracking |
| 1 | PresenceWithSignals | Presence + signal emission |
| 2 | PresenceWithEphemeralData | Full ephemeral data support |

### 2.2 Declaration Point

Capability is declared exactly once: **at epoch creation**.

---

## 3. Immutability Requirement

### 3.1 Core Invariant

**INV-CAP1: Capability Immutability**

```
FOR ALL epochs e:
  e.capability at creation == e.capability at any future time
```

Once set, capability MUST NOT change through any mechanism.

### 3.2 No Upgrade Path

Capabilities cannot be upgraded:
- PresenceOnly cannot become PresenceWithSignals
- PresenceWithSignals cannot become PresenceWithEphemeralData
- No "enable ephemeral data" operation exists

### 3.3 No Downgrade Path

Capabilities cannot be downgraded:
- PresenceWithEphemeralData cannot become PresenceOnly
- No "disable ephemeral data" operation exists
- Capability reduction is architecturally impossible

---

## 4. Rationale

### 4.1 Predictability

Actors joining an epoch can rely on its declared capability:
- Feature availability is known at join time
- No mid-epoch capability changes disrupt expectations
- Client implementations can make static assumptions

### 4.2 Security

Capability immutability prevents:
- **Escalation attacks**: Adding capabilities to harvest data
- **Downgrade attacks**: Removing protections mid-epoch
- **Governance bypass**: Changing rules after actors commit

### 4.3 Simplicity

Immutability simplifies:
- State machine logic (no capability transitions)
- Client implementations (no capability change handlers)
- Audit and compliance (deterministic capability)

---

## 5. State Transition Independence

### 5.1 Capability vs. Epoch State

Capability is orthogonal to epoch state:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  Epoch State:  Scheduled → Active → Closed → Finalized     │
│                                                             │
│  Capability:   [CONSTANT THROUGHOUT]                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 No State-Dependent Capability

Capability does not vary by epoch state:
- Same capability in Scheduled as in Active
- Same capability in Closed as in Finalized
- Queries return the same value regardless of when asked

---

## 6. Enforcement

### 6.1 Storage Design

Capability is stored in write-once storage:
- Set during epoch creation
- No setter function exists after creation
- Storage slot is effectively final

### 6.2 Interface Design

No interface exposes capability modification:
- No `setCapability()` function
- No `upgradeCapability()` function
- Only read operations exist after creation

### 6.3 Invariant Testing

Implementations MUST test immutability:
- Create epoch with capability X
- Transition through all states
- Assert capability remains X

---

## 7. Invariants

### 7.1 INV-CAP1: Immutability

```
FOR ALL epochs e, times t1 < t2:
  capability(e, t1) == capability(e, t2)
```

### 7.2 INV-CAP2: Valid Range

```
FOR ALL epochs e:
  capability(e) IN {0, 1, 2}
```

### 7.3 INV-CAP3: Creation-Time Binding

```
FOR ALL epochs e:
  capability(e) is set IFF e.exists == true
```

---

## 8. Security Considerations

### 8.1 Capability Escalation

Without immutability, an attacker could:
1. Create epoch with PresenceOnly
2. Wait for actors to join
3. Upgrade to PresenceWithEphemeralData
4. Harvest ephemeral data unexpectedly

Immutability prevents this attack vector.

### 8.2 Governance Manipulation

Without immutability, governance could:
1. Promise one capability set
2. Change capabilities after commitment
3. Invalidate actor expectations

Immutability ensures governance honesty.

---

## 9. Non-Goals

This specification explicitly does NOT define:
- How capability is stored (implementation detail)
- Capability migration between epochs
- Dynamic capability systems
- Capability inheritance

---

## 10. Backwards Compatibility

This specification is additive:
- Existing epochs have implicit PresenceOnly capability
- Immutability is already implicit (no change mechanism exists)
- This spec formalizes existing guarantees

---

## 11. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- model.md — Core entities

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.5.3 | Initial capability immutability specification |

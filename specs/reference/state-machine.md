# 7ay Proof of Presence (PoP)
## Protocol Specification — State Machines
**Version:** v0.6
**Status:** Active
**Scope:** Protocol-level (canonical)

---

## 1. Purpose

This specification consolidates all state machines in the 7ay Presence Protocol.

---

## 2. Presence States

```
                                    ┌─────────────────────────────────┐
                                    │                                 │
                                    │  slashPresence()                │
                                    │  (dispute upheld)               │
                                    ▼                                 │
None ──declarePresence()──► Declared ──validatePresence()──► Validated ──► Slashed
                                │           (quorum)              │
                                │                                 │
                                └─────────────────────────────────┘
                                                                  │
                                                                  │ finalizePresence()
                                                                  │ (epoch Closed)
                                                                  ▼
                                                              Finalized
```

### 2.1 Presence Transitions

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| None | Declared | `declarePresence` | Epoch Active, actor == caller |
| Declared | Validated | `validatePresence` | Quorum reached (67% validators) |
| Declared | Slashed | `resolveDispute` | Dispute upheld |
| Validated | Finalized | `finalizePresence` | Epoch Closed, no pending dispute |
| Validated | Slashed | `resolveDispute` | Dispute upheld |

### 2.2 Terminal States

- **Finalized**: Immutable success
- **Slashed**: Immutable failure (protocol violation)

---

## 3. Epoch States

```
None → Scheduled → Active → Closed → Finalized
```

### 3.1 Epoch Transitions

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| None | Scheduled | `createEpoch` | Valid params, epochId != 0 |
| Scheduled | Active | Time passes | `now >= startTime` |
| Active | Closed | Time passes | `now >= endTime` |
| Closed | Finalized | `finalizeEpoch` | All presences resolved |

### 3.2 Epoch Capabilities

```
PresenceOnly (0) < PresenceWithSignals (1) < PresenceWithEphemeralData (2)
```

| Capability | Presence | Signals | Ephemeral Data | Policy Required |
|------------|----------|---------|----------------|-----------------|
| PresenceOnly | Yes | No | No | No |
| PresenceWithSignals | Yes | Yes | No | No |
| PresenceWithEphemeralData | Yes | Yes | Yes | Yes |

---

## 4. Validator States

```
None → Active → Removed
```

### 4.1 Validator Transitions

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| None | Active | `addValidator` | Called by authority |
| Active | Removed | `removeValidator` | Called by authority |

### 4.2 Validator Constraints

- Minimum 3 active validators
- Removed validators cannot return to Active
- Quorum = ceil(activeCount * 2 / 3)

---

## 5. Dispute States

```
None → Pending → Upheld/Rejected
```

### 5.1 Dispute Transitions

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| None | Pending | `initiateDispute` | Valid target, within window |
| Pending | Upheld | `resolveDispute` | Majority vote to uphold |
| Pending | Rejected | `resolveDispute` | Majority vote to reject |

---

## 6. Node States (Semantic Layer)

```
Offline → Joining → Online → Leaving → Offline
```

### 6.1 Node Transitions

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| Offline | Joining | `join_epoch` | Valid presence |
| Joining | Online | Sync complete | State reconciled |
| Online | Leaving | `leave_epoch` | Voluntary |
| Online | Offline | Timeout | No heartbeat 30s |

---

## 7. Boomerang States (v0.6.5)

```
None → Pending → Complete/Timeout
```

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| None | Pending | BOOMERANG_SEND | Valid forward path |
| Pending | Complete | BOOMERANG_COMPLETE | Return path verified |
| Pending | Timeout | Time passes | 60s window exceeded |

---

## 8. Octopus States (v0.6.7)

```
Normal → Dividing → Divided → Merging → Normal
```

| From | To | Trigger | Condition |
|------|-----|---------|-----------|
| Normal | Dividing | OCTOPUS_THRESHOLD | throughput > 45% |
| Dividing | Divided | OCTOPUS_DIVIDE | Sub-nodes created |
| Divided | Merging | Sustained low load | throughput < 20% for 5min |
| Merging | Normal | OCTOPUS_MERGE | Sub-nodes reconciled |

---

## 9. Invariant Summary

All state machines must maintain:
- **Determinism**: Same inputs → same outputs
- **Monotonicity**: No backward transitions (except defined cycles)
- **Terminal finality**: Terminal states are irreversible
- **Isolation**: State changes don't affect unrelated entities

---

## 10. References

- presence.md — Presence state details
- epochs.md — Epoch lifecycle details
- validators.md — Validator mechanics
- disputes.md — Dispute mechanism
- node-model.md — Node lifecycle
- boomerang.md — Return path routing
- octopus.md — Dynamic scaling

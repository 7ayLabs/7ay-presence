# 7ay Proof of Presence (PoP)
## Protocol Specification — Compliance & Audit Hooks
**Version:** v0.5.7
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines **compliance and audit hooks** for the
7ay Presence Protocol's ephemeral data governance layer.

Hooks are integration points that allow compliance systems to observe
protocol behavior without accessing or storing ephemeral data content.

This document defines:
- Compliance observation points
- Audit metadata (not content)
- Integration boundaries
- Privacy-preserving audit patterns

This document does NOT:
- Define specific compliance requirements
- Implement logging systems
- Store ephemeral data content
- Change existing protocol behavior

---

## 2. Design Philosophy

### 2.1 Content-Free Auditing

Compliance hooks observe **metadata only**:
- Events (what happened)
- Timestamps (when it happened)
- Actors (who was involved)
- Policy references (which rules applied)

Hooks MUST NOT expose:
- Ephemeral data content
- Message payloads
- User-generated data

### 2.2 Observable Without Storing

Hooks enable observation without persistence:
- Real-time monitoring
- Statistical aggregation
- Anomaly detection

Post-epoch, only aggregate statistics remain.

---

## 3. Audit Hooks

### 3.1 Epoch Lifecycle Hooks

**H1: Epoch Created with Capability**
```
HOOK epoch_created_with_capability(
  epoch_id: uint256,
  capability: EpochCapability,
  policy_hash: bytes32,
  timestamp: uint256
)
```

**H2: Epoch State Transition**
```
HOOK epoch_state_changed(
  epoch_id: uint256,
  from_state: EpochState,
  to_state: EpochState,
  timestamp: uint256
)
```

### 3.2 Actor Hooks

**H3: Actor Gained Data Access**
```
HOOK actor_data_access_granted(
  actor: address,
  epoch_id: uint256,
  timestamp: uint256
)
```

**H4: Actor Lost Data Access**
```
HOOK actor_data_access_revoked(
  actor: address,
  epoch_id: uint256,
  reason: AccessRevocationReason,
  timestamp: uint256
)
```

### 3.3 Data Lifecycle Hooks (Metadata Only)

**H5: Data Activity Observed**
```
HOOK data_activity(
  epoch_id: uint256,
  activity_type: ActivityType,  // CREATED, PROPAGATED, DESTROYED
  actor_count: uint256,         // Not specific actors
  timestamp: uint256
)
```

**H6: Data Destruction Confirmed**
```
HOOK data_destruction_confirmed(
  epoch_id: uint256,
  destruction_method: DestructionMethod,
  timestamp: uint256
)
```

---

## 4. Audit Metadata

### 4.1 Permitted Metadata

Compliance systems MAY record:

| Metadata | Example | Permitted |
|----------|---------|-----------|
| Event type | "epoch_created" | Yes |
| Timestamp | 1704067200 | Yes |
| Epoch ID | 123 | Yes |
| Capability | PresenceWithEphemeralData | Yes |
| Policy hash | 0xabc...def | Yes |
| Actor count | 42 | Yes |
| Duration | 3600 seconds | Yes |

### 4.2 Prohibited Metadata

Compliance systems MUST NOT record:

| Metadata | Example | Permitted |
|----------|---------|-----------|
| Data content | "Hello world" | NO |
| Data hashes | keccak256(content) | NO |
| Actor identities | 0x1234...5678 | NO* |
| Message counts per actor | Alice: 5 msgs | NO |
| Data size | 1024 bytes | NO* |

*May be permitted with explicit consent or legal requirement.

---

## 5. Compliance Patterns

### 5.1 Statistical Monitoring

Compliance can observe aggregate statistics:

```
PATTERN statistical_monitoring:
  OBSERVE: epoch_count, actor_count, duration_average
  AGGREGATE: per_day, per_capability_type
  RETAIN: aggregate_only
```

### 5.2 Anomaly Detection

Compliance can detect anomalies without content:

```
PATTERN anomaly_detection:
  MONITOR: activity_rate, epoch_duration, actor_churn
  ALERT_IF: deviation > threshold
  LOG: alert_metadata_only
```

### 5.3 Policy Verification

Compliance can verify policy application:

```
PATTERN policy_verification:
  FOR EACH epoch with PresenceWithEphemeralData:
    ASSERT: policy_hash != bytes32(0)
    ASSERT: policy_document_exists(policy_hash)
    LOG: verification_result
```

---

## 6. Integration Boundaries

### 6.1 On-Chain Integration

On-chain hooks are limited to events:
- `EpochCreatedV2` (existing)
- `EpochStateChanged` (existing)
- No new on-chain hooks required

### 6.2 Off-Chain Integration

Off-chain hooks are observational:
- Subscribe to on-chain events
- Observe metadata through defined hooks
- No direct data access

### 6.3 Boundary Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPLIANCE BOUNDARY                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ON-CHAIN                    OFF-CHAIN                      │
│  ════════                    ════════                       │
│                                                             │
│  Events ──────────────────► Event Listeners                 │
│  (EpochCreatedV2)            (Metadata only)                │
│                                                             │
│  State ───────────────────► State Observers                 │
│  (epochCapability)           (Query results)                │
│                                                             │
│         ◄─── BOUNDARY: NO DATA CONTENT ───►                │
│                                                             │
│                              Ephemeral Data                 │
│                              (Not observable)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Privacy Considerations

### 7.1 Differential Privacy

Hook outputs SHOULD support differential privacy:
- Aggregate counts with noise
- Bucketed timestamps
- Anonymized actor counts

### 7.2 Minimization

Hooks MUST collect minimum necessary data:
- No speculative collection
- Purpose-limited retention
- Automatic expiration

### 7.3 Consent Model

Where actor-level data is needed:
- Explicit opt-in required
- Clear data use disclosure
- Right to withdraw

---

## 8. Audit Trail

### 8.1 What IS Auditable

Post-epoch, the following remain auditable:
- Epoch existed (on-chain)
- Epoch capability (on-chain)
- Policy hash (on-chain)
- Aggregate statistics (if recorded)

### 8.2 What IS NOT Auditable

Post-epoch, the following are NOT auditable:
- Ephemeral data content
- Specific messages
- Actor-level data activity
- Data propagation paths

This is by design.

---

## 9. Regulatory Alignment

### 9.1 GDPR Considerations

The ephemeral data model supports GDPR:
- Data minimization (only necessary data)
- Purpose limitation (epoch-scoped)
- Storage limitation (automatic destruction)
- Right to erasure (architecturally enforced)

### 9.2 Audit Requirements

For jurisdictions requiring audit trails:
- On-chain events provide immutable record
- Metadata hooks provide operational visibility
- Content is not required for compliance

---

## 10. Non-Goals

This specification explicitly does NOT define:
- Specific regulatory compliance
- Logging implementation
- Retention policies
- Legal interpretations

---

## 11. Backwards Compatibility

This specification is additive:
- No changes to existing events
- Optional hook integration
- No migration required

---

## 12. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- Events section — Existing event definitions

---

## 13. Changelog

| Version | Changes |
|---------|---------|
| v0.5.7 | Initial compliance hooks specification |

# 7ay Proof of Presence (PoP)
## Protocol Specification — Epoch Data Policies
**Version:** v0.6 (consolidated from v0.5.1, v0.5.2, v0.5.7)
**Status:** Active
**Scope:** Protocol-level (canonical)
**Depends on:** epochs.md, presence.md, ephemeral.md

---

## 1. Purpose

This specification defines **EpochDataPolicy** for the 7ay Presence Protocol.

An EpochDataPolicy declares governance rules for ephemeral, off-chain data
that may temporarily exist within an epoch's active window.

---

## 2. Definition

### 2.1 EpochDataPolicy

An **EpochDataPolicy** is a declarative governance document that specifies
constraints for ephemeral data within a specific epoch.

Properties:
- Bound to exactly one epoch
- Declared at epoch creation time
- Represented on-chain as a cryptographic hash
- Full content stored off-chain
- Immutable once committed

### 2.2 On-Chain Representation

Only a hash is stored on-chain:

```rust
let data_policy_hash: [u8; 32] = keccak256(policy_document);
```

Semantics:
- `bytes32(0)` — No policy committed (null policy)
- Non-zero — Policy committed, verifiable off-chain

### 2.3 Off-Chain Policy Structure

```json
{
  "version": "1.0.0",
  "epochId": 42,
  "constraints": {
    "maxPayloadSize": 1024,
    "maxTTL": 3600,
    "propagationScope": "global",
    "encryptionRequired": true
  },
  "actorRules": {
    "allowedTypes": ["validator", "observer"],
    "requiresPresence": true
  }
}
```

---

## 3. Commitment Semantics

### 3.1 Commitment Timing

Commitment MUST occur at epoch creation time:
- The policy hash is provided as a creation parameter
- No mechanism exists to commit a policy after creation
- Epochs without policies at creation cannot gain them later

### 3.2 Capability-Based Requirements

| Capability | Commitment | Requirement |
|------------|------------|-------------|
| PresenceOnly | Optional | MAY be bytes32(0) |
| PresenceWithSignals | Optional | MAY be bytes32(0) |
| PresenceWithEphemeralData | Required | MUST NOT be bytes32(0) |

### 3.3 Commitment Finality

Once committed, a policy hash MUST NOT change:
- No update mechanism exists
- No revocation mechanism exists
- The commitment persists through all epoch states

---

## 4. Verification

### 4.1 Hash Verification

Off-chain systems MUST verify policy integrity:

```
ASSERT: keccak256(policyDocument) == epochDataPolicyHash
```

### 4.2 Epoch Binding Verification

Policy documents MUST declare the correct epoch:

```
ASSERT: policyDocument.epochId == targetEpochId
```

---

## 5. Compliance Hooks

For auditing and compliance, the protocol supports content-free, aggregate-only hooks:

| Hook | Trigger | Data |
|------|---------|------|
| H1: DataCreated | Ephemeral data created | epochId, timestamp, createdCount, totalSizeDelta |
| H2: DataAccessed | Ephemeral data read | epochId, timestamp, accessCount |
| H3: DataExpired | TTL expiration | epochId, timestamp, expiredCount |
| H4: DataDestroyed | Epoch termination | epochId, timestamp, destroyedCount |
| H5: PolicyViolation | Constraint breach | epochId, constraintId, timestamp |
| H6: AuditCheckpoint | Periodic audit | epochId, timestamp, metrics |

Hooks MUST NOT expose ephemeral data content or any stable per-actor or per-data identifiers (including actorId, dataId); payloads MUST be aggregate-only at the epoch scope.

---

## 6. Invariants

### 6.1 Policy Invariants

- **INV-POL1**: Policy hash immutable after commitment
- **INV-POL2**: PresenceWithEphemeralData requires non-zero hash
- **INV-POL3**: Policy applies only during Active epoch state
- **INV-POL4**: Null policy (bytes32(0)) means no governance

### 6.2 Compliance Hook Invariants

- **INV-HOOK1**: Hooks MUST NOT contain ephemeral data content
- **INV-HOOK2**: Hooks MUST preserve actor privacy
- **INV-HOOK3**: Hook timing MUST be within epoch bounds

---

## 7. References

- ephemeral.md — Ephemeral data governance
- capabilities.md — EpochCapability immutability

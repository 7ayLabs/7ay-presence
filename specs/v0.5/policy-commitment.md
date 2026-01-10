# 7ay Proof of Presence (PoP)
## Protocol Specification — Policy Commitment Semantics
**Version:** v0.5.2
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines the **commitment semantics** for EpochDataPolicy
in the 7ay Presence Protocol.

Commitment is the act of irrevocably binding a policy hash to an epoch.

This document defines:
- What policy commitment means
- When commitment occurs
- The semantics of null vs. non-null commitments
- Commitment finality guarantees

This document does NOT:
- Implement storage or interfaces
- Define policy content or structure
- Change existing protocol behavior

---

## 2. Commitment Definition

### 2.1 What is Commitment?

**Policy commitment** is the on-chain declaration that a specific policy
governs an epoch's ephemeral data rules.

Commitment is:
- **Atomic** — Occurs in a single transaction
- **Final** — Cannot be modified after creation
- **Verifiable** — Hash can be verified against off-chain document

### 2.2 Commitment Timing

Commitment MUST occur at epoch creation time:
- The policy hash is provided as a creation parameter
- No mechanism exists to commit a policy after creation
- Epochs without policies at creation cannot gain them later

---

## 3. Hash Semantics

### 3.1 Null Commitment (bytes32(0))

A null policy hash indicates **no policy committed**:

```
dataPolicyHash == bytes32(0)  →  No governance rules declared
```

Implications:
- Epoch does not support ephemeral data governance
- Off-chain systems MUST NOT expect a policy document
- This is the default state for legacy epochs

### 3.2 Non-Null Commitment

A non-null policy hash indicates **policy committed**:

```
dataPolicyHash != bytes32(0)  →  Governance rules declared
```

Implications:
- A corresponding off-chain document MUST exist
- Off-chain systems MUST verify the hash
- The policy governs ephemeral data within the epoch

### 3.3 Semantic Table

| Hash Value | Meaning | Ephemeral Data | Policy Required |
|------------|---------|----------------|-----------------|
| bytes32(0) | No commitment | Not governed | No |
| Non-zero | Committed | Governed | Yes |

---

## 4. Commitment Requirements

### 4.1 Capability-Based Requirements

Policy commitment requirements depend on epoch capability:

| Capability | Commitment | Requirement |
|------------|------------|-------------|
| PresenceOnly | Optional | MAY be bytes32(0) |
| PresenceWithSignals | Optional | MAY be bytes32(0) |
| PresenceWithEphemeralData | Required | MUST NOT be bytes32(0) |

### 4.2 Validation Rule

```
IF capability == PresenceWithEphemeralData
THEN dataPolicyHash MUST NOT equal bytes32(0)
```

Violation results in transaction rejection.

---

## 5. Commitment Finality

### 5.1 Immutability

Once committed, a policy hash MUST NOT change:
- No update mechanism exists
- No revocation mechanism exists
- The commitment persists through all epoch states

### 5.2 State Independence

Commitment finality is independent of epoch state:
- Commitment occurs before epoch becomes Active
- Commitment remains valid through Closed and Finalized
- Commitment is queryable at any time

### 5.3 Non-Retroactivity

Commitment cannot be applied retroactively:
- Existing epochs without commitment cannot gain one
- New epochs inherit no commitment from prior epochs
- Each epoch requires explicit commitment

---

## 6. Verification Model

### 6.1 On-Chain Verification

On-chain systems verify:
- Commitment existence (hash != 0 for required capabilities)
- Commitment immutability (hash never changes)

### 6.2 Off-Chain Verification

Off-chain systems verify:
- Hash integrity: `keccak256(document) == committedHash`
- Document validity: Schema and content correctness
- Epoch binding: Document references correct epoch

---

## 7. Commitment Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│                    COMMITMENT LIFECYCLE                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Creation ──────► Committed ──────────────────────────────► │
│      │                │                                     │
│      │                │   (immutable through all states)    │
│      │                │                                     │
│      ▼                ▼                                     │
│  Transaction      Scheduled → Active → Closed → Finalized   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Non-Goals

This specification explicitly does NOT define:
- Policy document structure (see v0.5.1)
- Commitment storage implementation
- Policy enforcement mechanisms
- Off-chain document distribution

---

## 9. Backwards Compatibility

This specification is additive:
- Existing epochs have implicit null commitment
- No migration required
- Null commitment is valid for legacy capabilities

---

## 10. References

- v0.5.1 policy-definition.md — Policy structure
- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.5.2 | Initial policy commitment semantics |

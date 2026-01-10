# 7ay Proof of Presence (PoP)
## Protocol Specification — EpochDataPolicy Definition
**Version:** v0.5.1
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification formally defines the **EpochDataPolicy** concept for the
7ay Presence Protocol.

An EpochDataPolicy declares governance rules for ephemeral, off-chain data
that may temporarily exist within an epoch's active window.

This document defines:
- What an EpochDataPolicy IS
- Its structural representation
- Its relationship to epochs

This document does NOT:
- Implement storage or transport
- Define contract interfaces
- Change existing protocol behavior

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

### 2.2 Policy Content (Off-Chain)

The full policy document is a JSON structure containing governance parameters:

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

Field types:
- `version`: string (semantic version)
- `epochId`: number (uint256)
- `maxPayloadSize`: number (bytes)
- `maxTTL`: number (seconds)
- `propagationScope`: string ("global" | "local" | "restricted")
- `encryptionRequired`: boolean
- `allowedTypes`: array of strings
- `requiresPresence`: boolean

### 2.3 Policy Hash (On-Chain)

On-chain representation is limited to a 32-byte hash:

```
bytes32 dataPolicyHash = keccak256(policyJSON)
```

Semantics:
- `bytes32(0)` — No policy committed (null policy)
- Non-zero — Policy committed, verifiable off-chain

---

## 3. Structural Properties

### 3.1 Binding

An EpochDataPolicy is cryptographically bound to its epoch:
- The policy document MUST include the epoch identifier
- The hash MUST be committed at epoch creation
- No policy can be retroactively assigned

### 3.2 Immutability

Once committed, an EpochDataPolicy MUST NOT change:
- The on-chain hash is immutable
- The off-chain document is content-addressed
- Modifications require a new epoch

### 3.3 Optionality

An EpochDataPolicy is not required for all epochs:
- Basic presence tracking requires no policy
- Signal emission requires no policy
- Ephemeral data support REQUIRES a policy

---

## 4. Relationship to Epochs

### 4.1 Epoch Capability

The presence of an EpochDataPolicy is determined by epoch capability.

> **Note:** The `EpochCapability` enum (`PresenceOnly`, `PresenceWithSignals`,
> `PresenceWithEphemeralData`) is formally defined in `ephemeral.md v0.5`.

| Capability | Policy Required |
|------------|-----------------|
| PresenceOnly | No |
| PresenceWithSignals | No |
| PresenceWithEphemeralData | Yes |

### 4.2 Lifecycle Alignment

The policy's effective period aligns with the epoch lifecycle:
- Policy becomes effective when epoch transitions to the Active state
- Policy ceases to apply when the epoch leaves the Active state
- Policy remains queryable after epoch termination (for audit)

---

## 5. Verification

### 5.1 Hash Verification

Off-chain systems MUST verify policy integrity:

```
ASSERT: keccak256(policyDocument) == epochDataPolicyHash
```

### 5.2 Schema Validation

Policy documents MUST conform to the declared schema version.

### 5.3 Epoch Binding Verification

Policy documents MUST declare the correct epoch:

```
ASSERT: policyDocument.epochId == targetEpochId
```

---

## 6. Non-Goals

This specification explicitly does NOT define:
- How policies are transmitted
- How policies are stored off-chain
- Enforcement mechanisms
- Default policy values
- Policy migration between epochs

---

## 7. Backwards Compatibility

This specification is additive and does not change existing behavior:
- Existing epochs continue to function without policies
- No contract modifications required
- No migration necessary

---

## 8. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- model.md — Core entities

---

## 9. Changelog

| Version | Changes |
|---------|---------|
| v0.5.1 | Initial EpochDataPolicy definition |

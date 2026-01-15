# Errors Spec v0.6
> v0.6 semantic layer errors (primarily off-chain)

## Overview

v0.6 introduces a semantic layer for node discovery and messaging. Most v0.6
errors are **off-chain validation errors** that occur during message processing,
discovery, and state synchronization.

On-chain errors from v0.5 and earlier remain unchanged.

---

## Error Categories

| Category | Layer | Scope |
|----------|-------|-------|
| On-chain (v0.4-0.5) | Smart contracts | Preserved |
| Node Model | Off-chain | New in v0.6 |
| Discovery | Off-chain | New in v0.6 |
| Messaging | Off-chain | New in v0.6 |
| State Sync | Off-chain | New in v0.6 |
| Media | Off-chain | New in v0.6.4 |
| Boomerang | Off-chain | New in v0.6.5 |
| Autonomous | Off-chain | New in v0.6.6 |
| Octopus | Off-chain | New in v0.6.7 |

---

## Off-Chain Error Codes

### Error Code Format

Off-chain errors use a structured format:
```typescript
interface ProtocolError {
  code: string;
  category: ErrorCategory;
  message: string;
  context?: Record<string, unknown>;
}

enum ErrorCategory {
  NODE = "NODE",
  DISCOVERY = "DISCOVERY",
  MESSAGE = "MESSAGE",
  SYNC = "SYNC",
  MEDIA = "MEDIA",
  BOOMERANG = "BOOMERANG",
  AUTONOMOUS = "AUTONOMOUS",
  OCTOPUS = "OCTOPUS"
}
```

---

## Media Errors (v0.6.4)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| MEDIA_001 | InvalidMediaType | Unsupported media format | INV28 |
| MEDIA_002 | MediaTooLarge | Content exceeds size limit | INV28 |
| MEDIA_003 | MediaExpired | TTL has expired | INV29 |
| MEDIA_004 | MediaPolicyViolation | Violates epoch media policy | INV28 |
| MEDIA_005 | MediaEpochMismatch | Epoch lacks PresenceWithEphemeralData | INV27 |
| MEDIA_006 | MediaNotFound | Media not available | - |

---

## Boomerang Errors (v0.6.5)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| BOOM_001 | PathNotDivergent | Return path same as forward path | INV30 |
| BOOM_002 | BoomerangTimeout | Cycle timeout exceeded | INV31 |
| BOOM_003 | InvalidHopSignature | Hop signature verification failed | INV33 |
| BOOM_004 | BoomerangAborted | Cycle aborted mid-flight | INV32 |
| BOOM_005 | InvalidReturnPath | Return path contains invalid nodes | INV30 |

---

## Autonomous Errors (v0.6.6)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| AUTO_001 | InsufficientPresence | Actor not Validated/Finalized | INV34 |
| AUTO_002 | PatternThresholdNotMet | Pattern frequency below threshold | INV35 |
| AUTO_003 | QuorumNotReached | Insufficient validator approvals | INV36 |
| AUTO_004 | IntentExpired | Intent has passed expiration time | INV37 |
| AUTO_005 | MaxExecutionsReached | Execution count at maximum | - |
| AUTO_006 | IntentNotFound | Referenced intent does not exist | - |

---

## Octopus Errors (v0.6.7)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| OCTO_001 | BelowActivationThreshold | Division requested below 45% | INV38 |
| OCTO_002 | SubNodeLimitReached | Already at 4 sub-nodes | INV40 |
| OCTO_003 | InvalidSubNodeId | Sub-node ID doesn't match derivation | INV39 |
| OCTO_004 | HysteresisNotMet | Merge requested before sustained low | INV42 |
| OCTO_005 | StateReconciliationFailed | Missing sub-node states for merge | INV41 |
| OCTO_006 | InvalidDivisionState | Cannot divide/merge in current state | - |

### OCTO_001: BelowActivationThreshold
```typescript
{
  code: "OCTO_001",
  category: "OCTOPUS",
  message: "Division requested when throughput below 45%",
  context: {
    parentNode: "0x1234...",
    currentThroughput: 0.35,
    requiredThroughput: 0.45
  }
}
```

### OCTO_002: SubNodeLimitReached
```typescript
{
  code: "OCTO_002",
  category: "OCTOPUS",
  message: "Cannot create more sub-nodes, limit of 4 reached",
  context: {
    parentNode: "0x1234...",
    currentSubNodes: 4
  }
}
```

---

## Recovery Actions

| Error Category | Recovery |
|----------------|----------|
| NODE_* | Re-derive from on-chain |
| DISC_* | Retry with different peer |
| MSG_* | Reject message, log |
| SYNC_* | Force complete sync |
| MEDIA_* | Reject media, notify sender |
| BOOM_* | Retry with new boomerangId |
| AUTO_* | Revoke intent, re-declare if needed |
| OCTO_* | Wait for threshold, retry division/merge |

---

## Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Added off-chain error catalog for semantic layer |
| v0.6.4 | Added MEDIA_001-006 for ephemeral media |
| v0.6.5 | Added BOOM_001-005 for boomerang routing |
| v0.6.6 | Added AUTO_001-006 for autonomous transactions |
| v0.6.7 | Added OCTO_001-006 for octopus scaling |

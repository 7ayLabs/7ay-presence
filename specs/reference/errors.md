# 7ay Proof of Presence (PoP)
## Protocol Specification — Errors
**Version:** v0.6.9 (consolidated from v0.4-v0.6.9)
**Status:** Active

> Includes on-chain errors (v0.4-v0.5) and off-chain semantic layer errors (v0.6-v0.6.9)

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
| Discovery | Off-chain | New in v0.6, Updated v0.6.9 |
| Messaging | Off-chain | New in v0.6, Updated v0.6.9 |
| State Sync | Off-chain | New in v0.6 |
| Media | Off-chain | New in v0.6.4 |
| Boomerang | Off-chain | New in v0.6.5 |
| Autonomous | Off-chain | New in v0.6.6 |
| Octopus | Off-chain | New in v0.6.7, Updated v0.6.9 |
| Key Management | Off-chain | New in v0.6.9 |

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

### OCTO_007: InvalidVRFProof (v0.6.9)
```typescript
{
  code: "OCTO_007",
  category: "OCTOPUS",
  message: "VRF proof verification failed for epoch randomness",
  context: {
    epochId: 42,
    validator: "0x1234...",
    expectedRandomness: "0xabcd..."
  }
}
```

---

## Message Errors (v0.6.9 Security)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| MSG_009 | ChainMismatch | Message chain_id doesn't match current chain | INV43 |
| MSG_010 | BlockBoundExceeded | Current block exceeds message block_bound | INV43 |

### MSG_009: ChainMismatch
```typescript
{
  code: "MSG_009",
  category: "MESSAGE",
  message: "Message chain_id does not match current chain",
  context: {
    messageChainId: 1,
    currentChainId: 137,
    sender: "0x1234..."
  }
}
```

### MSG_010: BlockBoundExceeded
```typescript
{
  code: "MSG_010",
  category: "MESSAGE",
  message: "Message has expired (current block exceeds block_bound)",
  context: {
    blockBound: 1000000,
    currentBlock: 1000150,
    sender: "0x1234..."
  }
}
```

---

## Discovery Errors (v0.6.9 Security)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| DISC_010 | RateLimited | Query rate limit exceeded | INV45 |
| DISC_011 | PresenceRequired | Sender lacks presence for query | INV45 |

### DISC_010: RateLimited
```typescript
{
  code: "DISC_010",
  category: "DISCOVERY",
  message: "Query rate limit exceeded",
  context: {
    sender: "0x1234...",
    queriesThisMinute: 61,
    maxQueriesPerMinute: 60
  }
}
```

### DISC_011: PresenceRequired
```typescript
{
  code: "DISC_011",
  category: "DISCOVERY",
  message: "Sender must have valid presence to query discovery",
  context: {
    sender: "0x1234...",
    epochId: 42,
    presenceState: "None"
  }
}
```

---

## Key Management Errors (v0.6.9)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| KEY_001 | InsufficientValidators | Not enough validators for key distribution | - |
| KEY_002 | KeyShareAlreadyDestroyed | Validator already attested to destruction | INV44 |
| KEY_003 | DestructionWindowExpired | Destruction window has passed | INV44 |
| KEY_004 | InvalidDestructionAttestation | Invalid signature on destruction attestation | INV44 |

### KEY_001: InsufficientValidators
```typescript
{
  code: "KEY_001",
  category: "KEY_MANAGEMENT",
  message: "Insufficient validators for key distribution",
  context: {
    required: 5,
    available: 3,
    epochId: 42
  }
}
```

### KEY_002: KeyShareAlreadyDestroyed
```typescript
{
  code: "KEY_002",
  category: "KEY_MANAGEMENT",
  message: "Validator already attested to key share destruction",
  context: {
    validator: "0x1234...",
    epochId: 42,
    previousAttestationAt: 1705000000
  }
}
```

### KEY_003: DestructionWindowExpired
```typescript
{
  code: "KEY_003",
  category: "KEY_MANAGEMENT",
  message: "Key destruction window has expired",
  context: {
    epochId: 42,
    windowEnd: 1705000300,
    currentTime: 1705000400
  }
}
```

### KEY_004: InvalidDestructionAttestation
```typescript
{
  code: "KEY_004",
  category: "KEY_MANAGEMENT",
  message: "Invalid signature on destruction attestation",
  context: {
    validator: "0x1234...",
    epochId: 42
  }
}
```

---

## Recovery Actions

| Error Category | Recovery |
|----------------|----------|
| NODE_* | Re-derive from on-chain |
| DISC_* | Retry with different peer; wait if rate limited |
| MSG_* | Reject message, log; for MSG_009/010 reject immediately |
| SYNC_* | Force complete sync |
| MEDIA_* | Reject media, notify sender |
| BOOM_* | Retry with new boomerangId |
| AUTO_* | Revoke intent, re-declare if needed |
| OCTO_* | Wait for threshold, retry division/merge |
| KEY_* | Wait for epoch transition or contact validators |

---

## Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Added off-chain error catalog for semantic layer |
| v0.6.4 | Added MEDIA_001-006 for ephemeral media |
| v0.6.5 | Added BOOM_001-005 for boomerang routing |
| v0.6.6 | Added AUTO_001-006 for autonomous transactions |
| v0.6.7 | Added OCTO_001-006 for octopus scaling |
| v0.6.9 | **Security hardening**: Added MSG_009-010 (chain binding), DISC_010-011 (rate limiting), KEY_001-004 (key management), OCTO_007 (VRF verification) |

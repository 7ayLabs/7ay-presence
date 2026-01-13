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

---

## On-Chain Errors (Preserved)

All on-chain errors from v0.5 remain unchanged. See errors.md v0.5 for:
- Epoch errors
- Presence errors
- Dispute errors
- Validator errors
- Registry errors

---

## Off-Chain Error Codes

### Error Code Format

Off-chain errors use a structured format:
```typescript
interface ProtocolError {
  code: string;           // E.g., "NODE_001"
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
  BOOMERANG = "BOOMERANG"
}
```

---

## Node Model Errors

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| NODE_001 | InvalidNodeIdentity | Node address is zero or invalid | INV19 |
| NODE_002 | NodeNotOnChain | Node address has no on-chain presence | INV19 |
| NODE_003 | EpochMismatch | Node epoch does not match context | INV20 |
| NODE_004 | RoleDerivationFailed | Cannot derive role from on-chain state | INV19 |
| NODE_005 | PresenceStateInvalid | Presence state is None or Slashed | INV22 |

### NODE_001: InvalidNodeIdentity
```typescript
{
  code: "NODE_001",
  category: "NODE",
  message: "Node identity is invalid",
  context: {
    address: "0x0000000000000000000000000000000000000000"
  }
}
```

### NODE_002: NodeNotOnChain
```typescript
{
  code: "NODE_002",
  category: "NODE",
  message: "Node has no on-chain presence record",
  context: {
    address: "0x1234...",
    epochId: 123
  }
}
```

### NODE_003: EpochMismatch
```typescript
{
  code: "NODE_003",
  category: "NODE",
  message: "Node epoch does not match request context",
  context: {
    nodeEpochId: 123,
    requestEpochId: 456
  }
}
```

---

## Discovery Errors

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| DISC_001 | EpochNotActive | Epoch is not in Active state | INV21 |
| DISC_002 | InsufficientCapability | Epoch capability < PresenceWithSignals | INV23 |
| DISC_003 | NoPeersFound | No valid peers in epoch | - |
| DISC_004 | DiscoveryTimeout | Discovery request timed out | - |
| DISC_005 | InvalidDiscoveryResponse | Response contains invalid nodes | INV22 |

### DISC_001: EpochNotActive
```typescript
{
  code: "DISC_001",
  category: "DISCOVERY",
  message: "Cannot discover nodes in non-Active epoch",
  context: {
    epochId: 123,
    epochState: "Closed"
  }
}
```

### DISC_002: InsufficientCapability
```typescript
{
  code: "DISC_002",
  category: "DISCOVERY",
  message: "Epoch capability does not support v0.6 features",
  context: {
    epochId: 123,
    capability: "PresenceOnly",
    required: "PresenceWithSignals"
  }
}
```

---

## Messaging Errors

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| MSG_001 | InvalidMessageType | Unknown message type | - |
| MSG_002 | InvalidSignature | Signature verification failed | INV24 |
| MSG_003 | NonceReused | Nonce already used by sender | INV25 |
| MSG_004 | EpochMismatch | Message epoch != current context | INV23 |
| MSG_005 | SenderNotInEpoch | Sender has no presence in epoch | INV22 |
| MSG_006 | MessageExpired | Timestamp too old | - |
| MSG_007 | InvalidPayload | Payload does not match schema | - |
| MSG_008 | VersionMismatch | Protocol version unsupported | - |

### MSG_002: InvalidSignature
```typescript
{
  code: "MSG_002",
  category: "MESSAGE",
  message: "Message signature verification failed",
  context: {
    claimedSender: "0x1234...",
    recoveredSigner: "0x5678...",
    messageType: "NODE_ANNOUNCE"
  }
}
```

### MSG_003: NonceReused
```typescript
{
  code: "MSG_003",
  category: "MESSAGE",
  message: "Nonce has already been used by sender",
  context: {
    sender: "0x1234...",
    nonce: "0xabcd...",
    epochId: 123
  }
}
```

### MSG_005: SenderNotInEpoch
```typescript
{
  code: "MSG_005",
  category: "MESSAGE",
  message: "Message sender has no valid presence in epoch",
  context: {
    sender: "0x1234...",
    epochId: 123,
    presenceState: "None"
  }
}
```

---

## State Sync Errors

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| SYNC_001 | SyncRequestInvalid | Malformed sync request | - |
| SYNC_002 | EpochNotSyncable | Epoch does not exist or not started | - |
| SYNC_003 | VectorClockConflict | Cannot reconcile vector clocks | INV26 |
| SYNC_004 | StateRootMismatch | Reconciled state root differs | INV26 |
| SYNC_005 | OnChainVerificationFailed | Off-chain state contradicts on-chain | INV19 |
| SYNC_006 | SyncTimeout | Sync operation timed out | - |
| SYNC_007 | PeerUnreachable | Cannot connect to sync peer | - |

### SYNC_004: StateRootMismatch
```typescript
{
  code: "SYNC_004",
  category: "SYNC",
  message: "Reconciled state root does not match expected",
  context: {
    epochId: 123,
    localRoot: "0xabc...",
    expectedRoot: "0xdef...",
    blockNumber: 12345678
  }
}
```

### SYNC_005: OnChainVerificationFailed
```typescript
{
  code: "SYNC_005",
  category: "SYNC",
  message: "Off-chain state contradicts on-chain truth",
  context: {
    actor: "0x1234...",
    epochId: 123,
    offChainState: "Validated",
    onChainState: "Declared"
  }
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

### MEDIA_001: InvalidMediaType
```typescript
{
  code: "MEDIA_001",
  category: "MEDIA",
  message: "Media content type is not supported",
  context: {
    contentType: "image/gif",
    allowedTypes: ["image/jpeg", "image/png", "image/webp"],
    epochId: 123
  }
}
```

### MEDIA_002: MediaTooLarge
```typescript
{
  code: "MEDIA_002",
  category: "MEDIA",
  message: "Media content exceeds maximum allowed size",
  context: {
    contentSize: 10485760,
    maxSize: 5242880,
    contentType: "image/jpeg"
  }
}
```

### MEDIA_005: MediaEpochMismatch
```typescript
{
  code: "MEDIA_005",
  category: "MEDIA",
  message: "Epoch does not support ephemeral media",
  context: {
    epochId: 123,
    epochCapability: "PresenceWithSignals",
    requiredCapability: "PresenceWithEphemeralData"
  }
}
```

---

## Boomerang Errors (v0.6.5)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| BOOM_001 | PathNotDivergent | Return path same as forward path | INV30 |
| BOOM_002 | BoomerangTimeout | Cycle timeout exceeded | INV31 |
| BOOM_003 | InvalidHopSignature | Hop signature verification failed | INV33 |
| BOOM_004 | BoomerangAborted | Cycle aborted mid-flight | INV32 |
| BOOM_005 | InvalidReturnPath | Return path contains invalid nodes | INV30 |

### BOOM_001: PathNotDivergent
```typescript
{
  code: "BOOM_001",
  category: "BOOMERANG",
  message: "Return path must differ from forward path",
  context: {
    boomerangId: "0xabc...",
    forwardPath: ["0x1111...", "0x2222..."],
    returnPath: ["0x2222...", "0x1111..."]
  }
}
```

### BOOM_002: BoomerangTimeout
```typescript
{
  code: "BOOM_002",
  category: "BOOMERANG",
  message: "Boomerang cycle timeout exceeded",
  context: {
    boomerangId: "0xabc...",
    sentAt: 1700000000,
    timeout: 60,
    currentTime: 1700000061
  }
}
```

### BOOM_003: InvalidHopSignature
```typescript
{
  code: "BOOM_003",
  category: "BOOMERANG",
  message: "Hop signature verification failed",
  context: {
    boomerangId: "0xabc...",
    hopIndex: 2,
    claimedForwarder: "0x1234...",
    recoveredSigner: "0x5678..."
  }
}
```

---

## Error Priorities (Off-Chain)

### Message Validation Priority

| Priority | Error | Check |
|----------|-------|-------|
| 1 | MSG_008 | Version supported |
| 2 | MSG_001 | Message type valid |
| 3 | MSG_004 | Epoch exists and matches |
| 4 | MSG_002 | Signature valid |
| 5 | MSG_005 | Sender has presence |
| 6 | MSG_003 | Nonce unique |
| 7 | MSG_006 | Timestamp valid |
| 8 | MSG_007 | Payload valid |

### Discovery Validation Priority

| Priority | Error | Check |
|----------|-------|-------|
| 1 | DISC_001 | Epoch is Active |
| 2 | DISC_002 | Capability sufficient |
| 3 | NODE_001 | Requester identity valid |
| 4 | NODE_002 | Requester has on-chain presence |

### Sync Validation Priority

| Priority | Error | Check |
|----------|-------|-------|
| 1 | SYNC_001 | Request format valid |
| 2 | SYNC_002 | Epoch exists and syncable |
| 3 | NODE_001 | Requester identity valid |

### Media Validation Priority (v0.6.4)

| Priority | Error | Check |
|----------|-------|-------|
| 1 | MEDIA_005 | Epoch has PresenceWithEphemeralData |
| 2 | MEDIA_004 | Media complies with policy |
| 3 | MEDIA_001 | Media type allowed |
| 4 | MEDIA_002 | Media size within limits |
| 5 | MEDIA_003 | Media not expired |
| 6 | MEDIA_006 | Media exists |

### Boomerang Validation Priority (v0.6.5)

| Priority | Error | Check |
|----------|-------|-------|
| 1 | BOOM_001 | Return path divergent from forward |
| 2 | BOOM_005 | All return path nodes have presence |
| 3 | BOOM_003 | All hop signatures valid |
| 4 | BOOM_002 | Within timeout window |
| 5 | BOOM_004 | Cycle not aborted |

---

## Error Handling

### Off-Chain Error Response

Errors SHOULD be returned in a structured format:
```typescript
interface ErrorResponse {
  success: false;
  error: ProtocolError;
  timestamp: number;
}
```

### Error Logging

Implementations SHOULD log errors with:
- Error code
- Context (sanitized, no PII)
- Timestamp
- Correlation ID

### Recovery Actions

| Error Category | Recovery |
|----------------|----------|
| NODE_* | Re-derive from on-chain |
| DISC_* | Retry with different peer |
| MSG_* | Reject message, log |
| SYNC_* | Force complete sync |
| MEDIA_* | Reject media, notify sender |
| BOOM_* | Retry with new boomerangId |

---

## Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 on-chain errors | Unchanged |
| v0.4 error priority | Preserved |
| Custom errors | Preserved |
| Error parameters | Preserved |

---

## References

- errors.md v0.5 — On-chain error catalog
- invariants.md v0.6.1 — Invariants referenced by errors
- message-catalog.md v0.6.2 — Message types (forward reference)

---

## Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Added off-chain error catalog for semantic layer |
| v0.6.4 | Added MEDIA_001-006 for ephemeral media |
| v0.6.5 | Added BOOM_001-005 for boomerang routing |

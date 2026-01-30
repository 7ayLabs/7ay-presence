# 7ay Proof of Presence (PoP)
## Protocol Specification — Errors
**Version:** v0.7.1 (consolidated from v0.4-v0.7.1)
**Status:** Active

> Includes on-chain errors (v0.4-v0.5, v0.7.0) and off-chain semantic layer errors (v0.6-v0.7.0)

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
| Boomerang | Off-chain | New in v0.6.5, Updated v0.7.0 |
| Autonomous | Off-chain | New in v0.6.6, Updated v0.7.0 |
| Octopus | Off-chain | New in v0.6.7, Updated v0.7.0 |
| Key Management | Off-chain | New in v0.6.9 |
| Staking | On-chain | New in v0.7.0 (RFC-0001) |
| Recovery | On-chain | New in v0.7.0 (RFC-0004) |
| Upgrades | On-chain | New in v0.7.0 (RFC-0004) |
| Device | Off-chain | New in v0.7.1 |
| Storage | Off-chain | New in v0.7.1 |

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
  OCTOPUS = "OCTOPUS",
  KEY_MANAGEMENT = "KEY_MANAGEMENT",
  STAKING = "STAKING",
  RECOVERY = "RECOVERY",
  UPGRADES = "UPGRADES",
  DEVICE = "DEVICE",
  STORAGE = "STORAGE"
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

## Boomerang Errors (v0.6.5, Updated v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| BOOM_001 | PathNotDivergent | Return path same as forward path (standard mode) | INV30 |
| BOOM_002 | BoomerangTimeout | Cycle timeout exceeded | INV31 |
| BOOM_003 | InvalidHopSignature | Hop signature verification failed | INV33 |
| BOOM_004 | BoomerangAborted | Cycle aborted mid-flight | INV32 |
| BOOM_005 | InvalidReturnPath | Return path contains invalid nodes | INV30 |
| BOOM_006 | SmallNetworkFallbackDisabled | Same path used but fallback disabled | INV54 |
| BOOM_007 | InsufficientAttestations | Not enough validator attestations for level | INV55 |
| BOOM_008 | InvalidAttestation | Validator attestation verification failed | INV55 |
| BOOM_009 | ModeNotTransparent | Small network mode not indicated in complete | INV56 |

---

## Autonomous Errors (v0.6.6, Updated v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| AUTO_001 | InsufficientPresence | Actor not Validated/Finalized | INV34 |
| AUTO_002 | PatternThresholdNotMet | Pattern frequency below threshold | INV35 |
| AUTO_003 | QuorumNotReached | Insufficient validator approvals | INV36 |
| AUTO_004 | IntentExpired | Intent has passed expiration time | INV37 |
| AUTO_005 | MaxExecutionsReached | Execution count at maximum | - |
| AUTO_006 | IntentNotFound | Referenced intent does not exist | - |
| AUTO_010 | InsufficientReputation | Actor reputation below tier minimum | INV50 |
| AUTO_011 | CooldownActive | Actor in cooldown from rejection | INV53 |
| AUTO_012 | TierThresholdNotMet | Execution exceeds tier threshold | INV52 |
| AUTO_013 | ReputationUpdateFailed | Failed to update reputation score | INV51 |

---

## Octopus Errors (v0.6.7, Updated v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| OCTO_001 | BelowActivationThreshold | Division requested below 45% | INV38 |
| OCTO_002 | SubNodeLimitReached | Already at dynamic max for throughput | INV40, INV63 |
| OCTO_003 | InvalidSubNodeId | Sub-node ID doesn't match derivation | INV39 |
| OCTO_004 | HysteresisNotMet | Merge requested before sustained low | INV42 |
| OCTO_005 | StateReconciliationFailed | Missing sub-node states for merge | INV41 |
| OCTO_006 | InvalidDivisionState | Cannot divide/merge in current state | - |
| OCTO_007 | InvalidVRFProof | VRF proof verification failed | INV39 |
| OCTO_008 | ExceedsDynamicLimit | Requested sub-nodes exceeds calculated limit | INV63 |
| OCTO_009 | AbsoluteMaxExceeded | Cannot exceed 8 sub-nodes (hard cap) | INV63 |

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
  message: "Cannot create more sub-nodes, dynamic limit reached",
  context: {
    parentNode: "0x1234...",
    currentSubNodes: 4,
    dynamicLimit: 4,
    throughputPercent: 85
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

## Staking Errors (v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| STK_001 | InsufficientStake | Stake below minimum requirement | INV46 |
| STK_002 | StakeConcentrationExceeded | Stake exceeds 33% of total | INV47 |
| STK_003 | CooldownActive | Stake reduction cooldown not complete | - |
| STK_004 | InvalidSlashAmount | Slash exceeds maximum for violation type | INV48 |
| STK_005 | EvidenceRewardExceeded | Evidence reward exceeds cap | INV49 |
| STK_006 | NotValidator | Account is not an active validator | - |
| STK_007 | MinimumValidatorCount | Would reduce validators below minimum | INV46 |

### STK_001: InsufficientStake
```typescript
{
  code: "STK_001",
  category: "STAKING",
  message: "Stake amount below minimum requirement",
  context: {
    validator: "0x1234...",
    stakeAmount: 5000,
    minimumRequired: 10000
  }
}
```

### STK_002: StakeConcentrationExceeded
```typescript
{
  code: "STK_002",
  category: "STAKING",
  message: "Stake would exceed 33% concentration limit",
  context: {
    validator: "0x1234...",
    proposedStake: 50000,
    totalStake: 100000,
    maxAllowed: 33000
  }
}
```

---

## Recovery Errors (v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| REC_001 | NotSuspended | Validator not in Suspended status | INV57 |
| REC_002 | ProposalExists | Recovery already in progress | - |
| REC_003 | VotingExpired | Voting period has ended | - |
| REC_004 | NotValidator | Caller is not active validator | - |
| REC_005 | AlreadyVoted | Validator already voted on this recovery | - |
| REC_006 | CooldownActive | Recovery cooldown not complete | INV58 |

### REC_001: NotSuspended
```typescript
{
  code: "REC_001",
  category: "RECOVERY",
  message: "Validator must be in Suspended status to initiate recovery",
  context: {
    validator: "0x1234...",
    currentStatus: "Active"
  }
}
```

### REC_006: CooldownActive
```typescript
{
  code: "REC_006",
  category: "RECOVERY",
  message: "Recovery cooldown period not complete",
  context: {
    validator: "0x1234...",
    cooldownUntil: 1705604800,
    currentTime: 1705500000
  }
}
```

---

## Upgrade Errors (v0.7.0)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| UPG_001 | NotFound | Upgrade ID not found | - |
| UPG_002 | NotApproved | Upgrade not yet approved | - |
| UPG_003 | DelayNotElapsed | Upgrade delay not complete | INV59 |
| UPG_004 | MissingDisclosure | Emergency upgrade requires disclosure | INV60 |
| UPG_005 | NotValidator | Caller not active validator | - |
| UPG_006 | AlreadyVoted | Duplicate vote | - |
| UPG_007 | VotingClosed | Voting period ended | - |

### UPG_003: DelayNotElapsed
```typescript
{
  code: "UPG_003",
  category: "UPGRADES",
  message: "Upgrade delay period not complete",
  context: {
    upgradeId: 5,
    upgradeType: "Protocol",
    proposedAt: 1705000000,
    effectiveAt: 1705604800,
    currentTime: 1705300000
  }
}
```

### UPG_004: MissingDisclosure
```typescript
{
  code: "UPG_004",
  category: "UPGRADES",
  message: "Emergency upgrades require security disclosure",
  context: {
    upgradeId: 6,
    upgradeType: "Emergency"
  }
}
```

---

## Device Errors (v0.7.1)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| STOR_001 | DeviceNotRegistered | Device ID not found in registry | - |
| STOR_002 | DeviceAlreadyRegistered | Device index already used by owner | - |
| STOR_003 | DeviceNotPresent | Device lacks presence in current epoch | INV65 |
| STOR_004 | DeviceRevoked | Device permanently revoked | - |
| STOR_005 | DeviceLost | Device marked as lost | - |
| STOR_009 | InsufficientDevices | Not enough devices for threshold | INV66 |
| STOR_020 | UnauthorizedDevice | Device not in vault's ring | INV65 |

### STOR_001: DeviceNotRegistered
```typescript
{
  code: "STOR_001",
  category: "DEVICE",
  message: "Device ID not found in registry",
  context: {
    deviceId: "0x1234...",
    owner: "0xabcd..."
  }
}
```

### STOR_003: DeviceNotPresent
```typescript
{
  code: "STOR_003",
  category: "DEVICE",
  message: "Device lacks presence in current epoch",
  context: {
    deviceId: "0x1234...",
    owner: "0xabcd...",
    epochId: 42,
    deviceState: "Inactive",
    ownerPresence: "Validated"
  }
}
```

### STOR_004: DeviceRevoked
```typescript
{
  code: "STOR_004",
  category: "DEVICE",
  message: "Device has been permanently revoked",
  context: {
    deviceId: "0x1234...",
    owner: "0xabcd...",
    revokedAt: 1705000000,
    reason: "Compromised"
  }
}
```

---

## Storage Errors (v0.7.1)

| Code | Name | Condition | Invariant |
|------|------|-----------|-----------|
| STOR_006 | VaultNotFound | Vault ID not found | - |
| STOR_007 | VaultLocked | Vault access state is Locked | INV67 |
| STOR_008 | VaultSuspended | Vault suspended by owner | - |
| STOR_010 | ThresholdNotMet | Present devices below threshold | INV67 |
| STOR_011 | ShareAlreadyProvided | Device already provided share | - |
| STOR_012 | InvalidShare | Share verification failed | - |
| STOR_013 | ShareMismatch | Share index doesn't match device | INV69 |
| STOR_014 | StorageQuotaExceeded | Vault storage limit reached | - |
| STOR_015 | ItemNotFound | Storage item not found | - |
| STOR_016 | ItemTooLarge | Item exceeds max size | - |
| STOR_017 | InvalidMediaType | Media type not allowed by policy | - |
| STOR_018 | KeyVersionMismatch | Item encrypted with old key | INV70 |
| STOR_019 | IntegrityCheckFailed | Content hash mismatch | INV72 |

### STOR_007: VaultLocked
```typescript
{
  code: "STOR_007",
  category: "STORAGE",
  message: "Vault access state is Locked - insufficient devices present",
  context: {
    vaultId: "0x1234...",
    presentDevices: 2,
    threshold: 3,
    accessState: "Locked"
  }
}
```

### STOR_010: ThresholdNotMet
```typescript
{
  code: "STOR_010",
  category: "STORAGE",
  message: "Present devices below unlock threshold",
  context: {
    vaultId: "0x1234...",
    presentDevices: 1,
    threshold: 2,
    totalDevices: 3
  }
}
```

### STOR_019: IntegrityCheckFailed
```typescript
{
  code: "STOR_019",
  category: "STORAGE",
  message: "Content hash does not match stored hash",
  context: {
    itemId: "0x1234...",
    expectedHash: "0xabcd...",
    actualHash: "0xef01..."
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
| BOOM_* | Retry with new boomerangId; use fallback if small network |
| AUTO_* | Wait for cooldown, improve reputation, re-declare if needed |
| OCTO_* | Wait for threshold, retry division/merge |
| KEY_* | Wait for epoch transition or contact validators |
| STK_* | Adjust stake amount, wait for cooldown |
| REC_* | Wait for voting, ensure proper status |
| UPG_* | Wait for delay, ensure proper quorum |
| STOR_001-005 | Check device registration, recover lost device, re-register |
| STOR_006-019 | Unlock vault, wait for devices, retry operation |

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
| v0.7.0 | **Production readiness**: Added STK_001-007 (staking), REC_001-006 (recovery), UPG_001-007 (upgrades), AUTO_010-013 (reputation), BOOM_006-009 (small network), OCTO_008-009 (dynamic scaling) |
| v0.7.1 | **Device layer**: Added STOR_001-020 (device and storage errors) |

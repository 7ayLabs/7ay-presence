# 7ay Proof of Presence (PoP)
## Protocol Specification — Autonomous Transactions
**Version:** v0.6.6
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** message-catalog.md v0.6.2, node-model.md v0.6.2, validator.md v0.4

---

## 1. Purpose

This specification defines **Autonomous Transactions** for the 7ay Presence Protocol's
semantic layer.

Autonomous Transactions enable automatic transaction execution for frequent users
with validated presence, using a hybrid on-chain/off-chain model.

This specification defines:
- Autonomous intent declaration
- Pattern recognition
- Hybrid execution model
- Validator finalization
- State machine and invariants

This version does **NOT** define:
- Specific transaction types
- Token economics
- Gas optimization
- Cross-epoch persistence

---

## 2. Overview

### 2.1 Concept

Autonomous Transactions enable trusted, recurring actions for users with
established presence history:

```
┌─────────────────────────────────────────────────────────────────┐
│                  AUTONOMOUS TRANSACTION FLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. INTENT DECLARATION (on-chain commitment)                  │
│      Actor commits intent hash to PresenceRegistry              │
│                                                                 │
│   2. PATTERN RECOGNITION (off-chain)                           │
│      Validators observe recurring patterns                      │
│      Pattern threshold met → eligible for autonomous            │
│                                                                 │
│   3. AUTONOMOUS EXECUTION (off-chain)                          │
│      Actor executes action matching declared intent             │
│      Validators observe and validate execution                  │
│                                                                 │
│   4. FINALIZATION (validator quorum)                           │
│      Validators vote on execution validity                      │
│      Quorum reached → transaction finalized                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Benefits

1. **Reduced friction**: Frequent users skip repeated confirmations
2. **Presence-based trust**: Validated presence enables autonomy
3. **Validator oversight**: Autonomous actions still require quorum
4. **Epoch-scoped**: Authorizations reset with each epoch

### 2.3 Hybrid Model

| Component | Location | Purpose |
|-----------|----------|---------|
| Intent hash | On-chain | Commitment to action type |
| Pattern data | Off-chain | Frequency, conditions |
| Execution | Off-chain | Actual transaction |
| Finalization | On-chain | Validator quorum |

---

## 3. Autonomous States

### 3.1 State Machine

```
              AUTONOMOUS_INTENT
    ────────────────────────────────► Declared
                                          │
         ┌────────────────────────────────┼────────────────────┐
         │                                │                    │
         ▼                                ▼                    ▼
   AUTONOMOUS_PATTERN              Pattern not met        Revoked
   (threshold reached)                    │                    │
         │                                ▼                    │
         ▼                             Inactive                │
      Eligible                                                 │
         │                                                     │
         ▼                                                     │
   AUTONOMOUS_EXECUTE                                          │
         │                                                     │
         ▼                                                     │
   AUTONOMOUS_FINALIZE                                         │
   (validator quorum)                                          │
         │                                                     │
         ▼                                                     │
     Finalized ◄───────────────────────────────────────────────┘
```

### 3.2 State Definitions

| State | Description |
|-------|-------------|
| Declared | Intent committed on-chain, awaiting pattern recognition |
| Eligible | Pattern threshold met, can execute autonomously |
| Inactive | Pattern not met within window |
| Finalized | Execution finalized by validator quorum |
| Revoked | Authorization explicitly revoked |

---

## 4. Message Types

### 4.1 Message Type Enum Extension

```typescript
enum MessageType {
  // ... existing types (0x01-0x43)

  // Autonomous (0x50-0x5F) — v0.6.6
  AUTONOMOUS_INTENT = 0x50,
  AUTONOMOUS_PATTERN = 0x51,
  AUTONOMOUS_EXECUTE = 0x52,
  AUTONOMOUS_FINALIZE = 0x53,
  AUTONOMOUS_REVOKE = 0x54
}
```

### 4.2 AUTONOMOUS_INTENT (0x50)

Declare autonomous transaction intent.

```typescript
interface AutonomousIntentPayload {
  // Intent identification
  intentId: bytes32;              // Unique intent identifier
  intentHash: bytes32;            // Hash of intent details

  // Intent parameters
  actionType: bytes32;            // Type of action (e.g., "transfer", "vote")
  conditions: IntentCondition[];  // Conditions for auto-execution

  // Constraints
  maxExecutions: uint256;         // Max times can execute (0 = unlimited)
  expiresAt: uint256;             // Intent expiration timestamp

  // Commitment
  commitmentProof: bytes;         // Proof of on-chain commitment
}

interface IntentCondition {
  conditionType: string;          // e.g., "frequency", "threshold"
  parameters: bytes;              // Condition-specific parameters
}
```

**Validation Rules:**
- Sender MUST have Validated or Finalized presence (INV34)
- `intentHash` MUST match on-chain commitment
- `expiresAt` MUST be within epoch bounds
- `maxExecutions` SHOULD be <= 100 per epoch

**Usage:**
- Declare intent for autonomous actions
- Broadcast to validators for pattern tracking

### 4.3 AUTONOMOUS_PATTERN (0x51)

Report pattern recognition result.

```typescript
interface AutonomousPatternPayload {
  // Correlation
  intentId: bytes32;
  actor: Address;

  // Pattern data
  patternType: PatternType;
  frequency: uint256;             // Actions per time window
  windowStart: uint256;           // Observation window start
  windowEnd: uint256;             // Observation window end

  // Threshold check
  thresholdMet: bool;             // Whether threshold reached
  evidenceHash: bytes32;          // Hash of evidence data
}

enum PatternType {
  FREQUENCY = 0,      // N actions in time window
  PERIODIC = 1,       // Regular interval actions
  CONDITIONAL = 2     // Triggered by conditions
}
```

**Validation Rules:**
- Sender MUST be a validator
- `actor` MUST have declared intent
- `frequency` MUST be >= pattern threshold (INV35)
- Pattern observation MUST be within current epoch

**Usage:**
- Validators report pattern observations
- Triggers eligibility for autonomous execution

### 4.4 AUTONOMOUS_EXECUTE (0x52)

Notify autonomous execution.

```typescript
interface AutonomousExecutePayload {
  // Correlation
  intentId: bytes32;
  executionId: bytes32;           // Unique execution identifier

  // Execution details
  actionData: bytes;              // Encoded action parameters
  actionHash: bytes32;            // Hash of action for verification

  // Context
  executedAt: uint256;
  conditionsMet: bytes32[];       // Which conditions triggered
}
```

**Validation Rules:**
- Sender MUST be the intent declarer
- Intent MUST be in Eligible state
- `actionHash` MUST match declared intent type
- Execution count MUST be < `maxExecutions`
- Current time MUST be < `expiresAt`

**Usage:**
- Actor notifies autonomous action execution
- Triggers validator finalization

### 4.5 AUTONOMOUS_FINALIZE (0x53)

Validator finalization vote.

```typescript
interface AutonomousFinalizePayload {
  // Correlation
  intentId: bytes32;
  executionId: bytes32;

  // Vote
  vote: FinalizationVote;
  rationale: bytes32;             // Optional rationale hash

  // Verification
  validatorSignature: bytes;      // Validator signature on execution
}

enum FinalizationVote {
  APPROVE = 0,
  REJECT = 1,
  ABSTAIN = 2
}
```

**Validation Rules:**
- Sender MUST be a validator (INV36)
- Sender MUST have voted on pattern recognition
- `executionId` MUST reference valid execution
- Validator MUST NOT have already voted on this execution

**Usage:**
- Validators vote on execution validity
- Quorum of APPROVE → Finalized

### 4.6 AUTONOMOUS_REVOKE (0x54)

Revoke autonomous authorization.

```typescript
interface AutonomousRevokePayload {
  // Target
  intentId: bytes32;

  // Revocation
  reason: RevokeReason;
  effectiveAt: uint256;           // When revocation takes effect
}

enum RevokeReason {
  ACTOR_REQUEST = 0,    // Actor requested revocation
  VALIDATOR_FORCE = 1,  // Validator forced (abuse detection)
  EPOCH_END = 2,        // Epoch closing (automatic)
  EXPIRED = 3           // Intent expired
}
```

**Validation Rules:**
- If `reason == ACTOR_REQUEST`: sender MUST be actor
- If `reason == VALIDATOR_FORCE`: sender MUST be validator
- Intent MUST exist and not already revoked
- Epoch MUST be Active (INV37)

**Usage:**
- Terminate autonomous authorization
- Clean shutdown at epoch end

---

## 5. Pattern Recognition

### 5.1 Pattern Threshold (INV35)

Autonomous execution requires minimum pattern frequency:

```
∀ intent:
  intent.state = Eligible →
    observedFrequency(intent.actor, intent.actionType) >= patternThreshold
```

### 5.2 Default Thresholds

| Pattern Type | Default Threshold | Description |
|--------------|-------------------|-------------|
| FREQUENCY | 5 per hour | Minimum 5 actions in 1 hour |
| PERIODIC | 3 consecutive | 3 regular interval actions |
| CONDITIONAL | 2 triggers | 2 condition-triggered actions |

### 5.3 Pattern Evidence

Validators track pattern evidence:

```typescript
interface PatternEvidence {
  actor: Address;
  actionType: bytes32;
  observations: Observation[];
  threshold: uint256;
  thresholdMetAt?: uint256;
}

interface Observation {
  timestamp: uint256;
  actionHash: bytes32;
  validatorWitness: Address;
}
```

---

## 6. Validator Finalization

### 6.1 Finalization Quorum (INV36)

Autonomous executions require validator quorum:

```
∀ execution:
  execution.state = Finalized →
    count(votes where vote = APPROVE) >= quorumSize()
```

### 6.2 Finalization Window

- Validators have 60 seconds to vote after AUTONOMOUS_EXECUTE
- Quorum timeout: execution reverts to pending
- No quorum within 5 minutes: execution rejected

### 6.3 Vote Weight

All active validators have equal vote weight (1).

---

## 7. Epoch Scope

### 7.1 Epoch Binding (INV37)

Autonomous authorizations are epoch-scoped:

```
∀ intent:
  intent.epochId = currentEpoch ∧
  epochState(intent.epochId) = Active →
    intent.valid = true

∀ intent:
  epochState(intent.epochId) ∈ {Closed, Finalized} →
    intent.valid = false ∧
    intent.state = Revoked
```

### 7.2 Epoch Transition

On epoch close:
1. All pending intents → Revoked
2. Pattern data cleared
3. Execution counts reset

---

## 8. On-Chain Integration (Optional)

### 8.1 Intent Commitment

```solidity
// In PresenceRegistry (optional extension)
mapping(address => mapping(uint256 => bytes32)) private _autonomousIntentHashes;

/// @notice Commit autonomous intent hash
/// @param epochId Target epoch
/// @param intentHash Hash of intent details
function commitAutonomousIntent(uint256 epochId, bytes32 intentHash) external {
    require(
        presenceState(msg.sender, epochId) == PresenceState.Validated ||
        presenceState(msg.sender, epochId) == PresenceState.Finalized,
        "Insufficient presence"
    );
    require(epochState(epochId) == EpochState.Active, "Epoch not active");

    _autonomousIntentHashes[msg.sender][epochId] = intentHash;
    emit AutonomousIntentCommitted(msg.sender, epochId, intentHash);
}

/// @notice Get autonomous intent hash
function autonomousIntentHash(address actor, uint256 epochId)
    external view returns (bytes32)
{
    return _autonomousIntentHashes[actor][epochId];
}
```

### 8.2 Event

```solidity
event AutonomousIntentCommitted(
    address indexed actor,
    uint256 indexed epochId,
    bytes32 intentHash
);
```

---

## 9. Invariants

### 9.1 Autonomous Invariants

**INV34: Intent Presence**
Intent declaration requires Validated or Finalized presence.

```
∀ intent:
  presenceState(intent.actor, intent.epochId) ∈ {Validated, Finalized}
```

**INV35: Pattern Threshold**
Autonomous execution requires minimum pattern frequency.

```
∀ execution:
  execution.state = Eligible →
    patternFrequency(execution.actor, execution.actionType) >= threshold
```

**INV36: Validator Finalization**
Autonomous executions are finalized by validator quorum.

```
∀ execution:
  execution.state = Finalized →
    count(votes where vote = APPROVE) >= quorumSize()
```

**INV37: Epoch Scope**
Autonomous authorizations do not persist across epochs.

```
∀ intent:
  epochState(intent.epochId) ∈ {Closed, Finalized} →
    intent.state = Revoked
```

---

## 10. Error Codes

### 10.1 Autonomous Errors

| Code | Name | Description |
|------|------|-------------|
| AUTO_001 | InsufficientPresence | Actor lacks Validated/Finalized presence |
| AUTO_002 | PatternNotMet | Pattern threshold not reached |
| AUTO_003 | IntentExpired | Intent past expiration |
| AUTO_004 | ExecutionLimitReached | Max executions exceeded |
| AUTO_005 | FinalizationFailed | Quorum not reached |
| AUTO_006 | IntentRevoked | Intent already revoked |

### 10.2 Error Priority

```
1. InsufficientPresence → AUTO_001
2. IntentRevoked        → AUTO_006
3. IntentExpired        → AUTO_003
4. PatternNotMet        → AUTO_002
5. ExecutionLimitReached → AUTO_004
6. FinalizationFailed   → AUTO_005
```

---

## 11. Security Considerations

### 11.1 Abuse Prevention

Mitigations:
- Pattern threshold prevents immediate autonomy
- Validator quorum required for finalization
- Max execution limits
- Epoch-scoped (no persistent authorization)

### 11.2 Sybil Attacks

Mitigations:
- Requires Validated/Finalized presence
- Pattern recognition across multiple validators
- On-chain intent commitment

### 11.3 Validator Collusion

Mitigations:
- Standard quorum requirements
- Transparent vote records
- Dispute mechanism (existing)

---

## 12. Non-Goals

This specification explicitly does NOT define:

- Specific transaction types eligible for autonomy
- Token incentives for autonomous actions
- Cross-epoch pattern persistence
- Autonomous action gas sponsorship

---

## 13. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.6 message envelope | Used for all autonomous messages |
| v0.4 validator mechanics | Used for finalization |
| v0.4 presence states | Required for intent declaration |
| Existing epoch lifecycle | Extended with optional intent storage |

---

## 14. References

- message-catalog.md v0.6.2 — Message envelope structure
- validator.md v0.4 — Validator mechanics
- presence.md v0.4 — Presence states
- invariants.md v0.6.6 — Protocol invariants INV34-37
- errors.md v0.6.6 — Error catalog

---

## 15. Changelog

| Version | Changes |
|---------|---------|
| v0.6.6 | Initial autonomous transactions specification |

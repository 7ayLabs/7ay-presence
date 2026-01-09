# 7ay Proof of Presence (PoP)
## Protocol Specification — Presence
**Version:** v0.4
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** epoch.md v0.2, validator.md v0.4

---

## 1. Purpose

This specification defines the canonical rules for presence declaration,
validation, and finalization in the Proof of Presence protocol v0.4.

This version introduces:
- Validator-based presence validation
- Dispute mechanism for challenging presence claims
- Slashing for protocol violations

Implementations MUST follow this specification to be considered compliant.

---

## 2. States

```solidity
enum PresenceState {
    None,       // 0 - No presence exists
    Declared,   // 1 - Actor declared presence
    Validated,  // 2 - Quorum validated presence
    Finalized,  // 3 - Permanently recorded (terminal)
    Slashed     // 4 - Invalidated due to dispute (terminal)
}
```

### 2.1 None

No presence record exists for the (actor, epoch) tuple.

### 2.2 Declared

Actor has declared their presence within the epoch.
Awaiting validator quorum for validation.

### 2.3 Validated

Validator quorum has validated the presence claim.
Ready for finalization after epoch closes.

### 2.4 Finalized

Presence is permanently recorded and immutable.
Terminal state.

### 2.5 Slashed

Presence has been invalidated due to successful dispute.
Terminal state. Cannot be recovered.

---

## 3. Transitions

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

### 3.1 Transition Table

| From | To | Trigger | Guards | Event |
|------|-----|---------|--------|-------|
| None | Declared | `declarePresence` | A ∧ E | `PresenceDeclared` |
| Declared | Validated | `validatePresence` | V ∧ E ∧ Q | `PresenceValidated` |
| Declared | Slashed | `resolveDispute` | D_upheld | `PresenceSlashed` |
| Validated | Slashed | `resolveDispute` | D_upheld | `PresenceSlashed` |
| Validated | Finalized | `finalizePresence` | E_closed ∧ ¬D | `PresenceFinalized` |
| Declared/Validated/Finalized/Slashed | same | any | idempotent | - |

### 3.2 Guards

- `A` = `actor == msg.sender ∧ actor != 0x0 ∧ epochId != 0`
- `E` = `epochRegistry.isEpochActive(epochId)`
- `V` = `validatorRegistry.isValidatorActive(msg.sender)`
- `Q` = `validationVotes[actor][epochId] >= quorumSize()`
- `E_closed` = `epochRegistry.epochState(epochId) == Closed`
- `D` = `disputes[actor][epochId].status == Pending`
- `D_upheld` = dispute resolved with majority vote to uphold

---

## 4. Functions

### 4.1 Read Operations

```solidity
function protocolVersion() external pure returns (string memory);
function epochRegistry() external view returns (IEpochRegistry);
function validatorRegistry() external view returns (IValidatorRegistry);
function presenceState(address actor, uint256 epochId) external view returns (PresenceState);
function getPresence(address actor, uint256 epochId) external view returns (Presence memory);
function getDispute(address actor, uint256 epochId) external view returns (Dispute memory);
function disputeWindow() external view returns (uint256);
function hasValidatorVoted(address validator, address actor, uint256 epochId) external view returns (bool);
```

### 4.2 Presence Lifecycle

```solidity
function declarePresence(address actor, uint256 epochId) external;
function validatePresence(address actor, uint256 epochId) external;
function finalizePresence(address actor, uint256 epochId) external;
```

### 4.3 Dispute Mechanism

```solidity
function initiateDispute(address actor, uint256 epochId, bytes32 evidenceHash) external;
function voteOnDispute(address actor, uint256 epochId, bool upholdDispute) external;
function resolveDispute(address actor, uint256 epochId) external;
```

---

## 5. Validation

### 5.1 Validation Flow

1. Actor declares presence during Active epoch
2. Validators vote to validate the presence
3. When quorum is reached, state transitions to Validated
4. Each validator can vote once per (actor, epoch)

### 5.2 Quorum Requirement

```
requiredVotes = validatorRegistry.quorumSize()
currentVotes = validationVotes[actor][epochId]

if (currentVotes >= requiredVotes) {
    state = Validated
}
```

### 5.3 Validation Rules

A presence MAY be validated if and only if:
1. Current state is `Declared`
2. Epoch is `Active`
3. Caller is an active validator
4. Validator has not already voted for this presence

---

## 6. Dispute Mechanism

### 6.1 Dispute States

```solidity
enum DisputeStatus {
    None,       // 0 - No dispute exists
    Pending,    // 1 - Dispute initiated, awaiting votes
    Upheld,     // 2 - Dispute successful, presence slashed
    Rejected    // 3 - Dispute failed, presence remains valid
}
```

### 6.2 Dispute Flow

1. Any address can initiate a dispute during Active epoch
2. Validators vote to uphold or reject
3. When quorum votes, dispute resolves
4. If upheld: presence is slashed
5. If rejected: presence continues normally

### 6.3 Dispute Window

Disputes can only be initiated while:
- Epoch is `Active`, OR
- Epoch is `Closed` and within `disputeWindow` seconds after endTime

### 6.4 Dispute Rules

A dispute MAY be initiated if and only if:
1. `actor != 0x0 ∧ epochId != 0`
2. Presence state is `Declared` or `Validated`
3. No pending dispute exists
4. Within dispute window

A dispute vote MAY be cast if and only if:
1. Dispute is `Pending`
2. Caller is an active validator
3. Validator has not already voted on this dispute

---

## 7. Slashing

### 7.1 Slashing Conditions

Presence is slashed when:
- A dispute is resolved with majority vote to uphold

### 7.2 Slashing Effects

When presence is slashed:
1. State transitions to `Slashed`
2. `PresenceSlashed` event is emitted
3. Presence cannot be finalized
4. State is terminal (no recovery)

### 7.3 Slashing Rules

- Slashed presence MUST NOT transition to any other state
- Slashing is irreversible
- Only dispute resolution can trigger slashing

---

## 8. Finalization

### 8.1 Finalization Rules

Presence MAY be finalized if and only if:
1. Current state is `Validated`
2. Epoch is `Closed` or `Finalized`
3. No pending dispute exists
4. Presence is not slashed

### 8.2 Finalization Window

Finalization is permitted when:
- Epoch state is `Closed`
- Epoch state is `Finalized` (for late finalization)

---

## 9. Events

### 9.1 Presence Events

```solidity
event PresenceDeclared(address indexed actor, uint256 indexed epochId);
event PresenceValidated(address indexed actor, uint256 indexed epochId, uint256 validatorCount);
event PresenceFinalized(address indexed actor, uint256 indexed epochId);
event PresenceSlashed(address indexed actor, uint256 indexed epochId, address indexed challenger);
```

### 9.2 Validation Events

```solidity
event PresenceValidationVote(
    address indexed actor,
    uint256 indexed epochId,
    address indexed validator,
    uint256 currentVotes,
    uint256 requiredVotes
);
```

### 9.3 Dispute Events

```solidity
event DisputeInitiated(
    address indexed actor,
    uint256 indexed epochId,
    address indexed challenger,
    bytes32 evidenceHash
);

event DisputeVote(
    address indexed actor,
    uint256 indexed epochId,
    address indexed validator,
    bool voteToUphold
);

event DisputeResolved(
    address indexed actor,
    uint256 indexed epochId,
    DisputeStatus outcome
);
```

---

## 10. Errors

### 10.1 Priority Order (Presence Operations)

| Priority | Error | Condition |
|----------|-------|-----------|
| 1 | `InvalidActor()` | `actor == 0x0` |
| 2 | `UnauthorizedActor(caller, actor)` | `caller != actor` (declare only) |
| 3 | `InvalidEpoch(epochId)` | `epochId == 0` |
| 4 | `PresenceSlashed(actor, epochId)` | `state == Slashed` |
| 5 | `EpochNotActive(epochId)` | `!isEpochActive` (declare/validate) |
| 6 | `CallerNotValidator(caller)` | `!isValidatorActive` (validate) |
| 7 | `InvalidPresenceState(...)` | Wrong state for operation |
| 8 | `ValidatorAlreadyVoted(...)` | Double voting |

### 10.2 Priority Order (Dispute Operations)

| Priority | Error | Condition |
|----------|-------|-----------|
| 1 | `InvalidActor()` | `actor == 0x0` |
| 2 | `InvalidEpoch(epochId)` | `epochId == 0` |
| 3 | `PresenceSlashed(actor, epochId)` | Already slashed |
| 4 | `DisputeAlreadyExists(...)` | Pending dispute exists |
| 5 | `DisputeNotFound(...)` | No dispute for vote/resolve |
| 6 | `DisputeWindowClosed(epochId)` | Past dispute window |
| 7 | `CallerNotValidator(caller)` | Non-validator voting |
| 8 | `ValidatorAlreadyVoted(...)` | Double voting |
| 9 | `DisputeNotPending(...)` | Wrong dispute state |

---

## 11. Invariants

### 11.1 Preserved from v0.3

1. **Uniqueness**: `forall(actor,epoch): count(Finalized) <= 1`
2. **Finalized Immutability**: `Finalized -> immutable`
3. **Determinism**: Same inputs produce same outputs
4. **Self-Only Declaration**: `actor == msg.sender` for declare
5. **Actor Isolation**: `finalize(A) ⊥ finalize(B)`
6. **Epoch Isolation**: `finalize(E1) ⊥ finalize(E2)`
7. **Monotonicity**: `None -> Declared -> Validated -> Finalized`

### 11.2 New in v0.4

8. **Slashed Terminal**: `Slashed -> no outgoing transitions`
9. **No Retroactive Validation**: Cannot validate after epoch expires
10. **Quorum Required**: `Validated` requires `votes >= quorumSize`
11. **Single Vote**: Each validator votes once per presence
12. **Dispute Isolation**: Dispute affects only target presence
13. **Slashed Immutability**: `Slashed -> immutable`

---

## 12. Storage

```solidity
// Dependencies
IEpochRegistry public immutable epochRegistry;
IValidatorRegistry public immutable validatorRegistry;

// Configuration
uint256 public disputeWindow;  // seconds

// Presence state
mapping(address => mapping(uint256 => PresenceState)) private _presenceState;
mapping(address => mapping(uint256 => Presence)) private _presenceData;

// Validation tracking
mapping(address => mapping(uint256 => uint256)) private _validationVotes;
mapping(address => mapping(uint256 => mapping(address => bool))) private _hasVoted;

// Dispute tracking
mapping(address => mapping(uint256 => Dispute)) private _disputes;
mapping(address => mapping(uint256 => mapping(address => bool))) private _hasVotedOnDispute;
```

---

## 13. Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `disputeWindow` | 86400 | Seconds after epoch end to dispute (1 day) |

---

## 14. Compliance

An implementation is considered compliant if and only if:
- All Presence Invariants (11.1, 11.2) hold
- All required events are emitted correctly
- All error conditions are handled per specification
- State transitions follow the defined lifecycle

---

## 15. Versioning

| Version | Changes |
|---------|---------|
| v0.1 | Initial presence specification |
| v0.2 | (skipped - epoch focus) |
| v0.3 | Declaration layer (Declared state) |
| v0.4 | Validators, disputes, slashing |

---

## 16. References

- validator.md v0.4 — Validator specification
- epoch.md v0.2 — Epoch specification
- errors.md v0.4 — Error specification
- model.md — Conceptual system model

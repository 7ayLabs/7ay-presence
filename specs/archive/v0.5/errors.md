# Errors Spec v0.5
> Custom errors only. No revert strings.

## Epoch Errors (v0.5 Extended)

### createEpochWithCapability Priority Order

| Priority | Error | Condition |
|----------|-------|-----------|
| 1 | `InvalidEpochId()` | `epochId == 0` |
| 2 | `EpochAlreadyExists(epochId)` | `epochs[epochId].exists` |
| 3 | `InvalidEpochBounds(start, end)` | `start >= end` |
| 4 | `InvalidCapability()` | `capability > 2` |
| 5 | `InvalidDataPolicyHash()` | `capability == PresenceWithEphemeralData && hash == 0` |
| 6 | `UnauthorizedEpochAuthority(caller, auth)` | `caller != authority` |

### All Epoch Errors

| Error | Condition |
|-------|-----------|
| `InvalidEpochId()` | `epochId == 0` |
| `EpochAlreadyExists(epochId)` | `epochs[epochId].exists` |
| `EpochNotFound(epochId)` | `!epochs[epochId].exists` |
| `EpochNotActive(epochId)` | `state != Active` |
| `EpochAlreadyFinalized(epochId)` | `epochs[epochId].finalized` |
| `InvalidEpochBounds(start, end)` | `start >= end` |
| `UnauthorizedEpochAuthority(caller, auth)` | `caller != authority` |
| `EpochNotClosed(epochId, state)` | `state != Closed` |
| `InvalidEpochAuthority()` | `authority == 0x0` |
| `InvalidCapability()` | `capability > PresenceWithEphemeralData` |
| `InvalidDataPolicyHash()` | hash required but 0 |

## Presence Errors (unchanged from v0.4)

| Error | Condition | Priority |
|-------|-----------|----------|
| `InvalidActor()` | `actor == 0x0` | 1 |
| `UnauthorizedActor(caller, actor)` | `caller != actor` | 2 |
| `InvalidEpoch(epochId)` | `epochId == 0` | 3 |
| `PresenceSlashed(actor, epochId)` | `state == Slashed` | 4 |
| `EpochNotActive(epochId)` | `!isEpochActive(epochId)` | 5 |
| `CallerNotValidator(caller)` | `!isValidatorActive(caller)` | 6 |
| `InvalidPresenceState(actor, epochId, current, expected)` | wrong state | 7 |
| `ValidatorAlreadyVoted(validator, actor, epochId)` | double vote | 8 |
| `PresenceNotFinalizable(actor, epochId)` | cannot finalize | 9 |

## Dispute Errors (unchanged from v0.4)

| Error | Condition | Priority |
|-------|-----------|----------|
| `InvalidActor()` | `actor == 0x0` | 1 |
| `InvalidEpoch(epochId)` | `epochId == 0` | 2 |
| `PresenceSlashed(actor, epochId)` | already slashed | 3 |
| `DisputeAlreadyExists(actor, epochId)` | pending dispute | 4 |
| `DisputeNotFound(actor, epochId)` | no dispute | 5 |
| `DisputeWindowClosed(epochId)` | past window | 6 |
| `CallerNotValidator(caller)` | non-validator | 7 |
| `ValidatorAlreadyVotedOnDispute(validator, actor, epochId)` | double vote | 8 |
| `DisputeNotPending(actor, epochId)` | wrong status | 9 |

## Validator Errors (unchanged from v0.4)

| Error | Condition | Priority |
|-------|-----------|----------|
| `InvalidValidator()` | `validator == 0x0` | 1 |
| `UnauthorizedValidatorAuthority(caller, authority)` | `caller != authority` | 2 |
| `ValidatorAlreadyExists(validator)` | already registered | 3 |
| `ValidatorNotFound(validator)` | not registered | 4 |
| `ValidatorNotActive(validator)` | not active | 5 |
| `InsufficientValidators(current, required)` | below minimum | 6 |
| `InvalidQuorumThreshold(threshold)` | out of range | 7 |

## Registry Errors (unchanged from v0.4)

| Error | Condition |
|-------|-----------|
| `InvalidEpochRegistry()` | `epochRegistry == 0x0` |
| `InvalidValidatorRegistry()` | `validatorRegistry == 0x0` |

## New Error Definitions (v0.5)

### Epoch Capability

```solidity
/// @notice Raised when capability value is invalid (> 2)
error InvalidCapability();

/// @notice Raised when data policy hash is required but not provided
/// @dev Required only when capability == PresenceWithEphemeralData
error InvalidDataPolicyHash();
```

## Error Definitions (v0.4, preserved)

### Presence

```solidity
error InvalidActor();
error UnauthorizedActor(address caller, address actor);
error InvalidEpoch(uint256 epochId);
error PresenceSlashed(address actor, uint256 epochId);
error EpochNotActive(uint256 epochId);
error CallerNotValidator(address caller);
error InvalidPresenceState(
    address actor,
    uint256 epochId,
    PresenceState current,
    PresenceState expected
);
error ValidatorAlreadyVoted(address validator, address actor, uint256 epochId);
error PresenceNotFinalizable(address actor, uint256 epochId);
```

### Dispute

```solidity
error DisputeAlreadyExists(address actor, uint256 epochId);
error DisputeNotFound(address actor, uint256 epochId);
error DisputeWindowClosed(uint256 epochId);
error ValidatorAlreadyVotedOnDispute(address validator, address actor, uint256 epochId);
error DisputeNotPending(address actor, uint256 epochId);
```

### Validator

```solidity
error InvalidValidator();
error UnauthorizedValidatorAuthority(address caller, address authority);
error ValidatorAlreadyExists(address validator);
error ValidatorNotFound(address validator);
error ValidatorNotActive(address validator);
error InsufficientValidators(uint256 current, uint256 required);
error InvalidQuorumThreshold(uint256 threshold);
error InvalidValidatorAuthority();
```

### Epoch

```solidity
error InvalidEpochId();
error EpochAlreadyExists(uint256 epochId);
error EpochNotFound(uint256 epochId);
error EpochNotActive(uint256 epochId);
error EpochAlreadyFinalized(uint256 epochId);
error InvalidEpochBounds(uint256 startTime, uint256 endTime);
error UnauthorizedEpochAuthority(address caller, address authority);
error EpochNotClosed(uint256 epochId, EpochState currentState);
error InvalidEpochAuthority();
// v0.5 additions
error InvalidCapability();
error InvalidDataPolicyHash();
```

## Rules

- Check order = priority order (inline, no modifiers)
- Idempotent ops -> no error, silent return
- Custom errors -> gas efficient
- Errors include context parameters
- v0.5: InvalidCapability before InvalidDataPolicyHash before UnauthorizedEpochAuthority

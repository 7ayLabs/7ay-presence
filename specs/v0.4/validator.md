# 7ay Proof of Presence (PoP)
## Protocol Specification — Validator
**Version:** v0.4
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** epoch.md v0.2

---

## 1. Purpose

This specification defines the canonical rules for validator management
in the Proof of Presence protocol.

Validators are the trust anchors that validate presence claims.
Without validators, presence assertions cannot reach consensus.

This specification formalizes:
- What a validator IS
- How validators are managed
- What invariants validators MUST maintain
- How validators relate to presence validation

Implementations MUST follow this specification to be considered compliant.

---

## 2. Definitions

### 2.1 Validator

A **Validator** is an address authorized to validate presence claims
within the protocol.

A validator:
- Has a unique address
- Is registered by the validator authority
- Can vote on presence validation
- Can vote on disputes

### 2.2 Validator Authority

The **Validator Authority** is the address authorized to manage the
validator set.

Constraints:
- Single authority manages all validators
- Authority address MUST NOT be zero
- Only authority can add/remove validators

### 2.3 Quorum

A **Quorum** is the minimum number of validator votes required for
consensus.

```
quorumSize = ceil(activeValidatorCount * quorumThreshold / 100)
```

Constraints:
- `quorumThreshold` is a percentage (1-100)
- `quorumSize >= 1` always
- Quorum must be achievable with current validators

### 2.4 Minimum Validators

The protocol requires a minimum number of active validators.

Constraints:
- `minimumValidators >= 1`
- Cannot remove validators below minimum

---

## 3. Validator States

A validator MUST be in exactly one of the following states:

### 3.1 None

The validator has never been registered.

```
validator address has no record
```

Properties:
- No storage allocated
- Cannot validate presences
- Can transition to: `Active`

### 3.2 Active

The validator is currently authorized to validate.

```
validator.status == Active
```

Properties:
- Can vote on presence validation
- Can vote on disputes
- Can transition to: `Removed`

### 3.3 Removed

The validator was previously active but is now removed.

```
validator.status == Removed
```

Properties:
- Cannot validate presences
- Cannot vote on disputes
- Terminal state (cannot return to Active)

---

## 4. Validator Lifecycle

### 4.1 State Transition Diagram

```
                    addValidator()
        None ─────────────────────► Active
                                       │
                                       │ removeValidator()
                                       ▼
                                    Removed
```

### 4.2 State Transition Table

| From | To | Trigger | Conditions | Event |
|------|-----|---------|------------|-------|
| None | Active | `addValidator()` | Authority, valid address | `ValidatorAdded` |
| Active | Removed | `removeValidator()` | Authority, above minimum | `ValidatorRemoved` |

### 4.3 Add Validator Rules

A validator MAY be added if and only if:
1. `validator != 0x0`
2. Validator does not already exist (status == None)
3. Caller is the validator authority

### 4.4 Remove Validator Rules

A validator MAY be removed if and only if:
1. `validator != 0x0`
2. Validator is currently Active
3. `activeValidatorCount - 1 >= minimumValidators`
4. Caller is the validator authority

---

## 5. Quorum Mechanics

### 5.1 Quorum Calculation

```solidity
function quorumSize() returns (uint256) {
    uint256 count = activeValidatorCount;
    if (count == 0) return 1;
    return (count * quorumThreshold + 99) / 100; // ceil division
}
```

### 5.2 Quorum Threshold

- Default: 67 (67% majority)
- Range: 1-100
- Only authority can modify

### 5.3 Quorum Examples

| Active Validators | Threshold | Quorum Size |
|-------------------|-----------|-------------|
| 3 | 67% | 2 |
| 5 | 67% | 4 |
| 10 | 67% | 7 |
| 3 | 51% | 2 |
| 5 | 51% | 3 |

---

## 6. Functions

### 6.1 Read Operations

```solidity
function validatorAuthority() external view returns (address);
function quorumThreshold() external view returns (uint256);
function minimumValidators() external view returns (uint256);
function validatorStatus(address validator) external view returns (ValidatorStatus);
function isValidatorActive(address validator) external view returns (bool);
function activeValidatorCount() external view returns (uint256);
function getActiveValidators() external view returns (address[] memory);
function quorumSize() external view returns (uint256);
```

### 6.2 Write Operations

```solidity
function addValidator(address validator) external;
function removeValidator(address validator) external;
function setQuorumThreshold(uint256 threshold) external;
```

---

## 7. Events

### 7.1 ValidatorAdded

Emitted when a validator is registered.

```solidity
event ValidatorAdded(address indexed validator, uint256 timestamp);
```

### 7.2 ValidatorRemoved

Emitted when a validator is removed.

```solidity
event ValidatorRemoved(address indexed validator, uint256 timestamp);
```

### 7.3 QuorumThresholdUpdated

Emitted when quorum threshold changes.

```solidity
event QuorumThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
```

---

## 8. Errors

### 8.1 InvalidValidator

Raised when validator address is zero.

```solidity
error InvalidValidator();
```

### 8.2 UnauthorizedValidatorAuthority

Raised when caller is not the validator authority.

```solidity
error UnauthorizedValidatorAuthority(address caller, address authority);
```

### 8.3 ValidatorAlreadyExists

Raised when adding an already existing validator.

```solidity
error ValidatorAlreadyExists(address validator);
```

### 8.4 ValidatorNotFound

Raised when referencing a non-existent validator.

```solidity
error ValidatorNotFound(address validator);
```

### 8.5 ValidatorNotActive

Raised when operating on an inactive validator.

```solidity
error ValidatorNotActive(address validator);
```

### 8.6 InsufficientValidators

Raised when removal would drop below minimum.

```solidity
error InsufficientValidators(uint256 current, uint256 required);
```

### 8.7 InvalidValidatorAuthority

Raised when authority address is zero.

```solidity
error InvalidValidatorAuthority();
```

### 8.8 InvalidQuorumThreshold

Raised when threshold is out of range.

```solidity
error InvalidQuorumThreshold(uint256 threshold);
```

---

## 9. Invariants

The following invariants MUST NEVER be violated:

### 9.1 Validator Invariants

1. **Uniqueness**: Each address maps to at most one validator record.
2. **Authority Exclusivity**: Only authority can add/remove validators.
3. **Minimum Threshold**: `activeValidatorCount >= minimumValidators` always.
4. **Status Monotonicity**: Once Removed, cannot become Active again.
5. **Zero Reserved**: `address(0)` MUST NOT be a validator.

### 9.2 Quorum Invariants

6. **Achievable Quorum**: `quorumSize <= activeValidatorCount` always.
7. **Non-Zero Quorum**: `quorumSize >= 1` always.
8. **Valid Threshold**: `1 <= quorumThreshold <= 100` always.

---

## 10. Storage

```solidity
address public immutable validatorAuthority;
uint256 public quorumThreshold;          // 1-100
uint256 public constant minimumValidators = 3;

mapping(address => Validator) private _validators;
address[] private _validatorList;
uint256 private _activeValidatorCount;
```

---

## 11. Determinism

Given the same inputs, all compliant implementations MUST:
- Compute the same quorum size
- Return the same validator status
- Maintain consistent active validator count

---

## 12. Configuration

| Parameter | Default | Range | Mutable |
|-----------|---------|-------|---------|
| `quorumThreshold` | 67 | 1-100 | Yes (authority) |
| `minimumValidators` | 3 | 1+ | No (constant) |

---

## 13. Compliance

An implementation is considered compliant if and only if:
- All Validator Invariants (9.1) hold
- All Quorum Invariants (9.2) hold
- All required events are emitted correctly
- All error conditions are handled per specification

---

## 14. Versioning

| Version | Changes |
|---------|---------|
| v0.4 | Initial validator specification |

---

## 15. References

- presence.md v0.4 — Enhanced presence specification
- epoch.md v0.2 — Epoch specification
- model.md — Conceptual system model

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

```rust
pub fn quorum_size(&self) -> u32 {
    let count = self.active_validator_count;
    if count == 0 { return 1; }
    (count * self.quorum_threshold + 99) / 100  // ceil division
}
```

### 5.2 Quorum Threshold

- Default: 67 (67% majority)
- Range: 1-100
- Only authority can modify

### 5.3 Quorum Examples

| Active Validators | Threshold | Quorum Size |
|-------------------|-----------|-------------|
| 3 | 67% | 3 |
| 5 | 67% | 4 |
| 10 | 67% | 7 |
| 3 | 51% | 2 |
| 5 | 51% | 3 |

---

## 6. Functions

### 6.1 Read Operations

```rust
pub trait ValidatorRegistry {
    fn validator_authority(&self) -> AccountId;
    fn quorum_threshold(&self) -> u8;
    fn minimum_validators(&self) -> u32;
    fn validator_status(&self, validator: AccountId) -> ValidatorStatus;
    fn is_validator_active(&self, validator: AccountId) -> bool;
    fn active_validator_count(&self) -> u32;
    fn get_active_validators(&self) -> Vec<AccountId>;
    fn quorum_size(&self) -> u32;
}
```

### 6.2 Write Operations

```rust
impl ValidatorRegistry {
    pub fn add_validator(&mut self, validator: AccountId) -> Result<(), Error>;
    pub fn remove_validator(&mut self, validator: AccountId) -> Result<(), Error>;
    pub fn set_quorum_threshold(&mut self, threshold: u8) -> Result<(), Error>;
}
```

---

## 7. Events

### 7.1 ValidatorAdded

Emitted when a validator is registered.

```rust
pub struct ValidatorAdded { pub validator: AccountId, pub timestamp: u64 }
```

### 7.2 ValidatorRemoved

Emitted when a validator is removed.

```rust
pub struct ValidatorRemoved { pub validator: AccountId, pub timestamp: u64 }
```

### 7.3 QuorumThresholdUpdated

Emitted when quorum threshold changes.

```rust
pub struct QuorumThresholdUpdated { pub old_threshold: u8, pub new_threshold: u8 }
```

---

## 8. Errors

### 8.1 InvalidValidator

Raised when validator address is zero.

```rust
InvalidValidator
```

### 8.2 UnauthorizedValidatorAuthority

Raised when caller is not the validator authority.

```rust
UnauthorizedValidatorAuthority { caller: AccountId, authority: AccountId }
```

### 8.3 ValidatorAlreadyExists

Raised when adding an already existing validator.

```rust
ValidatorAlreadyExists { validator: AccountId }
```

### 8.4 ValidatorNotFound

Raised when referencing a non-existent validator.

```rust
ValidatorNotFound { validator: AccountId }
```

### 8.5 ValidatorNotActive

Raised when operating on an inactive validator.

```rust
ValidatorNotActive { validator: AccountId }
```

### 8.6 InsufficientValidators

Raised when removal would drop below minimum.

```rust
InsufficientValidators { current: u32, required: u32 }
```

### 8.7 InvalidValidatorAuthority

Raised when authority address is zero.

```rust
InvalidValidatorAuthority
```

### 8.8 InvalidQuorumThreshold

Raised when threshold is out of range.

```rust
InvalidQuorumThreshold { threshold: u8 }
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

```rust
pub struct Storage {
    pub validator_authority: AccountId,
    pub quorum_threshold: u8,            // 1-100
    pub const MINIMUM_VALIDATORS: u32 = 3;

    validators: BTreeMap<AccountId, Validator>,
    validator_list: Vec<AccountId>,
    active_validator_count: u32,
}
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

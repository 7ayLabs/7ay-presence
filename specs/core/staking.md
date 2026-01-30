# 7ay Proof of Presence (PoP)
## Protocol Specification — Validator Staking
**Version:** v0.7.0
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** validators.md v0.4, disputes.md v0.4
**RFC:** RFC-0001

---

## 1. Purpose

This specification defines the validator staking mechanism for the 7ay Presence Protocol. Staking provides economic security by requiring validators to bond tokens that can be slashed for misbehavior.

This specification defines:
- Staking requirements and limits
- Slashing conditions and penalties
- Evidence rewards
- Cooldown periods
- Stake concentration limits

---

## 2. Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Stake Storage | **On-chain** | Validator stakes in `pallet-validators` |
| Slashing Logic | **On-chain** | Slash calculations in `pallet-validators` |
| Evidence Submission | **On-chain** | Evidence stored in `pallet-disputes` |
| Cooldown Tracking | **On-chain** | Timestamps in validator storage |
| Concentration Limits | **On-chain** | Enforced on stake operations |

---

## 3. Constants

```rust
/// Minimum stake required to become a validator
pub const MINIMUM_VALIDATOR_STAKE: u128 = 10_000 * UNITS;

/// Maximum stake that counts towards voting power
pub const MAXIMUM_EFFECTIVE_STAKE: u128 = 100_000 * UNITS;

/// Maximum percentage of total stake per validator
pub const MAX_STAKE_CONCENTRATION: u8 = 33;

/// Evidence reward as percentage of slash amount
pub const EVIDENCE_REWARD_PERCENT: u8 = 10;

/// Maximum evidence reward
pub const MAXIMUM_EVIDENCE_REWARD: u128 = 1_000 * UNITS;

/// Cooldown for voluntary removal
pub const VOLUNTARY_REMOVAL_COOLDOWN: u64 = 7 * 24 * 3600;  // 7 days

/// Cooldown for stake reduction
pub const STAKE_REDUCTION_COOLDOWN: u64 = 14 * 24 * 3600;   // 14 days

/// Cooldown for full unstake
pub const FULL_UNSTAKE_COOLDOWN: u64 = 28 * 24 * 3600;      // 28 days
```

---

## 4. Staking Operations

### 4.1 Stake Registration

```rust
pub fn stake(
    validator: AccountId,
    amount: Balance,
) -> Result<(), Error> {
    // 1. Validate minimum stake
    ensure!(amount >= MINIMUM_VALIDATOR_STAKE, Error::InsufficientStake);

    // 2. Check concentration limit
    let new_total = TotalStake::get() + amount;
    let concentration = amount * 100 / new_total;
    ensure!(concentration <= MAX_STAKE_CONCENTRATION, Error::StakeConcentrationExceeded);

    // 3. Lock tokens
    Currency::reserve(&validator, amount)?;

    // 4. Update storage
    Validators::<T>::mutate(&validator, |info| {
        info.stake = info.stake.saturating_add(amount);
        info.stake_updated_at = frame_system::Pallet::<T>::block_number();
    });
    TotalStake::mutate(|total| *total = total.saturating_add(amount));

    // 5. Emit event
    Self::deposit_event(Event::ValidatorStakeUpdated {
        who: validator,
        new_stake: amount,
    });

    Ok(())
}
```

### 4.2 Stake Increase

Validators can increase stake at any time:

```rust
pub fn increase_stake(
    validator: AccountId,
    additional: Balance,
) -> Result<(), Error> {
    let info = Validators::<T>::get(&validator)?;
    ensure!(info.status == ValidatorStatus::Active, Error::ValidatorNotActive);

    let new_stake = info.stake.saturating_add(additional);

    // Check concentration
    let new_total = TotalStake::get() + additional;
    let concentration = new_stake * 100 / new_total;
    ensure!(concentration <= MAX_STAKE_CONCENTRATION, Error::StakeConcentrationExceeded);

    // Lock additional tokens
    Currency::reserve(&validator, additional)?;

    // Update storage
    Validators::<T>::mutate(&validator, |info| {
        info.stake = new_stake;
        info.stake_updated_at = frame_system::Pallet::<T>::block_number();
    });
    TotalStake::mutate(|total| *total = total.saturating_add(additional));

    Ok(())
}
```

### 4.3 Stake Reduction (with Cooldown)

```rust
pub fn request_stake_reduction(
    validator: AccountId,
    reduction: Balance,
) -> Result<(), Error> {
    let info = Validators::<T>::get(&validator)?;

    // Check remaining stake meets minimum
    let remaining = info.stake.saturating_sub(reduction);
    ensure!(remaining >= MINIMUM_VALIDATOR_STAKE, Error::InsufficientStake);

    // Create pending reduction with cooldown
    PendingReductions::<T>::insert(&validator, PendingReduction {
        amount: reduction,
        available_at: now() + STAKE_REDUCTION_COOLDOWN,
    });

    Ok(())
}

pub fn execute_stake_reduction(validator: AccountId) -> Result<(), Error> {
    let pending = PendingReductions::<T>::get(&validator)?;
    ensure!(now() >= pending.available_at, Error::CooldownActive);

    // Unreserve tokens
    Currency::unreserve(&validator, pending.amount);

    // Update storage
    Validators::<T>::mutate(&validator, |info| {
        info.stake = info.stake.saturating_sub(pending.amount);
    });
    TotalStake::mutate(|total| *total = total.saturating_sub(pending.amount));
    PendingReductions::<T>::remove(&validator);

    Ok(())
}
```

---

## 5. Slashing

### 5.1 Slash Reasons

```rust
pub enum SlashReason {
    /// Validated presence that was disputed and upheld
    InvalidValidation,

    /// Failed to destroy epoch key share
    KeyShareRetention,

    /// Submitted conflicting votes
    DoubleVoting,

    /// Proven coordination to defraud
    Collusion,

    /// Offline for extended period
    ExtendedDowntime,
}
```

### 5.2 Slash Percentages

| Reason | Base % | Max % | Severity Scale |
|--------|--------|-------|----------------|
| InvalidValidation | 1% | 5% | 1-10 |
| KeyShareRetention | 10% | 50% | 1-10 |
| DoubleVoting | 20% | 100% | 1-10 |
| Collusion | 100% | 100% | N/A |
| ExtendedDowntime | 0.1%/epoch | 10% | Epochs missed |

### 5.3 Slash Calculation

```rust
pub fn calculate_slash(
    reason: SlashReason,
    stake: Balance,
    severity: u8,
) -> Balance {
    let (base, max) = match reason {
        SlashReason::InvalidValidation => (1, 5),
        SlashReason::KeyShareRetention => (10, 50),
        SlashReason::DoubleVoting => (20, 100),
        SlashReason::Collusion => (100, 100),
        SlashReason::ExtendedDowntime => (1, 10),
    };

    // Linear interpolation based on severity
    let severity = severity.min(10);
    let percent = base + ((max - base) * severity as u32 / 10);

    stake * percent as u128 / 100
}
```

### 5.4 Slash Execution

```rust
pub fn slash(
    validator: AccountId,
    reason: SlashReason,
    evidence_provider: Option<AccountId>,
    severity: u8,
) -> Result<Balance, Error> {
    let info = Validators::<T>::get(&validator)?;

    // Calculate slash amount
    let slash_amount = calculate_slash(reason, info.stake, severity);

    // Ensure we don't slash more than available
    let actual_slash = slash_amount.min(info.stake);

    // Slash from reserved balance
    let (_, slashed) = Currency::slash_reserved(&validator, actual_slash);

    // Update validator info
    Validators::<T>::mutate(&validator, |info| {
        info.stake = info.stake.saturating_sub(slashed);
        info.slashed_total = info.slashed_total.saturating_add(slashed);
    });
    TotalStake::mutate(|total| *total = total.saturating_sub(slashed));

    // Distribute evidence reward
    if let Some(provider) = evidence_provider {
        let reward = calculate_evidence_reward(slashed);
        Currency::deposit(&provider, reward)?;

        Self::deposit_event(Event::EvidenceRewarded {
            provider,
            amount: reward,
        });
    }

    // Check if validator should be removed
    if info.stake.saturating_sub(slashed) < MINIMUM_VALIDATOR_STAKE {
        Self::force_remove_validator(&validator)?;
    }

    Self::deposit_event(Event::ValidatorSlashed {
        who: validator,
        amount: slashed,
        reason,
    });

    Ok(slashed)
}
```

---

## 6. Evidence Rewards

### 6.1 Reward Calculation

```rust
pub fn calculate_evidence_reward(slash_amount: Balance) -> Balance {
    let reward = slash_amount * EVIDENCE_REWARD_PERCENT as u128 / 100;
    reward.min(MAXIMUM_EVIDENCE_REWARD)
}
```

### 6.2 Eligible Evidence Providers

Evidence reward eligibility:
- Dispute initiator (if dispute upheld)
- First reporter of double voting
- First reporter of key retention violation
- First reporter of collusion (with cryptographic proof)

### 6.3 Evidence Requirements

| Slash Reason | Required Evidence |
|--------------|-------------------|
| InvalidValidation | Upheld dispute record |
| KeyShareRetention | Missing KeyShareDestroyed attestation after deadline |
| DoubleVoting | Two conflicting signed votes for same presence |
| Collusion | Multi-party signed agreement or coordinated transactions |
| ExtendedDowntime | Epoch participation records showing N consecutive misses |

---

## 7. Cooldown Periods

### 7.1 Cooldown Types

| Operation | Duration | Purpose |
|-----------|----------|---------|
| Voluntary removal | 7 days | Prevent exit during investigation |
| Stake reduction | 14 days | Allow slash before withdrawal |
| Full unstake | 28 days | Maximum protection window |
| Recovery from suspension | 7 days | Investigation period |

### 7.2 Cooldown State

```rust
pub struct CooldownState {
    pub operation: CooldownOperation,
    pub initiated_at: Timestamp,
    pub available_at: Timestamp,
}

pub enum CooldownOperation {
    VoluntaryRemoval,
    StakeReduction { amount: Balance },
    FullUnstake,
    SuspensionRecovery,
}
```

### 7.3 Cooldown Enforcement

```rust
pub fn check_cooldown(
    validator: &AccountId,
    operation: CooldownOperation,
) -> Result<(), Error> {
    if let Some(cooldown) = Cooldowns::<T>::get(validator) {
        ensure!(now() >= cooldown.available_at, Error::CooldownActive);
    }
    Ok(())
}
```

---

## 8. Stake Concentration

### 8.1 Concentration Limit

No single validator may hold more than 33% of total staked tokens:

```
∀ validator v:
  stake(v) / Σ stake(all_validators) <= 0.33
```

### 8.2 Enforcement Points

Concentration is checked on:
1. Initial stake registration
2. Stake increase
3. After another validator's stake reduction

### 8.3 Edge Cases

**Scenario: Concentration exceeded due to other validator's removal**

```rust
// Validator A: 30,000 (30%)
// Validator B: 30,000 (30%)
// Validator C: 40,000 (40%) — blocked, exceeds 33%

// If B is removed:
// A: 30,000 (42.8%) — now exceeds limit

// Resolution: A cannot increase stake until they reduce below 33%
// A is NOT forcibly slashed, but stake operations are blocked
```

---

## 9. Events

```rust
pub enum Event<T: Config> {
    /// Validator staked tokens
    ValidatorStaked {
        who: T::AccountId,
        amount: T::Balance,
    },

    /// Validator increased stake
    StakeIncreased {
        who: T::AccountId,
        additional: T::Balance,
        new_total: T::Balance,
    },

    /// Stake reduction requested
    StakeReductionRequested {
        who: T::AccountId,
        amount: T::Balance,
        available_at: T::BlockNumber,
    },

    /// Stake reduction executed
    StakeReductionExecuted {
        who: T::AccountId,
        amount: T::Balance,
    },

    /// Validator slashed
    ValidatorSlashed {
        who: T::AccountId,
        amount: T::Balance,
        reason: SlashReason,
    },

    /// Evidence reward paid
    EvidenceRewarded {
        provider: T::AccountId,
        amount: T::Balance,
    },

    /// Cooldown started
    CooldownStarted {
        who: T::AccountId,
        operation: CooldownOperation,
        available_at: T::BlockNumber,
    },
}
```

---

## 10. Invariants

### INV47: Stake Concentration Limit

```
∀ validator v where status = Active:
  stake(v) / total_stake <= MAX_STAKE_CONCENTRATION / 100
```

### INV48: Slashing Proportionality

```
∀ slash_event(v, reason, amount):
  amount <= stake(v) * max_slash_percent(reason) / 100
```

### INV49: Evidence Reward Cap

```
∀ evidence_reward(provider, slash_amount):
  reward = min(slash_amount * EVIDENCE_REWARD_PERCENT / 100, MAXIMUM_EVIDENCE_REWARD)
```

---

## 11. Error Codes

| Code | Name | Description |
|------|------|-------------|
| STAKE_001 | InsufficientStake | Stake below minimum |
| STAKE_002 | StakeConcentrationExceeded | Would exceed 33% |
| STAKE_003 | CooldownActive | Operation during cooldown |
| STAKE_004 | NoPendingReduction | No reduction to execute |
| STAKE_005 | SlashExceedsStake | Slash > available stake |
| STAKE_006 | InvalidEvidence | Evidence requirements not met |
| STAKE_007 | EvidenceAlreadySubmitted | Duplicate evidence |

---

## 12. References

- [RFC-0001](../rfcs/0001-validator-security-model.md) — Validator Security Model
- [validators.md](validators.md) — Validator registry
- [disputes.md](disputes.md) — Dispute resolution
- [invariants.md](../reference/invariants.md) — Protocol invariants

---

## 13. Changelog

| Version | Changes |
|---------|---------|
| v0.7.0 | Initial staking specification (RFC-0001) |

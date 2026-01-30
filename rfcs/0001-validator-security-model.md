# RFC-0001: Validator Security Model

| Field | Value |
|-------|-------|
| **RFC** | 0001 |
| **Title** | Validator Security Model with Economic Incentives |
| **Author** | 7ayLabs Security Council |
| **Status** | Draft |
| **Created** | 2026-01-29 |
| **Updated** | 2026-01-29 |
| **Requires** | None |
| **Supersedes** | None |

---

## Abstract

This RFC defines a comprehensive validator security model for the 7ay Presence Protocol, addressing critical vulnerabilities in the current v0.6.9 specification. It increases the minimum validator count from 3 to 5, introduces mandatory staking requirements, defines graduated slashing penalties, establishes evidence rewards for dispute initiators, and specifies cooldown periods for validator operations. These changes transform the protocol from a trust-based system to an economically-secured consensus mechanism suitable for production deployment.

---

## Motivation

### Problem Statement

The current validator model (v0.4) has critical security gaps:

1. **Insufficient Validator Count**: With `MINIMUM_VALIDATORS = 3` and `quorumThreshold = 67%`, only 2 validators are needed for consensus. A single compromised validator plus one colluding validator can control the entire network.

2. **No Economic Security**: Validators have no stake in the system. Misbehavior carries no financial penalty, creating no deterrent against malicious actions.

3. **No Slashing Amounts**: While the dispute mechanism can mark presence as "Slashed," there are no actual penalties applied to validators who vote incorrectly or maliciously.

4. **No Recovery Mechanism**: If validators go offline or are compromised, there's no defined path to restore network operation.

### Security Analysis

**Attack Scenario — 3 Validator Quorum:**
```
Validators: A, B, C
Quorum: ceil(3 * 0.67) = 2

If attacker controls A and B:
- Can finalize any presence claim
- Can reject all disputes
- Can collude on key retention
- Network is fully compromised
```

**Attack Cost (Current):** Zero economic cost
**Attack Cost (Proposed):** Minimum 20,000 UNITS staked, subject to 100% slashing

### Goals

1. Increase validator security through higher minimum count (5 validators)
2. Introduce economic security through mandatory staking
3. Define explicit slashing penalties for validator misbehavior
4. Establish evidence rewards to incentivize dispute reporting
5. Specify cooldown periods to prevent rapid validator churn
6. Add stake concentration limits to prevent centralization

### Non-Goals

1. Token economics beyond validator staking (distribution, inflation)
2. Delegation mechanisms (staking pools)
3. Validator selection algorithms (PoS vs DPoS)
4. Cross-chain validator sets
5. Governance token mechanics

---

## Specification

### Overview

This RFC introduces four interconnected components:

1. **Validator Count Constraints** — Minimum 5 active validators
2. **Staking Requirements** — Minimum stake to become/remain a validator
3. **Slashing Penalties** — Graduated penalties for different violations
4. **Cooldown Periods** — Time delays for validator operations

### Detailed Design

#### Constants

```rust
/// Minimum number of active validators required for network operation
pub const MINIMUM_VALIDATORS: u32 = 5;

/// Recommended number of validators for production networks
pub const RECOMMENDED_VALIDATORS: u32 = 7;

/// Maximum percentage of total stake a single validator can hold
pub const MAX_STAKE_CONCENTRATION: u8 = 33;

/// Minimum stake required to register as a validator
pub const MINIMUM_VALIDATOR_STAKE: u128 = 10_000 * UNITS;

/// Maximum stake that counts towards voting power (soft cap)
pub const MAXIMUM_EFFECTIVE_STAKE: u128 = 100_000 * UNITS;

/// Percentage of slashed amount awarded to evidence provider
pub const EVIDENCE_REWARD_PERCENT: u8 = 10;

/// Maximum evidence reward regardless of slash amount
pub const MAXIMUM_EVIDENCE_REWARD: u128 = 1_000 * UNITS;
```

#### Data Structures

**ValidatorInfo (Updated)**

```rust
#[derive(Clone, Encode, Decode, TypeInfo, MaxEncodedLen)]
pub struct ValidatorInfo<AccountId, Balance, BlockNumber> {
    /// Validator account
    pub account: AccountId,

    /// Current status
    pub status: ValidatorStatus,

    /// Staked amount (NEW)
    pub stake: Balance,

    /// Block when stake was last modified (NEW)
    pub stake_updated_at: BlockNumber,

    /// Block when status was last modified
    pub status_updated_at: BlockNumber,

    /// Accumulated slashing amount (NEW)
    pub slashed_total: Balance,

    /// Number of successful validations (NEW)
    pub validations: u32,

    /// Number of disputed validations (NEW)
    pub disputes_against: u32,
}
```

**ValidatorStatus (Extended)**

```rust
#[derive(Clone, Copy, Encode, Decode, TypeInfo, MaxEncodedLen, PartialEq, Eq)]
pub enum ValidatorStatus {
    /// Never registered
    None = 0,

    /// Currently active and can validate
    Active = 1,

    /// Permanently removed (terminal)
    Removed = 2,

    /// Temporarily suspended pending investigation (NEW)
    Suspended = 3,

    /// In cooldown after voluntary removal request (NEW)
    Unbonding = 4,
}
```

**SlashReason (New)**

```rust
#[derive(Clone, Copy, Encode, Decode, TypeInfo, MaxEncodedLen)]
pub enum SlashReason {
    /// Voted to validate a presence that was later disputed and upheld
    InvalidValidation,

    /// Failed to destroy epoch key share within required window
    KeyShareRetention,

    /// Submitted conflicting votes for the same presence
    DoubleVoting,

    /// Proven coordination with other validators to defraud
    Collusion,

    /// Offline for extended period (missed N consecutive epochs)
    ExtendedDowntime,
}
```

#### Slashing Schedule

| Reason | Base Penalty | Max Penalty | Evidence Required |
|--------|--------------|-------------|-------------------|
| InvalidValidation | 1% of stake | 5% of stake | Upheld dispute |
| KeyShareRetention | 10% of stake | 50% of stake | Missing attestation |
| DoubleVoting | 20% of stake | 100% of stake | Conflicting signatures |
| Collusion | 100% of stake | 100% of stake | Cryptographic proof |
| ExtendedDowntime | 0.1% per epoch | 10% of stake | Missed epoch records |

**Slashing Calculation:**

```rust
pub fn calculate_slash_amount(
    reason: SlashReason,
    stake: Balance,
    severity: u8,  // 1-10 scale
) -> Balance {
    let (base_percent, max_percent) = match reason {
        SlashReason::InvalidValidation => (1, 5),
        SlashReason::KeyShareRetention => (10, 50),
        SlashReason::DoubleVoting => (20, 100),
        SlashReason::Collusion => (100, 100),
        SlashReason::ExtendedDowntime => (1, 10),
    };

    let percent = base_percent + ((max_percent - base_percent) * severity as u32 / 10);
    stake * percent as u128 / 100
}
```

#### Cooldown Periods

| Operation | Cooldown Duration | Rationale |
|-----------|-------------------|-----------|
| Voluntary removal | 7 days | Prevent rapid exit during attacks |
| Recovery from suspension | 7 days | Investigation period |
| Stake reduction | 14 days | Prevent stake withdrawal before slash |
| Full unstake | 28 days | Maximum protection period |

**Cooldown Implementation:**

```rust
pub const VOLUNTARY_REMOVAL_COOLDOWN: u64 = 7 * 24 * 3600;  // 7 days
pub const RECOVERY_COOLDOWN: u64 = 7 * 24 * 3600;           // 7 days
pub const STAKE_REDUCTION_COOLDOWN: u64 = 14 * 24 * 3600;   // 14 days
pub const FULL_UNSTAKE_COOLDOWN: u64 = 28 * 24 * 3600;      // 28 days
```

#### State Transitions

**Validator Status Transitions:**

```
                              ┌─────────────────────────────────┐
                              │                                 │
              stake >= MIN    │    voluntary_remove()           │
    None ─────────────────► Active ──────────────────────► Unbonding
                              │                                 │
                              │ suspend()                       │ cooldown
                              ▼                                 │ expires
                          Suspended ◄───────────────────────────┘
                              │                                 │
                              │ slash(100%) OR                  │
                              │ authority_remove()              │
                              ▼                                 │
                           Removed ◄────────────────────────────┘
                          (terminal)        unbond_complete()
```

#### Invariants

| Invariant | Description |
|-----------|-------------|
| INV46 | **Minimum Active Validators**: `count(validators where status = Active) >= 5` |
| INV47 | **Stake Concentration Limit**: `∀ validator v: stake(v) / total_stake <= 0.33` |
| INV48 | **Slashing Proportionality**: `slash_amount <= stake(v) * max_slash_percent(reason)` |
| INV49 | **Evidence Reward Cap**: `evidence_reward <= min(slash_amount * 0.10, 1000 * UNITS)` |

**Formal Definitions:**

```
INV46: Minimum Active Validators
∀ block b:
  count({v | validators[v].status = Active}) >= MINIMUM_VALIDATORS

INV47: Stake Concentration Limit
∀ validator v where status = Active:
  stake(v) / Σ(stake(all_active_validators)) <= MAX_STAKE_CONCENTRATION / 100

INV48: Slashing Proportionality
∀ slash_event(v, reason, amount):
  amount <= stake(v) * max_slash_percent(reason) / 100

INV49: Evidence Reward Cap
∀ evidence_reward(provider, slash_event):
  reward <= min(slash_event.amount * EVIDENCE_REWARD_PERCENT / 100, MAXIMUM_EVIDENCE_REWARD)
```

#### Error Conditions

| Code | Name | Description |
|------|------|-------------|
| VAL_010 | InsufficientStake | Stake below MINIMUM_VALIDATOR_STAKE |
| VAL_011 | StakeConcentrationExceeded | Would exceed MAX_STAKE_CONCENTRATION |
| VAL_012 | MinimumValidatorsViolation | Operation would reduce active validators below 5 |
| VAL_013 | CooldownActive | Operation attempted during cooldown period |
| VAL_014 | ValidatorSuspended | Operation not allowed while suspended |
| VAL_015 | SlashExceedsStake | Calculated slash exceeds available stake |
| SLASH_001 | InvalidSlashReason | Unrecognized slash reason |
| SLASH_002 | InsufficientEvidence | Evidence does not meet threshold |
| SLASH_003 | SlashAlreadyApplied | Duplicate slash attempt for same event |

### Examples

**Example 1: Validator Registration**

```rust
// Alice wants to become a validator
let stake_amount = 15_000 * UNITS;  // Above minimum

// Check concentration limit (assume 100,000 total staked)
// 15,000 / 115,000 = 13% < 33% ✓

validator_registry.register(alice, stake_amount)?;
// Result: ValidatorInfo { account: alice, status: Active, stake: 15_000 }
```

**Example 2: Slashing for Invalid Validation**

```rust
// Bob validated a presence that was disputed and upheld
// Severity: 5 (medium - first offense)

let slash_amount = calculate_slash_amount(
    SlashReason::InvalidValidation,
    bob.stake,  // 20,000 UNITS
    5           // severity
);
// slash_amount = 20,000 * (1 + (5-1)*4/10) / 100 = 20,000 * 2.6% = 520 UNITS

let evidence_reward = min(520 * 10 / 100, 1_000);
// evidence_reward = 52 UNITS (to dispute initiator)

validator_registry.slash(bob, SlashReason::InvalidValidation, slash_amount)?;
evidence_pool.reward(dispute_initiator, evidence_reward)?;
```

**Example 3: Prevented Removal (Minimum Validators)**

```rust
// Current active validators: [Alice, Bob, Carol, Dave, Eve] = 5

// Eve tries to voluntarily remove
validator_registry.request_removal(eve)?;
// Error: VAL_012 MinimumValidatorsViolation
// Cannot reduce below MINIMUM_VALIDATORS (5)
```

---

## Backwards Compatibility

### Impact Assessment

| Component | Impact | Migration Required |
|-----------|--------|-------------------|
| ValidatorRegistry | Breaking | Yes |
| ValidatorStatus enum | Breaking | Yes (ABI change) |
| ValidatorInfo struct | Breaking | Yes (storage migration) |
| Quorum calculation | Minor | No (logic unchanged) |
| Dispute resolution | Minor | Yes (add slashing) |

### Migration Path

1. **Phase 1: Announce** (Block N)
   - Emit `UpgradeScheduled` event
   - 7-day notice period

2. **Phase 2: Stake Collection** (Block N + 7 days)
   - Existing validators must stake minimum amount
   - 14-day window to comply
   - Non-compliant validators marked `Suspended`

3. **Phase 3: Enforcement** (Block N + 21 days)
   - `MINIMUM_VALIDATORS = 5` enforced
   - Slashing active
   - Suspended validators without stake → `Removed`

4. **Phase 4: Stabilization** (Block N + 28 days)
   - Full v0.7.0 rules in effect
   - Monitor for edge cases

---

## Security Considerations

### Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| Validator collusion | Medium | Critical | Stake concentration limits, slashing |
| Stake grinding | Low | Medium | Maximum effective stake cap |
| Slashing griefing | Medium | Medium | Evidence requirements, appeal process |
| Validator exodus | Low | High | Cooldown periods, minimum count |

### Mitigations

1. **Collusion Prevention**
   - 5 validators required for quorum (3-of-5)
   - 33% stake concentration limit
   - 100% slashing for proven collusion

2. **Stake Grinding Prevention**
   - Effective stake capped at 100,000 UNITS
   - Voting power scales sub-linearly above cap

3. **Griefing Prevention**
   - Evidence must be cryptographically verifiable
   - Dispute initiator must have presence (skin in game)
   - False accusation penalty (future RFC)

4. **Validator Exodus Prevention**
   - 7-28 day cooldown periods
   - Minimum validator count enforced
   - Economic incentive to remain (rewards in future RFC)

### Audit Requirements

- Formal verification of INV46-49
- Slashing calculation review
- State transition exhaustive testing
- Economic model simulation (10,000+ epochs)

---

## Alternatives Considered

### Alternative 1: Proof of Authority (PoA)

Maintain current trust-based model with vetted validators.

**Rejected because:**
- No economic security
- Single point of trust (authority)
- Not suitable for decentralized networks

### Alternative 2: Full Proof of Stake

Implement complete PoS with delegation, rewards, and inflation.

**Rejected because:**
- Scope creep (separate RFC needed for rewards)
- Requires token economics RFC
- Can be added incrementally in v0.7.1+

### Alternative 3: Higher Minimum (7 or 11 validators)

Require 7 or 11 validators instead of 5.

**Considered but deferred:**
- 5 is sufficient for testnets and early production
- Can increase via parameter upgrade later
- Lower barrier to entry for new networks

---

## Implementation Notes

### Substrate-Specific

```rust
// Storage
#[pallet::storage]
pub type Validators<T: Config> = StorageMap<
    _,
    Blake2_128Concat,
    T::AccountId,
    ValidatorInfo<T::AccountId, T::Balance, T::BlockNumber>,
>;

#[pallet::storage]
pub type TotalStake<T: Config> = StorageValue<_, T::Balance, ValueQuery>;

// Ensure minimum validators on removal
#[pallet::call]
impl<T: Config> Pallet<T> {
    pub fn request_removal(origin: OriginFor<T>) -> DispatchResult {
        let who = ensure_signed(origin)?;

        let active_count = Self::active_validator_count();
        ensure!(
            active_count > T::MinimumValidators::get(),
            Error::<T>::MinimumValidatorsViolation
        );

        // ... proceed with removal request
    }
}
```

### Events

```rust
#[pallet::event]
pub enum Event<T: Config> {
    ValidatorRegistered { who: T::AccountId, stake: T::Balance },
    ValidatorStakeUpdated { who: T::AccountId, old_stake: T::Balance, new_stake: T::Balance },
    ValidatorSuspended { who: T::AccountId, reason: SuspensionReason },
    ValidatorSlashed { who: T::AccountId, amount: T::Balance, reason: SlashReason },
    ValidatorRemoved { who: T::AccountId },
    EvidenceRewarded { provider: T::AccountId, amount: T::Balance },
}
```

---

## Open Questions

1. **Appeal Process**: Should validators have a mechanism to appeal slashing decisions? If so, what's the process and timeline?

2. **Reward Distribution**: This RFC defines penalties but not rewards. Should validator rewards be included here or in a separate RFC?

3. **Validator Rotation**: Should there be a maximum validator tenure to encourage rotation?

4. **Emergency Override**: In catastrophic scenarios (>50% validators slashed), should there be an emergency recovery mechanism?

---

## References

- [specs/core/validators.md](../specs/core/validators.md) — Current validator specification
- [specs/core/disputes.md](../specs/core/disputes.md) — Dispute resolution
- [specs/reference/invariants.md](../specs/reference/invariants.md) — Protocol invariants
- [Ethereum 2.0 Slashing Conditions](https://ethereum.org/en/developers/docs/consensus-mechanisms/pos/rewards-and-penalties/)
- [Cosmos Slashing Module](https://docs.cosmos.network/main/modules/slashing)

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-29 | 7ayLabs Security Council | Initial draft |

# RFC-0004: Validator Recovery and Protocol Governance

| Field | Value |
|-------|-------|
| **RFC** | 0004 |
| **Title** | Validator Recovery Mechanism and Protocol Upgrade Path |
| **Author** | 7ayLabs Security Council |
| **Status** | Draft |
| **Created** | 2026-01-29 |
| **Updated** | 2026-01-29 |
| **Requires** | RFC-0001 |
| **Supersedes** | None |

---

## Abstract

This RFC defines mechanisms for validator recovery and protocol upgrades in the 7ay Presence Protocol. It addresses two critical gaps: (1) what happens when validators go offline or need to be recovered, and (2) how the protocol evolves without hard forks. The proposal introduces validator suspension and recovery states, defines a multi-tiered upgrade mechanism with appropriate delays and quorums, and establishes emergency procedures for critical security situations.

---

## Motivation

### Problem Statement

The current protocol (v0.6.9) has no provisions for:

1. **Validator Recovery**: If validators go offline, there's no defined recovery path
2. **Protocol Upgrades**: No mechanism to upgrade parameters or protocol rules
3. **Emergency Response**: No fast-track for critical security fixes
4. **State Migration**: No versioned storage for upgrades

### Scenarios Requiring Recovery

| Scenario | Current Outcome | Proposed Outcome |
|----------|-----------------|------------------|
| Validator key compromise | Permanent removal | Suspend → Recover with new key |
| Extended downtime (maintenance) | No mechanism | Suspend → Resume |
| False positive slashing | Permanent | Appeal → Recover stake |
| Network partition | Undefined | Graceful degradation |

### Goals

1. Define validator suspension and recovery states
2. Establish protocol upgrade mechanism with tiered delays
3. Create emergency upgrade path for security fixes
4. Enable state migration for storage changes
5. Maintain network stability during transitions

### Non-Goals

1. Governance token mechanics
2. On-chain voting UI
3. Proposal discussion forums
4. Treasury management

---

## Specification

### Part 1: Validator Recovery

#### Extended Validator Status

```rust
#[derive(Clone, Copy, Encode, Decode, TypeInfo, MaxEncodedLen, PartialEq, Eq)]
pub enum ValidatorStatus {
    /// Never registered
    None = 0,

    /// Currently active and can validate
    Active = 1,

    /// Permanently removed (terminal, existing)
    Removed = 2,

    /// Temporarily suspended pending investigation (NEW)
    Suspended = 3,

    /// In cooldown after voluntary removal request (NEW)
    Unbonding = 4,

    /// Recovering from suspension (NEW)
    Recovering = 5,
}
```

#### State Transitions

```
                          stake()
            None ────────────────────► Active
                                          │
               ┌──────────────────────────┼──────────────────────────┐
               │                          │                          │
               │ voluntary_remove()       │ suspend()                │ slash(100%)
               ▼                          ▼                          │
          Unbonding              ◄──── Suspended                     │
               │                          │                          │
               │ 7 days                   │ recover()                │
               │                          ▼                          │
               │                     Recovering                      │
               │                          │                          │
               │                          │ 7 days                   │
               │                          │                          │
               ▼                          ▼                          ▼
           Removed ◄─────────────────── Active ◄──────────────── Removed
          (terminal)                  (restored)                (terminal)
```

#### Suspension Mechanism

```rust
pub struct SuspensionInfo<BlockNumber> {
    /// Reason for suspension
    pub reason: SuspensionReason,

    /// Block when suspended
    pub suspended_at: BlockNumber,

    /// Who initiated suspension
    pub suspended_by: SuspensionAuthority,

    /// Evidence reference (if applicable)
    pub evidence: Option<EvidenceRef>,
}

pub enum SuspensionReason {
    /// Validator requested temporary suspension (maintenance)
    VoluntaryMaintenance,

    /// Detected potential security issue
    SecurityInvestigation,

    /// Extended downtime (missed N epochs)
    ExtendedDowntime,

    /// Pending slashing review
    PendingSlashReview,
}

pub enum SuspensionAuthority {
    /// Validator suspended themselves
    SelfSuspension,

    /// Authority initiated suspension
    ValidatorAuthority,

    /// Automatic suspension (downtime threshold)
    Automatic,
}
```

#### Recovery Process

```rust
pub fn initiate_recovery(
    validator: &AccountId,
    new_key: Option<PublicKey>,
) -> Result<(), Error> {
    let info = Validators::<T>::get(validator)?;
    ensure!(info.status == ValidatorStatus::Suspended, Error::NotSuspended);

    // Require 80% of active validators to approve
    let required_votes = (active_validator_count() * 80 + 99) / 100;

    // Create recovery proposal
    RecoveryProposals::<T>::insert(validator, RecoveryProposal {
        validator: validator.clone(),
        new_key,
        votes_for: 0,
        votes_against: 0,
        required_votes,
        deadline: now() + RECOVERY_VOTING_PERIOD,
    });

    Ok(())
}

pub fn vote_recovery(
    voter: &AccountId,
    validator: &AccountId,
    approve: bool,
) -> Result<(), Error> {
    ensure!(is_active_validator(voter), Error::NotValidator);

    let mut proposal = RecoveryProposals::<T>::get(validator)?;
    ensure!(now() < proposal.deadline, Error::VotingClosed);
    ensure!(!has_voted(voter, &proposal), Error::AlreadyVoted);

    if approve {
        proposal.votes_for += 1;
    } else {
        proposal.votes_against += 1;
    }

    if proposal.votes_for >= proposal.required_votes {
        // Recovery approved
        execute_recovery(validator, proposal.new_key)?;
        RecoveryProposals::<T>::remove(validator);
    } else if proposal.votes_against > (active_validator_count() - proposal.required_votes) {
        // Recovery rejected (impossible to reach quorum)
        RecoveryProposals::<T>::remove(validator);
    } else {
        RecoveryProposals::<T>::insert(validator, proposal);
    }

    Ok(())
}

fn execute_recovery(
    validator: &AccountId,
    new_key: Option<PublicKey>,
) -> Result<(), Error> {
    Validators::<T>::mutate(validator, |info| {
        info.status = ValidatorStatus::Recovering;
        info.status_updated_at = frame_system::Pallet::<T>::block_number();
        if let Some(key) = new_key {
            info.public_key = key;
        }
    });

    // Schedule transition to Active after cooldown
    Scheduler::schedule(
        now() + RECOVERY_COOLDOWN,
        Call::complete_recovery { validator: validator.clone() },
    );

    Ok(())
}
```

#### Recovery Constants

```rust
/// Voting period for recovery proposals
pub const RECOVERY_VOTING_PERIOD: u64 = 3 * 24 * 3600;  // 3 days

/// Cooldown after recovery approval before becoming Active
pub const RECOVERY_COOLDOWN: u64 = 7 * 24 * 3600;  // 7 days

/// Required quorum for recovery (percentage of active validators)
pub const RECOVERY_QUORUM: u8 = 80;
```

---

### Part 2: Protocol Upgrades

#### Upgrade Types

```rust
pub enum UpgradeType {
    /// Parameter change (e.g., timeout values, thresholds)
    /// 48-hour delay, 67% quorum
    Parameter,

    /// Protocol logic change (e.g., new validation rules)
    /// 7-day delay, 80% quorum
    Protocol,

    /// Emergency security fix
    /// No delay, 80% quorum, requires security disclosure
    Emergency,
}
```

#### Upgrade Structure

```rust
pub struct ProtocolUpgrade<AccountId, BlockNumber> {
    /// Unique upgrade identifier
    pub upgrade_id: u64,

    /// Type of upgrade
    pub upgrade_type: UpgradeType,

    /// Proposal block
    pub proposed_at: BlockNumber,

    /// Earliest execution block
    pub effective_at: BlockNumber,

    /// Proposer
    pub proposer: AccountId,

    /// Description/rationale
    pub description: Vec<u8>,

    /// Upgrade payload (encoded changes)
    pub payload: Vec<u8>,

    /// Votes
    pub votes_for: BTreeSet<AccountId>,
    pub votes_against: BTreeSet<AccountId>,

    /// Status
    pub status: UpgradeStatus,
}

pub enum UpgradeStatus {
    Proposed,
    Approved,
    Executed,
    Rejected,
    Cancelled,
}
```

#### Upgrade Delays and Quorums

| Type | Delay | Quorum | Use Case |
|------|-------|--------|----------|
| Parameter | 48 hours | 67% | Timeout adjustments, thresholds |
| Protocol | 7 days | 80% | New features, logic changes |
| Emergency | 0 | 80% | Critical security fixes |

```rust
pub const PARAMETER_UPGRADE_DELAY: u64 = 48 * 3600;     // 48 hours
pub const PROTOCOL_UPGRADE_DELAY: u64 = 7 * 24 * 3600;  // 7 days
pub const EMERGENCY_UPGRADE_DELAY: u64 = 0;             // Immediate

pub fn get_required_quorum(upgrade_type: UpgradeType) -> u8 {
    match upgrade_type {
        UpgradeType::Parameter => 67,
        UpgradeType::Protocol => 80,
        UpgradeType::Emergency => 80,
    }
}

pub fn get_upgrade_delay(upgrade_type: UpgradeType) -> u64 {
    match upgrade_type {
        UpgradeType::Parameter => PARAMETER_UPGRADE_DELAY,
        UpgradeType::Protocol => PROTOCOL_UPGRADE_DELAY,
        UpgradeType::Emergency => EMERGENCY_UPGRADE_DELAY,
    }
}
```

#### Upgrade Process

```rust
pub fn propose_upgrade(
    proposer: &AccountId,
    upgrade_type: UpgradeType,
    description: Vec<u8>,
    payload: Vec<u8>,
) -> Result<u64, Error> {
    ensure!(is_active_validator(proposer), Error::NotValidator);

    // Emergency upgrades require security disclosure
    if upgrade_type == UpgradeType::Emergency {
        ensure!(payload.contains_security_disclosure(), Error::MissingDisclosure);
    }

    let upgrade_id = NextUpgradeId::<T>::get();
    NextUpgradeId::<T>::set(upgrade_id + 1);

    let delay = get_upgrade_delay(upgrade_type);

    let upgrade = ProtocolUpgrade {
        upgrade_id,
        upgrade_type,
        proposed_at: frame_system::Pallet::<T>::block_number(),
        effective_at: now() + delay,
        proposer: proposer.clone(),
        description,
        payload,
        votes_for: BTreeSet::new(),
        votes_against: BTreeSet::new(),
        status: UpgradeStatus::Proposed,
    };

    Upgrades::<T>::insert(upgrade_id, upgrade);

    Self::deposit_event(Event::UpgradeProposed {
        upgrade_id,
        upgrade_type,
        proposer: proposer.clone(),
    });

    Ok(upgrade_id)
}

pub fn vote_upgrade(
    voter: &AccountId,
    upgrade_id: u64,
    approve: bool,
) -> Result<(), Error> {
    ensure!(is_active_validator(voter), Error::NotValidator);

    Upgrades::<T>::try_mutate(upgrade_id, |upgrade| {
        let upgrade = upgrade.as_mut().ok_or(Error::UpgradeNotFound)?;
        ensure!(upgrade.status == UpgradeStatus::Proposed, Error::VotingClosed);

        // Remove from opposite set if changing vote
        upgrade.votes_for.remove(voter);
        upgrade.votes_against.remove(voter);

        if approve {
            upgrade.votes_for.insert(voter.clone());
        } else {
            upgrade.votes_against.insert(voter.clone());
        }

        // Check if quorum reached
        let required = get_required_quorum(upgrade.upgrade_type);
        let total_validators = active_validator_count();
        let required_votes = (total_validators * required as u32 + 99) / 100;

        if upgrade.votes_for.len() as u32 >= required_votes {
            upgrade.status = UpgradeStatus::Approved;
            Self::deposit_event(Event::UpgradeApproved { upgrade_id });
        } else if upgrade.votes_against.len() as u32 > total_validators - required_votes {
            upgrade.status = UpgradeStatus::Rejected;
            Self::deposit_event(Event::UpgradeRejected { upgrade_id });
        }

        Ok(())
    })
}

pub fn execute_upgrade(upgrade_id: u64) -> Result<(), Error> {
    let mut upgrade = Upgrades::<T>::get(upgrade_id).ok_or(Error::UpgradeNotFound)?;
    ensure!(upgrade.status == UpgradeStatus::Approved, Error::NotApproved);
    ensure!(now() >= upgrade.effective_at, Error::DelayNotElapsed);

    // Execute the upgrade payload
    execute_payload(&upgrade.payload)?;

    upgrade.status = UpgradeStatus::Executed;
    Upgrades::<T>::insert(upgrade_id, upgrade);

    Self::deposit_event(Event::UpgradeExecuted { upgrade_id });

    Ok(())
}
```

---

### Part 3: State Migration

#### Storage Versioning

```rust
/// Current storage version
pub const STORAGE_VERSION: u16 = 2;

#[pallet::storage]
#[pallet::getter(fn storage_version)]
pub type StorageVersion<T> = StorageValue<_, u16, ValueQuery>;

/// Migration hooks
pub fn on_runtime_upgrade() -> Weight {
    let current = StorageVersion::<T>::get();

    if current < 2 {
        migrate_v1_to_v2();
    }

    StorageVersion::<T>::put(STORAGE_VERSION);
    Weight::zero()
}
```

#### Migration Pattern

```rust
fn migrate_v1_to_v2() {
    // Example: Add new field to ValidatorInfo
    for (account, old_info) in OldValidators::<T>::iter() {
        let new_info = ValidatorInfoV2 {
            account: old_info.account,
            status: old_info.status,
            stake: old_info.stake,
            stake_updated_at: old_info.stake_updated_at,
            status_updated_at: old_info.status_updated_at,
            // New fields with defaults
            slashed_total: 0,
            validations: 0,
            disputes_against: 0,
        };
        Validators::<T>::insert(account, new_info);
    }
    OldValidators::<T>::remove_all();
}
```

---

### Invariants

| Invariant | Description |
|-----------|-------------|
| INV57 | **Recovery Quorum**: `recovery REQUIRES votes >= ceil(active * 0.8)` |
| INV58 | **Recovery Cooldown**: `recovery → cooldown = 7 days` |
| INV59 | **Upgrade Delay**: `execute_at >= proposed_at + delay(type)` |
| INV60 | **Emergency Quorum**: `emergency REQUIRES votes >= ceil(active * 0.8)` |

**Formal Definitions:**

```
INV57: Recovery Quorum
∀ recovery r:
  r.status = Approved →
    count(r.votes_for) >= ceil(active_validators * 0.8)

INV58: Recovery Cooldown
∀ validator v where status transitions Suspended → Recovering:
  v.active_at >= v.recovery_approved_at + RECOVERY_COOLDOWN

INV59: Upgrade Delay
∀ upgrade u where status = Executed:
  u.executed_at >= u.proposed_at + delay(u.upgrade_type)

INV60: Emergency Upgrade Quorum
∀ emergency_upgrade u:
  u.status = Approved →
    count(u.votes_for) >= ceil(active_validators * 0.8)
```

---

### Error Conditions

| Code | Name | Description |
|------|------|-------------|
| REC_001 | NotSuspended | Validator not in Suspended state |
| REC_002 | RecoveryInProgress | Recovery already initiated |
| REC_003 | VotingClosed | Voting period ended |
| REC_004 | NotValidator | Caller is not active validator |
| UPG_001 | UpgradeNotFound | Invalid upgrade ID |
| UPG_002 | NotApproved | Upgrade not yet approved |
| UPG_003 | DelayNotElapsed | Upgrade delay not complete |
| UPG_004 | MissingDisclosure | Emergency upgrade requires disclosure |

---

## Backwards Compatibility

### Impact Assessment

| Component | Impact | Migration Required |
|-----------|--------|-------------------|
| ValidatorStatus enum | Breaking | Yes (ABI) |
| Storage structure | Breaking | Yes |
| Upgrade mechanism | New feature | No |

### Migration Path

1. **Block N**: Announce upgrade (7-day notice)
2. **Block N + 7 days**: Storage migration executes
3. **Block N + 7 days + 1**: New status values available
4. **Block N + 14 days**: Old RPC endpoints deprecated

---

## Security Considerations

### Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| Malicious recovery | Low | High | 80% quorum, 7-day cooldown |
| Upgrade hijacking | Low | Critical | Delay period, multi-sig |
| Emergency abuse | Medium | High | 80% quorum, disclosure req |

### Mitigations

1. **Recovery Abuse**: 80% quorum prevents minority takeover
2. **Upgrade Hijacking**: Delay allows community review
3. **Emergency Abuse**: Requires security disclosure (audit trail)

---

## References

- [RFC-0001](0001-validator-security-model.md) — Validator security model
- [specs/core/validators.md](../specs/core/validators.md) — Validator specification
- [Substrate Upgrades](https://docs.substrate.io/maintain/runtime-upgrades/)

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-29 | 7ayLabs Security Council | Initial draft |

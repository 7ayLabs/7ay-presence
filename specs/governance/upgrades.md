# 7ay Proof of Presence (PoP)
## Protocol Specification — Protocol Upgrades
**Version:** v0.7.0
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** validators.md v0.7.0
**RFC:** RFC-0004

---

## 1. Purpose

This specification defines the protocol upgrade mechanism for the 7ay Presence Protocol. It enables parameter changes, protocol updates, and emergency fixes through a validator-governed process with appropriate delays and quorum requirements.

---

## 2. Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Upgrade Proposals | **On-chain** | Stored in `pallet-governance` |
| Voting | **On-chain** | Validator votes on-chain |
| Execution | **On-chain** | Runtime upgrade via Substrate |
| Storage Migration | **On-chain** | Versioned storage hooks |

---

## 3. Upgrade Types

### 3.1 Parameter Upgrades

Changes to protocol parameters (thresholds, timeouts, limits).

- **Delay:** 48 hours
- **Quorum:** 67%
- **Examples:** `base_timeout_seconds`, `max_queries_per_minute`

### 3.2 Protocol Upgrades

Changes to protocol logic or state machines.

- **Delay:** 7 days
- **Quorum:** 80%
- **Examples:** New invariants, state transitions, message types

### 3.3 Emergency Upgrades

Critical security fixes requiring immediate action.

- **Delay:** 0 (immediate)
- **Quorum:** 80%
- **Requirements:** Security disclosure included

---

## 4. Constants

```rust
/// Delay for parameter upgrades (48 hours)
pub const PARAMETER_UPGRADE_DELAY: u64 = 48 * 3600;

/// Delay for protocol upgrades (7 days)
pub const PROTOCOL_UPGRADE_DELAY: u64 = 7 * 24 * 3600;

/// Delay for emergency upgrades (immediate)
pub const EMERGENCY_UPGRADE_DELAY: u64 = 0;

/// Quorum for parameter upgrades (67%)
pub const PARAMETER_QUORUM: u8 = 67;

/// Quorum for protocol/emergency upgrades (80%)
pub const PROTOCOL_QUORUM: u8 = 80;
```

---

## 5. Upgrade Process

### 5.1 Proposal

```rust
pub fn propose_upgrade(
    proposer: AccountId,
    upgrade_type: UpgradeType,
    description: Vec<u8>,
    payload: Vec<u8>,
) -> Result<u64, Error>;
```

### 5.2 Voting

```rust
pub fn vote_upgrade(
    voter: AccountId,
    upgrade_id: u64,
    approve: bool,
) -> Result<(), Error>;
```

### 5.3 Execution

```rust
pub fn execute_upgrade(upgrade_id: u64) -> Result<(), Error>;
```

**Requirements:**
- Status MUST be `Approved`
- Current time MUST be >= `effective_at`

---

## 6. Upgrade Lifecycle

```
                  propose()
            ────────────────► Proposed
                                  │
                                  │ voting
                                  ▼
                    ┌─────────────┴─────────────┐
                    │                           │
               votes_for >= quorum         votes_against > max
                    │                           │
                    ▼                           ▼
               Approved                     Rejected
                    │
                    │ delay elapsed
                    │ execute()
                    ▼
               Executed
```

---

## 7. Storage Versioning

### 7.1 Version Tracking

```rust
pub const STORAGE_VERSION: u16 = 2;

#[pallet::storage]
pub type StorageVersion<T> = StorageValue<_, u16, ValueQuery>;
```

### 7.2 Migration Hooks

```rust
pub fn on_runtime_upgrade() -> Weight {
    let current = StorageVersion::<T>::get();

    match current {
        0 => migrate_v0_to_v1(),
        1 => migrate_v1_to_v2(),
        _ => {}
    }

    StorageVersion::<T>::put(STORAGE_VERSION);
    Weight::zero()
}
```

---

## 8. Events

```rust
pub enum Event<T: Config> {
    /// Upgrade proposed
    UpgradeProposed {
        upgrade_id: u64,
        upgrade_type: UpgradeType,
        proposer: T::AccountId,
        effective_at: T::BlockNumber,
    },

    /// Vote cast
    UpgradeVoteCast {
        upgrade_id: u64,
        voter: T::AccountId,
        approve: bool,
    },

    /// Upgrade approved
    UpgradeApproved {
        upgrade_id: u64,
    },

    /// Upgrade rejected
    UpgradeRejected {
        upgrade_id: u64,
    },

    /// Upgrade executed
    UpgradeExecuted {
        upgrade_id: u64,
    },

    /// Upgrade cancelled
    UpgradeCancelled {
        upgrade_id: u64,
    },
}
```

---

## 9. Invariants

### INV59: Upgrade Delay

```
∀ upgrade u where status = Executed:
  u.executed_at >= u.proposed_at + delay(u.upgrade_type)
```

### INV60: Emergency Upgrade Quorum

```
∀ emergency_upgrade u where status = Approved:
  count(u.votes_for) >= ceil(active_validators * 0.8)
```

---

## 10. Error Codes

| Code | Name | Description |
|------|------|-------------|
| UPG_001 | NotFound | Upgrade ID not found |
| UPG_002 | NotApproved | Upgrade not yet approved |
| UPG_003 | DelayNotElapsed | Upgrade delay not complete |
| UPG_004 | MissingDisclosure | Emergency requires disclosure |
| UPG_005 | NotValidator | Caller not active validator |
| UPG_006 | AlreadyVoted | Duplicate vote |
| UPG_007 | VotingClosed | Voting period ended |

---

## 11. Security Considerations

### 11.1 Emergency Upgrade Abuse

Emergency upgrades bypass the delay period. Mitigations:
- 80% quorum requirement
- Mandatory security disclosure
- Audit trail in events

### 11.2 Upgrade Hijacking

Malicious upgrade proposals. Mitigations:
- Multi-day delay for review
- High quorum requirements
- Proposer identified in event

---

## 12. References

- [RFC-0004](../rfcs/0004-validator-recovery-governance.md) — Recovery & Governance
- [validators.md](../core/validators.md) — Validator specification
- [Substrate Runtime Upgrades](https://docs.substrate.io/maintain/runtime-upgrades/)

---

## 13. Changelog

| Version | Changes |
|---------|---------|
| v0.7.0 | Initial upgrades specification (RFC-0004) |

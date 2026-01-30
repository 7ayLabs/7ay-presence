# 7ay Proof of Presence (PoP)
## Protocol Specification — Validator Recovery
**Version:** v0.7.0
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** validators.md v0.7.0, staking.md v0.7.0
**RFC:** RFC-0004

---

## 1. Purpose

This specification defines the validator recovery mechanism for the 7ay Presence Protocol. Recovery enables suspended validators to return to active status through a quorum-based voting process with appropriate cooldown periods.

---

## 2. Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Recovery Proposals | **On-chain** | Proposals stored in `pallet-validators` |
| Recovery Votes | **On-chain** | Votes recorded on-chain |
| Status Transitions | **On-chain** | State changes in validator storage |
| Cooldown Tracking | **On-chain** | Timestamps in validator storage |

---

## 3. Constants

```rust
/// Voting period for recovery proposals (3 days)
pub const RECOVERY_VOTING_PERIOD: u64 = 3 * 24 * 3600;

/// Cooldown after recovery approval (7 days)
pub const RECOVERY_COOLDOWN: u64 = 7 * 24 * 3600;

/// Required quorum for recovery (80%)
pub const RECOVERY_QUORUM: u8 = 80;
```

---

## 4. Suspension Reasons

```rust
pub enum SuspensionReason {
    /// Validator requested maintenance window
    VoluntaryMaintenance,

    /// Potential security issue under investigation
    SecurityInvestigation,

    /// Missed N consecutive epochs
    ExtendedDowntime,

    /// Pending slashing review
    PendingSlashReview,
}
```

---

## 5. Recovery Process

### 5.1 Initiation

A suspended validator can initiate recovery:

```rust
pub fn initiate_recovery(
    validator: AccountId,
    new_key: Option<PublicKey>,
) -> Result<(), Error>;
```

**Requirements:**
- Validator MUST be in `Suspended` status
- No existing recovery proposal for this validator
- Validator MUST have minimum stake

### 5.2 Voting

Active validators vote on recovery:

```rust
pub fn vote_recovery(
    voter: AccountId,
    validator: AccountId,
    approve: bool,
) -> Result<(), Error>;
```

**Requirements:**
- Voter MUST be active validator
- Voting period MUST not be expired
- Voter MUST not have already voted

### 5.3 Approval

Recovery is approved when:
- `votes_for >= ceil(active_validators * 0.8)`

Recovery is rejected when:
- `votes_against > active_validators - required_votes`
- Voting period expires without quorum

### 5.4 Execution

After approval:
1. Status transitions to `Recovering`
2. 7-day cooldown begins
3. After cooldown, status becomes `Active`

---

## 6. State Transitions

```
Suspended ──► initiate_recovery() ──► Suspended (proposal created)
                                           │
                                           ▼ (voting)
                              ┌────────────┴────────────┐
                              │                         │
                         approved                   rejected
                              │                         │
                              ▼                         ▼
                        Recovering              Suspended (remains)
                              │
                              │ 7 days
                              ▼
                           Active
```

---

## 7. Events

```rust
pub enum Event<T: Config> {
    /// Recovery proposal created
    RecoveryInitiated {
        validator: T::AccountId,
        deadline: T::BlockNumber,
    },

    /// Vote cast on recovery
    RecoveryVoteCast {
        voter: T::AccountId,
        validator: T::AccountId,
        approve: bool,
    },

    /// Recovery approved, entering cooldown
    RecoveryApproved {
        validator: T::AccountId,
        cooldown_until: T::BlockNumber,
    },

    /// Recovery rejected
    RecoveryRejected {
        validator: T::AccountId,
        votes_for: u32,
        votes_against: u32,
    },

    /// Recovery complete, validator active
    RecoveryCompleted {
        validator: T::AccountId,
    },
}
```

---

## 8. Invariants

### INV57: Recovery Quorum

```
∀ recovery r where status = Approved:
  count(r.votes_for) >= ceil(active_validators * RECOVERY_QUORUM / 100)
```

### INV58: Recovery Cooldown

```
∀ validator v transitioning Recovering → Active:
  v.active_at >= v.recovery_approved_at + RECOVERY_COOLDOWN
```

---

## 9. Error Codes

| Code | Name | Description |
|------|------|-------------|
| REC_001 | NotSuspended | Validator not suspended |
| REC_002 | ProposalExists | Recovery already in progress |
| REC_003 | VotingExpired | Voting period ended |
| REC_004 | NotValidator | Caller not active validator |
| REC_005 | AlreadyVoted | Duplicate vote |
| REC_006 | CooldownActive | Recovery cooldown not complete |

---

## 10. References

- [RFC-0004](../rfcs/0004-validator-recovery-governance.md) — Recovery & Governance
- [validators.md](validators.md) — Validator specification
- [staking.md](staking.md) — Staking specification

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.7.0 | Initial recovery specification (RFC-0004) |

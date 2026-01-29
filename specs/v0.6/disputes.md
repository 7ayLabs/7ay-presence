# 7ay Proof of Presence (PoP)
## Protocol Specification — Disputes
**Version:** v0.6 (extracted from presence.md v0.4)
**Status:** Active
**Scope:** Protocol-level (canonical)
**Depends on:** presence.md, validators.md

---

## 1. Purpose

This specification defines the dispute mechanism for challenging presence claims
in the Proof of Presence protocol.

Disputes allow any address to challenge a presence claim, with validators
voting to uphold or reject the challenge.

---

## 2. Dispute States

```solidity
enum DisputeStatus {
    None,       // 0 - No dispute exists
    Pending,    // 1 - Dispute initiated, awaiting votes
    Upheld,     // 2 - Dispute successful, presence slashed
    Rejected    // 3 - Dispute failed, presence remains valid
}
```

---

## 3. Dispute Flow

```
1. Any address initiates dispute → status = Pending
2. Validators vote to uphold or reject
3. When quorum votes, dispute resolves
4. If upheld: presence is slashed (PresenceSlashed event)
5. If rejected: presence continues normally
```

---

## 4. Dispute Window

Disputes can only be initiated while:
- Epoch is `Active`, OR
- Epoch is `Closed` and within `disputeWindow` seconds after endTime

Default `disputeWindow`: 86400 seconds (1 day)

---

## 5. Functions

### 5.1 Initiate Dispute

```solidity
function initiateDispute(
    address actor,
    uint256 epochId,
    bytes32 evidenceHash
) external;
```

A dispute MAY be initiated if and only if:
1. `actor != 0x0 ∧ epochId != 0`
2. Presence state is `Declared` or `Validated`
3. No pending dispute exists
4. Within dispute window

### 5.2 Vote on Dispute

```solidity
function voteOnDispute(
    address actor,
    uint256 epochId,
    bool upholdDispute
) external;
```

A dispute vote MAY be cast if and only if:
1. Dispute is `Pending`
2. Caller is an active validator
3. Validator has not already voted on this dispute

### 5.3 Resolve Dispute

```solidity
function resolveDispute(address actor, uint256 epochId) external;
```

Resolves when validator quorum is reached.

---

## 6. Events

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

## 7. Errors (Priority Order)

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

## 8. Invariants

- **INV-D1**: Dispute affects only target presence
- **INV-D2**: Slashed presence is terminal (no recovery)
- **INV-D3**: Each validator votes once per dispute
- **INV-D4**: Quorum required for resolution

---

## 9. References

- presence.md — Presence state machine (includes slashing)
- validators.md — Validator registry and quorum

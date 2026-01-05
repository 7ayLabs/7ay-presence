# 7ay Proof of Presence (PoP)
## Protocol Specification — Epoch
**Version:** v0.2
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** presence.md v0.1

---

## 1. Purpose

This specification defines the canonical rules for epoch lifecycle management
in the Proof of Presence protocol.

An epoch is the fundamental temporal unit that bounds presence assertions.
Without epochs, presence has no temporal context.

This specification formalizes:
- What an epoch IS
- How epochs transition through states
- What invariants epochs MUST maintain
- How epochs relate to presence

Implementations MUST follow this specification to be considered compliant.

---

## 2. Definitions

### 2.1 Epoch

An **Epoch** is a discrete, bounded temporal window during which
presence can be declared, validated, and finalized.

An epoch:
- Has a unique identifier (`epochId`)
- Has defined temporal bounds (`startTime`, `endTime`)
- Follows a deterministic lifecycle
- Is immutable once finalized

### 2.2 Epoch Identifier

The **Epoch Identifier** (`epochId`) is a `uint256` value that uniquely
identifies an epoch within the protocol.

Constraints:
- `epochId = 0` is RESERVED and MUST be rejected
- `epochId` values MUST be unique
- `epochId` values SHOULD be assigned monotonically

### 2.3 Epoch Bounds

**Epoch Bounds** define the temporal window of an epoch:
- `startTime`: Unix timestamp when the epoch becomes active
- `endTime`: Unix timestamp when the epoch closes

Constraints:
- `startTime < endTime` MUST hold
- `endTime - startTime` defines the epoch duration
- Epochs MUST NOT have overlapping active windows

### 2.4 Epoch Authority

The **Epoch Authority** is the address authorized to manage epoch lifecycle.

In the reference implementation:
- A single authority (owner) manages all epochs
- Future versions MAY support distributed epoch management

---

## 3. Epoch States

An epoch MUST be in exactly one of the following states:

### 3.1 None

The epoch does not exist.

```
epochId has never been registered
```

Properties:
- No storage allocated
- Cannot accept presence finalization
- Can transition to: `Scheduled`

---

### 3.2 Scheduled

The epoch has been created but is not yet active.

```
block.timestamp < startTime
```

Properties:
- Epoch bounds are defined and immutable
- Presence declarations MAY be accepted (off-chain)
- Presence finalization MUST be rejected
- Can transition to: `Active`

---

### 3.3 Active

The epoch is currently accepting presence finalization.

```
startTime <= block.timestamp < endTime
```

Properties:
- Presence finalization is permitted
- Epoch bounds cannot be modified
- Can transition to: `Closed`

---

### 3.4 Closed

The epoch has ended but is not yet finalized.

```
block.timestamp >= endTime AND NOT finalized
```

Properties:
- Presence finalization MUST be rejected
- Grace period for late validations (off-chain)
- Can transition to: `Finalized`

---

### 3.5 Finalized

The epoch is permanently sealed.

```
epoch.finalized == true
```

Properties:
- Terminal state (no outgoing transitions)
- All presence states are immutable
- Epoch data is frozen
- Can transition to: (none)

---

## 4. Epoch Lifecycle

### 4.1 State Transition Diagram

```
                    createEpoch()
        None ─────────────────────► Scheduled
                                        │
                                        │ block.timestamp >= startTime
                                        │ (automatic)
                                        ▼
                                     Active
                                        │
                                        │ block.timestamp >= endTime
                                        │ (automatic)
                                        ▼
                                     Closed
                                        │
                                        │ finalizeEpoch()
                                        ▼
                                    Finalized
```

### 4.2 State Transition Table

| From | To | Trigger | Conditions | Event |
|------|-----|---------|------------|-------|
| None | Scheduled | `createEpoch()` | Valid bounds, authority | `EpochCreated` |
| Scheduled | Active | (automatic) | `block.timestamp >= startTime` | `EpochActivated` |
| Active | Closed | (automatic) | `block.timestamp >= endTime` | `EpochClosed` |
| Closed | Finalized | `finalizeEpoch()` | Authority, all disputes resolved | `EpochFinalized` |

### 4.3 Automatic Transitions

State transitions from `Scheduled → Active` and `Active → Closed` are
**time-based** and occur automatically based on `block.timestamp`.

The contract does NOT require explicit transactions for these transitions.
State is computed dynamically based on current time and epoch bounds.

### 4.4 Epoch Creation Rules

An epoch MAY be created if and only if:
1. `epochId != 0`
2. `epochId` does not already exist
3. `startTime < endTime`
4. `startTime > block.timestamp` (future epoch) OR `startTime <= block.timestamp < endTime` (immediate activation)
5. Caller is the epoch authority

### 4.5 Epoch Finalization Rules

An epoch MAY be finalized if and only if:
1. Current state is `Closed`
2. Caller is the epoch authority
3. All protocol-required conditions are met (implementation-specific)

---

## 5. Presence-Epoch Relationship

### 5.1 Binding Rules

Presence is bound to epochs with the following rules:

1. **Temporal Binding**: Presence can only be finalized during `Active` epoch state
2. **Epoch Existence**: The epoch MUST exist (state != None)
3. **Epoch Validity**: The epoch MUST be in a valid state for the operation
4. **Immutability**: Once epoch is `Finalized`, all presence states are frozen

### 5.2 Presence Finalization Window

```
     │◄─────── Scheduled ───────►│◄─────── Active ───────►│◄── Closed ──►│
     │                           │                        │              │
     │  Presence finalization    │  Presence finalization │  Presence    │
     │  REJECTED                 │  PERMITTED             │  REJECTED    │
     │                           │                        │              │
─────┼───────────────────────────┼────────────────────────┼──────────────┼────►
   create                     startTime               endTime        finalize
```

### 5.3 Cross-Reference

The presence specification (presence.md) defines:
- What presence IS
- How presence transitions through states
- Presence invariants

This specification defines:
- The temporal context (epoch) that bounds presence
- When presence operations are valid

Together, they form the complete presence-epoch model.

---

## 6. Events

The protocol MUST emit canonical events for epoch lifecycle transitions:

### 6.1 EpochCreated

Emitted when a new epoch is registered.

```solidity
event EpochCreated(
    uint256 indexed epochId,
    uint256 startTime,
    uint256 endTime
);
```

### 6.2 EpochActivated

Emitted when an epoch transitions to Active state.

```solidity
event EpochActivated(uint256 indexed epochId);
```

Note: This event MAY be emitted lazily on first interaction after `startTime`.

### 6.3 EpochClosed

Emitted when an epoch transitions to Closed state.

```solidity
event EpochClosed(uint256 indexed epochId);
```

Note: This event MAY be emitted lazily on first interaction after `endTime`.

### 6.4 EpochFinalized

Emitted when an epoch is permanently sealed.

```solidity
event EpochFinalized(uint256 indexed epochId);
```

---

## 7. Errors

### 7.1 EpochAlreadyExists

Raised when attempting to create an epoch that already exists.

```solidity
error EpochAlreadyExists(uint256 epochId);
```

### 7.2 EpochNotFound

Raised when referencing an epoch that does not exist.

```solidity
error EpochNotFound(uint256 epochId);
```

### 7.3 EpochNotActive

Raised when attempting presence finalization outside the active window.

```solidity
error EpochNotActive(uint256 epochId);
```

### 7.4 EpochAlreadyFinalized

Raised when attempting to modify a finalized epoch.

```solidity
error EpochAlreadyFinalized(uint256 epochId);
```

### 7.5 InvalidEpochBounds

Raised when epoch bounds are invalid.

```solidity
error InvalidEpochBounds(uint256 startTime, uint256 endTime);
```

### 7.6 UnauthorizedEpochAuthority

Raised when caller is not the epoch authority.

```solidity
error UnauthorizedEpochAuthority(address caller, address authority);
```

---

## 8. Invariants

The following invariants MUST NEVER be violated:

### 8.1 Epoch Invariants

1. **Uniqueness**: Each `epochId` MUST map to at most one epoch.
2. **Bound Validity**: `startTime < endTime` MUST hold for all epochs.
3. **Monotonic Finalization**: A finalized epoch MUST NOT transition to any other state.
4. **State Consistency**: Epoch state MUST be computable deterministically from storage and `block.timestamp`.
5. **Authority Exclusivity**: Only the epoch authority MAY create or finalize epochs.

### 8.2 Presence-Epoch Invariants

6. **Active Window Enforcement**: Presence finalization MUST only succeed when epoch is `Active`.
7. **Finalization Freeze**: Once epoch is `Finalized`, no presence state in that epoch MAY change.
8. **Epoch Existence Requirement**: Presence operations MUST fail for non-existent epochs.

### 8.3 Future Invariants (Reserved)

9. **Sequential Finalization**: Epochs MUST be finalized in order (epochId N before N+1).
10. **Non-Overlapping Windows**: Active windows of different epochs MUST NOT overlap.

---

## 9. Determinism

Given the same inputs and `block.timestamp`,
all compliant implementations MUST compute the same epoch state.

Epoch state is a pure function of:
- Stored epoch data (bounds, finalized flag)
- Current `block.timestamp`

---

## 10. Integration Modes

### 10.1 Standalone Mode

`EpochRegistry` operates independently of `PresenceRegistry`.

```
┌─────────────────┐     ┌─────────────────┐
│  EpochRegistry  │     │PresenceRegistry │
│                 │     │                 │
│  - createEpoch  │     │ - finalize      │
│  - epochState   │     │ - presenceState │
│  - finalizeEpoch│     │                 │
└─────────────────┘     └─────────────────┘
        │                       │
        └───────────┬───────────┘
                    │
              Off-chain
              Orchestrator
```

Use case: Off-chain systems enforce epoch validation.

### 10.2 Integrated Mode

`PresenceRegistry` queries `EpochRegistry` for validation.

```
┌─────────────────────────────────────────┐
│           PresenceRegistry v2           │
│                                         │
│  ┌─────────────────┐                    │
│  │  EpochRegistry  │◄── epochState()    │
│  └─────────────────┘                    │
│           │                             │
│           ▼                             │
│  finalizePresence() ──► validate epoch  │
│                                         │
└─────────────────────────────────────────┘
```

Use case: On-chain epoch enforcement.

---

## 11. Compliance

An implementation is considered compliant if and only if:
- All Epoch Invariants (8.1) hold
- All Presence-Epoch Invariants (8.2) hold
- All required events are emitted correctly
- All error conditions are handled per specification
- State transitions follow the defined lifecycle

---

## 12. Versioning

| Version | Changes |
|---------|---------|
| v0.2 | Initial epoch specification |

---

## 13. References

- presence.md v0.1 — Presence specification
- model.md v0.1 — Conceptual system model
- errors.md v0.1 — Error specification

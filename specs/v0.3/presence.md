# Presence Spec v0.3
> Depends: `epoch.md v0.2` | Integrates: `IEpochRegistry`

## States
```
enum PresenceState { None, Declared, Finalized }
```

## Transitions
```
None ──declarePresence()──► Declared ──finalizePresence()──► Finalized
  │                                                              ▲
  └─────────────finalizePresence() (legacy)────────────────────┘
```

| From | To | Trigger | Guards | Event |
|------|-----|---------|--------|-------|
| None | Declared | `declarePresence` | A ∧ E | `PresenceDeclared` |
| Declared | Finalized | `finalizePresence` | A ∧ E | `PresenceFinalized` |
| None | Finalized | `finalizePresence` | A ∧ E | `PresenceFinalized` |
| Declared/Finalized | same | any | idempotent | ∅ |

**Guards:**
- `A` = `actor == msg.sender ∧ actor != 0x0 ∧ epochId != 0`
- `E` = `epochRegistry.isEpochActive(epochId)`

## Functions

```solidity
function declarePresence(address actor, uint256 epochId) external;
function finalizePresence(address actor, uint256 epochId) external;
function presenceState(address actor, uint256 epochId) external view returns (PresenceState);
function epochRegistry() external view returns (address);
```

## Errors (priority order)
1. `InvalidActor()` — actor == 0x0
2. `UnauthorizedActor(caller, actor)` — caller != actor
3. `InvalidEpoch(epochId)` — epochId == 0
4. `EpochNotActive(epochId)` — !isEpochActive

## Events
```solidity
event PresenceDeclared(address indexed actor, uint256 indexed epochId);
event PresenceFinalized(address indexed actor, uint256 indexed epochId);
```

## Invariants
1. `∀(actor,epoch): count(Finalized) ≤ 1`
2. `Finalized → immutable`
3. `Declared → ¬None` (no revert)
4. `actor == msg.sender` (self-only)
5. `finalize(A) ⊥ finalize(B)` (actor isolation)
6. `finalize(E1) ⊥ finalize(E2)` (epoch isolation)
7. `state ∈ {None → Declared → Finalized}` (monotonic)
8. `declare ∧ finalize → epoch.Active`

## Storage
```solidity
mapping(address => mapping(uint256 => PresenceState)) _presence;
IEpochRegistry immutable epochRegistry;
```

## Version
`PROTOCOL_VERSION = "0.3.0"`

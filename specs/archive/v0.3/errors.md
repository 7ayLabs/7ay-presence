# Errors Spec v0.3
> Custom errors only. No revert strings.

## Presence Errors

| Error | Condition | Priority |
|-------|-----------|----------|
| `InvalidActor()` | `actor == 0x0` | 1 |
| `UnauthorizedActor(caller, actor)` | `caller != actor` | 2 |
| `InvalidEpoch(epochId)` | `epochId == 0` | 3 |
| `EpochNotActive(epochId)` | `!isEpochActive(epochId)` | 4 |

## Epoch Errors (ref: epoch.md)

| Error | Condition |
|-------|-----------|
| `InvalidEpochId()` | `epochId == 0` |
| `EpochAlreadyExists(epochId)` | `epochs[epochId].exists` |
| `EpochNotFound(epochId)` | `!epochs[epochId].exists` |
| `EpochNotActive(epochId)` | `state != Active` |
| `EpochAlreadyFinalized(epochId)` | `epochs[epochId].finalized` |
| `InvalidEpochBounds(start, end)` | `start >= end` |
| `UnauthorizedEpochAuthority(caller, auth)` | `caller != authority` |
| `EpochNotClosed(epochId, state)` | `state != Closed` |
| `InvalidEpochAuthority()` | `authority == 0x0` |

## Registry Errors

| Error | Condition |
|-------|-----------|
| `InvalidEpochRegistry()` | `epochRegistry == 0x0` |

## Rules
- Check order = priority order
- Idempotent ops → no error, silent return
- Custom errors → gas efficient

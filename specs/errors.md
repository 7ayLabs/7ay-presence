# 7ay Proof of Presence (PoP)
## Error Specification
**Version:** v0.1
**Status:** Draft (MVP)
**Scope:** Protocol-level error definitions

---

## 1. Purpose

This document defines the canonical error types for the Proof of Presence protocol.

All compliant implementations MUST use these error definitions
to ensure consistent error handling and auditability.

---

## 2. Error Design Principles

### 2.1 Gas Efficiency

Custom errors MUST be used instead of revert strings.
Custom errors are more gas-efficient and provide typed error data.

### 2.2 Determinism

Error conditions MUST be deterministic.
Given the same inputs and state, the same error MUST be raised.

### 2.3 Auditability

All errors MUST include sufficient context for debugging and auditing.
Error parameters MUST identify the relevant actors and values.

---

## 3. MVP Error Definitions

### 3.1 UnauthorizedActor

Raised when a caller attempts to finalize presence for a different actor.

```solidity
error UnauthorizedActor(address caller, address actor);
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `caller` | `address` | The address that called the function |
| `actor` | `address` | The actor address passed as parameter |

**Condition:** `msg.sender != actor`

**Invariant Reference:** Invariant #4 — Only the actor itself MAY finalize its own presence.

---

### 3.2 InvalidEpoch

Raised when an invalid epoch identifier is provided.

```solidity
error InvalidEpoch(uint256 epochId);
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `epochId` | `uint256` | The invalid epoch identifier |

**Condition:** `epochId == 0`

**Rationale:** Epoch 0 is reserved as the genesis/null epoch and cannot be used for presence finalization.

---

### 3.3 InvalidActor

Raised when the actor address is the zero address.

```solidity
error InvalidActor();
```

**Condition:** `actor == address(0)`

**Rationale:** The zero address cannot be a valid actor as it has no private key.

---

## 4. Error Handling Rules

### 4.1 Revert Behavior

When an error condition is met, the transaction MUST revert immediately.
No state changes MUST occur before the revert.

### 4.2 Error Priority

When multiple error conditions are met, errors MUST be checked in this order:

1. `InvalidActor` — Zero address check first
2. `UnauthorizedActor` — Authorization check second
3. `InvalidEpoch` — Parameter validation third

This order ensures validity checks precede authorization checks.

### 4.3 Idempotent Operations

Idempotent operations (e.g., finalizing an already-finalized presence)
MUST NOT raise errors. They MUST return silently without state changes.

---

## 5. Future Error Definitions (Non-MVP)

The following errors are reserved for future protocol versions:

| Error | Description | Status |
|-------|-------------|--------|
| `EpochNotActive` | Epoch is not in active state | Reserved |
| `EpochExpired` | Epoch has passed its finalization window | Reserved |
| `PresenceAlreadyDeclared` | Actor has existing declaration in epoch | Reserved |
| `InvalidValidator` | Caller is not an authorized validator | Reserved |
| `QuorumNotMet` | Validation quorum not reached | Reserved |
| `PresenceSlashed` | Presence has been slashed | Reserved |

---

## 6. Compliance

An implementation is considered compliant if:

- All MVP errors are implemented as custom errors (not revert strings)
- Error parameters match the specification exactly
- Error priority order is respected
- Idempotent operations do not raise errors

# 7ay Proof of Presence (PoP)
## Protocol Specification — State Synchronization and Reconciliation
**Version:** v0.6.1
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** epoch.md v0.2, presence.md v0.4, validator.md v0.4, ephemeral.md v0.5

---

## 1. Purpose

This specification defines the **State Synchronization and Reconciliation** semantics
for the 7ay Presence Protocol's semantic layer.

State synchronization enables protocol participants (nodes) to maintain a consistent
view of presence declarations, validations, and disputes across the network.

This specification defines:
- What state synchronization IS
- Partial vs complete synchronization modes
- Deterministic reconciliation algorithm
- Consistency invariants for synchronized state

This version does **NOT** define:
- Transport protocols or network topology
- Encryption or key management
- Specific implementation mechanisms
- SDK or client behavior

The State Synchronization specification exists solely to **define semantic rules**
for how nodes agree on protocol state.

Implementations MUST follow this specification to be considered compliant.

---

## 2. Definitions

### 2.1 Node

A **Node** is the logical representation of a protocol participant in the
context of discovery and messaging. Nodes are semantic abstractions over
on-chain entities (actors, validators).

> **Note:** The formal Node model is defined in node-model.md v0.6.2 (forward reference).
> This specification uses a minimal definition sufficient for state sync semantics.

A node is characterized by:
- `identity.address` — Ethereum address
- `epoch.epochId` — Current epoch context
- `role` — Participant or Validator
- `presence.state` — Current presence state

### 2.2 Protocol State

**Protocol State** is the collective view of:
- All presence declarations in an epoch
- All validation votes cast
- All disputes and their resolution status
- Epoch metadata and capabilities

State is partitioned by epoch:
```
state[epochId] = {
  presences: Map<address, PresenceRecord>,
  validations: Map<(address, validator), VoteRecord>,
  disputes: Map<address, DisputeRecord>
}
```

### 2.3 State Vector

A **State Vector** is a compact representation of state version:
```typescript
interface StateVector {
  epochId: uint256;
  presenceCount: uint256;
  validationCount: uint256;
  disputeCount: uint256;
  lastUpdated: uint256;        // Block number or timestamp
  stateRoot: bytes32;          // Merkle root of state
}
```

### 2.4 State Diff

A **State Diff** is an incremental update between two state versions:
```typescript
interface StateDiff {
  epochId: uint256;
  fromVector: StateVector;
  toVector: StateVector;
  changes: StateChange[];
}

interface StateChange {
  type: "presence" | "validation" | "dispute";
  actor: address;
  data: bytes;
}
```

---

## 3. Synchronization Modes

### 3.1 Complete Synchronization

Complete sync transfers the full state for an epoch. Used when:
- A new node joins the network
- State vectors differ significantly
- Recovery from network partition

```
COMPLETE_SYNC:
  requester → peer: STATE_SYNC_REQUEST { epochId, mode: "complete" }
  peer → requester: STATE_SYNC_RESPONSE { state[epochId] }
```

### 3.2 Partial Synchronization

Partial sync transfers only state changes since a known point. Used when:
- Nodes have recent shared state
- Incremental updates are more efficient
- Regular sync maintenance

```
PARTIAL_SYNC:
  requester → peer: STATE_SYNC_REQUEST { epochId, fromVector }
  peer → requester: STATE_SYNC_RESPONSE { diff(fromVector, currentVector) }
```

### 3.3 Mode Selection

Nodes SHOULD select sync mode based on:
- Vector clock distance
- Network bandwidth
- State size estimation

Complete sync MUST be used when `fromVector` is unknown to the peer.

---

## 4. Reconciliation Algorithm

### 4.1 Overview

Reconciliation resolves conflicts between local and remote state views.
The algorithm is **deterministic**: given identical on-chain state, all
nodes MUST produce identical reconciled state.

### 4.2 Conflict Definition

A conflict exists when:
```
local.state[actor][epochId] != remote.state[actor][epochId]
```

Conflicts may occur in:
- Presence state
- Validation vote counts
- Dispute status

### 4.3 Resolution Strategy

Conflicts are resolved by consulting **on-chain state** as the source of truth:

```
function reconcile(local: State, remote: State, epochId: uint256) → State:
  result = empty State

  // Union of all actors
  actors = union(local.presences.keys, remote.presences.keys)

  for actor in actors:
    if conflict(local.presences[actor], remote.presences[actor]):
      // On-chain is canonical
      result.presences[actor] = queryOnChain(actor, epochId)
    else:
      // No conflict, take latest
      result.presences[actor] = latest(local.presences[actor], remote.presences[actor])

  // Similarly for validations and disputes
  ...

  return result
```

### 4.4 On-Chain Query

When conflicts exist, nodes query on-chain state:

```solidity
// Canonical state query
PresenceState state = presenceRegistry.presenceState(actor, epochId);
Presence memory presence = presenceRegistry.getPresence(actor, epochId);
Dispute memory dispute = presenceRegistry.getDispute(actor, epochId);
```

### 4.5 Determinism Guarantee

The reconciliation algorithm MUST be deterministic:

**INV-SYNC-DET**: Given identical on-chain state at block `B`, all nodes
executing reconciliation MUST produce byte-identical output state.

This is achieved by:
- Using on-chain state as canonical source
- Applying changes in deterministic order (sorted by actor address)
- Using identical state encoding

---

## 5. Vector Clocks

### 5.1 Purpose

Vector clocks track state versions without full state comparison.

### 5.2 Structure

```typescript
interface VectorClock {
  epochId: uint256;
  entries: Map<address, uint256>;  // node address → logical timestamp
}
```

### 5.3 Operations

**Increment**: When a node observes a state change:
```
clock.entries[self.address] += 1
```

**Merge**: When receiving remote clock:
```
for each address in union(local.entries.keys, remote.entries.keys):
  merged.entries[address] = max(local.entries[address], remote.entries[address])
```

**Compare**: Determine if clocks are concurrent, ahead, or behind:
```
function compare(a: VectorClock, b: VectorClock) → Ordering:
  aAhead = false
  bAhead = false

  for each address in union(a.entries.keys, b.entries.keys):
    if a.entries[address] > b.entries[address]: aAhead = true
    if b.entries[address] > a.entries[address]: bAhead = true

  if aAhead and bAhead: return CONCURRENT
  if aAhead: return AHEAD
  if bAhead: return BEHIND
  return EQUAL
```

---

## 6. Sync Protocol

### 6.1 Message Types

> **Note:** Full message schemas are defined in message-catalog.md v0.6.2 (forward reference).

| Message | Direction | Purpose |
|---------|-----------|---------|
| STATE_SYNC_REQUEST | Request | Initiate sync with peer |
| STATE_SYNC_RESPONSE | Response | Return requested state/diff |
| STATE_VECTOR_CLOCK | Exchange | Share current vector clock |
| STATE_DIFF | Push | Send incremental update |

### 6.2 Sync Flow

```
┌──────────────┐                    ┌──────────────┐
│    Node A    │                    │    Node B    │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       │  STATE_VECTOR_CLOCK               │
       │  { clock_A }                      │
       │──────────────────────────────────►│
       │                                   │
       │◄──────────────────────────────────│
       │  STATE_VECTOR_CLOCK               │
       │  { clock_B }                      │
       │                                   │
       │  [compare clocks]                 │
       │                                   │
       │  STATE_SYNC_REQUEST               │
       │  { epochId, fromVector }          │
       │──────────────────────────────────►│
       │                                   │
       │◄──────────────────────────────────│
       │  STATE_SYNC_RESPONSE              │
       │  { state or diff }                │
       │                                   │
       │  [reconcile]                      │
       │                                   │
       │  STATE_VECTOR_CLOCK               │
       │  { merged_clock }                 │
       │──────────────────────────────────►│
       │                                   │
```

---

## 7. Consistency Guarantees

### 7.1 Eventual Consistency

The sync protocol provides **eventual consistency**:
- All non-faulty nodes eventually converge to the same state
- Convergence occurs within bounded time after network stabilizes
- Temporary inconsistencies are allowed during sync

### 7.2 Consistency Window

Nodes SHOULD achieve consistency within:
- One epoch duration for normal operation
- Before epoch close for finalization-critical state

### 7.3 Consistency Verification

Nodes MAY verify consistency by comparing state roots:
```
if local.stateRoot != peer.stateRoot:
  initiate full reconciliation
```

---

## 8. Epoch Scoping

### 8.1 Epoch Isolation

State sync is strictly epoch-scoped:
- Sync requests MUST specify `epochId`
- Responses MUST NOT include cross-epoch data
- Reconciliation operates on single epoch

### 8.2 Epoch State Requirements

Sync is valid only for epochs with:
- `epochState >= Active` (Scheduled epochs have no presence state)
- `epochCapability >= PresenceWithSignals` (for v0.6 features)

### 8.3 Post-Epoch Sync

After epoch closes:
- State becomes immutable
- Sync provides historical view
- No reconciliation needed (on-chain is final)

---

## 9. Invariants

### 9.1 Sync-Specific Invariants

These invariants apply to state synchronization:

**INV-SYNC1**: Sync MUST NOT modify on-chain state
State synchronization is read-only from on-chain perspective.

**INV-SYNC2**: Sync MUST be eventually consistent
All non-faulty nodes eventually converge to identical state view.

**INV-SYNC3**: Validators MUST converge before epoch close
Validator nodes MUST achieve consistency before epoch finalizes.

**INV-SYNC4**: Reconciliation MUST be deterministic
Given identical inputs, reconciliation produces identical outputs.

### 9.2 Cross-Reference Invariants

These invariants connect to node model (v0.6.2 forward reference):

**INV19**: Node identity MUST be derivable from on-chain state
**INV20**: Node MUST be bound to exactly one epoch at any time

---

## 10. Security Considerations

### 10.1 Byzantine Tolerance

The sync protocol tolerates Byzantine behavior:
- Malicious peers may send incorrect state
- On-chain verification detects discrepancies
- Nodes SHOULD sync with multiple peers

### 10.2 Eclipse Attack Resistance

Nodes SHOULD:
- Maintain connections to multiple peers
- Periodically verify state against on-chain
- Reject state that contradicts on-chain truth

### 10.3 Denial of Service

Nodes SHOULD:
- Rate-limit sync requests
- Bound response sizes
- Timeout long-running syncs

---

## 11. Performance Considerations

### 11.1 Bandwidth Optimization

- Use partial sync when possible
- Compress large responses
- Cache frequently-requested state

### 11.2 Latency Optimization

- Maintain warm connections to peers
- Pre-fetch state for upcoming epochs
- Use optimistic sync (apply, then verify)

### 11.3 Storage Optimization

- Prune finalized epoch state after retention period
- Use efficient encoding (e.g., RLP, SSZ)
- Index state by epoch for fast retrieval

---

## 12. Non-Goals

This specification explicitly does NOT define:

- Network discovery or peer selection
- Transport layer security (TLS, noise protocol)
- Specific serialization formats
- Client implementation details
- Gossip or broadcast protocols

These are implementation concerns outside protocol scope.

---

## 13. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 epochs | Supported (sync uses existing state) |
| v0.4 presence states | Unchanged (synced as-is) |
| On-chain queries | Uses existing registry functions |
| EpochCapability | Requires >= PresenceWithSignals for v0.6 features |

---

## 14. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- validator.md v0.4 — Validator mechanics
- ephemeral.md v0.5 — Epoch capabilities
- node-model.md v0.6.2 — Node definition (forward reference)
- message-catalog.md v0.6.2 — Message schemas (forward reference)

---

## 15. Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Initial state synchronization specification |

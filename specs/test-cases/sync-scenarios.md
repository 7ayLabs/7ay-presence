# 7ay Proof of Presence (PoP)
## Test Cases — State Synchronization Scenarios
**Version:** v0.6.9
**Status:** Draft

---

## 1. Complete Sync Scenarios

### TC-SYNC-001: Initial Complete Sync
**Category:** Happy Path
**Invariants:** INV26

**Preconditions:**
- Node A just joined epoch 42
- Node A has no local state for epoch 42
- Validator V has complete state

**Steps:**
1. Node A discovers Validator V
2. Node A sends `STATE_SYNC_REQUEST` (type: COMPLETE, epochId: 42)
3. Validator V queries on-chain state
4. Validator V sends `STATE_SYNC_RESPONSE` with full snapshot
5. Node A verifies and applies state

**Expected Results:**
- Node A receives all presences for epoch 42
- Node A receives all disputes for epoch 42
- stateRoot matches expected value
- Node A synced to latest block number

---

### TC-SYNC-002: Complete Sync with Large State
**Category:** Boundary
**Invariants:** INV26

**Preconditions:**
- Epoch 42 has 1000 presences
- Response chunking required

**Steps:**
1. Node A requests complete sync
2. Validator V sends chunked response
3. Node A reassembles chunks
4. Node A verifies complete state

**Expected Results:**
- All 1000 presences received
- Chunks properly ordered and verified
- Final stateRoot correct
- No data loss during transfer

---

### TC-SYNC-003: Complete Sync from Multiple Validators
**Category:** Redundancy
**Invariants:** INV26

**Preconditions:**
- 3 validators available with state

**Steps:**
1. Node A requests sync from all 3 validators
2. Receives 3 responses in parallel
3. Compares stateRoots

**Expected Results:**
- All 3 stateRoots match (deterministic reconciliation)
- Node A has high confidence in state
- Any mismatch triggers investigation

---

### TC-SYNC-004: Sync Request Timeout
**Category:** Error Handling

**Preconditions:**
- Validator V unresponsive

**Steps:**
1. Node A sends sync request to V
2. No response within 10 seconds

**Expected Results:**
- SYNC_004 (Timeout) triggered
- Validator V marked as slow/unreliable
- Node A retries with different validator

---

## 2. Partial Sync Scenarios

### TC-SYNC-010: Delta Sync After Blocks
**Category:** Happy Path
**Invariants:** INV26

**Preconditions:**
- Node A synced to block 18499000
- Current block is 18500000
- 50 new events in range

**Steps:**
1. Node A sends `STATE_SYNC_REQUEST`:
   - type: PARTIAL
   - fromBlock: 18499000
   - toBlock: null (latest)
2. Validator V computes delta
3. Validator V sends events list

**Expected Results:**
- Response contains 50 events
- Events ordered by (blockNumber, logIndex)
- Node A applies events in order
- Node A now at block 18500000

---

### TC-SYNC-011: Delta with No New Events
**Category:** Edge Case

**Preconditions:**
- Node A at block 18500000
- No new events since

**Steps:**
1. Node A requests partial sync from 18500000
2. Validator checks for new events

**Expected Results:**
- Response with empty events array
- fromBlock == toBlock == 18500000
- No state changes applied

---

### TC-SYNC-012: Delta with Block Gap
**Category:** Error Handling

**Preconditions:**
- Node A at block 18490000
- Validator V only has from 18495000

**Steps:**
1. Node A requests partial sync from 18490000
2. Validator V cannot provide complete range

**Expected Results:**
- SYNC_003 (BlockGap) error returned
- Node A requests complete sync instead
- Or Node A queries RPC directly for gap

---

### TC-SYNC-013: Partial Sync Event Types
**Category:** Happy Path
**Invariants:** INV26

**Preconditions:**
- Various event types in range

**Steps:**
1. Request partial sync covering:
   - PresenceDeclared events
   - PresenceValidated events
   - DisputeInitiated events
   - PresenceSlashed events

**Expected Results:**
- All event types properly serialized
- All event types properly applied
- State transitions correct for each type

---

## 3. Reconciliation Scenarios

### TC-SYNC-020: Deterministic State Root
**Category:** Core Invariant
**Invariants:** INV26

**Preconditions:**
- Two nodes (A and B) process same events

**Steps:**
1. Both nodes start with empty state
2. Apply: PresenceDeclared(Alice, 42) at block 100
3. Apply: PresenceDeclared(Bob, 42) at block 101
4. Apply: PresenceValidated(Alice, 42, 3) at block 102
5. Compute stateRoot

**Expected Results:**
- Node A stateRoot == Node B stateRoot
- Exact byte-for-byte match
- Order of application matches block order

---

### TC-SYNC-021: Event Ordering by Block and Log
**Category:** Core Invariant
**Invariants:** INV26

**Preconditions:**
- Multiple events in same block

**Steps:**
1. Block 100 contains:
   - Log 0: PresenceDeclared(Alice)
   - Log 1: PresenceDeclared(Bob)
   - Log 2: PresenceDeclared(Carol)
2. Process in order

**Expected Results:**
- Events processed: Alice, Bob, Carol
- Same order on all nodes
- Deterministic regardless of receipt order

---

### TC-SYNC-022: State Root Calculation
**Category:** Technical
**Invariants:** INV26

**Preconditions:**
- Known state at block 18500000

**Steps:**
1. Collect all presences: sorted by address
2. Collect all disputes: sorted by address
3. Compute merkle roots for each
4. Combine with epochId and blockNumber

**Expected Results:**
- stateRoot = keccak256(epochId, blockNumber, presenceRoot, disputeRoot)
- Reproducible by any node with same inputs
- Changes with any state modification

---

### TC-SYNC-023: Reconciliation After Dispute Resolution
**Category:** Happy Path
**Invariants:** INV26

**Preconditions:**
- Bob has Validated presence
- Dispute initiated and upheld

**Steps:**
1. State before: Bob.state = Validated
2. DisputeResolved(Bob, Upheld) emitted
3. PresenceSlashed(Bob) emitted
4. Reconcile state

**Expected Results:**
- Bob.state = Slashed
- disputes[Bob].status = Upheld
- stateRoot updated to reflect new state
- All nodes agree on final state

---

## 4. Vector Clock Scenarios

### TC-SYNC-030: Vector Clock Exchange
**Category:** Consistency Check

**Preconditions:**
- Nodes A, B, C all synced

**Steps:**
1. Node A broadcasts `STATE_VECTOR_CLOCK`:
   - epochId: 42
   - block: 18500000
   - stateRoot: 0xABC
2. Nodes B, C receive and compare

**Expected Results:**
- If stateRoots match: Consistency confirmed
- If mismatch: Trigger reconciliation
- Log consensus status

---

### TC-SYNC-031: Vector Clock Mismatch Detection
**Category:** Error Detection
**Invariants:** INV26

**Preconditions:**
- Node A: stateRoot X at block 100
- Node B: stateRoot Y at block 100

**Steps:**
1. Exchange vector clocks
2. Detect mismatch
3. Investigate cause

**Expected Results:**
- Mismatch logged as critical
- Both nodes request complete sync
- Root cause identified (bug or attack)

---

### TC-SYNC-032: Stale Vector Clock
**Category:** Edge Case

**Preconditions:**
- Node A at block 100
- Node B at block 150

**Steps:**
1. Node A sends vector clock (block 100)
2. Node B receives outdated clock

**Expected Results:**
- Node B ignores (clock is stale)
- Or Node B responds with current state
- No false mismatch reported

---

## 5. State Diff Scenarios

### TC-SYNC-040: Real-time State Diff
**Category:** Happy Path

**Preconditions:**
- Node A subscribed to validator V
- New block with presence event

**Steps:**
1. Validator V observes new block
2. Validator V creates `STATE_DIFF`:
   - operations: [{ op: "set", path: "presences/0xNew", value: {...} }]
   - stateRoot: (new)
3. Validator V broadcasts to subscribers
4. Node A applies diff

**Expected Results:**
- Node A state updated in real-time
- No full sync required
- stateRoot matches after application

---

### TC-SYNC-041: State Diff with Multiple Operations
**Category:** Happy Path

**Preconditions:**
- Single block with multiple events

**Steps:**
1. Block contains:
   - PresenceDeclared(A)
   - PresenceValidated(B)
   - DisputeVote(C)
2. State diff includes all operations

**Expected Results:**
- All operations in single diff message
- Applied atomically
- Intermediate states not exposed

---

### TC-SYNC-042: Out-of-Order State Diff
**Category:** Error Handling

**Preconditions:**
- Node A receives diff for block N+2
- Node A still at block N

**Steps:**
1. Diff for block N+2 arrives before N+1
2. Node A detects gap

**Expected Results:**
- Diff queued or rejected
- Node A requests missing block(s)
- Eventually consistent

---

## 6. Error Scenarios

### TC-SYNC-050: Invalid State Root in Response
**Category:** Error Handling

**Preconditions:**
- Validator V sends corrupted response

**Steps:**
1. Node A receives sync response
2. Node A recomputes stateRoot locally
3. Computed != claimed

**Expected Results:**
- SYNC_002 (InvalidStateRoot) triggered
- Response rejected
- Validator V flagged
- Retry with different validator

---

### TC-SYNC-051: Stale State Response
**Category:** Error Handling

**Preconditions:**
- Node A at block 18500000
- Validator V responds with block 18499000

**Steps:**
1. Node A requests sync
2. Response.blockNumber < local.blockNumber

**Expected Results:**
- SYNC_001 (StaleState) triggered
- Response discarded
- Retry with different validator

---

### TC-SYNC-052: Malformed Event in Response
**Category:** Error Handling

**Preconditions:**
- Response contains invalid event data

**Steps:**
1. Node A parses sync response
2. One event fails to decode

**Expected Results:**
- Event skipped or error logged
- Remaining events still processed
- State root will mismatch (triggers resync)

---

### TC-SYNC-053: Signature Verification Failure
**Category:** Security
**Invariants:** INV24

**Preconditions:**
- Response signature doesn't match sender

**Steps:**
1. Node A verifies response signature
2. ecrecover != claimed sender

**Expected Results:**
- Response rejected immediately
- Sender marked as untrusted
- Security incident logged

---

## 7. Performance Scenarios

### TC-SYNC-060: High-Volume Event Processing
**Category:** Performance
**Invariants:** INV26

**Preconditions:**
- 10,000 events to process

**Steps:**
1. Request complete sync
2. Process all 10,000 events
3. Measure time and memory

**Expected Results:**
- Processing completes in reasonable time
- Memory usage bounded
- Final stateRoot correct

---

### TC-SYNC-061: Concurrent Sync Requests
**Category:** Concurrency

**Preconditions:**
- 100 nodes request sync simultaneously

**Steps:**
1. All 100 send sync requests to validator
2. Validator handles concurrently

**Expected Results:**
- All requests served
- No response corruption
- Rate limiting may apply

---

### TC-SYNC-062: Sync During High Block Production
**Category:** Edge Case

**Preconditions:**
- Blocks produced rapidly (every 2 seconds)
- Sync takes 10 seconds

**Steps:**
1. Start sync at block N
2. Sync completes
3. Now at block N+5

**Expected Results:**
- Sync provides consistent snapshot
- Node requests delta for N to N+5
- Eventually catches up

---

## 8. Epoch Boundary Scenarios

### TC-SYNC-070: Sync at Epoch End
**Category:** Lifecycle

**Preconditions:**
- Epoch 42 about to close
- Node A still syncing

**Steps:**
1. Epoch 42 closes during sync
2. Sync response arrives

**Expected Results:**
- Epoch 42 state still valid
- Can complete sync for finalization
- Must start fresh for epoch 43

---

### TC-SYNC-071: Cross-Epoch Sync Rejection
**Category:** Error Handling
**Invariants:** INV21

**Preconditions:**
- Node A in epoch 42
- Request sync for epoch 43

**Steps:**
1. Send sync request for epoch 43
2. Node A has no presence in 43

**Expected Results:**
- Request rejected
- Must declare presence in 43 first
- Epoch isolation maintained

---

### TC-SYNC-072: Historical Epoch Sync
**Category:** Edge Case

**Preconditions:**
- Epoch 40 is Finalized
- Node needs historical data

**Steps:**
1. Request sync for epoch 40
2. Validator provides historical snapshot

**Expected Results:**
- Historical state retrievable
- State is immutable (finalized)
- Useful for auditing

---

## Summary

| Category | Test Cases | Coverage |
|----------|------------|----------|
| Complete Sync | TC-SYNC-001 to 004 | Full state transfer |
| Partial Sync | TC-SYNC-010 to 013 | Delta updates |
| Reconciliation | TC-SYNC-020 to 023 | Deterministic state (INV26) |
| Vector Clock | TC-SYNC-030 to 032 | Consistency checks |
| State Diff | TC-SYNC-040 to 042 | Real-time updates |
| Error Handling | TC-SYNC-050 to 053 | Failure modes |
| Performance | TC-SYNC-060 to 062 | Scale and concurrency |
| Epoch Boundary | TC-SYNC-070 to 072 | Lifecycle transitions |

---

## References

- state-sync.md v0.6.1 — Sync specification
- invariants.md v0.6.1 — INV26
- message-catalog.md v0.6.2 — Sync message types
- discovery.md v0.6.3 — Validator selection

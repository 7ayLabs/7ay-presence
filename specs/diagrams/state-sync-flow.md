# 7ay Proof of Presence (PoP)
## Diagram — State Synchronization Flow
**Version:** v0.6.9
**Status:** Draft

---

## 1. State Sync Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     STATE SYNCHRONIZATION MODEL                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                         ┌─────────────────────┐                             │
│                         │   On-Chain State    │                             │
│                         │   (Authoritative)   │                             │
│                         └──────────┬──────────┘                             │
│                                    │                                         │
│                                    │ Query                                   │
│                                    ▼                                         │
│          ┌─────────────────────────────────────────────────┐                │
│          │              Validator Nodes                     │                │
│          │                                                  │                │
│          │  ┌─────────┐   ┌─────────┐   ┌─────────┐        │                │
│          │  │ Val A   │   │ Val B   │   │ Val C   │        │                │
│          │  │ ┌─────┐ │   │ ┌─────┐ │   │ ┌─────┐ │        │                │
│          │  │ │Cache│ │◄─►│ │Cache│ │◄─►│ │Cache│ │        │                │
│          │  │ └─────┘ │   │ └─────┘ │   │ └─────┘ │        │                │
│          │  └─────────┘   └─────────┘   └─────────┘        │                │
│          │       ▲             ▲             ▲              │                │
│          └───────┼─────────────┼─────────────┼──────────────┘                │
│                  │             │             │                               │
│                  │    STATE_SYNC Messages    │                               │
│                  │◄────────────┼────────────►│                               │
│                  │             │             │                               │
│          ┌───────┴─────────────┴─────────────┴──────────────┐                │
│          │              Participant Nodes                    │                │
│          │                                                   │                │
│          │  ┌─────────┐   ┌─────────┐   ┌─────────┐         │                │
│          │  │ Part 1  │   │ Part 2  │   │ Part N  │         │                │
│          │  └─────────┘   └─────────┘   └─────────┘         │                │
│          │                                                   │                │
│          └───────────────────────────────────────────────────┘                │
│                                                                              │
│   KEY: Validators maintain caches and serve sync requests                    │
│        Participants query validators for state updates                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Complete Sync Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        COMPLETE SYNC REQUEST                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Requesting Node                         Validator Node                     │
│   ───────────────                         ──────────────                     │
│        │                                        │                            │
│        │  1. STATE_SYNC_REQUEST                 │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ type: COMPLETE              │      │                            │
│        │  │ epochId: 42                 │      │                            │
│        │  │ fromBlock: null             │      │                            │
│        │  │ toBlock: null               │      │                            │
│        ├──┴─────────────────────────────┴─────►│                            │
│        │                                        │                            │
│        │                                        │  2. Build State Snapshot   │
│        │                                        │  ┌─────────────────────┐  │
│        │                                        │  │ Query on-chain:     │  │
│        │                                        │  │ - All presences     │  │
│        │                                        │  │ - All disputes      │  │
│        │                                        │  │ - Epoch metadata    │  │
│        │                                        │  └─────────────────────┘  │
│        │                                        │                            │
│        │  3. STATE_SYNC_RESPONSE                │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ type: COMPLETE              │      │                            │
│        │  │ epochId: 42                 │      │                            │
│        │  │ stateRoot: 0x123...         │      │                            │
│        │  │ blockNumber: 18500000       │      │                            │
│        │  │ presences: [...]            │      │                            │
│        │  │ disputes: [...]             │      │                            │
│        │◄─┴─────────────────────────────┴──────┤                            │
│        │                                        │                            │
│        │  4. Verify Response                    │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ - Verify signature          │      │                            │
│        │  │ - Verify state root         │      │                            │
│        │  │ - Apply to local cache      │      │                            │
│        │  └─────────────────────────────┘      │                            │
│        │                                        │                            │
│        ▼                                        │                            │
│   ┌──────────────────┐                         │                            │
│   │ Synced to block  │                         │                            │
│   │ 18500000         │                         │                            │
│   └──────────────────┘                         │                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Partial Sync (Delta) Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PARTIAL SYNC (DELTA)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Node (has state up to block 18499000)       Validator                     │
│   ─────────────────────────────────────       ─────────                     │
│        │                                        │                            │
│        │  1. STATE_SYNC_REQUEST                 │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ type: PARTIAL               │      │                            │
│        │  │ epochId: 42                 │      │                            │
│        │  │ fromBlock: 18499000         │      │                            │
│        │  │ toBlock: null (latest)      │      │                            │
│        ├──┴─────────────────────────────┴─────►│                            │
│        │                                        │                            │
│        │                                        │  2. Compute Delta          │
│        │                                        │  ┌─────────────────────┐  │
│        │                                        │  │ Events since block  │  │
│        │                                        │  │ 18499000:           │  │
│        │                                        │  │ - 3 new presences   │  │
│        │                                        │  │ - 1 validation      │  │
│        │                                        │  │ - 0 disputes        │  │
│        │                                        │  └─────────────────────┘  │
│        │                                        │                            │
│        │  3. STATE_SYNC_RESPONSE                │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ type: PARTIAL               │      │                            │
│        │  │ fromBlock: 18499000         │      │                            │
│        │  │ toBlock: 18500000           │      │                            │
│        │  │ events: [                   │      │                            │
│        │  │   {PresenceDeclared, ...},  │      │                            │
│        │  │   {PresenceDeclared, ...},  │      │                            │
│        │  │   {PresenceValidated, ...}  │      │                            │
│        │  │ ]                           │      │                            │
│        │◄─┴─────────────────────────────┴──────┤                            │
│        │                                        │                            │
│        │  4. Apply Events                       │                            │
│        │  ┌─────────────────────────────┐      │                            │
│        │  │ For each event:             │      │                            │
│        │  │   Apply to local state      │      │                            │
│        │  │   Update state root         │      │                            │
│        │  └─────────────────────────────┘      │                            │
│        │                                        │                            │
│        ▼                                        │                            │
│   ┌──────────────────┐                         │                            │
│   │ Synced to block  │                         │                            │
│   │ 18500000         │                         │                            │
│   └──────────────────┘                         │                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Vector Clock Consistency Check

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VECTOR CLOCK CONSISTENCY                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Node A                Node B                Node C                         │
│   ──────                ──────                ──────                         │
│     │                     │                     │                            │
│     │  STATE_VECTOR_CLOCK │                     │                            │
│     │  ┌───────────────┐  │                     │                            │
│     │  │ epochId: 42   │  │                     │                            │
│     │  │ block: 18500  │  │                     │                            │
│     │  │ stateRoot: X  │  │                     │                            │
│     ├──┴───────────────┴─►│                     │                            │
│     │                     │  STATE_VECTOR_CLOCK │                            │
│     │                     │  ┌───────────────┐  │                            │
│     │                     │  │ epochId: 42   │  │                            │
│     │                     │  │ block: 18500  │  │                            │
│     │                     │  │ stateRoot: X  │  │  ✓ Consistent              │
│     │                     ├──┴───────────────┴─►│                            │
│     │                     │                     │                            │
│     │  Compare: stateRoot == X for all nodes   │                            │
│     │                                           │                            │
│     ▼                     ▼                     ▼                            │
│   ┌─────────────────────────────────────────────┐                           │
│   │          CONSISTENCY VERIFIED (INV26)        │                           │
│   │   Same on-chain state → Same state root     │                           │
│   └─────────────────────────────────────────────┘                           │
│                                                                              │
│                                                                              │
│   INCONSISTENCY DETECTED:                                                    │
│   ───────────────────────                                                    │
│                                                                              │
│   Node A                Node B                Node C                         │
│   ──────                ──────                ──────                         │
│     │                     │                     │                            │
│     │  stateRoot: X       │  stateRoot: X       │  stateRoot: Y  ✗          │
│     │                     │                     │                            │
│     │                     │                     │  Trigger:                  │
│     │                     │                     │  - Request complete sync   │
│     │                     │                     │  - Verify against chain    │
│     │                     │                     │  - Log discrepancy         │
│     │                     │                     │                            │
│     ▼                     ▼                     ▼                            │
│   ┌─────────────────────────────────────────────┐                           │
│   │          RECONCILIATION TRIGGERED            │                           │
│   └─────────────────────────────────────────────┘                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Deterministic Reconciliation (INV26)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  DETERMINISTIC RECONCILIATION (INV26)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INPUT: On-chain events for epoch 42                                        │
│   ───────────────────────────────────                                        │
│                                                                              │
│   Block 100: PresenceDeclared(Alice, 42)                                    │
│   Block 101: PresenceDeclared(Bob, 42)                                      │
│   Block 102: PresenceValidated(Alice, 42, count=3)                          │
│   Block 103: DisputeInitiated(Bob, 42, Charlie, hash)                       │
│   Block 104: DisputeVote(Bob, 42, Val1, true)                               │
│   Block 105: DisputeVote(Bob, 42, Val2, true)                               │
│   Block 106: DisputeVote(Bob, 42, Val3, false)                              │
│   Block 107: DisputeResolved(Bob, 42, Upheld)                               │
│   Block 107: PresenceSlashed(Bob, 42)                                       │
│                                                                              │
│                                                                              │
│   RECONCILIATION ALGORITHM:                                                  │
│   ─────────────────────────                                                  │
│                                                                              │
│   1. Initialize empty state                                                  │
│      ┌───────────────────────────────────────────────────────┐              │
│      │ presences: {}                                          │              │
│      │ disputes: {}                                           │              │
│      └───────────────────────────────────────────────────────┘              │
│                                                                              │
│   2. Apply events in block order (deterministic)                            │
│      ┌───────────────────────────────────────────────────────┐              │
│      │ for event in events.sortBy(blockNumber, logIndex):    │              │
│      │   match event:                                         │              │
│      │     PresenceDeclared → add to presences (Declared)    │              │
│      │     PresenceValidated → update state (Validated)       │              │
│      │     DisputeInitiated → create dispute (Pending)        │              │
│      │     DisputeVote → increment vote counters              │              │
│      │     DisputeResolved → update dispute status            │              │
│      │     PresenceSlashed → update presence (Slashed)        │              │
│      └───────────────────────────────────────────────────────┘              │
│                                                                              │
│   3. Compute state root                                                      │
│      ┌───────────────────────────────────────────────────────┐              │
│      │ stateRoot = keccak256(                                 │              │
│      │   epochId,                                             │              │
│      │   blockNumber,                                         │              │
│      │   merkleRoot(presences.sortBy(address)),              │              │
│      │   merkleRoot(disputes.sortBy(address))                 │              │
│      │ )                                                      │              │
│      └───────────────────────────────────────────────────────┘              │
│                                                                              │
│                                                                              │
│   OUTPUT: Final State                                                        │
│   ──────────────────                                                         │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐     │
│   │ presences: {                                                       │     │
│   │   Alice: { state: Validated, declaredAt: 100, validatedAt: 102 } │     │
│   │   Bob:   { state: Slashed, declaredAt: 101 }                      │     │
│   │ }                                                                  │     │
│   │ disputes: {                                                        │     │
│   │   Bob: { status: Upheld, votesFor: 2, votesAgainst: 1 }           │     │
│   │ }                                                                  │     │
│   │ stateRoot: 0xABC123...                                            │     │
│   └───────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│   ✓ Any node processing same events produces same stateRoot                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Multi-Validator Sync

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MULTI-VALIDATOR SYNC                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Participant Node                                                           │
│   ────────────────                                                           │
│        │                                                                    │
│        │  1. Select multiple validators (redundancy)                        │
│        │  ┌────────────────────────────────────────┐                        │
│        │  │ validators = selectDiscoveryPeers(3)   │                        │
│        │  └────────────────────────────────────────┘                        │
│        │                                                                    │
│        ├─────────────────┬─────────────────┬─────────────────┐              │
│        │                 │                 │                 │              │
│        ▼                 ▼                 ▼                 │              │
│   ┌─────────┐       ┌─────────┐       ┌─────────┐           │              │
│   │ Val A   │       │ Val B   │       │ Val C   │           │              │
│   └────┬────┘       └────┬────┘       └────┬────┘           │              │
│        │                 │                 │                 │              │
│        │ Response A      │ Response B      │ Response C      │              │
│        │ stateRoot: X    │ stateRoot: X    │ stateRoot: X    │              │
│        │                 │                 │                 │              │
│        └─────────────────┴─────────────────┴─────────────────┘              │
│                                    │                                         │
│                                    ▼                                         │
│        ┌─────────────────────────────────────────────────────┐              │
│        │                  CONSENSUS CHECK                     │              │
│        │                                                      │              │
│        │  if all stateRoots match:                           │              │
│        │    → Accept response, high confidence                │              │
│        │                                                      │              │
│        │  if majority match:                                  │              │
│        │    → Accept majority, flag minority                  │              │
│        │                                                      │              │
│        │  if no majority:                                     │              │
│        │    → Query on-chain directly, report validators      │              │
│        │                                                      │              │
│        └─────────────────────────────────────────────────────┘              │
│                                    │                                         │
│                                    ▼                                         │
│        ┌──────────────────────────────────────────────────────┐             │
│        │              VERIFIED STATE APPLIED                   │             │
│        └──────────────────────────────────────────────────────┘             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. State Diff (Incremental Update)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         STATE DIFF MESSAGE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Validator broadcasts incremental update to subscribers                     │
│                                                                              │
│   ┌─────────────┐                                                           │
│   │  Validator  │──── New block with presence events                        │
│   └──────┬──────┘                                                           │
│          │                                                                   │
│          │  STATE_DIFF                                                       │
│          │  ┌──────────────────────────────────────────────────────┐        │
│          │  │ epochId: 42                                           │        │
│          │  │ fromBlock: 18500000                                   │        │
│          │  │ toBlock: 18500001                                     │        │
│          │  │ operations: [                                         │        │
│          │  │   { op: "set", path: "presences/0xABC/state",        │        │
│          │  │     value: "Declared" },                              │        │
│          │  │   { op: "set", path: "presences/0xABC/declaredAt",   │        │
│          │  │     value: 1704067200 }                               │        │
│          │  │ ]                                                     │        │
│          │  │ stateRoot: 0xNEW...                                   │        │
│          │  └──────────────────────────────────────────────────────┘        │
│          │                                                                   │
│          ├───────────────┬───────────────┬───────────────┐                  │
│          │               │               │               │                  │
│          ▼               ▼               ▼               ▼                  │
│     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐            │
│     │ Sub 1   │     │ Sub 2   │     │ Sub 3   │     │ Sub N   │            │
│     │         │     │         │     │         │     │         │            │
│     │ Apply   │     │ Apply   │     │ Apply   │     │ Apply   │            │
│     │ diff    │     │ diff    │     │ diff    │     │ diff    │            │
│     └─────────┘     └─────────┘     └─────────┘     └─────────┘            │
│                                                                              │
│                                                                              │
│   DIFF OPERATION TYPES:                                                      │
│   ─────────────────────                                                      │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────┐      │
│   │ "set"    - Create or update a value at path                      │      │
│   │ "delete" - Remove a value at path                                 │      │
│   │ "merge"  - Merge object into existing value at path              │      │
│   └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Sync Error Handling

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SYNC ERROR HANDLING                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SYNC_001: Stale State                                                      │
│   ─────────────────────                                                      │
│                                                                              │
│   Response blockNumber < local blockNumber                                   │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────────────┐     ┌──────────────────┐                            │
│   │ Discard response │────►│ Try another peer │                            │
│   └──────────────────┘     └──────────────────┘                            │
│                                                                              │
│                                                                              │
│   SYNC_002: Invalid State Root                                               │
│   ─────────────────────────────                                              │
│                                                                              │
│   Computed stateRoot != claimed stateRoot                                   │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────────────┐     ┌──────────────────┐                            │
│   │ Log discrepancy  │────►│ Request complete │                            │
│   │ for validator    │     │ sync from chain  │                            │
│   └──────────────────┘     └──────────────────┘                            │
│                                                                              │
│                                                                              │
│   SYNC_003: Block Gap                                                        │
│   ────────────────────                                                       │
│                                                                              │
│   Missing blocks between local state and response                           │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────────────┐     ┌──────────────────┐                            │
│   │ Request partial  │────►│ Fill gap, then   │                            │
│   │ sync for gap     │     │ apply response   │                            │
│   └──────────────────┘     └──────────────────┘                            │
│                                                                              │
│                                                                              │
│   SYNC_004: Timeout                                                          │
│   ─────────────────                                                          │
│                                                                              │
│   No response within timeout (10s)                                          │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────────────┐     ┌──────────────────┐                            │
│   │ Mark peer as     │────►│ Try next peer    │                            │
│   │ slow/unreliable  │     │ in list          │                            │
│   └──────────────────┘     └──────────────────┘                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Complete Sync Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     COMPLETE SYNC LIFECYCLE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                      INITIAL SYNC                                  │    │
│   │                                                                    │    │
│   │   [Join Epoch] ──► [Find Validators] ──► [Request Complete Sync]  │    │
│   │                ──► [Verify & Apply]                                │    │
│   │                                                                    │    │
│   └───────────────────────────────────────┬───────────────────────────┘    │
│                                           │                                 │
│                                           ▼                                 │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                      STEADY STATE                                  │    │
│   │                                                                    │    │
│   │   ┌──────────────────────────────────────────────────────┐        │    │
│   │   │                  RECEIVE UPDATES                      │        │    │
│   │   │                                                       │        │    │
│   │   │   STATE_DIFF ──► [Verify] ──► [Apply] ──► [Update]   │        │    │
│   │   │                              stateRoot               │        │    │
│   │   └──────────────────────────────────────────────────────┘        │    │
│   │                           │                                        │    │
│   │                           │ Periodic (every 5 min)                 │    │
│   │                           ▼                                        │    │
│   │   ┌──────────────────────────────────────────────────────┐        │    │
│   │   │              CONSISTENCY CHECK                        │        │    │
│   │   │                                                       │        │    │
│   │   │   [Exchange Vector Clocks] ──► [Compare stateRoots]  │        │    │
│   │   │   ──► [Reconcile if needed]                          │        │    │
│   │   └──────────────────────────────────────────────────────┘        │    │
│   │                                                                    │    │
│   └───────────────────────────────────────┬───────────────────────────┘    │
│                                           │                                 │
│                                           │ Epoch Ends                      │
│                                           ▼                                 │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                      EPOCH TRANSITION                              │    │
│   │                                                                    │    │
│   │   [Finalize Local State] ──► [Clear Cache] ──► [Join New Epoch]   │    │
│   │                          ──► [Initial Sync for New Epoch]          │    │
│   │                                                                    │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## References

- state-sync.md v0.6.1 — Sync protocol specification
- invariants.md v0.6.1 — INV26 (Deterministic Reconciliation)
- message-catalog.md v0.6.2 — Sync message types
- discovery.md v0.6.3 — Validator selection

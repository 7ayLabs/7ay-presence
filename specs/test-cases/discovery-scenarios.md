# 7ay Proof of Presence (PoP)
## Test Cases — Node Discovery Scenarios
**Version:** v0.6.9
**Status:** Draft

---

## 1. Bootstrap Scenarios

### TC-DISC-001: Fresh Node Bootstrap
**Category:** Happy Path
**Invariants:** INV19, INV20

**Preconditions:**
- New node with valid Ethereum address
- Active epoch exists (epochId=42)
- At least one bootstrap source available

**Steps:**
1. Node queries bootstrap source for seed nodes
2. Node queries on-chain for epoch 42 status
3. Node calls `declarePresence(self, 42)`
4. Node receives `PresenceDeclared` event confirmation

**Expected Results:**
- Node has presence state `Declared` in epoch 42
- Node can create valid `NODE_ANNOUNCE` message
- Node identity derivable from address (INV19)
- Node bound to epoch 42 (INV20)

---

### TC-DISC-002: Bootstrap with Invalid Epoch
**Category:** Error Handling
**Invariants:** INV20

**Preconditions:**
- New node attempts to join epoch 999 (does not exist)

**Steps:**
1. Node queries on-chain for epoch 999
2. Node attempts `declarePresence(self, 999)`

**Expected Results:**
- Transaction reverts with `EpochNotActive(999)`
- Node remains in `None` state
- No `NODE_ANNOUNCE` can be created

---

### TC-DISC-003: Bootstrap with Epoch Capability Check
**Category:** Boundary
**Invariants:** INV20

**Preconditions:**
- Epoch 42 has capability `PresenceOnly`
- Epoch 43 has capability `PresenceWithSignals`

**Steps:**
1. Node declares presence in epoch 42
2. Node attempts discovery operations in epoch 42
3. Node declares presence in epoch 43
4. Node performs discovery operations in epoch 43

**Expected Results:**
- Epoch 42: Presence declared, but signal-based discovery limited
- Epoch 43: Full discovery operations available

---

## 2. Announcement Scenarios

### TC-DISC-010: Valid Node Announcement
**Category:** Happy Path
**Invariants:** INV21, INV22

**Preconditions:**
- Node A has `Declared` presence in epoch 42
- Node B is active peer in epoch 42

**Steps:**
1. Node A creates `NODE_ANNOUNCE` message with:
   - Valid signature
   - epochId: 42
   - role: Participant
   - ttl: 3600
2. Node A broadcasts to known peers
3. Node B receives announcement

**Expected Results:**
- Node B verifies signature against A's address
- Node B verifies A's presence on-chain (state=Declared)
- Node B adds A to peer list with TTL
- Node B logs successful verification

---

### TC-DISC-011: Announcement with Wrong Epoch
**Category:** Error Handling
**Invariants:** INV21

**Preconditions:**
- Node A has presence in epoch 41
- Current epoch is 42

**Steps:**
1. Node A creates `NODE_ANNOUNCE` with epochId: 41
2. Node A broadcasts to peers in epoch 42

**Expected Results:**
- Receiving nodes reject with DISC_002 (EpochMismatch)
- Node A not added to any peer list
- Warning logged: "Received node from wrong epoch"

---

### TC-DISC-012: Announcement with Invalid Signature
**Category:** Error Handling
**Invariants:** INV24

**Preconditions:**
- Node A attempts announcement with forged signature

**Steps:**
1. Node A creates `NODE_ANNOUNCE` with invalid signature
2. Node A broadcasts to peers

**Expected Results:**
- Signature verification fails (ecrecover != sender)
- Announcement discarded
- Node not added to peer list
- Security event logged

---

### TC-DISC-013: Announcement with No On-Chain Presence
**Category:** Error Handling
**Invariants:** INV22

**Preconditions:**
- Node A has never declared presence
- Node A attempts to announce

**Steps:**
1. Node A creates signed `NODE_ANNOUNCE`
2. Peer receives and verifies signature (passes)
3. Peer queries on-chain `presenceState(A, epochId)`

**Expected Results:**
- On-chain check returns `None`
- Verification fails with DISC_003
- Node A not added to peer list

---

### TC-DISC-014: Validator Role Claim Verification
**Category:** Happy Path
**Invariants:** INV22

**Preconditions:**
- Node V is registered validator
- Node V has declared presence in epoch 42

**Steps:**
1. Node V creates `NODE_ANNOUNCE` with role: Validator
2. Peer receives and verifies
3. Peer queries `isValidatorActive(V)`

**Expected Results:**
- Validator check returns true
- Node V added to peer list as Validator
- Can be selected as discovery peer with priority

---

### TC-DISC-015: False Validator Role Claim
**Category:** Error Handling
**Invariants:** INV22

**Preconditions:**
- Node P is regular participant (not validator)
- Node P has declared presence

**Steps:**
1. Node P creates `NODE_ANNOUNCE` with role: Validator
2. Peer receives and verifies signature (passes)
3. Peer queries `isValidatorActive(P)`

**Expected Results:**
- Validator check returns false
- Role claim rejected
- Node P NOT added to peer list (or added as Participant only)

---

## 3. Query Scenarios

### TC-DISC-020: Query for Validators Only
**Category:** Happy Path
**Invariants:** INV21, INV22

**Preconditions:**
- Epoch 42 has 3 validators and 10 participants
- Node A is participant with presence

**Steps:**
1. Node A sends `NODE_QUERY` with filter: { role: Validator }
2. Discovery peer processes query
3. Discovery peer sends `NODE_RESPONSE`

**Expected Results:**
- Response contains only validators (max 3)
- All returned nodes have valid presence
- All returned nodes are in epoch 42
- Response includes total count and pagination

---

### TC-DISC-021: Query with Pagination
**Category:** Happy Path

**Preconditions:**
- Epoch 42 has 150 active nodes
- Query limit: 50

**Steps:**
1. Send `NODE_QUERY` with limit: 50, offset: 0
2. Receive `NODE_RESPONSE`
3. Send `NODE_QUERY` with limit: 50, offset: 50
4. Send `NODE_QUERY` with limit: 50, offset: 100

**Expected Results:**
- First response: 50 nodes, hasMore: true
- Second response: 50 nodes, hasMore: true
- Third response: 50 nodes, hasMore: false
- Total: 150 unique nodes across all responses

---

### TC-DISC-022: Query by Non-Participant
**Category:** Error Handling
**Invariants:** INV22

**Preconditions:**
- Node X has no presence in epoch 42

**Steps:**
1. Node X sends `NODE_QUERY` for epoch 42

**Expected Results:**
- Query rejected (requester has no presence)
- No nodes returned
- Error logged

---

### TC-DISC-023: Query for Different Epoch
**Category:** Error Handling
**Invariants:** INV21

**Preconditions:**
- Node A has presence in epoch 42
- Node A queries for epoch 43

**Steps:**
1. Node A sends `NODE_QUERY` for epoch 43

**Expected Results:**
- If A has no presence in 43: Query rejected
- If A has presence in 43: Only epoch 43 nodes returned
- No epoch 42 nodes in response

---

## 4. TTL & Maintenance Scenarios

### TC-DISC-030: Announcement TTL Expiry
**Category:** Lifecycle
**Invariants:** None (operational)

**Preconditions:**
- Node A announced with TTL: 3600s
- 3601 seconds have passed
- No re-announcement received

**Steps:**
1. Peer runs periodic maintenance
2. Peer checks TTL for all entries
3. Peer identifies Node A as stale

**Expected Results:**
- Node A removed from peer list
- DISC_005 (StaleAnnouncement) logged
- Next query won't return Node A

---

### TC-DISC-031: Re-Announcement Before TTL
**Category:** Happy Path

**Preconditions:**
- Node A announced with TTL: 3600s
- 1800 seconds have passed (TTL/2)

**Steps:**
1. Node A sends new `NODE_ANNOUNCE` with TTL: 3600
2. Peer receives and verifies
3. Peer updates peer list entry

**Expected Results:**
- Node A's TTL refreshed to 3600s from now
- Node A remains active in peer list
- No stale removal triggered

---

### TC-DISC-032: Graceful Departure
**Category:** Happy Path

**Preconditions:**
- Node A is active in peer list

**Steps:**
1. Node A creates `NODE_LEAVE` message with reason
2. Node A broadcasts to peers
3. Peer receives and processes

**Expected Results:**
- Node A immediately removed from peer list
- State marked as "Departed" (not "Stale")
- Resources freed

---

### TC-DISC-033: Peer List Full
**Category:** Boundary

**Preconditions:**
- Peer list at maximum capacity (1000 nodes)
- New valid announcement received

**Steps:**
1. Peer receives valid `NODE_ANNOUNCE` from new node
2. Peer attempts to add to full list
3. DISC_004 error triggered

**Expected Results:**
- Oldest entry evicted from peer list
- New node added successfully
- Eviction logged

---

## 5. Verification Scenarios

### TC-DISC-040: Periodic Re-Verification Success
**Category:** Happy Path
**Invariants:** INV22

**Preconditions:**
- Node A in peer list
- 5 minutes since last verification

**Steps:**
1. Peer runs periodic verification
2. Peer queries `presenceState(A, epochId)`
3. Returns Validated (valid state)

**Expected Results:**
- Node A remains in peer list
- lastVerified timestamp updated
- No action required

---

### TC-DISC-041: Periodic Re-Verification Failure
**Category:** Error Handling
**Invariants:** INV22

**Preconditions:**
- Node A in peer list (was Declared)
- A's presence now Slashed on-chain

**Steps:**
1. Peer runs periodic verification
2. Peer queries `presenceState(A, epochId)`
3. Returns Slashed (invalid state)

**Expected Results:**
- DISC_003 (VerificationFailed) triggered
- Node A removed from peer list
- Other peers notified (optional)

---

### TC-DISC-042: Verification During Dispute
**Category:** Edge Case
**Invariants:** INV22

**Preconditions:**
- Node A in peer list (Validated)
- Dispute initiated against A (Pending)

**Steps:**
1. Peer runs verification
2. Peer queries `presenceState(A, epochId)`
3. Returns Validated (still valid)
4. Dispute resolved as Upheld

**Expected Results:**
- During pending: A remains in peer list
- After upheld: Next verification removes A
- State transition properly handled

---

## 6. Epoch Transition Scenarios

### TC-DISC-050: Epoch Closes
**Category:** Lifecycle
**Invariants:** INV20, INV21

**Preconditions:**
- Node A active in epoch 42
- Epoch 42 transitions to Closed

**Steps:**
1. Epoch 42 end time reached
2. Nodes observe epoch state change
3. Epoch 43 becomes Active

**Expected Results:**
- Epoch 42 peer list frozen (no new entries)
- Epoch 43 peer list initialized empty
- Nodes must re-declare and re-announce in epoch 43

---

### TC-DISC-051: Node Joins New Epoch
**Category:** Happy Path
**Invariants:** INV20

**Preconditions:**
- Node A was active in epoch 42
- Epoch 43 now Active

**Steps:**
1. Node A declares presence in epoch 43
2. Node A creates new `NODE_ANNOUNCE` for epoch 43
3. Node A broadcasts to known peers

**Expected Results:**
- Node A has separate presence in epoch 43
- Node A in peer list for epoch 43
- Epoch 42 presence unaffected (can still finalize)

---

### TC-DISC-052: Cross-Epoch Discovery Attempt
**Category:** Error Handling
**Invariants:** INV21

**Preconditions:**
- Node A in epoch 42
- Node B in epoch 43

**Steps:**
1. Node A sends `NODE_QUERY` for epoch 43
2. Node B receives query

**Expected Results:**
- Query rejected (A has no presence in 43)
- No epoch 43 nodes leaked to epoch 42 requester

---

## 7. Security Scenarios

### TC-DISC-060: Replay Attack Prevention
**Category:** Security
**Invariants:** INV25

**Preconditions:**
- Valid `NODE_ANNOUNCE` captured by attacker
- Attacker attempts replay

**Steps:**
1. Attacker replays exact message
2. Peer receives duplicate

**Expected Results:**
- Nonce already used: Message rejected
- No duplicate entries created
- Attack logged

---

### TC-DISC-061: Sybil Attack Resistance
**Category:** Security
**Invariants:** INV19, INV22

**Preconditions:**
- Attacker controls multiple addresses
- Attacker attempts mass registration

**Steps:**
1. Attacker declares presence for 100 addresses
2. Each requires on-chain transaction (gas cost)
3. Attacker announces all 100 nodes

**Expected Results:**
- Economic cost limits attack scale
- Each node requires valid presence
- Peer scoring can deprioritize suspicious nodes

---

### TC-DISC-062: Eclipse Attack Prevention
**Category:** Security

**Preconditions:**
- Attacker controls multiple nodes
- Attacker attempts to isolate victim

**Steps:**
1. Attacker floods victim with announcements
2. Victim verifies each against on-chain
3. Victim maintains diverse peer list

**Expected Results:**
- All attackers must have valid presence (cost)
- Victim should prefer validators (trusted)
- Multiple discovery sources recommended

---

## 8. Edge Cases

### TC-DISC-070: Empty Peer List Query
**Category:** Edge Case

**Preconditions:**
- Epoch just started
- No other nodes have announced

**Steps:**
1. Node A sends `NODE_QUERY`
2. Discovery peer has empty list

**Expected Results:**
- Empty response returned (nodes: [])
- total: 0, hasMore: false
- Node A should retry or query chain

---

### TC-DISC-071: Maximum Message Size
**Category:** Boundary

**Preconditions:**
- Response would contain 100+ nodes

**Steps:**
1. Query returns large response
2. Pagination kicks in

**Expected Results:**
- Max 100 nodes per response
- hasMore: true indicates more available
- Client handles pagination correctly

---

### TC-DISC-072: Concurrent Announcements
**Category:** Concurrency

**Preconditions:**
- Multiple nodes announce simultaneously

**Steps:**
1. Node A, B, C announce within same second
2. Peer D receives all three

**Expected Results:**
- All valid announcements processed
- No race conditions
- Peer list contains all three nodes

---

## Summary

| Category | Test Cases | Coverage |
|----------|------------|----------|
| Bootstrap | TC-DISC-001 to 003 | Initial join scenarios |
| Announcement | TC-DISC-010 to 015 | Message validation |
| Query | TC-DISC-020 to 023 | Peer list queries |
| Maintenance | TC-DISC-030 to 033 | TTL and lifecycle |
| Verification | TC-DISC-040 to 042 | On-chain checks |
| Epoch Transition | TC-DISC-050 to 052 | Cross-epoch rules |
| Security | TC-DISC-060 to 062 | Attack resistance |
| Edge Cases | TC-DISC-070 to 072 | Boundary conditions |

---

## References

- discovery.md v0.6.3 — Discovery specification
- invariants.md v0.6.1 — Protocol invariants
- message-catalog.md v0.6.2 — Message types

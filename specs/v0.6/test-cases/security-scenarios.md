# 7ay Proof of Presence (PoP)
## Test Cases — Security Scenarios
**Version:** v0.6.3
**Status:** Draft

---

## 1. Signature Verification Scenarios

### TC-SEC-001: Valid ECDSA Signature
**Category:** Happy Path
**Invariants:** INV24

**Preconditions:**
- Node A has valid keypair
- Message properly constructed

**Steps:**
1. Construct message hash:
   ```
   payloadHash = keccak256(payload)
   messageHash = keccak256(type || sender || epochId || timestamp || nonce || payloadHash)
   ```
2. Apply EIP-191 prefix:
   ```
   ethHash = keccak256("\x19Ethereum Signed Message:\n32" || messageHash)
   ```
3. Sign: `signature = sign(ethHash, privateKey)`
4. Send message with signature

**Expected Results:**
- Receiver recovers correct address via ecrecover
- Signature verification passes
- Message accepted

---

### TC-SEC-002: Forged Signature
**Category:** Attack
**Invariants:** INV24

**Preconditions:**
- Attacker creates message claiming to be from Node A
- Attacker does not have A's private key

**Steps:**
1. Attacker constructs message with sender: A.address
2. Attacker signs with different private key
3. Attacker sends message

**Expected Results:**
- ecrecover returns attacker's address, not A's
- Signature verification fails
- Message rejected and logged

---

### TC-SEC-003: Corrupted Signature
**Category:** Error Handling
**Invariants:** INV24

**Preconditions:**
- Valid message with corrupted signature bytes

**Steps:**
1. Create valid signed message
2. Flip random bits in signature
3. Send corrupted message

**Expected Results:**
- ecrecover fails or returns garbage address
- Signature verification fails
- Message rejected

---

### TC-SEC-004: Wrong Message Hash
**Category:** Attack
**Invariants:** INV24

**Preconditions:**
- Attacker modifies message after signing

**Steps:**
1. Node A signs message with nonce=1
2. Attacker intercepts and changes nonce=2
3. Attacker forwards modified message

**Expected Results:**
- Receiver computes different hash
- Signature invalid for modified message
- Attack detected

---

### TC-SEC-005: Missing Signature
**Category:** Error Handling
**Invariants:** INV24

**Preconditions:**
- Message with empty signature field

**Steps:**
1. Send message with signature: "0x" or null

**Expected Results:**
- Validation fails immediately
- Message rejected
- No crash or undefined behavior

---

## 2. Replay Attack Prevention

### TC-SEC-010: Basic Replay Attack
**Category:** Attack
**Invariants:** INV25

**Preconditions:**
- Valid signed message captured
- Nonce tracking enabled

**Steps:**
1. Node A sends valid message (nonce=5, epochId=42)
2. Attacker captures message
3. Attacker replays exact message

**Expected Results:**
- Receiver checks: usedNonces[A][42][5] == true
- Replay detected and rejected
- "Nonce already used" error

---

### TC-SEC-011: Cross-Epoch Replay
**Category:** Attack
**Invariants:** INV23, INV25

**Preconditions:**
- Valid message from epoch 41
- Epoch 42 now active

**Steps:**
1. Attacker replays epoch 41 message to epoch 42 peers

**Expected Results:**
- Epoch check fails (message.epochId != current)
- Message rejected before nonce check
- Epoch binding prevents cross-epoch replay

---

### TC-SEC-012: Nonce Exhaustion
**Category:** Boundary
**Invariants:** INV25

**Preconditions:**
- Node sends many messages

**Steps:**
1. Node uses nonces 1, 2, 3, ... up to 2^256-1

**Expected Results:**
- Nonces are unique per (sender, epoch)
- New epoch resets nonce space
- Practical limit never reached

---

### TC-SEC-013: Nonce Reuse Detection
**Category:** Attack
**Invariants:** INV25

**Preconditions:**
- Node A accidentally uses same nonce twice

**Steps:**
1. Node A sends message with nonce=7
2. Node A sends different message with nonce=7

**Expected Results:**
- Second message rejected
- Sender should increment nonces properly
- Protocol enforces uniqueness

---

## 3. Sybil Attack Resistance

### TC-SEC-020: Mass Identity Creation
**Category:** Attack
**Invariants:** INV19, INV22

**Preconditions:**
- Attacker controls 1000 addresses
- Attacker has limited ETH

**Steps:**
1. Attacker attempts to declare presence for all 1000
2. Each requires on-chain transaction
3. Calculate total gas cost

**Expected Results:**
- Significant ETH required (gas * 1000)
- Economic barrier limits attack scale
- Each identity requires ongoing costs

---

### TC-SEC-021: Single Address Multiple Nodes
**Category:** Attack
**Invariants:** INV19

**Preconditions:**
- Attacker tries to run multiple nodes with same address

**Steps:**
1. Address A declares presence once
2. Attacker runs 10 nodes claiming address A
3. All announce to network

**Expected Results:**
- Only one valid presence on-chain
- Duplicate announcements have same identity
- No amplification benefit

---

### TC-SEC-022: Identity Without Presence
**Category:** Attack
**Invariants:** INV22

**Preconditions:**
- Attacker announces without on-chain presence

**Steps:**
1. Attacker creates valid signature
2. Attacker sends NODE_ANNOUNCE
3. Receiver verifies on-chain

**Expected Results:**
- presenceState returns None
- Verification fails (no presence)
- Node rejected from peer list

---

## 4. Eclipse Attack Prevention

### TC-SEC-030: Peer List Flooding
**Category:** Attack

**Preconditions:**
- Attacker controls many nodes
- Victim has small peer list

**Steps:**
1. Attacker nodes flood victim with announcements
2. Attacker nodes respond to all queries
3. Victim's peer list filled with attackers

**Expected Results:**
- Max peer list size enforced
- Diversity requirements (validators preferred)
- Victim should use multiple discovery sources

---

### TC-SEC-031: Query Response Manipulation
**Category:** Attack

**Preconditions:**
- Attacker is discovery peer

**Steps:**
1. Victim queries for peers
2. Attacker returns only attacker-controlled nodes

**Expected Results:**
- Victim verifies each node on-chain
- Victim should query multiple peers
- Majority response comparison

---

### TC-SEC-032: Bootstrap Manipulation
**Category:** Attack

**Preconditions:**
- Attacker compromises bootstrap source

**Steps:**
1. Victim requests seeds from compromised source
2. Attacker returns only malicious seeds

**Expected Results:**
- Multiple bootstrap sources recommended
- On-chain verification catches invalid nodes
- DNS seeds + static seeds + chain query

---

## 5. Denial of Service Prevention

### TC-SEC-040: Announcement Flood
**Category:** Attack

**Preconditions:**
- Attacker sends high volume of announcements

**Steps:**
1. Attacker creates valid presences for N addresses
2. Attacker floods network with announcements
3. Each announcement is technically valid

**Expected Results:**
- Rate limiting on message acceptance
- Per-sender rate limits
- Bandwidth/CPU limits per peer

---

### TC-SEC-041: Query Flood
**Category:** Attack

**Preconditions:**
- Attacker sends many queries

**Steps:**
1. Attacker sends 1000 queries per second
2. Discovery peer receives flood

**Expected Results:**
- Rate limiting kicks in
- Attacker blocked/throttled
- Service remains available for others

---

### TC-SEC-042: Large Response Attack
**Category:** Attack

**Preconditions:**
- Attacker controls discovery peer

**Steps:**
1. Victim sends query
2. Attacker responds with huge payload

**Expected Results:**
- Response size limits enforced (max 100 nodes)
- Pagination required for large results
- Receiver drops oversized messages

---

### TC-SEC-043: Stale Announcement Accumulation
**Category:** Attack

**Preconditions:**
- Attacker sends announcements with max TTL
- Never re-announces or leaves

**Steps:**
1. Attacker declares, announces, disappears
2. Repeat for many addresses
3. Victim accumulates stale entries

**Expected Results:**
- TTL expiry removes stale entries
- Periodic verification catches gone nodes
- Max peer list prevents unbounded growth

---

## 6. State Manipulation Attacks

### TC-SEC-050: False State Sync Response
**Category:** Attack
**Invariants:** INV26

**Preconditions:**
- Attacker is validator
- Attacker sends false state

**Steps:**
1. Victim requests state sync
2. Attacker returns modified state
3. Attacker claims wrong presences

**Expected Results:**
- stateRoot verification fails
- Victim recomputes and detects mismatch
- Attacker flagged and reported

---

### TC-SEC-051: Omission Attack
**Category:** Attack
**Invariants:** INV26

**Preconditions:**
- Attacker omits some presences from response

**Steps:**
1. Victim requests complete sync
2. Attacker excludes target presence
3. Victim applies incomplete state

**Expected Results:**
- stateRoot will not match
- Victim detects inconsistency
- Must verify with multiple validators

---

### TC-SEC-052: State Diff Injection
**Category:** Attack

**Preconditions:**
- Attacker sends fake state diff

**Steps:**
1. Attacker broadcasts STATE_DIFF
2. Includes fabricated operations
3. Claims false stateRoot

**Expected Results:**
- Signature verification (is sender validator?)
- stateRoot verification after apply
- Reject if inconsistent

---

## 7. Validator-Specific Attacks

### TC-SEC-060: Validator Impersonation
**Category:** Attack
**Invariants:** INV22

**Preconditions:**
- Attacker claims validator role
- Attacker is not registered validator

**Steps:**
1. Attacker sends announcement with role: Validator
2. Receiver verifies on-chain

**Expected Results:**
- isValidatorActive returns false
- Role claim rejected
- Node not treated as validator

---

### TC-SEC-061: Validator Collusion
**Category:** Attack

**Preconditions:**
- Majority of validators compromised

**Steps:**
1. Colluding validators provide false state
2. All return same wrong stateRoot
3. Victim can't detect by majority vote

**Expected Results:**
- Ultimate truth is on-chain
- Victim can query chain directly
- Byzantine fault tolerance limited to 2/3

---

### TC-SEC-062: Validator Key Compromise
**Category:** Attack

**Preconditions:**
- Single validator key compromised

**Steps:**
1. Attacker signs messages as validator
2. Sends false attestations
3. Other validators disagree

**Expected Results:**
- Minority vote doesn't change outcome
- Quorum still requires 2/3
- Compromised validator can be removed

---

## 8. Information Leakage

### TC-SEC-070: Presence Enumeration
**Category:** Privacy

**Preconditions:**
- Attacker wants list of all participants

**Steps:**
1. Attacker queries for all nodes
2. Attacker enumerates peer lists
3. Attacker builds participant database

**Expected Results:**
- This is partially unavoidable in discovery
- On-chain presence is already public
- Consider rate limiting queries

---

### TC-SEC-071: Epoch Activity Tracking
**Category:** Privacy

**Preconditions:**
- Attacker monitors epochs

**Steps:**
1. Track which addresses active in which epochs
2. Build activity patterns

**Expected Results:**
- On-chain activity is public
- Off-chain could add obfuscation
- Accept as protocol tradeoff

---

### TC-SEC-072: Query Pattern Analysis
**Category:** Privacy

**Preconditions:**
- Attacker monitors query patterns

**Steps:**
1. Log all queries from victim
2. Analyze interests and contacts

**Expected Results:**
- Consider aggregated queries
- Response caching reduces patterns
- Accept some leakage risk

---

## 9. Implementation Vulnerabilities

### TC-SEC-080: Integer Overflow in Nonce
**Category:** Implementation

**Preconditions:**
- Nonce stored as uint256

**Steps:**
1. Use nonce = 2^256 - 1
2. Try to increment

**Expected Results:**
- Solidity 0.8+ reverts on overflow
- Practically unreachable limit
- No vulnerability

---

### TC-SEC-081: Timestamp Manipulation
**Category:** Implementation

**Preconditions:**
- Message timestamp in past/future

**Steps:**
1. Send message with timestamp = 0
2. Send message with timestamp = block.timestamp + 1 year

**Expected Results:**
- Reasonable timestamp window enforced
- Reject messages with extreme timestamps
- Prevent timestamp-based attacks

---

### TC-SEC-082: Gas Exhaustion via Verification
**Category:** Implementation

**Preconditions:**
- On-chain verification costs gas

**Steps:**
1. Attacker floods with messages
2. Each triggers on-chain check
3. Victim's RPC quota exhausted

**Expected Results:**
- Signature check is off-chain (cheap)
- Cache verification results
- Rate limit before on-chain calls

---

## 10. Protocol-Level Attacks

### TC-SEC-090: Fork Confusion
**Category:** Protocol

**Preconditions:**
- Chain fork occurs

**Steps:**
1. Nodes on different forks
2. State sync across forks
3. Inconsistent state

**Expected Results:**
- Wait for finality before trusting state
- Handle reorgs gracefully
- Re-sync after fork resolution

---

### TC-SEC-091: Time Manipulation
**Category:** Protocol

**Preconditions:**
- Block timestamps can vary

**Steps:**
1. Miner manipulates block timestamp
2. Affects TTL calculations
3. Affects dispute windows

**Expected Results:**
- Use block numbers where possible
- Accept reasonable timestamp variance
- Critical logic on-chain (validator check)

---

### TC-SEC-092: Smart Contract Vulnerability
**Category:** Protocol

**Preconditions:**
- Bug in PresenceRegistry

**Steps:**
1. Attacker exploits contract bug
2. Gains unauthorized presence
3. Participates in protocol

**Expected Results:**
- Thorough contract auditing
- Upgrade mechanism if needed
- Protocol can recover from contract issues

---

## Summary

| Category | Test Cases | Threat Model |
|----------|------------|--------------|
| Signature Verification | TC-SEC-001 to 005 | Forgery, corruption |
| Replay Prevention | TC-SEC-010 to 013 | Message replay |
| Sybil Resistance | TC-SEC-020 to 022 | Identity spam |
| Eclipse Prevention | TC-SEC-030 to 032 | Peer manipulation |
| DoS Prevention | TC-SEC-040 to 043 | Resource exhaustion |
| State Manipulation | TC-SEC-050 to 052 | False state |
| Validator Attacks | TC-SEC-060 to 062 | Validator compromise |
| Information Leakage | TC-SEC-070 to 072 | Privacy concerns |
| Implementation | TC-SEC-080 to 082 | Code bugs |
| Protocol-Level | TC-SEC-090 to 092 | Systemic issues |

---

## Security Properties

### Guaranteed by Protocol:
- **INV24**: Signature verification prevents forgery
- **INV25**: Nonce uniqueness prevents replay
- **INV22**: On-chain presence gates discovery
- **INV26**: Deterministic reconciliation enables verification

### Mitigated but Not Eliminated:
- Sybil attacks (economic cost barrier)
- Eclipse attacks (diversity + verification)
- DoS attacks (rate limiting + quotas)
- Validator collusion (limited to 1/3 tolerance)

### Accept as Tradeoffs:
- Public presence enumeration
- Validator identity visibility
- Some query pattern leakage

---

## References

- invariants.md v0.6.1 — Security invariants
- message-catalog.md v0.6.2 — Message security
- discovery.md v0.6.3 — Security considerations
- state-sync.md v0.6.1 — Sync security

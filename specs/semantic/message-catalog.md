# 7ay Proof of Presence (PoP)
## Protocol Specification — Message Catalog
**Version:** v0.6.9
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** node-model.md v0.6.2, state-sync.md v0.6.1, invariants.md v0.6.9

---

## 1. Purpose

This specification defines the **Message Catalog** for the 7ay Presence Protocol's
semantic layer.

Messages are the vocabulary for off-chain node coordination. This catalog defines
all message types, their structure, validation rules, and usage.

This specification defines:
- Message envelope structure
- Message type catalog
- Validation rules per message type
- Signature and replay protection

This version does **NOT** define:
- Transport layer (TCP, UDP, WebSocket)
- Encoding format (implementation choice)
- Network topology
- Delivery guarantees

### 1.1 Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Message Exchange | **Off-chain (P2P)** | Messages sent between nodes via P2P network |
| Chain Binding (INV43) | **On-chain** | `chain_id` verified against `pallet-messaging` |
| Nonce Tracking (INV25) | **On-chain** | Nonce uniqueness enforced in `pallet-messaging` |
| Signature Verification | **Off-chain** | Verified by receiving node against sender's public key |
| Epoch Reference | **On-chain** | `epochId` validated against `pallet-epochs` |
| Sender Presence | **On-chain** | Sender's presence validated against `pallet-presence` |

---

## 2. Message Envelope

### 2.1 Envelope Structure

All messages share a common envelope:

```typescript
interface MessageEnvelope {
  // Protocol version
  version: "0.6.9";

  // Message classification
  type: MessageType;

  // Sender identification
  sender: NodeIdentity;

  // Epoch context
  epochId: uint256;

  // Temporal data
  timestamp: uint256;        // Unix timestamp (seconds)

  // Replay protection
  nonce: bytes32;            // Random 32-byte nonce
  chain_id: uint64;          // Chain identifier (prevents cross-chain replay)
  block_bound: uint64;       // Message expiration block number

  // Cryptographic signature
  signature: bytes;          // ECDSA signature (65 bytes)

  // Message-specific data
  payload: MessagePayload;
}
```

### 2.2 Chain Binding (INV43)

Messages are bound to a specific chain and block range:

- `chain_id` MUST match the current chain identifier
- `block_bound` specifies the maximum block number for message validity
- Messages with `current_block > block_bound` MUST be rejected
- Recommended `block_bound` = `current_block + 100` (~20 minutes on most chains)

```
∀ msg:
  msg.chain_id == currentChainId ∧
  currentBlock <= msg.block_bound
```

### 2.3 Message Type Enum

```typescript
enum MessageType {
  // Discovery (0x01-0x0F)
  NODE_ANNOUNCE = 0x01,
  NODE_QUERY = 0x02,
  NODE_RESPONSE = 0x03,
  NODE_LEAVE = 0x04,

  // State Sync (0x10-0x1F)
  STATE_SYNC_REQUEST = 0x10,
  STATE_SYNC_RESPONSE = 0x11,
  STATE_VECTOR_CLOCK = 0x12,
  STATE_DIFF = 0x13,

  // Attestation (0x20-0x2F)
  PRESENCE_ATTESTATION = 0x20,
  VALIDATION_VOTE = 0x21,
  DISPUTE_NOTICE = 0x22,

  // Media (0x30-0x3F) — v0.6.4
  MEDIA_ANNOUNCE = 0x30,
  MEDIA_REQUEST = 0x31,
  MEDIA_RESPONSE = 0x32,
  MEDIA_REVOKE = 0x33,

  // Boomerang (0x40-0x4F) — v0.6.5
  BOOMERANG_SEND = 0x40,
  BOOMERANG_ACK = 0x41,
  BOOMERANG_RETURN = 0x42,
  BOOMERANG_COMPLETE = 0x43,

  // Autonomous (0x50-0x5F) — v0.6.6
  AUTONOMOUS_INTENT = 0x50,
  AUTONOMOUS_PATTERN = 0x51,
  AUTONOMOUS_EXECUTE = 0x52,
  AUTONOMOUS_FINALIZE = 0x53,
  AUTONOMOUS_REVOKE = 0x54,

  // Octopus (0x60-0x6F) — v0.6.7
  OCTOPUS_THRESHOLD = 0x60,
  OCTOPUS_DIVIDE = 0x61,
  OCTOPUS_SUBNODE = 0x62,
  OCTOPUS_COORDINATE = 0x63,
  OCTOPUS_MERGE = 0x64,
  OCTOPUS_STATE_SHARE = 0x65
}
```

### 2.4 Signature Scheme

All messages MUST be signed by the sender:

```
signaturePayload = keccak256(
  abi.encodePacked(
    version,           // "0.6.9"
    type,              // uint8
    sender.address,    // address
    epochId,           // uint256
    timestamp,         // uint256
    nonce,             // bytes32
    chain_id,          // uint64 (NEW: chain binding)
    block_bound,       // uint64 (NEW: expiration)
    keccak256(payload) // bytes32
  )
)

signature = ecdsaSign(signaturePayload, senderPrivateKey)
```

### 2.5 Signature Verification

```
function verifySignature(message: MessageEnvelope) → bool:
  // 1. Verify chain binding (INV43)
  if message.chain_id != currentChainId:
    return false

  // 2. Verify block bound (INV43)
  if currentBlock > message.block_bound:
    return false

  // 3. Verify signature
  signaturePayload = keccak256(abi.encodePacked(
    message.version,
    message.type,
    message.sender.address,
    message.epochId,
    message.timestamp,
    message.nonce,
    message.chain_id,
    message.block_bound,
    keccak256(message.payload)
  ))

  recoveredAddress = ecrecover(signaturePayload, message.signature)
  return recoveredAddress == message.sender.address
```

---

## 3. Discovery Messages

### 3.1 NODE_ANNOUNCE (0x01)

Broadcast node availability to the network.

```typescript
interface NodeAnnouncePayload {
  // Full node information
  node: Node;

  // Discovery endpoints (optional)
  endpoints?: string[];

  // Time-to-live in seconds
  ttl: uint256;
}
```

**Validation Rules:**
- `node.identity.address` MUST equal `sender.address`
- `node.epoch.epochId` MUST equal `epochId`
- `ttl` SHOULD be <= 3600 (1 hour)
- Epoch MUST be Active

**Usage:**
- Sent when a node joins an epoch
- Periodically re-announced before TTL expires
- Broadcast to discovery peers

### 3.2 NODE_QUERY (0x02)

Request nodes matching criteria.

```typescript
interface NodeQueryPayload {
  // Filter criteria
  filter: {
    role?: NodeRole;              // Filter by role
    capabilities?: NodeCapability[]; // Filter by capabilities
    limit?: uint256;              // Max results
  };

  // Pagination
  offset?: uint256;
}
```

**Validation Rules:**
- `limit` SHOULD be <= 100
- Sender MUST have valid presence in epoch

**Usage:**
- Request validator nodes for sync
- Discover peers in epoch
- Directed to known discovery peers

### 3.3 NODE_RESPONSE (0x03)

Response to NODE_QUERY.

```typescript
interface NodeResponsePayload {
  // Query echo (for correlation)
  queryNonce: bytes32;

  // Matching nodes
  nodes: MinimalNode[];

  // Pagination info
  total: uint256;
  hasMore: bool;
}
```

**Validation Rules:**
- `queryNonce` MUST match a pending query
- All nodes MUST have valid presence in the queried epoch
- `nodes.length` MUST be <= query limit

**Usage:**
- Response to NODE_QUERY
- Contains discovered peer information

### 3.4 NODE_LEAVE (0x04)

Announce node departure from epoch.

```typescript
interface NodeLeavePayload {
  // Reason for leaving
  reason: LeaveReason;
}

enum LeaveReason {
  VOLUNTARY = 0,      // Explicit exit
  EPOCH_CLOSING = 1,  // Epoch transitioning to Closed
  SLASHED = 2         // Actor was slashed
}
```

**Validation Rules:**
- Sender MUST have had valid presence
- Broadcast once per departure

**Usage:**
- Clean exit from epoch
- Allows peers to update node lists

---

## 4. State Sync Messages

### 4.1 STATE_SYNC_REQUEST (0x10)

Request state synchronization with a peer.

```typescript
interface StateSyncRequestPayload {
  // Sync mode
  mode: SyncMode;

  // For partial sync: starting point
  fromVector?: StateVector;

  // Requested state types
  include: StateType[];
}

enum SyncMode {
  COMPLETE = 0,   // Full state transfer
  PARTIAL = 1     // Incremental from vector
}

enum StateType {
  PRESENCES = 0,
  VALIDATIONS = 1,
  DISPUTES = 2
}
```

**Validation Rules:**
- Sender MUST be a validator (for StateSync capability)
- `fromVector` required if `mode == PARTIAL`
- Epoch MUST be Active or Closed

**Usage:**
- Validator-to-validator sync
- New validator joining epoch

### 4.2 STATE_SYNC_RESPONSE (0x11)

Response to STATE_SYNC_REQUEST.

```typescript
interface StateSyncResponsePayload {
  // Request correlation
  requestNonce: bytes32;

  // Current state vector
  currentVector: StateVector;

  // State data (based on mode)
  state?: EpochState;     // For COMPLETE mode
  diff?: StateDiff;       // For PARTIAL mode

  // Continuation
  hasMore: bool;
  continuationToken?: bytes32;
}

interface EpochState {
  epochId: uint256;
  presences: PresenceRecord[];
  validations: ValidationRecord[];
  disputes: DisputeRecord[];
}
```

**Validation Rules:**
- `requestNonce` MUST match pending request
- State data MUST be verifiable against on-chain
- Sender MUST be a validator

**Usage:**
- Complete or partial state transfer
- May require multiple responses for large states

### 4.3 STATE_VECTOR_CLOCK (0x12)

Exchange vector clock for consistency check.

```typescript
interface StateVectorClockPayload {
  // Current vector clock
  vectorClock: VectorClock;

  // State root for quick comparison
  stateRoot: bytes32;
}

interface VectorClock {
  epochId: uint256;
  entries: Map<Address, uint256>;  // node → logical timestamp
}
```

**Validation Rules:**
- Sender MUST be a validator
- `epochId` MUST match message `epochId`

**Usage:**
- Quick consistency check
- Determine sync necessity
- Detect divergence

### 4.4 STATE_DIFF (0x13)

Push incremental state update.

```typescript
interface StateDiffPayload {
  // Vector clock context
  fromVector: StateVector;
  toVector: StateVector;

  // Changes
  changes: StateChange[];
}

interface StateChange {
  type: StateChangeType;
  actor: Address;
  data: bytes;
}

enum StateChangeType {
  PRESENCE_DECLARED = 0,
  PRESENCE_VALIDATED = 1,
  PRESENCE_FINALIZED = 2,
  DISPUTE_INITIATED = 3,
  DISPUTE_VOTED = 4,
  DISPUTE_RESOLVED = 5
}
```

**Validation Rules:**
- Sender MUST be a validator
- Changes MUST be verifiable against on-chain
- `fromVector` MUST match recipient's current vector

**Usage:**
- Proactive state push
- Real-time sync updates

---

## 5. Attestation Messages

### 5.1 PRESENCE_ATTESTATION (0x20)

Validator attests to presence observation.

```typescript
interface PresenceAttestationPayload {
  // Attested presence
  actor: Address;

  // Observation details
  observedAt: uint256;
  evidenceHash: bytes32;  // Optional evidence reference
}
```

**Validation Rules:**
- Sender MUST be a validator
- `actor` MUST have presence in epoch
- `observedAt` MUST be within epoch bounds

**Usage:**
- Pre-vote attestation
- Evidence sharing

### 5.2 VALIDATION_VOTE (0x21)

Broadcast validation vote intent.

```typescript
interface ValidationVotePayload {
  // Target presence
  actor: Address;

  // Vote intent
  vote: bool;  // true = validate, false = abstain

  // Optional rationale
  rationaleHash?: bytes32;
}
```

**Validation Rules:**
- Sender MUST be a validator
- Sender MUST NOT have voted on-chain for this presence
- `actor` MUST be in Declared state

**Usage:**
- Off-chain vote coordination
- Intent signaling before on-chain tx

### 5.3 DISPUTE_NOTICE (0x22)

Broadcast dispute initiation or update.

```typescript
interface DisputeNoticePayload {
  // Disputed presence
  actor: Address;

  // Dispute details
  action: DisputeAction;
  evidenceHash: bytes32;
}

enum DisputeAction {
  INITIATED = 0,
  VOTE_CAST = 1,
  RESOLVED = 2
}
```

**Validation Rules:**
- Sender MUST be a validator (for VOTE_CAST)
- `actor` MUST have presence in epoch
- Dispute MUST exist on-chain (for updates)

**Usage:**
- Dispute coordination
- Evidence sharing
- Resolution notification

---

## 6. Message Validation

### 6.1 Common Validation

All messages MUST pass:

1. **Version check**: `version == "0.6.9"`
2. **Type validity**: `type` in defined range
3. **Epoch check**: `epochId` exists and supports signals
4. **Chain binding**: `chain_id == currentChainId` (INV43)
5. **Block bound**: `currentBlock <= block_bound` (INV43)
6. **Signature**: Valid ECDSA signature from sender
7. **Presence check**: Sender has valid presence (for most messages)
8. **Nonce check**: Nonce not previously used by sender in epoch
9. **Timestamp**: Within acceptable window (±5 minutes)

### 6.2 Validation Order

```
1. version      → MSG_008
2. type         → MSG_001
3. chain_id     → MSG_009 (INV43)
4. block_bound  → MSG_010 (INV43)
5. epochId      → MSG_004
6. signature    → MSG_002
7. presence     → MSG_005
8. nonce        → MSG_003
9. timestamp    → MSG_006
10. payload     → MSG_007
```

### 6.3 Error Responses

See `errors.md v0.6.9` for error codes:
- MSG_001: InvalidMessageType
- MSG_002: InvalidSignature
- MSG_003: NonceReused
- MSG_004: EpochMismatch
- MSG_005: SenderNotInEpoch
- MSG_006: MessageExpired
- MSG_007: InvalidPayload
- MSG_008: VersionMismatch
- MSG_009: ChainMismatch (INV43)
- MSG_010: BlockBoundExceeded (INV43)

---

## 7. Invariants

### 7.1 Message Invariants

**INV23: Epoch-Bound Messages**
All messages MUST reference a valid epoch with sufficient capability.

**INV24: Signature Validity**
Message signature MUST verify against sender's address.

**INV25: Nonce Uniqueness**
Each (sender, nonce) pair MUST be unique within an epoch.

**INV43: Chain Binding** (v0.6.9)
Messages MUST be bound to the current chain and within block bounds.

```
∀ msg:
  msg.chain_id == currentChainId ∧
  currentBlock <= msg.block_bound
```

This invariant prevents:
- **Cross-chain replay**: Messages cannot be replayed on different chains
- **Delayed replay**: Messages expire after block_bound, preventing replay attacks
- **Fork attacks**: Messages signed for one fork are invalid on others

### 7.2 Enforcement

See `invariants.md v0.6.9` for formal definitions.

---

## 8. Security Considerations

### 8.1 Replay Protection (Enhanced v0.6.9)

Replay attacks are prevented by multiple layers:
- **Unique nonce** per message (INV25)
- **Epoch binding** (messages invalid after epoch closes)
- **Timestamp validation** (±5 minute window)
- **Chain binding** via `chain_id` (INV43) — prevents cross-chain replay
- **Block bound** via `block_bound` (INV43) — prevents delayed replay

The chain binding mechanism ensures:
```
1. Messages cannot be replayed on forks or sidechains
2. Messages expire after ~100 blocks (~20 minutes)
3. Old signatures become invalid automatically
```

### 8.2 Spoofing Prevention

Sender spoofing is prevented by:
- ECDSA signature verification
- On-chain presence verification

### 8.3 Denial of Service

Mitigation:
- Rate limiting per sender
- Message size limits
- Nonce tracking bounds

---

## 9. Non-Goals

This specification explicitly does NOT define:

- Message routing or delivery
- Peer discovery protocols
- Connection management
- Encoding formats
- Compression

---

## 10. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 presence states | Used for validation |
| v0.4 validator logic | Used for role checks |
| Existing events | Not affected |
| On-chain functions | Used for verification |

---

## 11. References

- node-model.md v0.6 — Node structure
- state-sync.md v0.6 — Sync protocol
- invariants.md v0.6.9 — Protocol invariants INV19-26, INV43
- errors.md v0.6.9 — Error catalog
- presence.md v0.4 — Presence states
- validator.md v0.4 — Validator mechanics

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.6.2 | Initial message catalog specification |
| v0.6.4 | Added Media messages (0x30-0x33) |
| v0.6.5 | Added Boomerang messages (0x40-0x43) |
| v0.6.6 | Added Autonomous messages (0x50-0x54) |
| v0.6.7 | Added Octopus messages (0x60-0x65) |
| v0.6.9 | **Security hardening**: Added chain_id, block_bound to envelope; INV43 chain binding |

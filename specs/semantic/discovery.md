# 7ay Proof of Presence (PoP)
## Protocol Specification — Node Discovery
**Version:** v0.6.9
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** node-model.md v0.6.2, message-catalog.md v0.6.9, state-sync.md v0.6.1

---

## 1. Purpose

This specification defines the **Node Discovery** semantics for the 7ay Presence Protocol's
semantic layer.

Discovery enables nodes to find and connect with peers within an epoch. This specification
defines the discovery model, verification requirements, and operational semantics.

This specification defines:
- Discovery model and phases
- Node announcement and query semantics
- Identity verification requirements
- Epoch-scoped discovery rules

This version does **NOT** define:
- Transport layer (TCP, UDP, WebSocket)
- Peer-to-peer networking
- NAT traversal
- Bootstrap mechanisms

### 1.1 Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Peer Discovery | **Off-chain (P2P)** | Nodes discover each other via P2P protocol |
| Node Announcement | **Off-chain (P2P)** | NODE_ANNOUNCE broadcast to network |
| Presence Verification | **On-chain** | Validates sender presence via `pallet-presence` |
| Epoch Scoping (INV21) | **On-chain** | Epoch existence checked via `pallet-epochs` |
| Validator Role Check | **On-chain** | Validator status via `pallet-validators` |
| Rate Limiting (INV45) | **Off-chain** | Enforced in node software |
| Peer List | **Off-chain** | Maintained in node memory, not on-chain |

---

## 2. Discovery Model

### 2.1 Overview

Discovery operates in a decentralized, epoch-scoped manner:

```
                    ┌─────────────────────────────────────┐
                    │           Epoch Context             │
                    │                                     │
   ┌────────┐       │    ┌────────┐      ┌────────┐      │
   │  New   │ ──────┼───►│ Known  │─────►│  Peer  │      │
   │  Node  │       │    │  Peer  │      │  List  │      │
   └────────┘       │    └────────┘      └────────┘      │
       │            │         │               │          │
       │            │         ▼               ▼          │
       │            │    ┌────────┐      ┌────────┐      │
       └────────────┼───►│Announce│      │ Query  │      │
                    │    └────────┘      └────────┘      │
                    │                                     │
                    └─────────────────────────────────────┘
```

### 2.2 Discovery Phases

| Phase | Description | Messages |
|-------|-------------|----------|
| Bootstrap | Initial peer acquisition | Out of scope (implementation-specific) |
| Announcement | Broadcast presence to network | NODE_ANNOUNCE |
| Query | Request peer lists | NODE_QUERY, NODE_RESPONSE |
| Maintenance | Keep peer lists updated | NODE_ANNOUNCE (refresh), NODE_LEAVE |

### 2.3 Epoch Scoping (INV21)

**INV21: Discovery Epoch Scope**
Discovery MUST NOT return nodes from different epochs.

```
∀ query(epochId), response:
  ∀ node ∈ response.nodes:
    node.epochId == epochId
```

All discovery operations are strictly epoch-scoped:
- NODE_ANNOUNCE only valid for sender's current epoch
- NODE_QUERY returns only nodes in the queried epoch
- NODE_RESPONSE filtered by epoch before transmission

---

## 3. Node Announcement

### 3.1 Announcement Semantics

When a node joins an epoch, it announces its presence:

```
function announce(node: Node):
  // 1. Validate node has presence
  require node.presence.state ∈ {Declared, Validated, Finalized}

  // 2. Check epoch capability
  require epochCapability(node.epoch.epochId) >= PresenceWithSignals

  // 3. Create announcement message
  message = createNodeAnnounce(node, ttl=3600)

  // 4. Broadcast to known peers
  broadcast(message)
```

### 3.2 Announcement Lifecycle

```
                    TTL Expiry
                        │
    ┌──────────┐        │        ┌──────────┐
    │ Announce │────────┼───────►│ Expired  │
    └──────────┘        │        └──────────┘
         │              │              │
         │ Re-announce  │              │
         │ (before TTL) │              │
         ▼              │              │
    ┌──────────┐        │              │
    │ Active   │────────┘              │
    └──────────┘                       │
         │                             │
         │ NODE_LEAVE                  │
         ▼                             ▼
    ┌──────────┐                  ┌──────────┐
    │ Departed │                  │ Stale    │
    └──────────┘                  └──────────┘
```

### 3.3 TTL Management

- Default TTL: 3600 seconds (1 hour)
- Maximum TTL: 3600 seconds
- Re-announcement: Before TTL expires (recommended: TTL/2)
- Stale removal: After TTL expires without re-announcement

---

## 4. Node Query

### 4.1 Query Semantics

Nodes query for peers matching specific criteria:

```
function queryNodes(filter: NodeFilter, epochId: uint256) → Node[]:
  // 1. Validate requester has presence
  require presenceState(msg.sender, epochId) ∈ {Declared, Validated, Finalized}

  // 2. Build query message
  query = createNodeQuery(filter, epochId)

  // 3. Send to known discovery peers
  responses = await sendToDiscoveryPeers(query)

  // 4. Merge and deduplicate
  return mergeResponses(responses)
```

### 4.2 Filter Criteria

```typescript
interface NodeFilter {
  // Role filter
  role?: NodeRole;           // Participant | Validator

  // Capability filter
  capabilities?: NodeCapability[];

  // Pagination
  limit?: uint256;           // Max 100
  offset?: uint256;
}
```

### 4.3 Query Response

Response contains matching nodes with pagination info:

```typescript
interface QueryResponse {
  nodes: MinimalNode[];      // Matching nodes (max 100)
  total: uint256;            // Total matches
  hasMore: bool;             // More results available
}
```

---

## 5. Identity Verification

### 5.1 Verification Requirements (INV22)

**INV22: Presence-Gated Discovery**
Only nodes with valid presence are discoverable.

```
∀ node ∈ discoveredNodes:
  presenceState(node.address, node.epochId) ∈ {Declared, Validated, Finalized}
```

### 5.2 Verification Process

```
function verifyDiscoveredNode(node: MinimalNode) → bool:
  // 1. Check epoch exists and supports signals
  if epochCapability(node.epochId) < PresenceWithSignals:
    return false

  // 2. Verify presence on-chain
  state = presenceRegistry.presenceState(node.address, node.epochId)
  if state ∉ {Declared, Validated, Finalized}:
    return false

  // 3. Verify role claim (intentionally asymmetric)
  // Non-validators CANNOT claim Validator (no role upgrade without validator status)
  // Validators MAY announce as Participant (they may choose not to exercise validator privileges)
  isValidator = validatorRegistry.isValidatorActive(node.address)
  if node.role == Validator && !isValidator:
    return false

  return true
```

### 5.3 Verification Timing

| Scenario | When to Verify |
|----------|----------------|
| New peer | Before adding to peer list |
| Announcement received | Before processing |
| Query response | Before using results |
| Periodic refresh | Configurable interval (recommended: 5 min) |

---

## 6. Discovery Operations

### 6.1 Peer List Management

```typescript
interface PeerList {
  // Active peers by epoch
  peers: Map<EpochId, Map<Address, PeerEntry>>;

  // Operations
  add(node: MinimalNode, ttl: uint256): void;
  remove(address: Address, epochId: uint256): void;
  get(epochId: uint256): MinimalNode[];
  prune(): void;  // Remove expired entries
}

interface PeerEntry {
  node: MinimalNode;
  announcedAt: uint256;
  ttl: uint256;
  lastVerified: uint256;
}
```

### 6.2 Discovery Peer Selection

For query routing, select discovery peers:

```
function selectDiscoveryPeers(epochId: uint256, count: uint256) → Address[]:
  peers = peerList.get(epochId)

  // Prefer validators (they have StateSync capability)
  validators = peers.filter(p => p.role == Validator)
  participants = peers.filter(p => p.role == Participant)

  // Select up to count peers, prioritizing validators
  selected = validators.slice(0, count)
  if selected.length < count:
    selected.concat(participants.slice(0, count - selected.length))

  return selected.map(p => p.address)
```

### 6.3 Graceful Departure

When leaving an epoch:

```
function leaveEpoch(epochId: uint256, reason: LeaveReason):
  // 1. Create leave message
  message = createNodeLeave(reason)

  // 2. Broadcast to peers
  broadcast(message, epochId)

  // 3. Clear local state
  peerList.remove(self.address, epochId)
```

---

## 7. Error Handling

### 7.1 Discovery Errors

| Code | Name | Description | Invariant |
|------|------|-------------|-----------|
| DISC_001 | PeerNotFound | Requested peer not in list | - |
| DISC_002 | EpochMismatch | Node from different epoch | INV21 |
| DISC_003 | VerificationFailed | On-chain verification failed | INV22 |
| DISC_004 | PeerListFull | Maximum peers reached | - |
| DISC_005 | StaleAnnouncement | Announcement TTL expired | - |
| DISC_010 | RateLimited | Query rate limit exceeded | INV45 (v0.6.9) |
| DISC_011 | PresenceRequired | Sender lacks presence for query | INV45 (v0.6.9) |

### 7.2 Error Recovery

```
function handleDiscoveryError(error: DiscoveryError):
  switch error.code:
    case DISC_001:
      // Peer not found - normal, ignore
      return

    case DISC_002:
      // Epoch mismatch - reject and log
      log.warn("Received node from wrong epoch")
      return

    case DISC_003:
      // Verification failed - remove from peer list
      peerList.remove(error.node.address, error.node.epochId)
      return

    case DISC_004:
      // Peer list full - evict oldest entry
      peerList.evictOldest(error.epochId)
      retry()

    case DISC_005:
      // Stale announcement - remove entry
      peerList.remove(error.node.address, error.node.epochId)
      return

    case DISC_010:
      // Rate limited - wait and retry (v0.6.9)
      wait(query_cooldown_ms)
      retry()

    case DISC_011:
      // Presence required - declare presence first (v0.6.9)
      log.error("Must have presence to query discovery")
      return
```

---

## 8. Security Considerations

### 8.1 Sybil Resistance

Discovery inherits Sybil resistance from the presence system:
- Each node requires on-chain presence declaration (gas cost)
- Presence is tied to a unique Ethereum address
- Validator role requires permissioned registration

### 8.2 Eclipse Attack Prevention

Mitigations:
- Verify all discovered nodes against on-chain state
- Maintain diverse peer connections (validators + participants)
- Periodic re-verification of peer list
- Multiple discovery sources

### 8.3 Denial of Service

Mitigations:
- Rate limiting on announcements and queries (see Section 8.5)
- Maximum peer list size per epoch
- TTL enforcement
- Query result pagination (max 100)

### 8.5 Rate Limiting (v0.6.9 — INV45)

Discovery queries are rate limited to prevent network enumeration and DoS attacks.

#### 8.5.1 Configuration

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| max_queries_per_minute | 60 | 10-300 | Prevent enumeration attacks |
| max_response_nodes | 50 | 10-200 | Limit response size |
| require_presence_for_query | true | bool | Sybil resistance |
| query_cooldown_ms | 1000 | 100-5000 | Minimum time between queries |

#### 8.5.2 Query Validation

```typescript
interface RateLimitState {
  queryCount: Map<Address, number>;  // queries in current minute
  lastQueryTime: Map<Address, uint256>;
  windowStart: uint256;
}

function validateQuery(
  sender: Address,
  epochId: uint256,
  state: RateLimitState
): Result<void, DiscoveryError> {
  // 1. Check rate limit (INV45)
  const currentMinute = block.timestamp / 60;
  if (currentMinute != state.windowStart) {
    state.queryCount.clear();
    state.windowStart = currentMinute;
  }

  const count = state.queryCount.get(sender) || 0;
  if (count >= config.max_queries_per_minute) {
    return Err(DISC_010_RateLimited);
  }

  // 2. Check cooldown
  const lastQuery = state.lastQueryTime.get(sender) || 0;
  if (block.timestamp - lastQuery < config.query_cooldown_ms / 1000) {
    return Err(DISC_010_RateLimited);
  }

  // 3. Check presence requirement (Sybil resistance)
  if (config.require_presence_for_query) {
    const presence = presenceRegistry.presenceState(sender, epochId);
    if (presence == PresenceState.None) {
      return Err(DISC_011_PresenceRequired);
    }
  }

  // Update state
  state.queryCount.set(sender, count + 1);
  state.lastQueryTime.set(sender, block.timestamp);

  return Ok();
}
```

#### 8.5.3 Invariant (INV45)

**INV45: Discovery Rate Limit**
Query frequency MUST NOT exceed the configured rate limit.

```
∀ sender, minute:
  count(queries(sender, minute)) <= max_queries_per_minute
```

#### 8.5.4 Paginated Responses

Responses are paginated to limit resource usage:

```typescript
interface PaginatedQueryResponse {
  nodes: MinimalNode[];           // max: max_response_nodes
  total: uint256;                 // total available matches
  hasMore: bool;
  nextOffset: uint256;            // for pagination
}
```

### 8.4 Information Leakage

Considerations:
- Peer lists reveal active participants
- Query patterns may reveal interests
- Mitigation: Aggregate queries, cache responses

---

## 9. Invariants

### 9.1 Discovery Invariants

**INV21: Discovery Epoch Scope** (Section 2.3)
Discovery MUST NOT return nodes from different epochs.

**INV22: Presence-Gated Discovery** (Section 5.1)
Only nodes with valid presence are discoverable.

**INV45: Discovery Rate Limit** (v0.6.9 — Section 8.5)
Query frequency MUST NOT exceed the configured rate limit.

```
∀ sender, minute:
  count(queries(sender, minute)) <= max_queries_per_minute
```

### 9.2 Related Invariants

See `invariants.md v0.6.9` for:
- INV19: Node Identity Derivability
- INV20: Epoch Binding
- INV23-25: Message invariants
- INV43: Chain Binding

---

## 10. Implementation Guidance

### 10.1 Bootstrap Strategies

Implementation-specific, but common patterns:
- **Static seeds**: Hardcoded known nodes
- **DNS seeds**: DNS records with node addresses
- **DHT**: Distributed hash table for peer discovery
- **Chain state**: Query on-chain events for active presences

### 10.2 Recommended Parameters

| Parameter | Recommended Value | Notes |
|-----------|-------------------|-------|
| Announcement TTL | 3600s (1 hour) | Balance freshness vs. overhead |
| Re-announce interval | 1800s (30 min) | TTL/2 |
| Max peers per epoch | 1000 | Memory/bandwidth tradeoff |
| Query timeout | 10s | Network conditions dependent |
| Verification interval | 300s (5 min) | Balance security vs. RPC load |
| Discovery peers | 3-5 | Redundancy vs. bandwidth |

### 10.3 Peer Scoring

Optional peer reputation for better selection:

```typescript
interface PeerScore {
  address: Address;
  score: number;  // 0-100

  // Factors
  uptime: number;         // Time since first seen
  responseRate: number;   // Query response success rate
  latency: number;        // Average response time
  validationRate: number; // On-chain verification success rate
}
```

---

## 11. Non-Goals

This specification explicitly does NOT define:

- Bootstrap node lists
- Peer-to-peer networking protocols
- NAT traversal mechanisms
- Connection management
- Bandwidth optimization

---

## 12. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 presence states | Used for verification |
| v0.4 validator logic | Used for role checks |
| Existing events | Not affected |
| On-chain functions | Used for verification |

---

## 13. References

- node-model.md v0.6.2 — Node structure
- message-catalog.md v0.6.2 — Discovery messages
- state-sync.md v0.6.1 — Sync protocol
- invariants.md v0.6.1 — Protocol invariants
- presence.md v0.4 — Presence states
- validator.md v0.4 — Validator mechanics

---

## 14. Changelog

| Version | Changes |
|---------|---------|
| v0.6.3 | Initial discovery specification |
| v0.6.9 | **Security hardening**: Rate limiting (INV45), presence requirement for queries, pagination |

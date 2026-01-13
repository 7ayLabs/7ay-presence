# 7ay Proof of Presence (PoP)
## Protocol Specification — Octopus Scaling
**Version:** v0.6.7
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** node-model.md v0.6.2, message-catalog.md v0.6.6, invariants.md v0.6.6

---

## 1. Purpose

This specification defines **Octopus Scaling** — a dynamic node division mechanism
for handling high message throughput.

When a node's message throughput exceeds a threshold (45%), it can divide into
multiple sub-nodes to distribute the load. When throughput drops below a lower
threshold (20%) for a sustained period, sub-nodes merge back into the parent.

This version defines:
- Threshold-based activation (INV38)
- Sub-node identity derivation (INV39)
- Sub-node limits (INV40)
- State consistency guarantees (INV41)
- Hysteresis-based deactivation (INV42)

---

## 2. Motivation

### 2.1 Problem Statement

In high-throughput epochs, individual nodes may become bottlenecks:
- Message processing latency increases
- Validation delays compound
- Network congestion affects reliability

### 2.2 Solution Overview

Octopus scaling allows a single logical node to operate as multiple physical
nodes ("tentacles") during high-load periods:

```
Normal Load:                    High Load (> 45%):
┌─────────┐                    ┌─────────────────────┐
│  Node   │                    │    Parent Node      │
│   (1)   │        =>          │         ↓           │
└─────────┘                    ├────┬────┬────┬────┤
                               │ S1 │ S2 │ S3 │ S4 │
                               └────┴────┴────┴────┘
                               (Up to 4 sub-nodes)
```

### 2.3 Key Properties

- **Transparent**: Other nodes interact with parent identity
- **Bounded**: Maximum 4 sub-nodes (2 divisions)
- **Reversible**: Sub-nodes merge when load decreases
- **Consistent**: State reconcilable across sub-nodes

---

## 3. Threshold Model

### 3.1 Activation Threshold (INV38)

```typescript
const ACTIVATION_THRESHOLD = 0.45;  // 45%
const MAX_THROUGHPUT = 1000;        // msgs/second (configurable)

function shouldActivate(currentThroughput: number): boolean {
  return currentThroughput > (MAX_THROUGHPUT * ACTIVATION_THRESHOLD);
}
```

**INV38: Activation Threshold**
Division MUST only occur when throughput exceeds 45% of capacity.

```
∀ division event:
  throughput[parent] / maxThroughput > 0.45
```

### 3.2 Deactivation Threshold (INV42)

```typescript
const DEACTIVATION_THRESHOLD = 0.20;  // 20%
const HYSTERESIS_WINDOW = 300;        // 5 minutes

function shouldDeactivate(
  currentThroughput: number,
  belowThresholdDuration: number
): boolean {
  const belowThreshold = currentThroughput < (MAX_THROUGHPUT * DEACTIVATION_THRESHOLD);
  return belowThreshold && belowThresholdDuration >= HYSTERESIS_WINDOW;
}
```

**INV42: Deactivation Hysteresis**
Merge MUST only occur when throughput remains below 20% for the hysteresis window.

```
∀ merge event:
  throughput[parent] / maxThroughput < 0.20 ∧
  duration(belowThreshold) ≥ HYSTERESIS_WINDOW
```

### 3.3 Threshold Diagram

```
Throughput %
    │
100%├─────────────────────────────────
    │
 45%├- - - - ACTIVATION THRESHOLD - - -
    │        ↑ Divide
    │        ↓ (Hysteresis prevents immediate merge)
 20%├- - - - DEACTIVATION THRESHOLD - -
    │        ↓ Merge (after sustained period)
  0%├─────────────────────────────────
    └────────────────────────────────→ Time
```

---

## 4. Sub-Node Identity

### 4.1 Identity Derivation (INV39)

Sub-node identities are derived from the parent node:

```typescript
function deriveSubNodeId(
  parentAddress: Address,
  subNodeIndex: number  // 0-3
): bytes32 {
  return keccak256(abi.encodePacked(parentAddress, subNodeIndex));
}
```

**INV39: Sub-Node Identity**
Sub-node identity MUST be deterministically derived from parent.

```
∀ subNode:
  subNode.id = keccak256(parentAddress, subNodeIndex)
```

### 4.2 Sub-Node Structure

```typescript
interface SubNode {
  // Derived identity
  id: bytes32;
  index: number;           // 0-3

  // Parent reference
  parent: {
    address: Address;
    epochId: uint256;
  };

  // Lifecycle
  activatedAt: uint256;
  lastActivity: uint256;

  // Load distribution
  assignedRange: {
    start: number;         // 0-255 hash range
    end: number;
  };
}
```

### 4.3 Sub-Node Limit (INV40)

**INV40: Sub-Node Limit**
A node MUST NOT have more than 4 sub-nodes.

```
∀ parent:
  count(subNodes[parent]) ≤ 4
```

Division can occur twice:
- First division: 1 → 2 sub-nodes
- Second division: 2 → 4 sub-nodes

```
Division 1:       Division 2:
    P                 P
   / \              / | | \
  S0  S1          S0 S1 S2 S3
```

---

## 5. Division Process

### 5.1 Division Sequence

```
1. Node detects throughput > 45%
2. Node sends OCTOPUS_THRESHOLD to validators
3. Validators acknowledge threshold
4. Node sends OCTOPUS_DIVIDE announcement
5. Node creates sub-nodes (2 or 4)
6. Each sub-node sends OCTOPUS_SUBNODE registration
7. Sub-nodes begin OCTOPUS_COORDINATE for load distribution
```

### 5.2 Load Distribution

Sub-nodes partition the message space by hash range:

```typescript
// 2 sub-nodes
S0: handles messages where hash(msg) % 256 in [0, 127]
S1: handles messages where hash(msg) % 256 in [128, 255]

// 4 sub-nodes
S0: handles messages where hash(msg) % 256 in [0, 63]
S1: handles messages where hash(msg) % 256 in [64, 127]
S2: handles messages where hash(msg) % 256 in [128, 191]
S3: handles messages where hash(msg) % 256 in [192, 255]
```

### 5.3 State Distribution

When dividing, parent state is distributed:

```typescript
function distributeState(
  parentState: NodeState,
  subNodes: SubNode[]
): Map<SubNode, NodeState> {
  const distribution = new Map();

  for (const item of parentState.items) {
    const hash = keccak256(item.id);
    const bucket = hash[0];  // First byte: 0-255
    const subNode = subNodes.find(s =>
      bucket >= s.assignedRange.start &&
      bucket <= s.assignedRange.end
    );
    distribution.get(subNode).items.push(item);
  }

  return distribution;
}
```

---

## 6. Merge Process

### 6.1 Merge Sequence

```
1. Parent detects sustained low throughput (< 20% for 5 min)
2. Parent sends OCTOPUS_MERGE announcement
3. Sub-nodes send OCTOPUS_STATE_SHARE to parent
4. Parent reconciles all sub-node states
5. Parent confirms merge complete
6. Sub-nodes are deactivated
```

### 6.2 State Reconciliation (INV41)

**INV41: State Consistency**
Merged state MUST be reconcilable from all sub-node states.

```
∀ merge:
  parentState' = reconcile(subNode[0].state, subNode[1].state, ...)
```

Reconciliation rules:
- Latest timestamp wins for conflicting updates
- All sub-node items are combined
- Duplicates are deduplicated by ID

```typescript
function reconcileStates(subNodes: SubNode[]): NodeState {
  const merged = new Map<string, StateItem>();

  for (const subNode of subNodes) {
    for (const item of subNode.state.items) {
      const existing = merged.get(item.id);
      if (!existing || item.timestamp > existing.timestamp) {
        merged.set(item.id, item);
      }
    }
  }

  return { items: Array.from(merged.values()) };
}
```

---

## 7. Message Types

### 7.1 OCTOPUS_THRESHOLD (0x60)

Announce throughput threshold reached.

```typescript
interface OctopusThresholdPayload {
  node: Address;
  currentThroughput: uint256;
  maxThroughput: uint256;
  thresholdType: ThresholdType;
  measurementWindow: uint256;    // seconds
}

enum ThresholdType {
  ACTIVATION = 0,   // > 45%
  DEACTIVATION = 1  // < 20% sustained
}
```

### 7.2 OCTOPUS_DIVIDE (0x61)

Announce node division.

```typescript
interface OctopusDividePayload {
  parent: Address;
  subNodeCount: uint256;         // 2 or 4
  divisionLevel: uint256;        // 1 or 2
  subNodeIds: bytes32[];
  effectiveAt: uint256;
}
```

### 7.3 OCTOPUS_SUBNODE (0x62)

Register sub-node.

```typescript
interface OctopusSubNodePayload {
  subNodeId: bytes32;
  parentAddress: Address;
  index: uint256;                // 0-3
  assignedRange: {
    start: uint256;
    end: uint256;
  };
}
```

### 7.4 OCTOPUS_COORDINATE (0x63)

Sub-node coordination message.

```typescript
interface OctopusCoordinatePayload {
  subNodeId: bytes32;
  coordinationType: CoordinationType;
  metrics: {
    processedCount: uint256;
    queueDepth: uint256;
    latencyMs: uint256;
  };
}

enum CoordinationType {
  HEARTBEAT = 0,
  LOAD_REPORT = 1,
  REBALANCE_REQUEST = 2
}
```

### 7.5 OCTOPUS_MERGE (0x64)

Announce node merger.

```typescript
interface OctopusMergePayload {
  parent: Address;
  subNodeIds: bytes32[];
  mergeReason: MergeReason;
  effectiveAt: uint256;
}

enum MergeReason {
  LOW_THROUGHPUT = 0,
  EPOCH_CLOSING = 1,
  PARENT_REQUEST = 2
}
```

### 7.6 OCTOPUS_STATE_SHARE (0x65)

Share sub-node state for merge.

```typescript
interface OctopusStateSharePayload {
  subNodeId: bytes32;
  parentAddress: Address;
  stateRoot: bytes32;
  itemCount: uint256;
  state: bytes;                  // Serialized state
}
```

---

## 8. Coordination Protocol

### 8.1 Heartbeat

Sub-nodes send periodic heartbeats to parent:

```
Every 10 seconds:
  SubNode → Parent: OCTOPUS_COORDINATE (HEARTBEAT)
```

Missing heartbeats trigger failover:
- 3 missed heartbeats = sub-node considered failed
- Parent redistributes failed sub-node's range

### 8.2 Load Balancing

Sub-nodes report load metrics:

```typescript
interface LoadMetrics {
  processedCount: uint256;   // Messages processed
  queueDepth: uint256;       // Pending messages
  latencyMs: uint256;        // Average processing time
}
```

If imbalanced:
1. Overloaded sub-node sends REBALANCE_REQUEST
2. Parent adjusts hash ranges
3. Sub-nodes migrate items to new ranges

### 8.3 Failover

If a sub-node fails:

```
1. Parent detects missing heartbeats (3 consecutive)
2. Parent sends OCTOPUS_DIVIDE with reduced subNodeCount
3. Remaining sub-nodes absorb failed sub-node's range
4. State recovery from last STATE_SHARE
```

---

## 9. Invariants Summary

| ID | Name | Rule |
|----|------|------|
| INV38 | Activation Threshold | Divide when throughput > 45% |
| INV39 | Sub-Node Identity | ID = keccak256(parent, index) |
| INV40 | Sub-Node Limit | Max 4 sub-nodes per parent |
| INV41 | State Consistency | Merged state reconcilable |
| INV42 | Deactivation Hysteresis | Merge when < 20% sustained |

---

## 10. Security Considerations

### 10.1 Sybil Prevention

Sub-nodes share parent's on-chain identity:
- Cannot create arbitrary sub-nodes
- All sub-nodes tied to parent's presence
- Validators verify parent authorization

### 10.2 State Integrity

State consistency verified:
- State roots computed deterministically
- Merge requires all sub-node states
- Missing state prevents merge

### 10.3 DoS Mitigation

Division rate limited:
- Minimum time between divisions
- Maximum division depth (2)
- Validator acknowledgment required

---

## 11. Integration Notes

### 11.1 Discovery

Sub-nodes are not independently discoverable:
- Discovery returns parent node only
- Parent routes to appropriate sub-node
- Transparent to other nodes

### 11.2 Messaging

Messages routed based on hash:
- Sender includes message hash
- Parent or network routes to sub-node
- Response includes sub-node ID for correlation

### 11.3 State Sync

State sync with octopus nodes:
- Sync with parent (logical view)
- Or sync with specific sub-node (physical view)
- STATE_SHARE used for sub-node state

---

## 12. Error Codes

| Code | Name | Condition |
|------|------|-----------|
| OCTO_001 | ThresholdNotMet | Division requested below 45% |
| OCTO_002 | MaxSubNodesReached | Already at 4 sub-nodes |
| OCTO_003 | InvalidSubNodeId | Sub-node ID doesn't match derivation |
| OCTO_004 | ParentNotFound | Referenced parent doesn't exist |
| OCTO_005 | MergeIncomplete | Missing sub-node states for merge |
| OCTO_006 | HysteresisNotMet | Merge requested before sustained low |

---

## 13. Implementation Notes

### 13.1 Recommended Configuration

```typescript
const OctopusConfig = {
  activationThreshold: 0.45,     // 45%
  deactivationThreshold: 0.20,   // 20%
  hysteresisWindow: 300,         // 5 minutes
  heartbeatInterval: 10,         // seconds
  missedHeartbeats: 3,           // failover trigger
  minDivisionInterval: 60,       // seconds between divisions
  maxThroughput: 1000            // msgs/second (adjustable)
};
```

### 13.2 State Machine

```
       NORMAL
         │
         │ throughput > 45%
         ↓
      DIVIDING
         │
         │ sub-nodes registered
         ↓
       DIVIDED
         │
         ├─────────────────┐
         │                 │ sub-node fails
         │                 ↓
         │             FAILOVER
         │                 │
         │←────────────────┘
         │
         │ throughput < 20% (5 min)
         ↓
      MERGING
         │
         │ states reconciled
         ↓
       NORMAL
```

---

## 14. References

- node-model.md v0.6.2 — Node structure
- message-catalog.md v0.6.6 — Message types
- invariants.md v0.6.6 — Protocol invariants
- state-sync.md v0.6.1 — State synchronization

---

## 15. Changelog

| Version | Changes |
|---------|---------|
| v0.6.7 | Initial Octopus Scaling specification |

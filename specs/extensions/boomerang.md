# 7ay Proof of Presence (PoP)
## Protocol Specification — Boomerang Routing
**Version:** v0.6.9
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** message-catalog.md v0.6.9, node-model.md v0.6.2, discovery.md v0.6.9

---

## 1. Purpose

This specification defines **Boomerang Routing** for the 7ay Presence Protocol's
semantic layer.

Boomerang Routing is a message delivery pattern where messages travel to their
destination and return via a different path, providing delivery verification
and routing redundancy.

This specification defines:
- Boomerang message flow
- Path divergence requirements
- Verification chain
- Timeout handling
- State machine and invariants

This version does **NOT** define:
- Routing algorithms
- Network topology
- Path selection optimization
- QoS guarantees

### 1.1 Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Boomerang Messages | **Off-chain (P2P)** | All BOOMERANG_* messages via P2P network |
| Hop Signatures | **Off-chain** | Each hop signed by forwarding node |
| Path Verification | **Off-chain** | Verification chain validated by receiver |
| Node Identity | **On-chain** | Forwarder presence validated via `pallet-presence` |
| Timeout Extension Votes | **Off-chain** | Validator votes collected off-chain |
| Boomerang State | **Off-chain** | Cycle state maintained in node memory |

Boomerang routing is entirely off-chain but validates node identities against on-chain presence.

---

## 2. Overview

### 2.1 Concept

A boomerang cycle consists of:

```
Forward Path:  A → B → C (destination)
                        ↓
Return Path:   A ← D ← C (via different intermediaries)
```

The key property is **path divergence**: the return path MUST differ from the
forward path by at least one intermediate node.

### 2.2 Benefits

1. **Delivery verification**: Origin confirms message reached destination
2. **Path redundancy**: Tests multiple routes simultaneously
3. **Faster confirmation**: Bidirectional acknowledgment reduces latency
4. **Fault detection**: Identifies failing network paths

---

## 3. Boomerang States

### 3.1 State Machine

```
             BOOMERANG_SEND
    ──────────────────────────► Pending
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
          ▼                         ▼                         ▼
    BOOMERANG_ACK            Timeout expires             Error
          │                         │                         │
          ▼                         ▼                         ▼
    AwaitingReturn               Timeout                   Failed
          │
          ▼
    BOOMERANG_RETURN
          │
          ▼
    BOOMERANG_COMPLETE
          │
          ▼
       Complete
```

### 3.2 State Definitions

| State | Description |
|-------|-------------|
| Pending | Initial send, awaiting destination acknowledgment |
| AwaitingReturn | Destination acknowledged, awaiting return path |
| Complete | Full cycle completed successfully |
| Timeout | Cycle did not complete within timeout window |
| Failed | Unrecoverable error during cycle |

---

## 4. Message Types

### 4.1 Message Type Enum Extension

```typescript
enum MessageType {
  // ... existing types (0x01-0x33)

  // Boomerang (0x40-0x4F) — v0.6.5
  BOOMERANG_SEND = 0x40,
  BOOMERANG_ACK = 0x41,
  BOOMERANG_RETURN = 0x42,
  BOOMERANG_COMPLETE = 0x43
}
```

### 4.2 BOOMERANG_SEND (0x40)

Initiate a boomerang message cycle.

```typescript
interface BoomerangSendPayload {
  // Boomerang identifier
  boomerangId: bytes32;           // Unique cycle identifier

  // Target
  destination: Address;           // Final destination node

  // Content
  innerPayload: bytes;            // Actual message content
  innerPayloadHash: bytes32;      // Hash for verification

  // Timing
  timeout: uint256;               // Max seconds for full cycle
  sentAt: uint256;                // Send timestamp

  // Path hints (optional)
  preferredReturnPath?: Address[]; // Suggested return route
}
```

**Validation Rules:**
- Sender MUST have valid presence in epoch
- `destination` MUST have valid presence in epoch
- `timeout` MUST be <= 300 seconds (5 minutes)
- `boomerangId` MUST be unique per sender per epoch
- Epoch MUST be Active

**Usage:**
- Initiate reliable message delivery
- Request delivery confirmation

### 4.3 BOOMERANG_ACK (0x41)

Destination acknowledges receipt and initiates return.

```typescript
interface BoomerangAckPayload {
  // Correlation
  boomerangId: bytes32;
  originalSendNonce: bytes32;     // Nonce from BOOMERANG_SEND

  // Acknowledgment
  receivedAt: uint256;
  innerPayloadHash: bytes32;      // Confirms received content

  // Return path
  returnPath: Address[];          // Planned return route (divergent)
}
```

**Validation Rules:**
- Sender MUST be the `destination` from BOOMERANG_SEND
- `boomerangId` MUST match pending boomerang
- `innerPayloadHash` MUST match sent payload hash
- `returnPath` MUST differ from forward path (INV30)
- `returnPath` MUST only include nodes with valid presence

**Usage:**
- Confirm message receipt
- Declare return routing intent

### 4.4 BOOMERANG_RETURN (0x42)

Return message traversing back to origin.

```typescript
interface BoomerangReturnPayload {
  // Correlation
  boomerangId: bytes32;
  ackNonce: bytes32;              // Nonce from BOOMERANG_ACK

  // Return journey
  hops: BoomerangHop[];           // Signed hops in return path

  // Current position
  hopIndex: uint256;              // Current hop in return path
}

interface BoomerangHop {
  forwarder: Address;             // Node that forwarded
  forwardedAt: uint256;           // Forward timestamp
  signature: bytes;               // Forwarder's signature on hop data
}
```

**Validation Rules:**
- Each hop MUST be signed by the forwarder
- Hop forwarders MUST match declared return path
- `hopIndex` MUST increment correctly
- All forwarders MUST have valid presence

**Usage:**
- Propagate return confirmation
- Build verification chain

### 4.5 BOOMERANG_COMPLETE (0x43)

Origin confirms cycle completion.

```typescript
interface BoomerangCompletePayload {
  // Correlation
  boomerangId: bytes32;

  // Completion stats
  completedAt: uint256;
  totalHops: uint256;
  roundTripTime: uint256;         // Total cycle time in ms

  // Verification
  forwardPathHash: bytes32;       // Hash of forward path
  returnPathHash: bytes32;        // Hash of return path
  pathsDivergent: bool;           // Confirms INV30
}
```

**Validation Rules:**
- Sender MUST be original boomerang sender
- `boomerangId` MUST match completed cycle
- `pathsDivergent` MUST be true (INV30)
- `completedAt` - `sentAt` MUST be <= timeout

**Usage:**
- Finalize boomerang cycle
- Record successful delivery

---

## 5. Path Divergence

### 5.1 Divergence Requirement (INV30)

The return path MUST differ from the forward path:

```
∀ boomerang:
  forwardPath.intermediateNodes ≠ returnPath.intermediateNodes
```

At least one intermediate node must be different between forward and return paths.
This can be achieved by having different intermediaries, different path lengths,
or any combination that results in non-identical intermediate node sets.

### 5.2 Valid Divergence Examples

**Example 1: Different intermediaries**
```
Forward: A → B → C
Return:  A ← D ← C   ✓ (D ≠ B)
```

**Example 2: Different path length**
```
Forward: A → B → C → D
Return:  A ← E ← D   ✓ (E ≠ B, C)
```

**Example 3: Direct return (no intermediaries)**
```
Forward: A → B → C
Return:  A ← C       ✓ (direct vs. via B)
```

### 5.3 Invalid Divergence

```
Forward: A → B → C
Return:  A ← B ← C   ✗ (same path reversed)
```

---

## 6. Verification Chain

### 6.1 Hop Signature

Each forwarder signs their hop:

```
hopSignaturePayload = keccak256(
  abi.encodePacked(
    boomerangId,
    forwarder,
    previousHopHash,
    forwardedAt
  )
)

hop.signature = ecdsaSign(hopSignaturePayload, forwarderPrivateKey)
```

### 6.2 Chain Verification

```
function verifyHopChain(hops: BoomerangHop[]) → bool:
  previousHash = bytes32(0)

  for each hop in hops:
    expectedPayload = keccak256(abi.encodePacked(
      boomerangId,
      hop.forwarder,
      previousHash,
      hop.forwardedAt
    ))

    recoveredSigner = ecrecover(expectedPayload, hop.signature)
    if recoveredSigner != hop.forwarder:
      return false

    previousHash = keccak256(abi.encodePacked(hop))

  return true
```

### 6.3 Chain Integrity (INV33)

```
∀ boomerang, hop ∈ boomerang.returnPath.hops:
  verify(hop.signature, hop.forwarder, hop.data) = true
```

---

## 7. Timeout Handling

### 7.1 Timeout Configuration (v0.6.9 — INV31 Update)

Boomerang timeouts are configurable to accommodate varying network conditions:

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| base_timeout_seconds | 60 | 30-300 | Default timeout value |
| adaptive_timeout | false | bool | Adjust to network conditions |
| max_timeout_extension | 60 | 0-120 | Maximum validator-approved extension |
| network_latency_percentile | 95 | 50-99 | Percentile for adaptive calculation |

```typescript
interface TimeoutConfig {
  base_timeout_seconds: uint256;    // Default: 60
  adaptive_timeout: bool;           // Default: false
  max_timeout_extension: uint256;   // Default: 60
  network_latency_percentile: uint8; // Default: 95 (p95)
}
```

### 7.2 Adaptive Timeout (v0.6.9)

When `adaptive_timeout = true`, the effective timeout adjusts to network conditions:

```typescript
function calculateEffectiveTimeout(
  config: TimeoutConfig,
  networkMetrics: NetworkMetrics
): uint256 {
  if (!config.adaptive_timeout) {
    return config.base_timeout_seconds;
  }

  // Calculate network latency at configured percentile
  const latencyP95 = networkMetrics.latencyPercentile(
    config.network_latency_percentile
  );

  // Effective timeout = base + network latency buffer
  return config.base_timeout_seconds + (latencyP95 / 1000);
}
```

### 7.3 Timeout Extension (v0.6.9)

Validators may vote to extend timeout for in-flight boomerangs:

```typescript
interface TimeoutExtensionVote {
  boomerangId: bytes32;
  extensionSeconds: uint256;      // Must be <= max_timeout_extension
  validator: Address;
  signature: bytes;
}

function processTimeoutExtension(
  boomerang: Boomerang,
  votes: TimeoutExtensionVote[]
): uint256 {
  // Require 2+ validator votes
  const validVotes = votes.filter(v =>
    v.extensionSeconds <= config.max_timeout_extension &&
    isValidatorActive(v.validator) &&
    verifySignature(v)
  );

  if (validVotes.length < 2) {
    return 0;  // No extension
  }

  // Extension is minimum of all votes (conservative)
  const extension = Math.min(...validVotes.map(v => v.extensionSeconds));

  // Only one extension per boomerang
  if (boomerang.extensionApplied) {
    return 0;
  }

  boomerang.extensionApplied = true;
  return extension;
}
```

Rules:
- Requires 2+ validator votes
- Extension MUST be <= `max_timeout_extension`
- Only one extension per boomerang cycle
- Extension amount is minimum of all votes (conservative approach)

### 7.4 Timeout Window (INV31 — Updated)

```
∀ boomerang:
  boomerang.completedAt - boomerang.sentAt ≤
    effectiveTimeout + approvedExtension

where:
  effectiveTimeout = adaptive_timeout ?
    base_timeout + network_latency_p95 :
    base_timeout
  approvedExtension = min(validator_voted_extensions) if votes >= 2 else 0
```

### 7.5 Timeout Detection

Origin monitors for timeout:

```
function checkTimeout(boomerang: Boomerang) → bool:
  if boomerang.state ∈ {Complete, Timeout, Failed}:
    return false  // Already terminal

  const effectiveTimeout = calculateEffectiveTimeout(config, networkMetrics);
  const extension = boomerang.approvedExtension || 0;
  const deadline = boomerang.sentAt + effectiveTimeout + extension;

  if (block.timestamp > deadline:
    boomerang.state = Timeout
    return true

  return false
```

### 7.6 Timeout Recovery

On timeout:
1. Boomerang marked as `Timeout`
2. Sender MAY retry with new `boomerangId`
3. Partial hops are discarded
4. No state is persisted from failed cycle

---

## 8. Invariants

### 8.1 Boomerang Invariants

**INV30: Path Divergence**
Return path MUST differ from forward path by at least one intermediate node.

```
∀ boomerang:
  ∃ node:
    (node ∈ forwardPath.intermediates ∧ node ∉ returnPath.intermediates) ∨
    (node ∉ forwardPath.intermediates ∧ node ∈ returnPath.intermediates)
```

**INV31: Boomerang Timeout (Updated v0.6.9)**
Boomerang cycle MUST complete within effective timeout window plus approved extension.

```
∀ boomerang:
  boomerang.state = Complete →
    boomerang.completedAt - boomerang.sentAt ≤
      effectiveTimeout + approvedExtension

where:
  effectiveTimeout = base_timeout + (adaptive ? network_latency_p95 : 0)
  approvedExtension ≤ max_timeout_extension (if 2+ validators voted)
```

**INV32: Boomerang Atomicity**
Partial boomerang cycles MUST NOT affect message finality.

```
∀ boomerang:
  boomerang.state ∈ {Pending, AwaitingReturn, Complete, Timeout, Failed}
  // No intermediate "partial" states persist
```

**INV33: Verification Chain**
Each hop in boomerang path MUST be signed by the forwarding node.

```
∀ boomerang, hop ∈ boomerang.hops:
  verify(hop.signature, hop.forwarder, hop.messageHash) = true
```

---

## 9. Error Codes

### 9.1 Boomerang Errors

| Code | Name | Description |
|------|------|-------------|
| BOOM_001 | PathNotDivergent | Return path same as forward path |
| BOOM_002 | BoomerangTimeout | Cycle timeout exceeded |
| BOOM_003 | InvalidHopSignature | Hop signature verification failed |
| BOOM_004 | BoomerangAborted | Cycle aborted mid-flight |
| BOOM_005 | InvalidReturnPath | Return path contains invalid nodes |

### 9.2 Error Priority

```
1. PathNotDivergent   → BOOM_001
2. InvalidReturnPath  → BOOM_005
3. InvalidHopSignature → BOOM_003
4. BoomerangTimeout   → BOOM_002
5. BoomerangAborted   → BOOM_004
```

---

## 10. Security Considerations

### 10.1 Path Manipulation

Mitigation:
- All hops are signed
- Path declared in BOOMERANG_ACK
- Divergence verified at completion

### 10.2 Replay Attacks

Mitigation:
- Unique `boomerangId` per sender per epoch
- Nonce tracking for each message
- Timeout invalidation

### 10.3 Denial of Service

Mitigation:
- Rate limiting per sender
- Timeout prevents resource exhaustion
- Maximum hop count (10)

---

## 11. Non-Goals

This specification explicitly does NOT define:

- Optimal path selection algorithms
- Network topology discovery
- Latency optimization
- Multi-destination boomerang

---

## 12. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.6 message envelope | Used for all boomerang messages |
| v0.6 discovery | Used for path node validation |
| Existing message types | Unchanged |

---

## 13. References

- message-catalog.md v0.6.2 — Message envelope structure
- node-model.md v0.6.2 — Node capabilities
- discovery.md v0.6.3 — Node discovery
- invariants.md v0.6.5 — Protocol invariants INV30-33
- errors.md v0.6.5 — Error catalog

---

## 14. Changelog

| Version | Changes |
|---------|---------|
| v0.6.5 | Initial boomerang routing specification |
| v0.6.9 | **Security hardening**: Configurable timeout (INV31 update), adaptive timeout, validator-approved extensions |

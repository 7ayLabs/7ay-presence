# 7ay Proof of Presence (PoP)
## Protocol Specification — Invariants
**Version:** v0.6.9 (consolidated INV1-45)
**Status:** Active
**Scope:** Protocol-level (canonical)
**Depends on:** All v0.6.9 specifications

---

## 1. Purpose

This specification defines all **protocol invariants** for v0.6, including
preserved invariants from previous versions and new invariants for the
semantic layer (node discovery, messaging, state synchronization).

Invariants are properties that MUST NEVER be violated by any compliant
implementation.

---

## 2. Invariant Categories

| Category | Invariants | Scope |
|----------|------------|-------|
| Presence | INV1-13 | On-chain (v0.4) |
| Ephemeral Data | INV14-18, INV44 | Off-chain (v0.5, v0.6.9) |
| Node Model | INV19-20 | Off-chain (v0.6) |
| Discovery | INV21-22, INV45 | Off-chain (v0.6, v0.6.9) |
| Messaging | INV23-25, INV43 | Off-chain (v0.6, v0.6.9) |
| State Sync | INV26 | Off-chain (v0.6) |
| Media | INV27-29 | Off-chain (v0.6.4) |
| Boomerang | INV30-33 | Off-chain (v0.6.5, INV31 updated v0.6.9) |
| Autonomous | INV34-37 | Off-chain (v0.6.6) |
| Octopus | INV38-42 | Off-chain (v0.6.7, INV39 updated v0.6.9) |
| Security | INV43-45 | Off-chain (v0.6.9) |

---

## 3. Preserved Invariants (INV1-18)

### 3.1 Presence Invariants (v0.4)

**INV1: Uniqueness**
An actor MUST NOT have more than one finalized presence per epoch.

**INV2: Finalized Immutability**
Terminal states (Finalized, Slashed) MUST NOT be modified.

**INV3: Determinism**
Presence state transitions MUST be deterministic and idempotent.

**INV4: Self-Only Declaration**
Only the actor itself MAY declare its own presence.

**INV5: Actor Isolation**
Finalizing one actor's presence does not affect other actors.

**INV6: Epoch Isolation**
Finalizing in one epoch does not affect other epochs.

**INV7: Monotonicity**
Presence state progresses forward only: None → Declared → Validated → Finalized.

**INV8: Slashed Terminal**
Slashed state has no outgoing transitions.

**INV9: No Retroactive Validation**
Cannot validate after epoch expires.

**INV10: Quorum Required**
Validated requires votes ≥ quorumSize.

**INV11: Single Vote**
Each validator votes once per presence.

**INV12: Dispute Isolation**
A dispute affects only the target presence.

**INV13: Slashed Immutability**
Slashed state is immutable (equivalent to INV2 for Slashed).

### 3.2 Ephemeral Data Invariants (v0.5)

**INV14: Temporal Boundary**
Ephemeral Data MUST NOT exist outside an Active epoch.

**INV15: Read Termination**
Ephemeral Data MUST NOT be readable after epoch termination.

**INV16: Actor Exit Invalidation**
Actors leaving an epoch MUST immediately lose access to Ephemeral Data.

**INV17: State Independence**
Ephemeral Data MUST NOT influence presence state.

**INV18: Non-Persistence**
Ephemeral Data MUST NOT be persisted or finalized.

---

## 4. New Invariants (INV19-42)

### 4.1 Node Model Invariants

**INV19: Node Identity Derivability**
A node's identity MUST be derivable from on-chain state.

**INV20: Epoch Binding**
A node MUST be bound to exactly one epoch at any time.

### 4.2 Discovery Invariants

**INV21: Epoch-Scoped Discovery**
Discovery MUST NOT return nodes from different epochs.

**INV22: Presence-Gated Discovery**
Only nodes with valid presence are discoverable.

### 4.3 Messaging Invariants

**INV23: Epoch-Bound Messages**
All messages MUST reference a valid epoch.

**INV24: Signature Validity**
Message signature MUST verify against sender's address.

**INV25: Nonce Uniqueness**
Each (sender, nonce) pair MUST be unique within an epoch.

### 4.4 State Sync Invariants

**INV26: Sync Determinism**
Given identical on-chain state, reconciliation MUST be deterministic.

### 4.5 Media Invariants (v0.6.4)

**INV27: Media Epoch Binding**
All media MUST be bound to exactly one epoch with PresenceWithEphemeralData capability.

**INV28: Media Policy Compliance**
Media MUST comply with the epoch's data policy constraints.

**INV29: Media Temporal Boundary**
Media MUST NOT be accessible after epoch transition from Active.

### 4.6 Boomerang Invariants (v0.6.5)

**INV30: Path Divergence**
Return path MUST differ from forward path by at least one intermediate node.

**INV31: Boomerang Timeout**
Boomerang cycle MUST complete within timeout window.

**INV32: Boomerang Atomicity**
Partial boomerang cycles MUST NOT affect message finality.

**INV33: Verification Chain**
Each hop in boomerang return path MUST be signed by the forwarding node.

### 4.7 Autonomous Invariants (v0.6.6)

**INV34: Intent Presence**
Intent declaration MUST require Validated or Finalized presence.

**INV35: Pattern Threshold**
Execution eligibility MUST require pattern threshold.

**INV36: Validator Finalization**
Autonomous execution MUST be finalized by validator quorum.

**INV37: Epoch Scope**
Autonomous authorizations MUST NOT persist across epochs.

### 4.8 Octopus Invariants (v0.6.7)

**INV38: Activation Threshold**
Division MUST only occur when throughput > 45%.

```
∀ division:
  division.parentThroughput > (MAX_THROUGHPUT * 45 / 100)
```

A node may only divide into sub-nodes when message throughput exceeds 45% of maximum capacity.

**INV39: Sub-Node Identity**
Sub-node identity MUST be derivable from parent.

```
∀ subNode:
  subNode.id = keccak256(parentAddress, subNodeIndex) ∧
  subNode.index ∈ {0, 1, 2, 3}
```

**INV40: Sub-Node Limit**
A parent node MUST NOT have more than 4 sub-nodes.

```
∀ parent:
  count(subNodes[parent]) ≤ 4
```

**INV41: State Consistency**
Sub-node states MUST be reconcilable with parent state.

```
∀ parent, time t:
  parentState(t) = merge(subNodeStates[parent], t)
```

**INV42: Deactivation Hysteresis**
Merge MUST only occur after sustained low throughput (< 20% for 5 minutes).

```
∀ merge:
  ∀ t ∈ [merge.requestTime - 5min, merge.requestTime]:
    throughput(merge.parent, t) < (MAX_THROUGHPUT * 20 / 100)
```

### 4.9 Security Invariants (v0.6.9)

**INV43: Chain Binding**
Messages MUST be bound to the current chain and within block bounds.

```
∀ msg:
  msg.chain_id == currentChainId ∧
  currentBlock <= msg.block_bound
```

This prevents:
- Cross-chain replay attacks
- Delayed replay attacks (messages expire after block_bound)
- Fork-based attacks

**INV44: Key Destruction Attestation**
When an epoch closes, at least 3 validators MUST attest to key share destruction within the destruction window.

```
∀ epoch where state = Closed:
  ∃ attestations: Vec<KeyShareDestroyed>:
    count(attestations) >= 3 ∧
    ∀ a ∈ attestations:
      a.destroyed_at <= epoch.closed_at + DESTRUCTION_WINDOW (300s) ∧
      verify_signature(a.attestation_signature, a.validator)
```

This ensures ephemeral data becomes cryptographically inaccessible.

**INV45: Discovery Rate Limit**
Query frequency MUST NOT exceed the configured rate limit.

```
∀ sender, minute:
  count(queries(sender, minute)) <= max_queries_per_minute
```

This prevents:
- Network enumeration attacks
- Discovery-based DoS attacks
- Sybil-based probing

### 4.10 Updated Invariants (v0.6.9)

**INV31: Boomerang Timeout (Updated)**
Boomerang cycle MUST complete within effective timeout plus approved extension.

```
∀ boomerang:
  boomerang.completedAt - boomerang.sentAt ≤
    effectiveTimeout + approvedExtension

where:
  effectiveTimeout = base_timeout + (adaptive ? network_latency_p95 : 0)
  approvedExtension ≤ max_timeout_extension (if 2+ validators voted)
```

**INV39: Sub-Node Identity (Updated)**
Sub-node identity MUST be derived from parent, index, epoch, and verifiable randomness.

```
∀ subNode:
  subNode.id = keccak256(parentAddress, subNodeIndex, epochId, epochRandomness) ∧
  vrf_verify(validatorPublicKey, epochId, epochRandomness) = true
```

---

## 5. Invariant Enforcement

### 5.1 Enforcement Model

| Invariant | Enforcement Layer | Mechanism |
|-----------|-------------------|-----------|
| INV1-13 | On-chain | Substrate pallet ensure!/Error |
| INV14-18 | Off-chain | Implementation constraints |
| INV19-20 | Off-chain | Node validation |
| INV21-22 | Off-chain | Discovery filtering |
| INV23-25 | Off-chain | Message validation |
| INV26 | Off-chain | Reconciliation algorithm |
| INV27-29 | Off-chain | Media validation |
| INV30-33 | Off-chain | Boomerang routing validation |
| INV34-37 | Off-chain | Autonomous execution validation |
| INV38-42 | Off-chain | Octopus scaling validation |
| INV43 | Off-chain | Message envelope validation (chain_id, block_bound) |
| INV44 | Off-chain | Validator attestation collection |
| INV45 | Off-chain | Rate limiter enforcement |

---

## 6. Compliance

An implementation is considered compliant if and only if:
- All invariants INV1-45 hold under all conditions
- Violations are detected and handled appropriately
- On-chain invariants are enforced via smart contracts
- Off-chain invariants are enforced via client validation
- Security invariants (INV43-45) are enforced at message/query boundaries

---

## 7. Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Added INV19-26 for semantic layer |
| v0.6.4 | Added INV27-29 for media |
| v0.6.5 | Added INV30-33 for boomerang |
| v0.6.6 | Added INV34-37 for autonomous |
| v0.6.7 | Added INV38-42 for octopus |
| v0.6.9 | **Security hardening**: Added INV43 (chain binding), INV44 (key destruction), INV45 (rate limiting); Updated INV31, INV39 |

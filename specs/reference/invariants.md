# 7ay Proof of Presence (PoP)
## Protocol Specification — Invariants
**Version:** v0.7.1 (consolidated INV1-65)
**Status:** Active
**Scope:** Protocol-level (canonical)
**Depends on:** All v0.7.0 specifications
**RFCs:** RFC-0001, RFC-0002, RFC-0003, RFC-0004

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
| Boomerang | INV30-33, INV54-56 | Off-chain (v0.6.5, v0.7.0) |
| Autonomous | INV34-37, INV50-53 | Off-chain (v0.6.6, v0.7.0) |
| Octopus | INV38-42, INV63 | Off-chain (v0.6.7, v0.7.0) |
| Security | INV43-45 | Off-chain (v0.6.9) |
| Validator | INV46-49 | On-chain (v0.7.0 — RFC-0001) |
| Recovery | INV57-58 | On-chain (v0.7.0 — RFC-0004) |
| Governance | INV59-60 | On-chain (v0.7.0 — RFC-0004) |
| Verification | INV61-62 | Hybrid (v0.7.0) |
| Device | INV64-65 | Hybrid (v0.7.1) |

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

### 4.11 Validator Invariants (v0.7.0)

**INV46: Minimum Active Validators**
The network MUST maintain at least 5 active validators at all times.

```
∀ time t:
  count(validators where status = Active) >= 5
```

This ensures Byzantine fault tolerance with 2f+1 honest validators.

**INV47: Stake Concentration Limit**
No single validator MAY control more than 33% of total stake.

```
∀ validator v:
  stake(v) / totalStake <= 0.33
```

This prevents stake centralization and ensures decentralization.

**INV48: Slashing Proportionality**
Slash amount MUST NOT exceed the maximum slash percentage for the violation type.

```
∀ slash s:
  s.amount <= stake(s.validator) * maxSlashPercent(s.violationType)

where maxSlashPercent:
  InvalidValidation: 5%
  KeyShareRetention: 50%
  DoubleVoting: 100%
  Collusion: 100%
```

**INV49: Evidence Reward Cap**
Evidence rewards MUST be capped at 10% of slash and absolute maximum.

```
∀ evidence e:
  reward(e) <= min(slash(e) * 0.10, 1000 * UNITS)
```

### 4.12 Reputation Invariants (v0.7.0)

**INV50: Reputation Range**
Actor reputation score MUST be within valid bounds.

```
∀ actor a:
  0 <= reputation(a) <= 100
```

Initial reputation is 50 for new actors.

**INV51: Reputation Impact**
Reputation MUST decrease on rejection with proportional penalty.

```
∀ rejection r:
  reputation'(r.actor) = max(0, reputation(r.actor) - penalty(r))

where penalty:
  first_rejection: 5
  consecutive_rejection: 5 * consecutiveCount
  revocation: 10
  cooldown_violation: 20
```

**INV52: Progressive Threshold**
Autonomous execution threshold MUST scale with reputation tier.

```
∀ actor a:
  threshold(a) = baseThreshold * tierMultiplier(tier(a))

where:
  tier(0-24) = Restricted, multiplier = 1
  tier(25-49) = Basic, multiplier = 4
  tier(50-74) = Enhanced, multiplier = 10
  tier(75-100) = Trusted, multiplier = 20
```

**INV53: Cooldown Enforcement**
Rejection MUST trigger exponential backoff cooldown.

```
∀ rejection r:
  cooldownUntil(r.actor) = now + min(86400, 60 * 2^(consecutiveRejections - 1))
```

### 4.13 Small Network Invariants (v0.7.0)

**INV54: Small Network Detection**
Small network mode MUST activate when active nodes fall below threshold.

```
∀ epoch e:
  activeNodeCount(e) < small_network_threshold →
    smallNetworkMode(e) = true
```

Default threshold is 5 nodes.

**INV55: Fallback Path Verification**
Small network mode MUST use enhanced verification.

```
∀ boomerang b where smallNetworkMode = true:
  verificationLevel(b) >= Enhanced
```

Enhanced verification includes validator attestation of path integrity.

**INV56: Mode Transparency**
Small network fallback MUST be explicitly indicated in completion.

```
∀ boomerang b where smallNetworkMode = true:
  BOOMERANG_COMPLETE(b).smallNetworkMode = true ∧
  BOOMERANG_COMPLETE(b).verificationLevel is set
```

### 4.14 Recovery Invariants (v0.7.0)

**INV57: Recovery Quorum**
Validator recovery MUST require 80% of active validators.

```
∀ recovery r where status = Approved:
  count(r.votes_for) >= ceil(activeValidatorCount * 0.8)
```

**INV58: Recovery Cooldown**
Recovered validators MUST wait 7 days before becoming active.

```
∀ validator v transitioning Recovering → Active:
  v.active_at >= v.recovery_approved_at + RECOVERY_COOLDOWN

where RECOVERY_COOLDOWN = 7 * 24 * 3600 seconds
```

### 4.15 Governance Invariants (v0.7.0)

**INV59: Upgrade Delay**
Upgrades MUST respect the delay period for their type.

```
∀ upgrade u where status = Executed:
  u.executed_at >= u.proposed_at + delay(u.upgrade_type)

where delay:
  Parameter: 48 hours
  Protocol: 7 days
  Emergency: 0
```

**INV60: Emergency Upgrade Quorum**
Emergency upgrades MUST require 80% quorum and security disclosure.

```
∀ emergency_upgrade u where status = Approved:
  count(u.votes_for) >= ceil(activeValidatorCount * 0.8) ∧
  u.payload.contains_security_disclosure = true
```

### 4.16 Verification Invariants (v0.7.0)

**INV61: Invariant Violation Logging**
All invariant violations MUST emit an event with full context.

```
∀ violation v:
  emit InvariantViolation {
    invariant_id: v.id,
    violation_type: v.type,
    context: v.context,
    block_number: current_block,
    timestamp: now
  }
```

**INV62: Debug Mode Assertion**
Debug builds MUST check all invariants at runtime.

```
#[cfg(feature = "invariant-checks")]:
  ∀ invariant INV1-63:
    check_invariant(INV, condition, context)
```

### 4.17 Octopus Dynamic Scaling (v0.7.0)

**INV63: Dynamic Sub-Node Limit**
Sub-node limit MUST scale dynamically with throughput.

```
∀ parent p:
  count(subNodes[p]) <= dynamicLimit(throughput(p))

where:
  dynamicLimit(t) = min(8, ceil(t / 22.5))

Examples:
  45% throughput → max 2 sub-nodes
  90% throughput → max 4 sub-nodes
  180% throughput → max 8 sub-nodes (cap)
```

This replaces the fixed limit of 4 from INV40.

### 4.18 Device Invariants (v0.7.1)

**INV64: Device Identity Derivation**
Device identity MUST be derivable from owner, index, and epoch randomness.

```
∀ device d:
  d.deviceId = keccak256(
    "7ay-device-v1",
    d.owner,
    d.deviceIndex,
    d.registrationEpochId,
    epochRandomness(d.registrationEpochId)
  )
```

This ensures:
- **Uniqueness**: Same owner + index + epoch = same deviceId
- **Unpredictability**: Cannot pre-compute deviceId before epoch randomness revealed
- **Verifiability**: Anyone can verify deviceId given inputs
- **Non-transferability**: DeviceId bound to owner address

**INV65: Device Presence Binding**
A device MUST have valid presence to participate in vault operations.

```
∀ device d, operation o:
  o.requiresPresence = true →
    presenceState(d.owner, currentEpoch) ∈ {Declared, Validated, Finalized} ∧
    d.state = DeviceState.Present ∧
    d.currentEpochId = currentEpoch
```

This ensures:
- Device operations require owner's active presence
- Device must be in Present state
- Device must be bound to current epoch

---

## 5. Invariant Enforcement

### 5.1 7aychain Architecture

The 7ay Presence Protocol is implemented on a dedicated Substrate-based blockchain (7aychain).

**On-Chain (Substrate Pallets)**
Core consensus primitives with permanent state stored in blockchain storage.

**Off-Chain (P2P Layer)**
Network coordination validated against on-chain state, running in node software.

**Hybrid**
Some data stored on-chain (hashes, attestations), with full data off-chain.

### 5.2 Enforcement Model

| Invariant | Layer | Pallet/Component | Description |
|-----------|-------|------------------|-------------|
| INV1-13 | **On-chain** | `pallet-presence` | Presence state machine, validation votes |
| INV14-18 | **Off-chain** | P2P + memory | Ephemeral data lifecycle (keys never on-chain) |
| INV19-20 | **Hybrid** | `pallet-presence` → P2P | Node identity derived from on-chain presence |
| INV21-22 | **Off-chain** | P2P discovery | Discovery validates against on-chain state |
| INV23-25 | **Off-chain** | P2P messaging | Messages reference on-chain epochs |
| INV26 | **Off-chain** | P2P state sync | Sync verifies against on-chain state |
| INV27-29 | **Off-chain** | P2P media | Media bound to on-chain epoch capability |
| INV30-33, INV54-56 | **Off-chain** | P2P routing | Boomerang routing, small network fallback |
| INV34-37 | **Hybrid** | `pallet-autonomous` → P2P | Intent hash on-chain, patterns off-chain |
| INV38-42, INV63 | **Off-chain** | P2P scaling | Sub-nodes derive from on-chain identity |
| INV43 | **On-chain** | `pallet-messaging` | Chain binding verified in pallet |
| INV44 | **On-chain** | `pallet-ephemeral` | Destruction attestations stored on-chain |
| INV45 | **Off-chain** | P2P discovery | Rate limiting in node software |
| INV46-49 | **On-chain** | `pallet-staking` | Validator economics, slashing |
| INV50-53 | **Off-chain** | P2P autonomous | Reputation tracking, progressive thresholds |
| INV57-58 | **On-chain** | `pallet-validators` | Recovery process, cooldowns |
| INV59-60 | **On-chain** | `pallet-governance` | Upgrade delays, quorums |
| INV61-62 | **Hybrid** | Runtime + P2P | Invariant violation logging |
| INV64-65 | **Hybrid** | `pallet-devices` → P2P | Device identity and presence binding |

### 5.3 On-Chain Pallets

| Pallet | Storage | Invariants |
|--------|---------|------------|
| `pallet-presence` | Presences, ValidationVotes, VoteCounts | INV1-13 |
| `pallet-epochs` | Epochs, Capabilities, PolicyHashes | INV14 (boundary) |
| `pallet-validators` | Validators, Quorum, Authority, RecoveryProposals | INV10-11, INV46, INV57-58 |
| `pallet-disputes` | Disputes, DisputeVotes, Resolutions | INV12-13 |
| `pallet-ephemeral` | DestructionAttestations | INV44 |
| `pallet-messaging` | ChainId, NonceTracking | INV43, INV25 |
| `pallet-autonomous` | IntentHashes, ExecutionCounts | INV34 (partial) |
| `pallet-staking` | Stakes, SlashRecords, EvidenceRewards | INV47-49 |
| `pallet-governance` | Upgrades, UpgradeVotes, StorageVersion | INV59-60 |

### 5.4 Off-Chain Components

| Component | Purpose | Validates Against |
|-----------|---------|-------------------|
| P2P Discovery | Node announcement, peer queries | On-chain presence state |
| P2P Messaging | Protocol message exchange | On-chain epoch capability |
| P2P State Sync | Validator state reconciliation | On-chain state roots |
| Ephemeral Storage | Encrypted temporary data | On-chain epoch bounds |
| Key Management | HKDF derivation, Shamir sharing | On-chain validator set |
| Boomerang Router | Return path verification, small network fallback | On-chain node identities |
| Octopus Coordinator | Sub-node management, dynamic scaling | On-chain parent identity |
| Reputation Tracker | Actor reputation scoring | Local state + execution history |
| Invariant Monitor | Runtime invariant checking | All invariant conditions |

---

## 6. Compliance

An implementation is considered compliant if and only if:
- All invariants INV1-65 hold under all conditions
- On-chain invariants are enforced via Substrate pallets
- Off-chain invariants validate against on-chain state
- Hybrid invariants have on-chain anchors with off-chain execution
- Security invariants (INV43-45) are enforced at appropriate boundaries
- Economic invariants (INV46-49) are enforced by staking pallet
- Recovery invariants (INV57-58) are enforced by validator pallet
- Governance invariants (INV59-60) are enforced by governance pallet

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
| v0.7.0 | **Production readiness**: Added INV46-49 (validator economics — RFC-0001), INV50-53 (reputation — RFC-0002), INV54-56 (small network — RFC-0003), INV57-60 (recovery & governance — RFC-0004), INV61-62 (verification), INV63 (dynamic scaling) |
| v0.7.1 | **Device layer**: Added INV64 (device identity derivation), INV65 (device presence binding) |

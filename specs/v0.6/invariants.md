# 7ay Proof of Presence (PoP)
## Protocol Specification — v0.6 Invariants
**Version:** v0.6.6
**Status:** Draft
**Scope:** Protocol-level (canonical)
**Depends on:** epoch.md v0.2, presence.md v0.4, validator.md v0.4, ephemeral.md v0.5, autonomous.md v0.6.6

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
| Ephemeral Data | INV14-18 | Off-chain (v0.5) |
| Node Model | INV19-20 | Off-chain (v0.6) |
| Discovery | INV21-22 | Off-chain (v0.6) |
| Messaging | INV23-25 | Off-chain (v0.6) |
| State Sync | INV26 | Off-chain (v0.6) |
| Media | INV27-29 | Off-chain (v0.6.4) |
| Boomerang | INV30-33 | Off-chain (v0.6.5) |
| Autonomous | INV34-37 | Off-chain (v0.6.6) |

---

## 3. Preserved Invariants (INV1-18)

### 3.1 Presence Invariants (v0.4)

**INV1: Uniqueness**
An actor MUST NOT have more than one finalized presence per epoch.
```
∀ actor, epochId:
  count(presence[actor][epochId] where state = Finalized) ≤ 1
```

**INV2: Finalized Immutability**
Terminal states (Finalized, Slashed) MUST NOT be modified.
```
∀ actor, epochId:
  presence[actor][epochId].state ∈ {Finalized, Slashed} →
    ¬∃ transition from presence[actor][epochId]
```

**INV3: Determinism**
Presence state transitions MUST be deterministic and idempotent.
```
∀ inputs I:
  apply(apply(state, I), I) = apply(state, I)
```

**INV4: Self-Only Declaration**
Only the actor itself MAY declare its own presence.
```
∀ actor, epochId:
  declarePresence(actor, epochId) requires msg.sender = actor
```

**INV5: Actor Isolation**
Finalizing one actor's presence does not affect other actors.
```
∀ actor1, actor2 where actor1 ≠ actor2:
  finalize(actor1) → presence[actor2] unchanged
```

**INV6: Epoch Isolation**
Finalizing in one epoch does not affect other epochs.
```
∀ epochId1, epochId2 where epochId1 ≠ epochId2:
  finalize(actor, epochId1) → presence[actor][epochId2] unchanged
```

**INV7: Monotonicity**
Presence state progresses forward only: None → Declared → Validated → Finalized.
```
∀ state transitions:
  None → Declared ✓
  Declared → Validated ✓
  Validated → Finalized ✓
  Declared → Slashed ✓
  Validated → Slashed ✓
  (all others prohibited)
```

**INV8: Slashed Terminal**
Slashed state has no outgoing transitions.
```
∀ actor, epochId:
  presence[actor][epochId].state = Slashed →
    ¬∃ next state
```

**INV9: No Retroactive Validation**
Cannot validate after epoch expires.
```
∀ actor, epochId:
  epochState(epochId) ≠ Active →
    validatePresence(actor, epochId) reverts
```

**INV10: Quorum Required**
Validated requires votes ≥ quorumSize.
```
∀ actor, epochId:
  presence[actor][epochId].state = Validated →
    presence[actor][epochId].validationCount ≥ quorumSize()
```

**INV11: Single Vote**
Each validator votes once per presence.
```
∀ validator, actor, epochId:
  count(votes[validator][actor][epochId]) ≤ 1
```

**INV12: Dispute Isolation**
A dispute affects only the target presence.
```
∀ actor1, actor2 where actor1 ≠ actor2:
  dispute[actor1].upheld → presence[actor2] unchanged
```

**INV13: Slashed Immutability**
Slashed state is immutable (equivalent to INV2 for Slashed).

### 3.2 Ephemeral Data Invariants (v0.5)

**INV14: Temporal Boundary**
Ephemeral Data MUST NOT exist outside an Active epoch.
```
∀ epochId, data:
  data.epochId = epochId ∧ data exists →
    epochState(epochId) = Active
```

**INV15: Read Termination**
Ephemeral Data MUST NOT be readable after epoch termination.
```
∀ epochId:
  epochState(epochId) ∈ {Closed, Finalized} →
    ¬∃ accessible ephemeral data for epochId
```

**INV16: Actor Exit Invalidation**
Actors leaving an epoch MUST immediately lose access to Ephemeral Data.
```
∀ actor, epochId:
  actor exits epochId →
    actor.ephemeralDataAccess(epochId) = false immediately
```

**INV17: State Independence**
Ephemeral Data MUST NOT influence presence state.
```
∀ actor, epochId:
  presence[actor][epochId].state is independent of ephemeralData[epochId]
```

**INV18: Non-Persistence**
Ephemeral Data MUST NOT be persisted or finalized.
```
∀ epochId:
  epochState(epochId) = Finalized →
    ephemeralData[epochId] = ∅
```

---

## 4. New Invariants (INV19-37)

### 4.1 Node Model Invariants

**INV19: Node Identity Derivability**
A node's identity MUST be derivable from on-chain state.

```
∀ node:
  node.identity.address ∈ validAddresses(on-chain) ∧
  node.epoch.epochId ∈ existingEpochs(on-chain) ∧
  node.presence.state = presenceRegistry.presenceState(node.identity.address, node.epoch.epochId) ∧
  node.role = (validatorRegistry.isValidatorActive(node.identity.address) ? Validator : Participant)
```

This ensures nodes are not arbitrary constructs but reflect actual on-chain state.

**INV20: Epoch Binding**
A node MUST be bound to exactly one epoch at any time.

```
∀ node, t:
  |{epochId : node.isActiveIn(epochId, t)}| = 1
```

A node cannot participate in multiple epochs simultaneously for messaging purposes.
This prevents cross-epoch data leakage and simplifies state management.

### 4.2 Discovery Invariants

**INV21: Epoch-Scoped Discovery**
Discovery MUST NOT return nodes from different epochs.

```
∀ discoveryRequest(epochId):
  ∀ node ∈ discoveryResponse:
    node.epoch.epochId = epochId
```

This ensures discovery results are epoch-local.

**INV22: Presence-Gated Discovery**
Only nodes with valid presence are discoverable.

```
∀ node ∈ discoverableNodes(epochId):
  presenceRegistry.presenceState(node.identity.address, epochId) ∈ {Declared, Validated, Finalized}
```

Nodes without presence (None) or with revoked presence (Slashed) MUST NOT appear in discovery.

### 4.3 Messaging Invariants

**INV23: Epoch-Bound Messages**
All messages MUST reference a valid epoch.

```
∀ message:
  epochRegistry.epochState(message.epochId) ≠ None ∧
  epochRegistry.epochCapability(message.epochId) ≥ PresenceWithSignals
```

Messages for non-existent or PresenceOnly epochs are invalid.

**INV24: Signature Validity**
Message signature MUST verify against sender's address.

```
∀ message:
  ecrecover(
    hash(message.type, message.sender.address, message.epochId, message.timestamp, message.nonce, hash(message.payload)),
    message.signature
  ) = message.sender.address
```

**INV25: Nonce Uniqueness**
Each (sender, nonce) pair MUST be unique within an epoch.

```
∀ epochId, sender:
  ∀ message1, message2 where message1 ≠ message2:
    (message1.sender = sender ∧ message2.sender = sender ∧
     message1.epochId = epochId ∧ message2.epochId = epochId) →
      message1.nonce ≠ message2.nonce
```

This prevents replay attacks within an epoch.

### 4.4 State Sync Invariants

**INV26: Sync Determinism**
Given identical on-chain state, reconciliation MUST be deterministic.

```
∀ nodes n1, n2, block B:
  onChainState(n1, B) = onChainState(n2, B) →
    reconcile(n1.localState, remoteState, B) = reconcile(n2.localState, remoteState, B)
```

This ensures all nodes converge to identical state views.

### 4.5 Media Invariants (v0.6.4)

**INV27: Media Epoch Binding**
All media MUST be bound to exactly one epoch with `PresenceWithEphemeralData` capability.

```
∀ media:
  media.epochId ∈ existingEpochs ∧
  epochRegistry.epochCapability(media.epochId) = PresenceWithEphemeralData
```

Media cannot exist in epochs with lower capabilities (PresenceOnly, PresenceWithSignals).

**INV28: Media Policy Compliance**
Media MUST comply with the epoch's data policy constraints.

```
∀ media, epochId:
  media.contentType ∈ policy.allowedTypes ∧
  media.contentSize ≤ policy.maxSize ∧
  media.ttl ≤ policy.maxTTL ∧
  (media.isAudio → media.duration ≤ policy.maxAudioDuration)
```

This ensures all media respects size, type, and duration limits.

**INV29: Media Temporal Boundary**
Media MUST NOT be accessible after epoch transition from Active.

```
∀ media, epochId:
  epochRegistry.epochState(epochId) ≠ Active →
    media.accessible = false
```

When epoch closes, all media becomes immediately unavailable, regardless of TTL.

### 4.6 Boomerang Invariants (v0.6.5)

**INV30: Path Divergence**
Return path MUST differ from forward path by at least one intermediate node.

```
∀ boomerang:
  forwardPath.intermediateNodes ≠ returnPath.intermediateNodes
```

This ensures boomerang routing tests multiple network paths.

**INV31: Boomerang Timeout**
Boomerang cycle MUST complete within timeout window.

```
∀ boomerang:
  boomerang.state = Complete →
    boomerang.completedAt - boomerang.sentAt ≤ boomerang.timeout
```

Maximum timeout is 300 seconds (5 minutes).

**INV32: Boomerang Atomicity**
Partial boomerang cycles MUST NOT affect message finality.

```
∀ boomerang:
  boomerang.state ∈ {Pending, AwaitingReturn, Complete, Timeout, Failed}
```

No intermediate "partial" states persist. Terminal states are Complete, Timeout, and Failed.

**INV33: Verification Chain**
Each hop in boomerang return path MUST be signed by the forwarding node.

```
∀ boomerang, hop ∈ boomerang.returnPath.hops:
  verify(hop.signature, hop.forwarder, hop.messageHash) = true
```

This creates a cryptographic chain of custody for the return path.

### 4.7 Autonomous Invariants (v0.6.6)

**INV34: Intent Presence**
Intent declaration MUST require Validated or Finalized presence.

```
∀ intent:
  presenceRegistry.presenceState(intent.actor, intent.epochId) ∈ {Validated, Finalized}
```

Declared-only or None presence cannot declare intents.

**INV35: Pattern Threshold**
Execution eligibility MUST require pattern threshold.

```
∀ intent:
  intent.state = Eligible →
    patternFrequency(intent) ≥ patternThreshold(intent.patternType)
```

**INV36: Validator Finalization**
Autonomous execution MUST be finalized by validator quorum.

```
∀ execution:
  execution.state = Finalized →
    count(approveVotes[execution]) ≥ quorumSize()
```

**INV37: Epoch Scope**
Autonomous authorizations MUST NOT persist across epochs.

```
∀ intent, epoch1, epoch2 where epoch1 ≠ epoch2:
  intent.epochId = epoch1 →
    ¬∃ execution for intent in epoch2
```

All pending intents are revoked when epoch closes.

---

## 5. Invariant Enforcement

### 5.1 Enforcement Model

| Invariant | Enforcement Layer | Mechanism |
|-----------|-------------------|-----------|
| INV1-13 | On-chain | Solidity require/revert |
| INV14-18 | Off-chain | Implementation constraints |
| INV19-20 | Off-chain | Node validation |
| INV21-22 | Off-chain | Discovery filtering |
| INV23-25 | Off-chain | Message validation |
| INV26 | Off-chain | Reconciliation algorithm |
| INV27-29 | Off-chain | Media validation |
| INV30-33 | Off-chain | Boomerang routing validation |
| INV34-37 | Off-chain | Autonomous execution validation |

### 5.2 Verification Points

**On-Chain Verification:**
- Smart contract tests (Unit, Fuzz, Invariants)
- Formal verification (optional)

**Off-Chain Verification:**
- Message validation before processing
- State consistency checks during sync
- Discovery result filtering
- Node identity derivation from on-chain queries

---

## 6. Invariant Dependencies

```
┌──────────────────────────────────────────────────────────────┐
│                      INVARIANT HIERARCHY                      │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  On-Chain (v0.4)                                            │
│  ══════════════                                             │
│  INV1-13: Presence + Validator + Dispute                    │
│      ↓                                                       │
│  Off-Chain (v0.5)                                           │
│  ═══════════════                                            │
│  INV14-18: Ephemeral Data                                   │
│      ↓                                                       │
│  Off-Chain (v0.6)                                           │
│  ═══════════════                                            │
│  INV19-20: Node Model    ──┐                                │
│  INV21-22: Discovery     ──┼── Requires INV19-20            │
│  INV23-25: Messaging     ──┤                                │
│  INV26: State Sync       ──┘                                │
│      ↓                                                       │
│  Off-Chain (v0.6.4+)                                        │
│  ════════════════════                                       │
│  INV27-29: Media         ── Requires INV14-18               │
│  INV30-33: Boomerang     ── Requires INV23-25               │
│  INV34-37: Autonomous    ── Requires INV1-13, INV23-25      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 7. Invariant Violations

### 7.1 On-Chain Violations

On-chain invariant violations result in:
- Transaction revert
- Gas consumption (up to revert point)
- No state change

### 7.2 Off-Chain Violations

Off-chain invariant violations result in:
- Message rejection
- Discovery exclusion
- Sync failure
- Node considered malicious

### 7.3 Recovery

| Violation | Recovery |
|-----------|----------|
| INV19-20 | Re-derive node from on-chain |
| INV21-22 | Re-filter discovery results |
| INV23-25 | Reject invalid messages |
| INV26 | Force complete sync with on-chain verification |
| INV27-29 | Reject invalid media |
| INV30-33 | Retry with new boomerangId |
| INV34-37 | Revoke intent, re-declare if needed |

---

## 8. Formal Notation

### 8.1 Symbols

| Symbol | Meaning |
|--------|---------|
| ∀ | For all |
| ∃ | Exists |
| ¬ | Not |
| ∧ | And |
| ∨ | Or |
| → | Implies |
| ∈ | Element of |
| ∉ | Not element of |
| ≤ | Less than or equal |
| ≠ | Not equal |
| ∅ | Empty set |
| \| \| | Cardinality (count) |

### 8.2 Functions

| Function | Meaning |
|----------|---------|
| epochState(id) | Current state of epoch |
| presenceState(actor, epochId) | Current presence state |
| isValidatorActive(addr) | Validator status check |
| quorumSize() | Current quorum requirement |
| hash(...) | Cryptographic hash |
| ecrecover(hash, sig) | Signature recovery |

---

## 9. Compliance

An implementation is considered compliant if and only if:
- All invariants INV1-37 hold under all conditions
- Violations are detected and handled appropriately
- On-chain invariants are enforced via smart contracts
- Off-chain invariants are enforced via client validation

---

## 10. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- validator.md v0.4 — Validator mechanics
- ephemeral.md v0.5 — Ephemeral data governance
- state-sync.md v0.6.1 — State synchronization
- node-model.md v0.6.2 — Node definition (forward reference)
- message-catalog.md v0.6.2 — Message schemas (forward reference)

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.6.1 | Added INV19-26 for semantic layer |
| v0.6.4 | Added INV27-29 for media |
| v0.6.5 | Added INV30-33 for boomerang |
| v0.6.6 | Added INV34-37 for autonomous |

# 7ay Proof of Presence (PoP)
## Diagram — Validation Broadcast Flow
**Version:** v0.6.9
**Status:** Draft

---

## 1. Validation Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VALIDATION BROADCAST MODEL                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        PRESENCE LIFECYCLE                            │   │
│   │                                                                      │   │
│   │    ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐  │   │
│   │    │   None   │────►│ Declared │────►│ Validated│────►│Finalized │  │   │
│   │    └──────────┘     └──────────┘     └──────────┘     └──────────┘  │   │
│   │                           │               │                          │   │
│   │                           │               │                          │   │
│   │                           ▼               ▼                          │   │
│   │                      ┌──────────┐    ┌──────────┐                   │   │
│   │                      │ Slashed  │◄───│ Disputed │                   │   │
│   │                      └──────────┘    └──────────┘                   │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│                                                                              │
│   MESSAGE TYPES IN VALIDATION FLOW:                                          │
│   ──────────────────────────────────                                         │
│                                                                              │
│   • PRESENCE_ATTESTATION — Validator attests to presence                    │
│   • VALIDATION_VOTE — Broadcast vote for validation                         │
│   • DISPUTE_NOTICE — Announce dispute initiation                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Declaration & Attestation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DECLARATION & ATTESTATION                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Actor                   On-Chain              Validators                   │
│   ─────                   ────────              ──────────                   │
│     │                        │                      │                        │
│     │  1. declarePresence()  │                      │                        │
│     ├───────────────────────►│                      │                        │
│     │                        │                      │                        │
│     │                        │  PresenceDeclared    │                        │
│     │                        │  (Event)             │                        │
│     │                        ├─────────────────────►│                        │
│     │                        │                      │                        │
│     │                        │                      │  2. Each validator     │
│     │                        │                      │     observes event     │
│     │                        │                      │                        │
│     │                        │                      │  3. Validator attests  │
│     │                        │                      │     off-chain          │
│     │                        │                      │                        │
│     │                        │                      │  PRESENCE_ATTESTATION  │
│     │                        │                      │  ┌──────────────────┐ │
│     │                        │                      │  │ actor: 0xABC     │ │
│     │                        │                      │  │ epochId: 42      │ │
│     │◄───────────────────────┼──────────────────────┤  │ validator: 0xV1  │ │
│     │                        │                      │  │ attestedState:   │ │
│     │                        │                      │  │   Declared       │ │
│     │                        │                      │  │ signature: ...   │ │
│     │                        │                      │  └──────────────────┘ │
│     │                        │                      │                        │
│     │  Actor now has proof   │                      │                        │
│     │  of validator          │                      │                        │
│     │  acknowledgment        │                      │                        │
│     │                        │                      │                        │
│     ▼                        ▼                      ▼                        │
│   ┌──────────────────────────────────────────────────────────────────┐      │
│   │  State: Declared (on-chain) + Attestation (off-chain proof)     │      │
│   └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Validation Voting Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       VALIDATION VOTING                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Validators           On-Chain (PresenceRegistry)        Network            │
│   ──────────           ───────────────────────────        ───────            │
│                                                                              │
│   Validator 1                    │                           │               │
│       │                          │                           │               │
│       │  validatePresence()      │                           │               │
│       ├─────────────────────────►│                           │               │
│       │                          │  PresenceValidationVote   │               │
│       │                          │  (actor, epoch, val1,     │               │
│       │                          │   count=1, required=3)    │               │
│       │                          ├──────────────────────────►│               │
│       │                          │                           │               │
│       │                          │                           │  VALIDATION_  │
│       │                          │                           │  VOTE         │
│       │                          │                           │  broadcast    │
│       │                          │                           │               │
│   Validator 2                    │                           │               │
│       │                          │                           │               │
│       │  validatePresence()      │                           │               │
│       ├─────────────────────────►│                           │               │
│       │                          │  PresenceValidationVote   │               │
│       │                          │  (count=2, required=3)    │               │
│       │                          ├──────────────────────────►│               │
│       │                          │                           │               │
│   Validator 3                    │                           │               │
│       │                          │                           │               │
│       │  validatePresence()      │                           │               │
│       ├─────────────────────────►│                           │               │
│       │                          │                           │               │
│       │                          │  PresenceValidationVote   │               │
│       │                          │  (count=3, required=3)    │               │
│       │                          │                           │               │
│       │                          │  PresenceValidated ✓      │               │
│       │                          │  (Quorum reached!)        │               │
│       │                          ├──────────────────────────►│               │
│       │                          │                           │               │
│       ▼                          ▼                           ▼               │
│   ┌──────────────────────────────────────────────────────────────────┐      │
│   │          State: Validated (quorum of 3 votes reached)            │      │
│   └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Validation Vote Message Details

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     VALIDATION_VOTE MESSAGE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Validator creates signed vote message for network broadcast:               │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ {                                                                    │   │
│   │   "version": "0.6.0",                                               │   │
│   │   "type": "VALIDATION_VOTE",                                        │   │
│   │   "sender": {                                                        │   │
│   │     "address": "0xValidator1...",                                   │   │
│   │     "publicKey": "0x04..."                                          │   │
│   │   },                                                                 │   │
│   │   "epochId": 42,                                                    │   │
│   │   "timestamp": 1704067200,                                          │   │
│   │   "nonce": 7,                                                       │   │
│   │   "signature": "0xSIG...",                                          │   │
│   │   "payload": {                                                       │   │
│   │     "actor": "0xActorAddress...",                                   │   │
│   │     "voteType": "validation",                                       │   │
│   │     "currentCount": 2,                                              │   │
│   │     "requiredCount": 3,                                             │   │
│   │     "txHash": "0xOnChainTxHash..."   // Reference to on-chain tx    │   │
│   │   }                                                                  │   │
│   │ }                                                                    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│                                                                              │
│   PURPOSE:                                                                   │
│   ────────                                                                   │
│                                                                              │
│   • Off-chain notification of on-chain vote                                 │
│   • Faster propagation than event indexing                                  │
│   • Enables real-time UI updates                                            │
│   • Allows pre-verification before chain confirmation                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Dispute Broadcast Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DISPUTE BROADCAST                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Challenger          On-Chain              Validators         Network       │
│   ──────────          ────────              ──────────         ───────       │
│       │                  │                      │                 │          │
│       │  initiateDispute │                      │                 │          │
│       │  (actor, epoch,  │                      │                 │          │
│       │   evidenceHash)  │                      │                 │          │
│       ├─────────────────►│                      │                 │          │
│       │                  │                      │                 │          │
│       │                  │  DisputeInitiated    │                 │          │
│       │                  │  (Event)             │                 │          │
│       │                  ├─────────────────────►│                 │          │
│       │                  │                      │                 │          │
│       │                  │                      │   DISPUTE_NOTICE│          │
│       │                  │                      │   (broadcast)   │          │
│       │                  │                      ├────────────────►│          │
│       │                  │                      │                 │          │
│       │                  │                      │                 │          │
│       │                  │  ┌───────────────────┴──────────────┐ │          │
│       │                  │  │       VALIDATOR VOTING           │ │          │
│       │                  │  │                                   │ │          │
│       │                  │  │  Val1: voteOnDispute(true)  ────►│ │          │
│       │                  │  │  Val2: voteOnDispute(true)  ────►│ │          │
│       │                  │  │  Val3: voteOnDispute(false) ────►│ │          │
│       │                  │  │                                   │ │          │
│       │                  │  │  Each vote emits DisputeVote     │ │          │
│       │                  │  │  Each validator broadcasts       │ │          │
│       │                  │  │  VALIDATION_VOTE (dispute type)  │ │          │
│       │                  │  └───────────────────────────────────┘ │          │
│       │                  │                      │                 │          │
│       │                  │  Quorum reached      │                 │          │
│       │  resolveDispute()│  (2 for, 1 against)  │                 │          │
│       ├─────────────────►│                      │                 │          │
│       │                  │                      │                 │          │
│       │                  │  DisputeResolved     │                 │          │
│       │                  │  (Upheld)            │                 │          │
│       │                  │                      │                 │          │
│       │                  │  PresenceSlashed     │                 │          │
│       │                  │  (actor slashed)     │                 │          │
│       │                  ├─────────────────────►│────────────────►│          │
│       │                  │                      │                 │          │
│       ▼                  ▼                      ▼                 ▼          │
│   ┌──────────────────────────────────────────────────────────────────┐      │
│   │  Final State: Dispute Upheld, Actor Slashed                      │      │
│   └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Dispute Notice Message Details

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DISPUTE_NOTICE MESSAGE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ {                                                                    │   │
│   │   "version": "0.6.0",                                               │   │
│   │   "type": "DISPUTE_NOTICE",                                         │   │
│   │   "sender": {                                                        │   │
│   │     "address": "0xChallenger...",                                   │   │
│   │     "publicKey": "0x04..."                                          │   │
│   │   },                                                                 │   │
│   │   "epochId": 42,                                                    │   │
│   │   "timestamp": 1704067200,                                          │   │
│   │   "nonce": 1,                                                       │   │
│   │   "signature": "0xSIG...",                                          │   │
│   │   "payload": {                                                       │   │
│   │     "disputedActor": "0xActor...",                                  │   │
│   │     "evidenceHash": "0xEVIDENCE...",                                │   │
│   │     "reason": "Invalid presence claim",                             │   │
│   │     "currentPresenceState": "Validated",                            │   │
│   │     "txHash": "0xOnChainTxHash..."                                  │   │
│   │   }                                                                  │   │
│   │ }                                                                    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│                                                                              │
│   BROADCAST TARGETS:                                                         │
│   ──────────────────                                                         │
│                                                                              │
│   1. All validators (they need to vote)                                     │
│   2. The disputed actor (notification)                                      │
│   3. Other interested parties (transparency)                                │
│                                                                              │
│   VALIDATOR ACTION ON RECEIPT:                                               │
│   ─────────────────────────────                                              │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ 1. Verify signature                                                  │   │
│   │ 2. Verify evidenceHash matches on-chain                             │   │
│   │ 3. Review evidence (off-chain process)                              │   │
│   │ 4. Cast vote: voteOnDispute(actor, epochId, true/false)             │   │
│   │ 5. Broadcast VALIDATION_VOTE with dispute vote                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Quorum Calculation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       QUORUM CALCULATION                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   FORMULA:                                                                   │
│   ────────                                                                   │
│                                                                              │
│   quorumSize = ceil(activeValidators * threshold / 100)                     │
│                                                                              │
│   Default threshold: 67% (2/3 majority)                                      │
│                                                                              │
│                                                                              │
│   EXAMPLES:                                                                  │
│   ─────────                                                                  │
│                                                                              │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │ Active Validators │ Threshold │ Quorum Required │ Example          │    │
│   ├────────────────────────────────────────────────────────────────────┤    │
│   │         3         │    67%    │       2         │ Val1, Val2 vote  │    │
│   │         5         │    67%    │       4         │ 4 of 5 needed    │    │
│   │        10         │    67%    │       7         │ 7 of 10 needed   │    │
│   │       100         │    67%    │      67         │ 67 of 100 needed │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│                                                                              │
│   VALIDATION QUORUM TIMELINE:                                                │
│   ───────────────────────────                                                │
│                                                                              │
│   3 Active Validators, Quorum = 2                                           │
│                                                                              │
│          Vote 1        Vote 2         Vote 3                                │
│   ─────────┼────────────┼──────────────┼─────────►                          │
│            │            │              │                                     │
│        count=1      count=2        count=3                                  │
│        (pending)    (VALIDATED!)   (extra)                                  │
│                         │                                                    │
│                         ▼                                                    │
│                   State changes to                                           │
│                   Validated                                                  │
│                                                                              │
│                                                                              │
│   DISPUTE QUORUM RESOLUTION:                                                 │
│   ──────────────────────────                                                 │
│                                                                              │
│   3 Active Validators, Quorum = 2                                           │
│                                                                              │
│        For: 2         Against: 1                                            │
│   ─────────┼─────────────┼──────────────────────►                           │
│            │             │                                                   │
│     votesFor=2    totalVotes=3                                              │
│            │             │                                                   │
│            │             ▼                                                   │
│            │      Quorum met (2 >= 2)                                       │
│            │      Majority upholds (2 > 1)                                  │
│            │             │                                                   │
│            └─────────────┼───────► Dispute UPHELD                           │
│                          │         Actor SLASHED                             │
│                          ▼                                                   │
│                   ┌──────────────┐                                          │
│                   │ PresenceState│                                          │
│                   │ = Slashed    │                                          │
│                   └──────────────┘                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Message Signature Verification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SIGNATURE VERIFICATION (INV24)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   MESSAGE SIGNING (Sender):                                                  │
│   ─────────────────────────                                                  │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                      │   │
│   │   1. Construct message hash:                                         │   │
│   │                                                                      │   │
│   │      payloadHash = keccak256(abi.encode(payload))                   │   │
│   │                                                                      │   │
│   │      messageHash = keccak256(abi.encodePacked(                      │   │
│   │        type,              // "VALIDATION_VOTE"                       │   │
│   │        sender.address,    // 0xValidator...                          │   │
│   │        epochId,           // 42                                      │   │
│   │        timestamp,         // 1704067200                              │   │
│   │        nonce,             // 7                                       │   │
│   │        payloadHash        // 0x...                                   │   │
│   │      ))                                                              │   │
│   │                                                                      │   │
│   │   2. Apply EIP-191 prefix:                                           │   │
│   │                                                                      │   │
│   │      ethHash = keccak256(abi.encodePacked(                          │   │
│   │        "\x19Ethereum Signed Message:\n32",                           │   │
│   │        messageHash                                                   │   │
│   │      ))                                                              │   │
│   │                                                                      │   │
│   │   3. Sign with private key:                                          │   │
│   │                                                                      │   │
│   │      signature = ecdsaSign(ethHash, privateKey)                      │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│                                                                              │
│   MESSAGE VERIFICATION (Receiver):                                           │
│   ─────────────────────────────────                                          │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                      │   │
│   │   1. Reconstruct message hash (same as sender)                       │   │
│   │                                                                      │   │
│   │   2. Apply EIP-191 prefix (same as sender)                           │   │
│   │                                                                      │   │
│   │   3. Recover signer:                                                 │   │
│   │                                                                      │   │
│   │      recoveredAddress = ecrecover(ethHash, signature)                │   │
│   │                                                                      │   │
│   │   4. Verify:                                                         │   │
│   │                                                                      │   │
│   │      assert recoveredAddress == message.sender.address               │   │
│   │                                                                      │   │
│   │   5. Additional checks:                                              │   │
│   │                                                                      │   │
│   │      • If sender claims Validator role:                              │   │
│   │        assert validatorRegistry.isValidatorActive(sender)            │   │
│   │                                                                      │   │
│   │      • Check nonce not reused (INV25):                               │   │
│   │        assert !usedNonces[sender][epochId][nonce]                    │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Complete Validation Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   COMPLETE VALIDATION LIFECYCLE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                       DECLARATION                                  │    │
│   │                                                                    │    │
│   │   [Actor: declarePresence] ──► [Event: PresenceDeclared]          │    │
│   │                            ──► [Validators: Attestations]          │    │
│   │                                                                    │    │
│   │   State: None ──► Declared                                         │    │
│   │                                                                    │    │
│   └───────────────────────────────┬───────────────────────────────────┘    │
│                                   │                                         │
│                                   ▼                                         │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                       VALIDATION                                   │    │
│   │                                                                    │    │
│   │   [Validator 1: validatePresence] ──► [Vote broadcast]            │    │
│   │   [Validator 2: validatePresence] ──► [Vote broadcast]            │    │
│   │   [Validator N: validatePresence] ──► [Quorum check]              │    │
│   │                                                                    │    │
│   │   State: Declared ──► Validated (when quorum met)                  │    │
│   │                                                                    │    │
│   └───────────────────────────────┬───────────────────────────────────┘    │
│                                   │                                         │
│                    ┌──────────────┴──────────────┐                         │
│                    │                             │                         │
│                    ▼                             ▼                         │
│   ┌────────────────────────────┐   ┌────────────────────────────┐         │
│   │        FINALIZATION        │   │          DISPUTE            │         │
│   │                            │   │                             │         │
│   │   [Epoch closes]           │   │   [Challenger: initiate]    │         │
│   │   [No pending disputes]    │   │   [DISPUTE_NOTICE]          │         │
│   │   [Anyone: finalize]       │   │   [Validators: vote]        │         │
│   │                            │   │   [Resolution]              │         │
│   │   State: Validated         │   │                             │         │
│   │       ──► Finalized        │   │   If Upheld:                │         │
│   │                            │   │   State ──► Slashed         │         │
│   │                            │   │                             │         │
│   │                            │   │   If Rejected:              │         │
│   │                            │   │   State unchanged           │         │
│   │                            │   │   (can still finalize)      │         │
│   │                            │   │                             │         │
│   └────────────────────────────┘   └────────────────────────────┘         │
│                                                                              │
│                                                                              │
│   TERMINAL STATES:                                                           │
│   ────────────────                                                           │
│                                                                              │
│   ┌──────────────┐     ┌──────────────┐                                    │
│   │  Finalized   │     │   Slashed    │                                    │
│   │              │     │              │                                    │
│   │  ✓ Valid     │     │  ✗ Invalid   │                                    │
│   │  ✓ Complete  │     │  ✗ Penalized │                                    │
│   │  ✓ Immutable │     │  ✗ Immutable │                                    │
│   └──────────────┘     └──────────────┘                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## References

- presence.md v0.4 — Presence lifecycle
- validator.md v0.4 — Validator mechanics
- message-catalog.md v0.6.2 — Attestation message types
- invariants.md v0.6.1 — INV24, INV25

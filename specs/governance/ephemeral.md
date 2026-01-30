# 7ay Proof of Presence (PoP)
## Protocol Specification — Ephemeral Data Governance
**Version:** v0.7.0 (consolidated from v0.5, security hardening, trust model)
**Status:** Active
**Scope:** Protocol-level (canonical)
**Depends on:** epochs.md, presence.md, validators.md
**See also:** Non-addressability specification in archive/v0.5/non-addressability.md

---

## 1. Purpose

This specification defines the **Ephemeral Data Governance Layer** for the
7ay Presence Protocol.

This layer defines:
- **When** ephemeral, off-chain data is allowed to exist
- **Under which constraints** data may be created
- **When** data must cease to exist

This specification formalizes:
- What Ephemeral Data IS
- How epochs declare capability for ephemeral data
- What invariants ephemeral data MUST maintain
- How ephemeral data relates to presence (orthogonality)

This version does **NOT** define:
- Data transport or messaging protocols
- Specific encryption algorithms (implementation choice)
- Network topology or routing
- SDK or client behavior
- Storage mechanisms

**v0.6.9 Addition:** This version now defines **epoch key lifecycle** including
derivation, distribution, and cryptographic destruction (see Section 7.3).

The Ephemeral Data Governance Layer exists solely to **govern data lifecycle**,
not to enable communication features.

Implementations MUST follow this specification to be considered compliant.

### 1.1 Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Epoch Capability | **On-chain** | Stored in `pallet-epochs` at epoch creation |
| Data Policy Hash | **On-chain** | Policy hash stored in `pallet-epochs` |
| Full Policy Document | **Off-chain** | JSON policy stored off-chain, verified by hash |
| Ephemeral Data | **Off-chain (memory)** | NEVER stored on-chain, exists only in node memory |
| Encryption Keys | **Off-chain (memory)** | Derived via HKDF, NEVER on-chain |
| Key Shares | **Off-chain** | Shamir shares distributed to validators |
| Destruction Attestations | **On-chain** | Stored in `pallet-ephemeral` for INV44 |
| Epoch State | **On-chain** | Epoch lifecycle in `pallet-epochs` |

**Critical:** Ephemeral data content and encryption keys are NEVER stored on-chain.
Only governance metadata (capability, policy hash, destruction attestations) is on-chain.

---

## 2. Definitions

### 2.1 Ephemeral Data

**Ephemeral Data** is any off-chain information that satisfies **all** of:

- Scoped to a specific `epochId`
- Exists only while the epoch is in state `Active`
- Cryptographically bound to the epoch lifecycle
- Cannot be finalized, validated, disputed, or slashed
- Cannot be persisted on-chain or off-chain after epoch termination
- Inaccessible to actors outside the epoch context

Data that does not meet all criteria MUST NOT be considered Ephemeral Data.

### 2.2 Epoch Capability

An **Epoch Capability** declares what features an epoch supports beyond
basic presence tracking.

```rust
pub enum EpochCapability {
    PresenceOnly,             // 0 - Default, v0.4 compatible
    PresenceWithSignals,      // 1 - Presence + signal emission
    PresenceWithEphemeralData, // 2 - Full ephemeral data support
    PresenceWithStorage       // 3 - Presence-based encrypted storage (v0.7.4)
}
```

Constraints:
- Capability is declared at epoch creation (immutable)
- Capability is stored on-chain in a separate mapping
- Default capability is `PresenceOnly` for backwards compatibility

### 2.3 Epoch Data Policy

An **Epoch Data Policy** defines governance rules for ephemeral data
within an epoch.

On-chain representation:
```rust
data_policy_hash: [u8; 32]  // keccak256 of full policy
```

Constraints:
- `bytes32(0)` means "no policy committed"
- Required only when `capability == PresenceWithEphemeralData`
- Optional for `PresenceOnly` and `PresenceWithSignals`
- Full policy is stored off-chain, verified by hash

### 2.4 Propagation Scope (Off-Chain)

**Propagation Scope** defines where ephemeral data is allowed to exist.

This is a **purely off-chain concept** and is NOT stored on-chain.

Semantic values:
- `None` — No propagation
- `LocalOnly` — Within same epoch only
- `AdjacentSubEpochs` — To immediate sub-epochs

Propagation scope expresses **where data is allowed to exist**, not how
it is transmitted.

---

## 3. Design Principles

The Ephemeral Data Governance Layer is governed by:

1. **Presence-first**
   Ephemeral data is secondary to presence and cannot exist independently.

2. **Epoch sovereignty**
   The epoch, not the actor, determines whether ephemeral data may exist.

3. **Strict ephemerality**
   All data must become irreversibly inaccessible after epoch termination.

4. **Orthogonality**
   Presence consensus and ephemeral data lifecycles are logically independent.

5. **Protocol-level governance**
   The protocol defines constraints, not implementation mechanisms.

---

## 4. Epoch Capability

### 4.1 Capability Properties

| Capability | Presence | Signals | Ephemeral Data | Policy Required |
|------------|----------|---------|----------------|-----------------|
| PresenceOnly | Yes | No | No | No |
| PresenceWithSignals | Yes | Yes | No | No |
| PresenceWithEphemeralData | Yes | Yes | Yes | Yes |

### 4.2 Capability Rules

- Epochs with `PresenceOnly` MUST NOT allow Ephemeral Data
- Ephemeral Data MAY exist only in epochs with `PresenceWithEphemeralData`
- Capability is declared at creation and MUST NOT change
- Capability is stored in a separate mapping, not in the Epoch struct

---

## 5. Epoch Data Policy

### 5.1 On-Chain Representation

Only a hash is stored on-chain:
```rust
data_policy_hash: [u8; 32]  // keccak256 of full policy JSON
```

### 5.2 Off-Chain Policy Structure

```json
{
  "version": "1.0.0",
  "maxPayloadSize": 1024,
  "maxTTL": 3600,
  "propagationScope": "LocalOnly",
  "encryptionRequired": true,
  "allowedActorTypes": ["validator", "participant"]
}
```

### 5.3 Policy Verification

Off-chain systems MUST verify:
```
keccak256(policyJSON) == epochDataPolicyHash
```

### 5.4 Policy Hash Semantics

- `bytes32(0)` MUST mean "no policy committed"
- Epochs with `PresenceWithEphemeralData` MUST have non-zero policy hash
- Other capabilities MAY use `bytes32(0)`

---

## 6. Separation from Presence Logic

A strict separation between **presence state** and **ephemeral data** is mandatory.

### 6.1 Normative Rules

- Presence state transitions MUST NOT depend on Ephemeral Data
- Ephemeral Data MUST NOT affect validation, disputes, or slashing
- Presence remains the sole consensus primitive of the protocol

This separation ensures that v0.4 invariants remain intact and prevents
data-based manipulation of presence outcomes.

---

## 7. Lifecycle and Destruction

### 7.1 Data Lifecycle

Ephemeral Data MUST become irreversibly inaccessible upon any of:

1. Epoch transition from `Active` to `Closed`
2. Actor exit from the epoch domain (slashed, not declared)
3. Capability revocation (not applicable after creation)
4. Expiration of declared TTL (per policy)

### 7.2 Destruction Definition

Destruction MUST be cryptographic in nature (e.g., key destruction).

The following are INSUFFICIENT:
- UI-level deletion
- Soft invalidation
- Hiding data from display
- Database tombstoning

### 7.3 Epoch Key Management (v0.6.9)

Ephemeral data MUST be protected by epoch-scoped cryptographic keys with
guaranteed destruction.

#### 7.3.1 Key Derivation

Epoch keys are derived using HKDF-SHA256:

```rust
pub fn derive_epoch_key(
    master_secret: &[u8; 32],
    epoch_id: u128,
) -> [u8; 32] {
    // HKDF-SHA256 key derivation
    let salt = epoch_id.to_be_bytes();
    let info = b"7ay-ephemeral-v1";

    hkdf_sha256(master_secret, &salt, info)
}
```

Properties:
- Each epoch derives a unique key from the master secret
- Key derivation is deterministic and reproducible
- Keys are forward-secure (compromising one epoch doesn't affect others)

#### 7.3.2 Key Distribution

Keys are distributed using Shamir Secret Sharing (3-of-5 threshold):

```rust
pub struct KeyShare {
    pub share_index: u8,        // 1-5
    pub share_data: [u8; 33],   // Shamir share
    pub validator: AccountId,   // Assigned validator
    pub epoch_id: u128,
}

pub fn distribute_key_shares(
    epoch_key: &[u8; 32],
    validators: &[AccountId; 5],
) -> Vec<KeyShare> {
    // Shamir Secret Sharing: 3-of-5 threshold
    shamir_split(epoch_key, threshold: 3, shares: 5)
        .enumerate()
        .map(|(i, share)| KeyShare {
            share_index: i as u8 + 1,
            share_data: share,
            validator: validators[i],
            epoch_id,
        })
        .collect()
}
```

Requirements:
- Minimum 5 validators for key distribution
- Any 3 validators can reconstruct the key
- Shares are encrypted to individual validator public keys

#### 7.3.3 Key Destruction Protocol (INV44)

When an epoch transitions to Closed, keys MUST be destroyed:

```rust
pub struct KeyShareDestroyed {
    pub validator: AccountId,
    pub epoch_id: u128,
    pub destroyed_at: u64,
    pub attestation_signature: [u8; 65],
}

pub struct EpochKeyDestroyed {
    pub epoch_id: u128,
    pub attestations: Vec<KeyShareDestroyed>,
    pub destruction_confirmed_at: u64,
}
```

**Destruction Sequence:**

```
1. Epoch transitions to Closed state
2. Each validator (within destruction_window = 300 seconds):
   a. Calls secure_zero() on key share memory
   b. Signs destruction attestation
   c. Broadcasts KeyShareDestroyed message
3. When 3+ attestations received:
   a. Key reconstruction becomes impossible
   b. Emit EpochKeyDestroyed event
   c. Epoch key considered irrecoverable
```

**Secure Memory Zeroing:**

```rust
pub fn secure_zero(key_material: &mut [u8]) {
    // Volatile write to prevent compiler optimization
    for byte in key_material.iter_mut() {
        unsafe { std::ptr::write_volatile(byte, 0) };
    }
    // Memory barrier
    std::sync::atomic::fence(Ordering::SeqCst);
}
```

#### 7.3.4 Key Destruction Invariant (INV44)

```
∀ epoch where state = Closed:
  ∃ attestations: Vec<KeyShareDestroyed>:
    count(attestations) >= 3 ∧
    ∀ a ∈ attestations:
      a.destroyed_at <= epoch.closed_at + DESTRUCTION_WINDOW ∧
      verify_signature(a.attestation_signature, a.validator)
```

**INV44: Key Destruction Attestation**
When an epoch closes, at least 3 validators MUST attest to key share
destruction within the destruction window.

#### 7.3.5 Configuration

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| key_share_threshold | 3 | 3-5 | Minimum shares for reconstruction |
| key_share_count | 5 | 5-10 | Total shares distributed |
| destruction_window | 300 | 60-600 | Seconds to complete destruction |
| min_destruction_attestations | 3 | 3-5 | Required attestations |

---

## 8. Trust Model (v0.7.0)

This section explicitly documents what the ephemeral data system can and cannot
guarantee from a security perspective.

### 8.1 Cryptographic Guarantees (Strong)

The following guarantees are mathematically enforced:

**Key destruction makes data cryptographically inaccessible**
- Once 3+ key shares are destroyed, the epoch key cannot be reconstructed
- Shamir Secret Sharing with 3-of-5 threshold is information-theoretically secure
- Without the key, encrypted ephemeral data is computationally infeasible to decrypt

**Forward secrecy between epochs**
- HKDF derivation ensures each epoch has a unique, independent key
- Compromising one epoch's key does not reveal other epochs' keys
- Past epochs remain protected even if future keys are compromised

**Validator attestations are cryptographically verifiable**
- Each destruction attestation is signed by the validator's key
- Signatures are publicly verifiable
- Validators cannot deny their attestations

### 8.2 Physical Limitations (Acknowledged)

The protocol acknowledges these limitations that are inherent to computer systems:

**RAM retention after key destruction**
- Key material may persist in physical memory after `secure_zero()` is called
- Cold boot attacks could theoretically recover key material
- CPU caches and registers may retain key fragments

**Validator collusion risk**
- 3 or more validators could collude to retain key shares
- Colluding validators could reconstruct keys after destruction attestation
- The protocol relies on validator honesty for true destruction

**Network observation**
- Ephemeral data in transit may be observed by network intermediaries
- Encryption protects content but metadata (timing, size) is observable
- Historical traffic analysis could reveal patterns

**Client-side copies**
- Users may screenshot, copy, or export ephemeral data before destruction
- The protocol cannot prevent human-level data exfiltration
- Application-layer controls are outside protocol scope

### 8.3 What Validators CAN Guarantee

Validators can cryptographically attest to:

| Guarantee | Verification |
|-----------|--------------|
| Key share was zeroed in memory | Signed attestation with timestamp |
| Attestation was timely | Within destruction window |
| Threshold was reached | 3+ attestations on-chain |
| Key reconstruction impossible | Shamir 3-of-5 math |

### 8.4 What Validators CANNOT Guarantee

Validators CANNOT guarantee:

| Limitation | Reason |
|------------|--------|
| Physical memory scrubbing | Hardware-level operation |
| No copies were made | Validator could retain before zeroing |
| No third-party observers | Network is public |
| Data was never intercepted | End-to-end encryption is separate |
| Client compliance | Outside protocol scope |

### 8.5 Trust Assumptions

The ephemeral data system operates under these trust assumptions:

**Honest majority assumption**
- At least 3 of 5 validators are honest
- Honest validators genuinely destroy key shares
- Colluding minority cannot reconstruct keys

**Secure key generation**
- Master secret has sufficient entropy
- HKDF implementation is correct
- VRF (if used) provides genuine randomness

**Correct implementation**
- `secure_zero()` is properly implemented
- Memory barriers function correctly
- No side-channel leakage in key operations

### 8.6 Recommendations for Maximum Security

For applications requiring maximum security, combine protocol guarantees with:

**Hardware Security Modules (HSM)**
- Store key shares in tamper-resistant hardware
- Hardware-enforced key destruction
- Side-channel resistant operations

**Secure Enclaves (SGX/TrustZone)**
- Process ephemeral data in isolated execution environments
- Memory encryption prevents cold boot attacks
- Attestation of enclave integrity

**End-to-End Encryption**
- Encrypt data at application layer before protocol encryption
- Sender and recipient keys, not epoch keys
- Protocol layer provides transport security

**Network Privacy**
- Use onion routing or mix networks for message transport
- Minimize metadata leakage
- Consider timing attack mitigations

### 8.7 Security Classification

| Security Level | Achievable With |
|----------------|-----------------|
| **Basic** | Protocol defaults (key destruction, attestations) |
| **Enhanced** | + End-to-end encryption + trusted validator set |
| **Maximum** | + HSM + Secure enclaves + network privacy |

The protocol provides **Basic** security by default. Applications requiring
higher security levels should implement additional layers as documented.

---

## 9. Functions

### 8.1 Epoch Creation (v0.5)

```rust
pub fn create_epoch_with_capability(
    &mut self,
    epoch_id: u128,
    start_time: u64,
    end_time: u64,
    capability: EpochCapability,
    data_policy_hash: [u8; 32],
) -> Result<(), Error>;
```

Rules:
- MUST be called by epoch authority
- MUST reject if `epochId == 0`
- MUST reject if epoch already exists
- MUST reject if `startTime >= endTime`
- MUST reject if `capability` is invalid (> 2)
- MUST reject if `capability == PresenceWithEphemeralData && dataPolicyHash == 0`
- MUST emit `EpochCreatedV2` and `EpochCreated` (legacy)

### 8.2 Read Operations (v0.5)

```rust
pub fn epoch_capability(&self, epoch_id: u128) -> EpochCapability;
pub fn epoch_data_policy_hash(&self, epoch_id: u128) -> [u8; 32];
pub fn supports_ephemeral_data(&self, epoch_id: u128) -> bool;
```

Rules:
- `epochCapability` returns `PresenceOnly` (0) for non-existent epochs
- `epochDataPolicyHash` returns `bytes32(0)` for non-existent epochs
- `supportsEphemeralData` returns `true` only if epoch exists AND capability is `PresenceWithEphemeralData`

---

## 10. Events

### 9.1 EpochCreatedV2

Emitted when an epoch is created (v0.5).

```rust
pub struct EpochCreatedV2 {
    pub epoch_id: u128,
    pub start_time: u64,
    pub end_time: u64,
    pub capability: EpochCapability,
    pub data_policy_hash: [u8; 32],
}
```

### 9.2 Legacy Compatibility

The legacy `EpochCreated` event MUST also be emitted for backwards compatibility:

```rust
pub struct EpochCreated {
    pub epoch_id: u128,
    pub start_time: u64,
    pub end_time: u64,
}
```

### 9.3 Key Destruction Events (v0.6.9)

```rust
/// Emitted when a validator destroys their key share
pub struct KeyShareDestroyed {
    pub validator: AccountId,
    pub epoch_id: u128,
    pub destroyed_at: u64,
}

/// Emitted when sufficient attestations confirm key destruction
pub struct EpochKeyDestroyed {
    pub epoch_id: u128,
    pub attestation_count: u32,
    pub destruction_confirmed_at: u64,
}
```

---

## 11. Errors

### 10.1 InvalidCapability

Raised when capability value is invalid.

```rust
InvalidCapability
```

### 10.2 InvalidDataPolicyHash

Raised when data policy hash is required but not provided.

```rust
InvalidDataPolicyHash
```

### 10.3 Key Management Errors (v0.6.9)

```rust
/// Insufficient validators for key distribution
InsufficientValidatorsForKeyDistribution { required: u32, available: u32 }

/// Key share already destroyed
KeyShareAlreadyDestroyed { validator: AccountId, epoch_id: u128 }

/// Destruction window expired
DestructionWindowExpired { epoch_id: u128, window_end: u64 }

/// Invalid destruction attestation signature
InvalidDestructionAttestation { validator: AccountId }
```

---

## 12. Invariants

The following invariants MUST NEVER be violated:

### 11.1 Preserved from v0.4 (Invariants 1-13)

All invariants from v0.4 remain in effect.

### 11.2 New in v0.5 (Invariants 14-18)

14. **Temporal Boundary**
    Ephemeral Data MUST NOT exist outside an Active epoch.

15. **Read Termination**
    Ephemeral Data MUST NOT be readable after epoch termination.

16. **Actor Exit Invalidation**
    Actors leaving an epoch MUST immediately lose access to Ephemeral Data.

17. **State Independence**
    Ephemeral Data MUST NOT influence presence state.

18. **Non-Persistence**
    Ephemeral Data MUST NOT be persisted or finalized.

### 11.3 New in v0.6.9 (Invariant 44)

44. **Key Destruction Attestation** (INV44)
    When an epoch closes, at least 3 validators MUST attest to key share
    destruction within the destruction window.

```
∀ epoch where state = Closed:
  count(KeyShareDestroyed attestations) >= 3
  within destruction_window (300 seconds)
```

### 11.4 Enforcement Model

| Invariant | Enforcement |
|-----------|-------------|
| INV14 | Off-chain (epoch state check) |
| INV15 | Off-chain (key destruction) |
| INV16 | Off-chain (access revocation) |
| INV17 | On-chain (orthogonal design) |
| INV18 | Off-chain (no permanent storage) |
| INV44 | Off-chain (validator attestations) |

---

## 13. Storage

### 12.1 On-Chain Storage

```rust
pub struct Storage {
    // Existing (unchanged)
    epochs: BTreeMap<u128, Epoch>,

    // New (v0.5)
    epoch_capabilities: BTreeMap<u128, EpochCapability>,
    epoch_data_policy_hashes: BTreeMap<u128, [u8; 32]>,
}
```

### 12.2 ABI Safety

The `Epoch` struct is NOT modified. New fields are stored in separate
mappings to maintain ABI compatibility with v0.4 clients.

---

## 14. Explicit Non-Goals

This version explicitly does NOT:

- Define messaging or chat systems
- Define transport layers or mesh networking
- Define encryption primitives
- Define client or SDK behavior
- Guarantee data delivery or reachability
- Store ephemeral data on-chain

Any such mechanisms exist outside the protocol scope.

---

## 15. Backwards Compatibility

| Aspect | Approach |
|--------|----------|
| Epoch struct | Unchanged |
| createEpoch() | Still works, defaults to PresenceOnly |
| Events | Dual emission (v0.5 + legacy) |
| PresenceRegistry | No changes required |
| ValidatorRegistry | No changes required |

---

## 16. Configuration

| Parameter | Default | Range | Mutable |
|-----------|---------|-------|---------|
| capability | PresenceOnly | 0-2 | No (immutable) |
| dataPolicyHash | bytes32(0) | any | No (immutable) |

---

## 17. Compliance

An implementation is considered compliant if and only if:
- All v0.4 invariants (1-13) hold
- All v0.5 invariants (14-18) hold
- All required events are emitted correctly
- All error conditions are handled per specification
- Epoch struct remains unchanged (ABI safety)

---

## 18. Versioning

| Version | Changes |
|---------|---------|
| v0.5 | Ephemeral Data Governance Layer |
| v0.6.9 | **Security hardening**: Epoch key management, HKDF derivation, Shamir distribution, destruction attestation (INV44) |
| v0.7.0 | **Trust model documentation**: Explicit trust assumptions, security limitations, recommendations for maximum security |

---

## 19. References

- epoch.md v0.2 — Epoch specification
- presence.md v0.4 — Presence specification
- validator.md v0.4 — Validator specification
- errors.md v0.5 — Error catalog

---

## 20. Closing Statement

> The 7ay Presence Protocol does not transmit or store data.
> It defines the conditions under which data may temporarily exist.
> When presence ends, data ceases to exist as well.

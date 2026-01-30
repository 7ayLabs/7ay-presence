# RFC-0005: Presence-Based Secure Data Storage

| Field | Value |
|-------|-------|
| **RFC** | 0005 |
| **Title** | Presence-Based Secure Data Storage |
| **Author** | 7ayLabs |
| **Status** | Draft |
| **Created** | 2026-01-29 |
| **Updated** | 2026-01-29 |
| **Requires** | None |
| **Supersedes** | None |

---

## Abstract

This RFC proposes a presence-gated personal data storage system where sensitive data (text, images, documents, video, audio) is protected by Shamir Secret Sharing across user's trusted devices. Data is ONLY accessible when a threshold of devices are actively present in the current epoch.

Key innovation: Unlike centralized clouds or P2P storage, 7ay storage uses **real-time presence verification** to control access. When devices leave, data automatically locks.

---

## Motivation

### Problem Statement

Current storage solutions have fundamental trust issues:

| Solution | Problem |
|----------|---------|
| **Centralized Cloud** | Trust single entity; data always accessible to provider; vulnerable to subpoena, breach, insider threat |
| **P2P Storage**| No presence verification; any node holder can access; no automatic lock mechanism |
| **Traditional E2E Encryption** | Static keys; no automatic lock on device loss; key theft = permanent access |

Users need storage that:
1. Requires **physical device presence** to access
2. **Automatically locks** when devices leave
3. Cannot be accessed by non-trusted devices
4. Provides **forward secrecy** via epoch-bound keys

### Goals

1. **Presence-Gated Access**: Data only accessible when threshold devices are present
2. **Threshold Security**: k-of-n Shamir Secret Sharing protects vault keys
3. **Automatic Locking**: Vault locks instantly when devices leave
4. **Privacy-First**: Zero-knowledge proofs for anonymous vault operations
5. **Forward Secrecy**: Key rotation per epoch prevents past data compromise

### Non-Goals

1. **High-Performance File System**: Not optimized for frequent read/write patterns
2. **Real-Time Collaboration**: Not designed for simultaneous multi-device editing
3. **Public File Sharing**: Focused on personal/private storage only
4. **Backup/Recovery Service**: Users responsible for device ring management

---

## Specification

### Overview

The Presence Storage system consists of four layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                      STORAGE LAYER                              │
│  PUT/GET/DELETE operations on encrypted items                   │
├─────────────────────────────────────────────────────────────────┤
│                   CRYPTOGRAPHIC LAYER                           │
│  Shamir Secret Sharing, ECIES, key reconstruction               │
├─────────────────────────────────────────────────────────────────┤
│                       VAULT LAYER                               │
│  Vault creation, device ring, access states, ZK proofs          │
├─────────────────────────────────────────────────────────────────┤
│                      DEVICE LAYER                               │
│  Device registration, identity derivation, presence binding     │
└─────────────────────────────────────────────────────────────────┘
```

### Detailed Design

#### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER'S VAULT                                 │
│   Owner: 0xAlice                                                │
│   Threshold: 3-of-5 devices                                     │
│   Status: UNLOCKED (4 devices present)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   TRUSTED DEVICES (Device Ring):                                │
│   ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐       │
│   │ Phone  │ │ Laptop │ │ Tablet │ │Desktop │ │ Watch  │       │
│   │PRESENT │ │PRESENT │ │ ABSENT │ │PRESENT │ │PRESENT │       │
│   │Share 1 │ │Share 2 │ │Share 3 │ │Share 4 │ │Share 5 │       │
│   └────────┘ └────────┘ └────────┘ └────────┘ └────────┘       │
│        │          │                     │          │            │
│        └──────────┴─────────────────────┴──────────┘            │
│                          │                                      │
│                   Key Reconstruction                            │
│                   (3 shares = UNLOCK)                           │
│                          │                                      │
│                          ▼                                      │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │              ENCRYPTED STORAGE                           │  │
│   │  [Photos] [Documents] [Video] [Audio] [Text]            │  │
│   └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### Data Structures

**Device Structure (v0.7.1):**
```typescript
interface Device {
  deviceId: bytes32;        // Derived identity
  owner: Address;
  deviceIndex: uint8;       // 0-254
  deviceType: DeviceType;   // Mobile, Desktop, etc.
  publicKey: bytes;         // secp256k1 (33 bytes)
  state: DeviceState;       // Registered, Present, Absent, etc.
  shareIndex: uint8;        // 1-based Shamir index
}
```

**Vault Structure (v0.7.2):**
```typescript
interface Vault {
  vaultId: bytes32;
  owner: Address;
  deviceRing: DeviceRing;
  accessState: VaultAccessState;
  policy: VaultPolicy;
  zkConfig?: ZKConfig;
}

interface DeviceRing {
  threshold: uint8;         // k in k-of-n
  totalDevices: uint8;      // n in k-of-n
  devices: bytes32[];
  shareCommitments: bytes32[];
  membershipRoot: bytes32;  // For ZK proofs
}
```

#### State Transitions

**Device State Machine:**
```
               DEVICE_REGISTER
    ──────────────────────────────► Registered
                                         │
         ┌───────────────────────────────┼───────────────────┐
         │                               │                   │
         ▼                               ▼                   ▼
  DEVICE_ENTER_EPOCH              DEVICE_REVOKE        DEVICE_LOST
         │                               │                   │
         ▼                               ▼                   ▼
      Present                        Revoked              Lost
         │                          (terminal)        (recoverable)
    ┌────┴────┐
    │         │
    ▼         ▼
DEVICE_LEAVE  epoch closes
    │         │
    ▼         ▼
 Absent    Inactive ◄────────────── DEVICE_RECOVER
```

**Vault Access State Machine:**
```
                VAULT_CREATE
    ───────────────────────────────────► Locked
                                             │
          ┌──────────────────────────────────┼──────────────────┐
          │                                  │                  │
          ▼                                  ▼                  ▼
    threshold met                     VAULT_SUSPEND      DEVICE_RECOVER
          │                                  │                  │
          ▼                                  ▼                  ▼
      Unlocked                          Suspended          Recovering
          │
     ┌────┴────┐
     │         │
     ▼         ▼
device leaves  VAULT_LOCK
(< threshold)       │
     │              │
     ▼              ▼
  Locked ◄──────────┘
```

#### Invariants

| Invariant | Description |
|-----------|-------------|
| INV64 | Device identity derivable from owner, index, epoch randomness |
| INV65 | Device operations require owner's valid presence |
| INV66 | Device ring: `2 ≤ threshold ≤ totalDevices`, min 2-of-3 |
| INV67 | Vault locked when `presentDevices < threshold` |
| INV68 | Reconstructed key zeroed on vault lock |
| INV73 | ZK share proofs must verify when policy requires |
| INV74 | ZK presence proofs must verify when policy requires |
| INV75 | ZK access proofs must verify when policy requires |

#### Error Conditions

**Device Errors (STOR_001-005):**
| Code | Name | Description |
|------|------|-------------|
| STOR_001 | DeviceNotRegistered | Device ID not found |
| STOR_002 | DeviceAlreadyRegistered | Device index used |
| STOR_003 | DeviceNotPresent | No presence in epoch |
| STOR_004 | DeviceRevoked | Permanently revoked |
| STOR_005 | DeviceLost | Marked as lost |

**Vault Errors (STOR_006-010):**
| Code | Name | Description |
|------|------|-------------|
| STOR_006 | VaultNotFound | Vault ID not found |
| STOR_007 | VaultLocked | Access state locked |
| STOR_008 | VaultSuspended | Owner-suspended |
| STOR_009 | InsufficientDevices | Not enough in ring |
| STOR_010 | ThresholdNotMet | Present < threshold |

**Cryptographic Errors (STOR_011-013):**
| Code | Name | Description |
|------|------|-------------|
| STOR_011 | ShareAlreadyProvided | Duplicate share |
| STOR_012 | InvalidShare | Verification failed |
| STOR_013 | ShareMismatch | Wrong share index |

**Storage Errors (STOR_014-020):**
| Code | Name | Description |
|------|------|-------------|
| STOR_014 | StorageQuotaExceeded | Limit reached |
| STOR_015 | ItemNotFound | Item not found |
| STOR_016 | ItemTooLarge | Exceeds max size |
| STOR_017 | InvalidMediaType | Type not allowed |
| STOR_018 | KeyVersionMismatch | Old key version |
| STOR_019 | IntegrityCheckFailed | Hash mismatch |
| STOR_020 | UnauthorizedDevice | Not in vault ring |

#### Message Types (0x70-0x7F)

| Code | Name | Purpose |
|------|------|---------|
| 0x70 | DEVICE_REGISTER | Register trusted device |
| 0x71 | DEVICE_ENTER_EPOCH | Device enters epoch with presence |
| 0x72 | DEVICE_LEAVE | Device leaves epoch |
| 0x73 | DEVICE_REVOKE | Permanently revoke device |
| 0x74 | DEVICE_RECOVER | Initiate device recovery |
| 0x75 | VAULT_CREATE | Create new vault |
| 0x76 | VAULT_CONFIGURE | Update vault configuration |
| 0x77 | VAULT_UNLOCK | Request vault unlock |
| 0x78 | VAULT_LOCK | Request vault lock |
| 0x79 | STORAGE_PUT | Store encrypted item |
| 0x7A | STORAGE_GET | Retrieve encrypted item |
| 0x7B | STORAGE_DELETE | Delete stored item |
| 0x7C | STORAGE_LIST | List stored items |
| 0x7D | SHARE_DISTRIBUTE | Distribute key shares |
| 0x7E | SHARE_REQUEST | Request share for reconstruction |
| 0x7F | SHARE_PROVIDE | Provide share |

### Examples

**Example 1: Basic Unlock Flow**

```
1. Alice has 5 devices in vault ring (3-of-5 threshold)
2. Phone, Laptop, Desktop enter epoch (3 present)
3. Phone sends VAULT_UNLOCK request
4. Laptop and Desktop receive SHARE_REQUEST
5. Each provides encrypted share via SHARE_PROVIDE
6. Phone collects 3 shares, reconstructs vault key
7. Vault state → Unlocked
8. Alice can now PUT/GET/DELETE items
```

**Example 2: Auto-Lock on Device Leave**

```
1. Vault is Unlocked with 3 devices present
2. Laptop sends DEVICE_LEAVE (going offline)
3. Present count drops to 2
4. 2 < threshold (3)
5. Vault immediately → Locked
6. Reconstructed key zeroed (secureZero)
7. Further storage operations fail with STOR_007
```

**Example 3: ZK Anonymous Unlock**

```
1. Policy requires ZKPresenceProof
2. Phone generates ZK proof of presence
3. Proof shows: "some device in ring is present"
4. Does NOT reveal: which device
5. Observer cannot correlate which device participated
6. Privacy preserved during threshold unlock
```

---

## Backwards Compatibility

### Impact Assessment

| Component | Impact | Migration Required |
|-----------|--------|-------------------|
| Presence Registry | None | No |
| Epoch Registry | None | No |
| Validator Registry | None | No |
| Message Catalog | Additive | No |
| Capabilities | Additive | No |

### Migration Path

This RFC adds new functionality without modifying existing behavior:
- New message types (0x70-0x7F) added to catalog
- New capability (PresenceWithStorage) added
- Existing epochs unaffected
- Existing presences unaffected

---

## Security Considerations

### Threat Model

| Threat | Severity | Description |
|--------|----------|-------------|
| Device theft | High | Attacker gains physical device |
| Malware on device | High | Software compromise of device |
| Network eavesdropping | Medium | Passive traffic observation |
| Owner key compromise | Critical | Master key stolen |
| Colluding devices | High | k devices cooperate maliciously |
| Replay attacks | Medium | Old messages reused |

### Mitigations

| Threat | Mitigation |
|--------|------------|
| Device theft | Threshold security (need k devices) |
| Malware on device | Secure enclave for shares; hardware device requirement |
| Network eavesdropping | ECIES encryption of shares; ZK proofs |
| Owner key compromise | Multi-device verification; no single point of access |
| Colluding devices | Physical diversity requirement; policy constraints |
| Replay attacks | Nonce + epoch + chain binding (INV43) |

### Cryptographic Guarantees

**Strong guarantees:**
- Data inaccessible without k-of-n shares (information-theoretic)
- Vault key never stored in single location
- Epoch-bound keys provide forward secrecy
- ZK proofs are computationally sound

**Acknowledged limitations:**
- Requires k devices online simultaneously
- Owner's private key is SPOF for device management
- Root-level malware on k devices could collude
- ZK proofs assume correct implementation

### Audit Requirements

1. **Shamir implementation**: Verify correct polynomial evaluation
2. **ZK circuits**: Formal verification of constraint satisfaction
3. **Key derivation**: HKDF parameter correctness
4. **Memory handling**: Verify secure_zero effectiveness
5. **State machine**: Verify all transitions preserve invariants

---

## Alternatives Considered

### Alternative 1: Pure Centralized Storage

**Approach:** Store encrypted data on centralized server, decrypt locally.

**Rejected because:**
- No presence verification
- Server can be compelled to retain data
- Single point of failure/compromise
- No automatic lock mechanism

### Alternative 2: MPC-Based Access Control

**Approach:** Use secure multi-party computation for every access.

**Rejected because:**
- High latency (multiple round trips)
- Complex implementation
- Doesn't leverage existing presence infrastructure
- Overkill for personal storage use case

### Alternative 3: Time-Locked Encryption

**Approach:** Data automatically unlocks/locks based on time.

**Rejected because:**
- Time is not presence
- Doesn't verify device actually present
- Clock manipulation attacks possible
- Not aligned with epoch-based model

---

## Implementation Notes

### Substrate-Specific Considerations

**Pallets Required:**
- `pallet-devices`: Device registration and state management
- `pallet-vaults`: Vault creation and configuration
- `pallet-storage`: Encrypted item storage (off-chain)

**Off-Chain Workers:**
- Share distribution coordination
- ZK proof generation (client-side)
- Storage item encryption/decryption

### Performance Considerations

**ZK Proof Generation:**
- Groth16 proofs: ~500ms on mobile
- PLONK proofs: ~1s on mobile
- Consider pre-computation for anticipated operations

**Storage Limits:**
- Default quota: 1 GB per vault
- Max item size: 100 MB
- Consider chunking for large files

---

## Open Questions

1. **Recovery without owner key**: Should there be a social recovery mechanism if owner loses master key?

2. **Cross-vault sharing**: Should items be shareable between vaults (different owners)?

3. **Offline access**: Should devices cache data for temporary offline access? What are the security implications?

4. **Enterprise features**: Should there be admin override capabilities for business use cases?

---

## References

- [devices.md](../specs/extensions/devices.md) — Device layer specification
- [vaults.md](../specs/extensions/vaults.md) — Vault layer specification
- [zk-proofs.md](../specs/extensions/zk-proofs.md) — ZK proof specification
- [ephemeral.md](../specs/governance/ephemeral.md) — Key management patterns
- [Shamir's Secret Sharing](https://dl.acm.org/doi/10.1145/359168.359176) — Original paper
- [ECIES](https://en.wikipedia.org/wiki/Integrated_Encryption_Scheme) — Encryption scheme
- [Groth16](https://eprint.iacr.org/2016/260) — ZK-SNARK proving system

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-29 | 7ayLabs | Initial draft |

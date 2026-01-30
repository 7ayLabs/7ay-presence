# 7ay Proof of Presence (PoP)
## Protocol Specification — Vaults
**Version:** v0.7.2
**Status:** Draft
**Depends on:** devices.md v0.7.1, ephemeral.md v0.7.0

> Presence-gated encrypted storage containers with threshold device access

## 1. Overview

The Vault extension enables users to create encrypted storage containers that are only accessible when a threshold of their trusted devices are actively present in the current epoch.

### 1.1 Design Principles

1. **Presence-Gated Access**: Vault operations require threshold device presence
2. **Threshold Security**: Data protected by k-of-n Shamir Secret Sharing
3. **Privacy-First**: Zero-knowledge proofs for anonymous vault operations
4. **Epoch Binding**: Vault keys rotate per epoch for forward secrecy

### 1.2 Key Innovation

7ay vaults use **real-time presence verification** to control access:

| Storage Type | Access Control | Presence Verification |
|--------------|----------------|----------------------|
| Centralized Cloud | Password/OAuth | None |
| P2P Storage | Node holding data | None |
| 7ay Vault | Threshold devices | **Real-time epoch presence** |

---

## 2. Vault Model

### 2.1 Vault Structure

```typescript
interface Vault {
  // Identity
  vaultId: bytes32;             // keccak256(owner, creationEpoch, nonce)
  owner: Address;

  // Creation metadata
  createdAt: uint256;
  createdInEpoch: uint256;

  // Device ring configuration
  deviceRing: DeviceRing;

  // Key management
  vaultKeyVersion: uint256;     // Increments on rotation
  keyRotatedAt: uint256;
  keyCommitment: bytes32;       // Pedersen commitment to vault key

  // Storage metadata
  storageQuota: uint256;        // Max bytes
  storageUsed: uint256;
  itemCount: uint256;

  // Access control
  accessState: VaultAccessState;
  lastUnlockedAt?: uint256;
  lastLockedAt?: uint256;

  // Policy
  policy: VaultPolicy;
  policyHash: bytes32;

  // ZK Configuration
  zkConfig: ZKConfig;
}
```

### 2.2 Vault Identity Derivation

Vault identity is deterministically derived:

```typescript
function deriveVaultId(
  owner: Address,
  creationEpochId: uint256,
  nonce: bytes32
): bytes32 {
  return keccak256(abi.encodePacked(
    "7ay-vault-v1",         // Domain separator
    owner,                   // 20 bytes
    creationEpochId,         // 32 bytes
    nonce                    // 32 bytes (user-provided)
  ));
}
```

---

## 3. Device Ring (INV66)

### 3.1 Device Ring Structure

```typescript
interface DeviceRing {
  // Threshold configuration
  threshold: uint8;             // k in k-of-n (min 2)
  totalDevices: uint8;          // n in k-of-n (min 3)

  // Device membership
  devices: bytes32[];           // Array of deviceIds
  devicePublicKeys: Map<bytes32, bytes>; // For ECIES encryption

  // Share distribution
  shareCommitments: bytes32[];  // Pedersen commitments to shares
  sharesDistributed: bool;
  distributedAt?: uint256;

  // ZK verification
  membershipRoot: bytes32;      // Merkle root for ZK membership proof
}
```

### 3.2 Ring Constraints (INV66)

```
FOR ALL vault v:
  v.deviceRing.threshold >= 2 AND
  v.deviceRing.totalDevices >= 3 AND
  v.deviceRing.threshold <= v.deviceRing.totalDevices AND
  v.deviceRing.totalDevices <= 255 AND
  count(v.deviceRing.devices) = v.deviceRing.totalDevices AND
  FOR ALL d IN v.deviceRing.devices:
    device(d).owner = v.owner AND
    device(d).state != Revoked
```

### 3.3 Recommended Configurations

| Configuration | Threshold | Total | Security Level | Use Case |
|---------------|-----------|-------|----------------|----------|
| Minimum | 2 | 3 | Basic | Personal, few devices |
| Standard | 3 | 5 | Enhanced | Most users |
| High Security | 4 | 7 | High | Sensitive data |
| Maximum | 5 | 9 | Maximum | Enterprise |

### 3.4 Membership Merkle Tree

For ZK proofs, device membership is committed to a Merkle tree:

```typescript
function buildMembershipRoot(devices: bytes32[]): bytes32 {
  // Build balanced Merkle tree of deviceIds
  let leaves = devices.map(d => keccak256(d));
  return merkleRoot(leaves);
}
```

---

## 4. Vault Access States (INV67)

### 4.1 State Enum

```typescript
enum VaultAccessState {
  Locked = 0,       // < threshold devices present
  Unlocked = 1,     // >= threshold devices present
  Suspended = 2,    // Owner-initiated lock (emergency)
  Recovering = 3,   // In device recovery process
  Migrating = 4     // Key rotation in progress
}
```

### 4.2 State Machine

```
                   VAULT_CREATE
    ─────────────────────────────────────────► Locked
                                                   │
              ┌────────────────────────────────────┼──────────────────────┐
              │                                    │                      │
              ▼                                    ▼                      ▼
        threshold met                      VAULT_SUSPEND           DEVICE_RECOVER
              │                                    │                      │
              ▼                                    ▼                      ▼
          Unlocked                            Suspended              Recovering
              │                                    │                      │
         ┌────┴────┐                               │                      │
         │         │                               │                      │
         ▼         ▼                               │                      │
   device leaves   VAULT_LOCK                      │                      │
   (< threshold)         │                         │                      │
         │               │                         │                      │
         ▼               ▼                         │                      │
      Locked ◄───────────┴─────────────────────────┴──────────────────────┘
                     (VAULT_RESUME or recovery complete)
```

### 4.3 Threshold Access Logic (INV67)

```typescript
function checkAccessState(vault: Vault, currentEpochId: uint256): VaultAccessState {
  // Count present devices
  let presentCount = 0;
  for (const deviceId of vault.deviceRing.devices) {
    const device = getDevice(deviceId);
    if (device.state === DeviceState.Present &&
        device.currentEpochId === currentEpochId) {
      presentCount++;
    }
  }

  // Threshold check
  if (presentCount < vault.deviceRing.threshold) {
    return VaultAccessState.Locked;
  }

  // Manual overrides
  if (vault.accessState === VaultAccessState.Suspended) {
    return VaultAccessState.Suspended;
  }

  if (vault.accessState === VaultAccessState.Recovering) {
    return VaultAccessState.Recovering;
  }

  return VaultAccessState.Unlocked;
}
```

---

## 5. Vault Policy

### 5.1 Policy Structure

```typescript
interface VaultPolicy {
  version: "1.0.0";

  // Device constraints
  minDevices: uint8;            // Minimum devices (default: 3)
  maxDevices: uint8;            // Maximum devices (default: 9)
  minThreshold: uint8;          // Minimum threshold (default: 2)

  // Required device types
  requireHardwareDevice: bool;  // At least one Hardware type
  requireDeviceDiversity: bool; // Multiple device types

  // Storage constraints
  maxStorageBytes: uint256;
  allowedMediaTypes: string[];  // MIME types
  maxItemSize: uint256;

  // Epoch behavior
  autoLockOnEpochClose: bool;
  keyRotationOnEpochChange: bool;
  persistDataAcrossEpochs: bool; // true for persistent storage

  // ZK requirements
  requireZKShareProof: bool;    // Require ZK proof for share provision
  requireZKPresenceProof: bool; // Require ZK proof for presence
  requireZKAccessProof: bool;   // Require ZK proof for storage access
}
```

### 5.2 Default Policy

```typescript
const DEFAULT_VAULT_POLICY: VaultPolicy = {
  version: "1.0.0",

  // Device constraints
  minDevices: 3,
  maxDevices: 9,
  minThreshold: 2,

  // Device types
  requireHardwareDevice: false,
  requireDeviceDiversity: false,

  // Storage
  maxStorageBytes: 1073741824,  // 1 GB
  allowedMediaTypes: ["*/*"],
  maxItemSize: 104857600,       // 100 MB

  // Epoch behavior
  autoLockOnEpochClose: true,
  keyRotationOnEpochChange: true,
  persistDataAcrossEpochs: true,

  // ZK (off by default for simplicity)
  requireZKShareProof: false,
  requireZKPresenceProof: false,
  requireZKAccessProof: false
};
```

### 5.3 Policy Hash

Policy is stored as a hash on-chain:

```typescript
function computePolicyHash(policy: VaultPolicy): bytes32 {
  return keccak256(JSON.stringify(policy));
}
```

---

## 6. Vault Key Management

### 6.1 Key Derivation

Vault keys are derived using HKDF (reusing ephemeral.md pattern):

```typescript
function deriveVaultKey(
  ownerMasterSecret: bytes32,
  vaultId: bytes32,
  epochId: uint256,
  epochRandomness: bytes32
): bytes32 {
  const salt = keccak256(abi.encodePacked(vaultId, epochId, epochRandomness));
  const info = "7ay-vault-key-v1";
  return hkdf_sha256(ownerMasterSecret, salt, info);
}
```

### 6.2 Share Distribution

Shares are distributed using Shamir Secret Sharing:

```typescript
function distributeVaultShares(
  vaultKey: bytes32,
  devices: Device[],
  threshold: uint8
): DistributedShares {
  // Split key into shares
  const shares = shamirSplit(vaultKey, threshold, devices.length);

  // Encrypt each share to device public key
  const encryptedShares = devices.map((device, i) => ({
    deviceId: device.deviceId,
    encryptedShare: eciesEncrypt(shares[i], device.publicKey),
    commitment: pedersenCommit(shares[i])
  }));

  // Build membership root
  const membershipRoot = buildMembershipRoot(devices.map(d => d.deviceId));

  return {
    encryptedShares,
    shareCommitments: encryptedShares.map(s => s.commitment),
    membershipRoot
  };
}
```

### 6.3 Key Reconstruction

```typescript
function reconstructVaultKey(
  providedShares: Share[],
  threshold: uint8
): Result<bytes32, Error> {
  if (providedShares.length < threshold) {
    return Err(STOR_010_ThresholdNotMet);
  }

  // Verify shares
  for (const share of providedShares) {
    if (!verifyShareCommitment(share)) {
      return Err(STOR_012_InvalidShare);
    }
  }

  // Reconstruct
  const vaultKey = shamirReconstruct(providedShares);

  return Ok(vaultKey);
}
```

### 6.4 Key Isolation (INV68)

```
FOR ALL vault v transitioning to Locked:
  secureZero(v.reconstructedKey) AND
  v.reconstructedKey = null
```

---

## 7. Zero-Knowledge Integration

### 7.1 ZK Configuration

```typescript
interface ZKConfig {
  // Circuit configuration
  shareProofCircuit: CircuitId;     // Share verification circuit
  presenceProofCircuit: CircuitId;  // Presence verification circuit
  accessProofCircuit: CircuitId;    // Access rights circuit

  // Verification keys (on-chain)
  shareVerifyingKey: bytes;
  presenceVerifyingKey: bytes;
  accessVerifyingKey: bytes;

  // Proving system
  provingSystem: ProvingSystem;
}

enum ProvingSystem {
  Groth16 = 0,      // Fast verification, trusted setup
  PLONK = 1,        // Universal setup, larger proofs
  STARK = 2         // No trusted setup, largest proofs
}
```

### 7.2 Why ZK in Vault Layer?

| Without ZK | With ZK |
|------------|---------|
| Share reveals which device provided it | Prove valid share without revealing device |
| Presence reveals device identity | Prove presence without revealing which device |
| Access reveals what you're accessing | Prove access rights without revealing item |
| Threshold reveals exact count | Prove threshold met without exact count |

### 7.3 ZK Share Proof (INV73)

Prove you hold a valid Shamir share without revealing it.

```typescript
interface ZKShareProof {
  // Public inputs
  vaultId: bytes32;
  shareCommitment: bytes32;     // Pedersen(share)
  epochId: uint256;

  // Proof
  proof: bytes;                 // ZK proof (Groth16: ~200 bytes)

  // The circuit proves:
  // 1. prover knows 'share' such that Pedersen(share) = shareCommitment
  // 2. shareCommitment is in vault's shareCommitments array
  // 3. share is a valid point on Shamir polynomial
}
```

### 7.4 ZK Presence Proof (INV74)

Prove a device is present in epoch without revealing which device.

```typescript
interface ZKPresenceProof {
  // Public inputs
  epochId: uint256;
  membershipRoot: bytes32;      // Merkle root of device ring

  // Proof
  proof: bytes;

  // The circuit proves:
  // 1. prover knows deviceId in the device ring
  // 2. device has valid presence in epochId
  // 3. Merkle path from deviceId to membershipRoot is valid
}
```

### 7.5 ZK Access Proof (INV75)

Prove you have access to a storage item without revealing which item.

```typescript
interface ZKAccessProof {
  // Public inputs
  vaultId: bytes32;
  accessRoot: bytes32;          // Merkle root of access list

  // Proof
  proof: bytes;

  // The circuit proves:
  // 1. prover knows itemId they want to access
  // 2. itemId is in the vault's item list
  // 3. prover has valid vault access (unlocked state)
}
```

---

## 8. Message Types

### 8.1 VAULT_CREATE (0x75)

Create a new vault with initial device ring.

```typescript
interface VaultCreatePayload {
  // Vault identity
  nonce: bytes32;               // Random nonce for vaultId derivation

  // Device ring
  devices: bytes32[];           // Initial device IDs
  threshold: uint8;             // k in k-of-n

  // Policy
  policy: VaultPolicy;

  // Key setup
  keyCommitment: bytes32;       // Pedersen commitment to vault key
  shareCommitments: bytes32[];  // Commitments to each share

  // ZK configuration (optional)
  zkConfig?: ZKConfig;

  // Signatures
  ownerSignature: bytes;
  deviceSignatures: bytes[];    // Each device signs acceptance
}
```

**Validation Rules:**
- Owner MUST have Validated/Finalized presence
- `devices.length >= 3` (or policy minimum)
- `threshold >= 2`
- `threshold <= devices.length`
- All devices MUST be registered to owner
- All device signatures MUST be valid
- `shareCommitments.length == devices.length`

**Events:**
```typescript
event VaultCreated {
  vaultId: bytes32;
  owner: Address;
  threshold: uint8;
  deviceCount: uint8;
  createdInEpoch: uint256;
  policyHash: bytes32;
}
```

### 8.2 VAULT_CONFIGURE (0x76)

Update vault configuration.

```typescript
interface VaultConfigurePayload {
  vaultId: bytes32;

  // What to configure
  configType: ConfigType;

  // Configuration data (based on type)
  addDevices?: bytes32[];
  removeDevices?: bytes32[];
  newThreshold?: uint8;
  newPolicy?: VaultPolicy;
  newZKConfig?: ZKConfig;

  // New share commitments (for device changes)
  newShareCommitments?: bytes32[];

  // Authorization
  ownerSignature: bytes;
  deviceSignatures?: bytes[];   // Required for device changes
}

enum ConfigType {
  AddDevices = 0,
  RemoveDevices = 1,
  ChangeThreshold = 2,
  UpdatePolicy = 3,
  EnableZK = 4,
  RotateKey = 5
}
```

**Validation Rules:**
- Owner signature MUST be valid
- Vault MUST exist
- For device changes: vault MUST be Unlocked
- After changes: INV66 constraints MUST hold
- For RotateKey: new share commitments required

**Events:**
```typescript
event VaultConfigured {
  vaultId: bytes32;
  configType: ConfigType;
  newThreshold?: uint8;
  newDeviceCount?: uint8;
  configuredAt: uint256;
}
```

### 8.3 VAULT_UNLOCK (0x77)

Request vault unlock (trigger share collection).

```typescript
interface VaultUnlockPayload {
  vaultId: bytes32;

  // Requesting device
  requestingDeviceId: bytes32;

  // ZK proof of presence (if required by policy)
  presenceProof?: ZKPresenceProof;

  // Device signature
  deviceSignature: bytes;
}
```

**Validation Rules:**
- Requesting device MUST be Present
- Vault MUST be Locked or Unlocked
- Device MUST be in vault's device ring

**Flow:**
1. Device broadcasts VAULT_UNLOCK
2. Present devices receive SHARE_REQUEST
3. Devices respond with SHARE_PROVIDE
4. Requesting device collects shares
5. When threshold met, reconstructs key
6. Vault state → Unlocked

### 8.4 VAULT_LOCK (0x78)

Manually lock vault (emergency).

```typescript
interface VaultLockPayload {
  vaultId: bytes32;

  // Reason
  reason: LockReason;

  // Authorization (owner OR any device)
  ownerSignature?: bytes;
  deviceSignature?: bytes;
  deviceId?: bytes32;
}

enum LockReason {
  Manual = 0,           // User-initiated
  Emergency = 1,        // Security concern
  DeviceLost = 2,       // Device reported lost
  PolicyViolation = 3   // Policy constraint violated
}
```

**Validation Rules:**
- Owner signature OR device signature required
- If device: device MUST be in vault ring

**Effects:**
- Vault state → Locked (or Suspended if Emergency)
- Reconstructed key zeroed immediately
- All active storage sessions terminated

---

## 9. Invariants

### 9.1 INV66: Device Ring Integrity

```
FOR ALL vault v:
  v.deviceRing.threshold >= 2 AND
  v.deviceRing.totalDevices >= 3 AND
  v.deviceRing.threshold <= v.deviceRing.totalDevices AND
  count(v.deviceRing.devices) = v.deviceRing.totalDevices AND
  FOR ALL d IN v.deviceRing.devices:
    device(d).owner = v.owner AND
    device(d).state != Revoked
```

### 9.2 INV67: Vault Access Threshold

```
FOR ALL vault v:
  let presentCount = count(d IN v.deviceRing.devices
    WHERE device(d).state = Present AND
          device(d).currentEpochId = currentEpoch)

  presentCount < v.deviceRing.threshold IMPLIES
    v.accessState = Locked
```

### 9.3 INV68: Vault Key Isolation

```
FOR ALL vault v WHERE v.accessState transitions to Locked:
  secureZero(v.reconstructedKey) AND
  v.reconstructedKey = null
```

### 9.4 INV73: ZK Share Proof Validity

```
FOR ALL share_provision sp WHERE sp.vault.policy.requireZKShareProof = true:
  verify(sp.zkShareProof.proof, sp.zkShareProof.publicInputs,
         sp.vault.zkConfig.shareVerifyingKey) = true
```

### 9.5 INV74: ZK Presence Proof Validity

```
FOR ALL presence_claim pc WHERE pc.vault.policy.requireZKPresenceProof = true:
  verify(pc.zkPresenceProof.proof, pc.zkPresenceProof.publicInputs,
         pc.vault.zkConfig.presenceVerifyingKey) = true
```

### 9.6 INV75: ZK Access Proof Validity

```
FOR ALL access_request ar WHERE ar.vault.policy.requireZKAccessProof = true:
  verify(ar.zkAccessProof.proof, ar.zkAccessProof.publicInputs,
         ar.vault.zkConfig.accessVerifyingKey) = true
```

---

## 10. Security Considerations

### 10.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Device theft | Threshold security (need k devices) |
| Malware on device | Secure enclave for shares |
| Network eavesdropping | ECIES encryption of shares |
| Owner key compromise | Multi-device verification |
| Colluding devices | Physical diversity requirement |
| Replay attacks | Nonce + epoch + chain binding |
| Correlation attacks | ZK proofs for anonymous operations |

### 10.2 Security Guarantees

**Cryptographic:**
- Data inaccessible without k-of-n shares
- Vault key never stored in single location
- Epoch-bound keys provide forward secrecy
- Automatic lock on device departure

**With ZK Enabled:**
- Anonymous share provision (INV73)
- Anonymous presence verification (INV74)
- Private data access (INV75)

### 10.3 Acknowledged Limitations

- Requires k devices online simultaneously
- Owner's private key is SPOF for device management
- Root-level malware on k devices could collude
- ZK proofs add computational overhead

### 10.4 Recommendations

- Enable at least one Hardware device type
- Distribute devices across physical locations
- Enable ZK proofs for high-security vaults
- Regular key rotation via epoch transitions

---

## 11. Error Codes

| Code | Name | Description | Invariant |
|------|------|-------------|-----------|
| STOR_006 | VaultNotFound | Vault ID not found | - |
| STOR_007 | VaultLocked | Vault access state is Locked | INV67 |
| STOR_008 | VaultSuspended | Vault is owner-suspended | - |
| STOR_009 | InsufficientDevices | Not enough devices in ring | INV66 |
| STOR_010 | ThresholdNotMet | Present devices < threshold | INV67 |

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.7.2 | Initial vault specification with ZK integration |

---

## 13. References

- [devices.md](devices.md) — Device management
- [ephemeral.md](../governance/ephemeral.md) — Key management patterns
- [zk-proofs.md](zk-proofs.md) — ZK circuit specifications
- [message-catalog.md](../semantic/message-catalog.md) — Message types

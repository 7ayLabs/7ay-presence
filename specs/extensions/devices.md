# 7ay Proof of Presence (PoP)
## Protocol Specification — Trusted Devices
**Version:** v0.7.1
**Status:** Draft

> Device registration, identity derivation, and presence binding for presence-based storage

## 1. Overview

The Trusted Devices extension enables users to register and manage a set of personal devices that collectively control access to encrypted storage. Each device holds a share of the vault encryption key, and data is only accessible when a threshold of devices are actively present in the current epoch.

### 1.1 Design Principles

1. **Presence-Gated Access**: Device operations require owner's valid presence
2. **Cryptographic Identity**: Device IDs derived from owner + index + epoch randomness
3. **Threshold Security**: Minimum 2-of-3 devices required for vault access
4. **Epoch Binding**: Device presence is scoped to current epoch

### 1.2 Relationship to Existing Protocol

| Existing Pattern | Device Adaptation |
|------------------|-------------------|
| Validator key shares (Shamir) | Device key shares |
| VRF identity derivation (Octopus) | Device ID derivation |
| Presence state machine | Device presence tracking |
| Key destruction attestation | Device departure attestation |

---

## 2. Device Model

### 2.1 Device Structure

```typescript
interface Device {
  // Identity (derived, not stored)
  deviceId: bytes32;

  // Owner binding
  owner: Address;
  deviceIndex: uint8;           // 0-254 (max 255 devices per owner)

  // Registration
  registeredAt: uint256;        // Block timestamp
  registrationEpochId: uint256; // Epoch when registered
  registrationProof: bytes;     // Owner signature

  // Device metadata
  deviceType: DeviceType;
  deviceName: string;           // Max 32 UTF-8 characters
  publicKey: bytes;             // secp256k1 public key (33 bytes compressed)

  // Current state
  state: DeviceState;
  stateUpdatedAt: uint256;

  // Epoch context (when present)
  currentEpochId?: uint256;
  presenceState?: PresenceState;
  lastSeenAt?: uint256;

  // Share assignment
  shareIndex: uint8;            // 1-based Shamir share index
  shareDistributedAt?: uint256;
}
```

### 2.2 Device Types

```typescript
enum DeviceType {
  Mobile = 0,       // Smartphone (iOS, Android)
  Desktop = 1,      // Desktop/laptop computer
  Tablet = 2,       // Tablet device
  Wearable = 3,     // Smartwatch, fitness band
  Hardware = 4,     // Hardware security key (YubiKey, Ledger)
  Server = 5,       // Always-on server, NAS
  Browser = 6       // Browser extension/PWA
}
```

### 2.3 Device States

```typescript
enum DeviceState {
  Registered = 0,   // Device registered but not in any epoch
  Present = 1,      // Device has valid presence in current epoch
  Absent = 2,       // Device left current epoch (voluntary)
  Inactive = 3,     // Epoch closed, device needs to re-enter next epoch
  Revoked = 4,      // Permanently removed by owner (terminal)
  Lost = 5          // Marked as lost, pending recovery (recoverable)
}
```

---

## 3. Device State Machine

### 3.1 State Transitions

```
                        DEVICE_REGISTER
    ────────────────────────────────────────────► Registered
                                                       │
              ┌────────────────────────────────────────┼────────────────────┐
              │                                        │                    │
              ▼                                        ▼                    ▼
       DEVICE_ENTER_EPOCH                       DEVICE_REVOKE         DEVICE_LOST
       (owner has presence)                          │                    │
              │                                       ▼                    ▼
              ▼                                   Revoked              Lost
          Present                               (terminal)         (recoverable)
              │                                                          │
         ┌────┴────┐                                                     │
         │         │                                                     │
         ▼         ▼                                                     │
   DEVICE_LEAVE   Epoch closes                                           │
         │         │                                                     │
         ▼         ▼                                                     │
      Absent    Inactive                                                 │
         │         │                                                     │
         └────┬────┘                                                     │
              │                                                          │
              │◄─────────────────────────────────────────────────────────┘
              │                     DEVICE_RECOVER
              ▼
    (re-enter via DEVICE_ENTER_EPOCH)
```

### 3.2 Transition Rules

| From | To | Trigger | Conditions |
|------|----|---------| -----------|
| (none) | Registered | DEVICE_REGISTER | Owner has Validated/Finalized presence |
| Registered | Present | DEVICE_ENTER_EPOCH | Owner has presence in target epoch |
| Registered | Revoked | DEVICE_REVOKE | Owner signature required |
| Registered | Lost | DEVICE_LOST | Owner signature required |
| Present | Absent | DEVICE_LEAVE | Device signature OR owner signature |
| Present | Inactive | Epoch closes | Automatic on epoch state change |
| Present | Revoked | DEVICE_REVOKE | Owner signature required |
| Present | Lost | DEVICE_LOST | Owner signature required |
| Absent | Present | DEVICE_ENTER_EPOCH | Owner has presence in new epoch |
| Absent | Revoked | DEVICE_REVOKE | Owner signature required |
| Inactive | Present | DEVICE_ENTER_EPOCH | Owner has presence in new epoch |
| Inactive | Revoked | DEVICE_REVOKE | Owner signature required |
| Lost | Registered | DEVICE_RECOVER | Recovery quorum met |
| Lost | Revoked | DEVICE_REVOKE | Owner signature required |

### 3.3 Terminal States

- **Revoked**: Permanent removal. Share destroyed. Cannot be recovered.
- **Lost**: Temporary suspension. Can be recovered via DEVICE_RECOVER.

---

## 4. Device Identity Derivation (INV64)

### 4.1 Identity Formula

Device identity is deterministically derived to prevent spoofing:

```typescript
function deriveDeviceId(
  owner: Address,
  deviceIndex: uint8,
  registrationEpochId: uint256,
  epochRandomness: bytes32  // VRF output from registration epoch
): bytes32 {
  return keccak256(abi.encodePacked(
    "7ay-device-v1",       // Domain separator
    owner,                  // 20 bytes
    deviceIndex,            // 1 byte
    registrationEpochId,    // 32 bytes
    epochRandomness         // 32 bytes (from VRF)
  ));
}
```

### 4.2 Properties

| Property | Guarantee |
|----------|-----------|
| **Uniqueness** | Same owner + index + epoch = same deviceId |
| **Unpredictability** | Cannot pre-compute deviceId before epoch randomness revealed |
| **Verifiability** | Anyone can verify deviceId given inputs |
| **Non-transferability** | DeviceId bound to owner address |

### 4.3 Epoch Randomness Source

Epoch randomness MUST come from a verifiable random function (VRF):

```typescript
interface EpochRandomness {
  epochId: uint256;
  randomness: bytes32;      // VRF output
  vrfProof: bytes;          // VRF proof for verification
  producer: Address;        // Validator who produced randomness
}
```

---

## 5. Device Presence Binding (INV65)

### 5.1 Presence Requirement

A device can only perform vault operations when:
1. Owner has valid presence (Declared, Validated, or Finalized) in current epoch
2. Device state is `Present`
3. Device's `currentEpochId` matches current epoch

### 5.2 Validation Logic

```typescript
function validateDevicePresence(
  device: Device,
  currentEpochId: uint256
): Result<void, DeviceError> {
  // 1. Check device is registered
  if (device.state === DeviceState.Revoked) {
    return Err(STOR_004_DeviceRevoked);
  }

  if (device.state === DeviceState.Lost) {
    return Err(STOR_005_DeviceLost);
  }

  // 2. Check device is present in current epoch
  if (device.state !== DeviceState.Present) {
    return Err(STOR_003_DeviceNotPresent);
  }

  if (device.currentEpochId !== currentEpochId) {
    return Err(STOR_003_DeviceNotPresent);
  }

  // 3. Check owner has presence
  const ownerPresence = presenceRegistry.presenceState(device.owner, currentEpochId);
  if (ownerPresence === PresenceState.None || ownerPresence === PresenceState.Slashed) {
    return Err(STOR_003_DeviceNotPresent);
  }

  return Ok();
}
```

### 5.3 Presence Lifecycle

```
Owner declares presence in Epoch N
           │
           ▼
Device sends DEVICE_ENTER_EPOCH
           │
           ▼
Device state = Present
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
Device leaves   Epoch N closes
     │           │
     ▼           ▼
state = Absent  state = Inactive
     │           │
     └─────┬─────┘
           │
           ▼
Epoch N+1: Owner declares presence
           │
           ▼
Device sends DEVICE_ENTER_EPOCH
           │
           ▼
Device state = Present (new epoch)
```

---

## 6. Message Types

### 6.1 DEVICE_REGISTER (0x70)

Register a new trusted device for the owner.

```typescript
interface DeviceRegisterPayload {
  // Device identity parameters
  deviceIndex: uint8;           // Unique index for this owner (0-254)
  deviceType: DeviceType;
  deviceName: string;           // Max 32 UTF-8 characters

  // Device cryptographic material
  publicKey: bytes;             // secp256k1 compressed public key (33 bytes)

  // Proof of ownership
  ownerSignature: bytes;        // Owner signs: hash(deviceIndex, publicKey, epochId)
  deviceSignature: bytes;       // Device signs: hash(owner, publicKey)

  // Share assignment
  shareIndex: uint8;            // 1-based Shamir share index
}
```

**Validation:**
- Sender MUST be device owner
- Owner MUST have Validated or Finalized presence
- `deviceIndex` MUST be unique for this owner
- `shareIndex` MUST be unique within owner's device ring
- `publicKey` MUST be valid secp256k1 point
- Both signatures MUST be valid

**Events:**
```typescript
event DeviceRegistered {
  owner: Address;
  deviceId: bytes32;
  deviceIndex: uint8;
  deviceType: DeviceType;
  shareIndex: uint8;
  registrationEpochId: uint256;
}
```

### 6.2 DEVICE_ENTER_EPOCH (0x71)

Device declares presence in an epoch.

```typescript
interface DeviceEnterEpochPayload {
  deviceId: bytes32;
  epochId: uint256;

  // Proof that owner has presence
  ownerPresenceProof: bytes;    // Signature from owner authorizing device entry

  // Device attestation
  deviceAttestation: DeviceAttestation;
}

interface DeviceAttestation {
  deviceId: bytes32;
  epochId: uint256;
  timestamp: uint256;
  capabilities: DeviceCapability[];
  deviceSignature: bytes;       // Device signs attestation
}

enum DeviceCapability {
  ShareStorage = 0,     // Can store key share
  ShareProvide = 1,     // Can provide share for reconstruction
  StorageAccess = 2,    // Can access stored data
  OfflineCache = 3      // Can cache data for offline access
}
```

**Validation:**
- Device MUST be in state: Registered, Absent, or Inactive
- Owner MUST have valid presence in target epoch
- Epoch MUST be Active
- `deviceAttestation.deviceSignature` MUST be valid

**Events:**
```typescript
event DeviceEnteredEpoch {
  deviceId: bytes32;
  owner: Address;
  epochId: uint256;
  capabilities: DeviceCapability[];
}
```

### 6.3 DEVICE_LEAVE (0x72)

Device voluntarily leaves the current epoch.

```typescript
interface DeviceLeavePayload {
  deviceId: bytes32;
  epochId: uint256;

  // Reason for leaving
  reason: LeaveReason;

  // Authorization (one of)
  deviceSignature?: bytes;      // Device self-signs leave
  ownerSignature?: bytes;       // Owner forces device leave

  // Share destruction attestation
  shareDestroyed: bool;
  destructionAttestation?: bytes;
}

enum LeaveReason {
  Voluntary = 0,        // User-initiated
  Timeout = 1,          // Heartbeat timeout
  OwnerForced = 2,      // Owner forced removal
  NetworkError = 3      // Connectivity issues
}
```

**Validation:**
- Device MUST be in Present state
- `epochId` MUST match device's current epoch
- Either device or owner signature MUST be valid

**Effects:**
- Device state → Absent
- If `shareDestroyed`, share is marked as zeroed
- Triggers vault lock check (if device was in a vault ring)

**Events:**
```typescript
event DeviceLeft {
  deviceId: bytes32;
  owner: Address;
  epochId: uint256;
  reason: LeaveReason;
  shareDestroyed: bool;
}
```

### 6.4 DEVICE_REVOKE (0x73)

Permanently revoke a device (terminal state).

```typescript
interface DeviceRevokePayload {
  deviceId: bytes32;

  // Authorization
  ownerSignature: bytes;        // Owner MUST sign revocation

  // Reason
  reason: RevokeReason;

  // Share handling
  shareDestroyedAttestation?: bytes;
}

enum RevokeReason {
  UserInitiated = 0,    // User no longer wants this device
  Compromised = 1,      // Device suspected compromised
  Lost = 2,             // Device lost, promote to revoked
  Replaced = 3          // Device being replaced
}
```

**Validation:**
- Device MUST exist
- Device MUST NOT already be Revoked
- Owner signature MUST be valid

**Effects:**
- Device state → Revoked (terminal)
- Share MUST be destroyed (if held)
- Device removed from all vault rings

**Events:**
```typescript
event DeviceRevoked {
  deviceId: bytes32;
  owner: Address;
  reason: RevokeReason;
  revokedAt: uint256;
}
```

### 6.5 DEVICE_RECOVER (0x74)

Initiate recovery for a lost device.

```typescript
interface DeviceRecoverPayload {
  deviceId: bytes32;

  // New device credentials
  newPublicKey: bytes;          // New secp256k1 public key

  // Recovery authorization
  ownerSignature: bytes;        // Owner authorizes recovery

  // Optional: Multi-device attestation for high security
  deviceAttestations?: DeviceRecoveryAttestation[];
}

interface DeviceRecoveryAttestation {
  attestingDeviceId: bytes32;
  targetDeviceId: bytes32;
  approves: bool;
  signature: bytes;
}
```

**Validation:**
- Device MUST be in Lost state
- Owner signature MUST be valid
- If `deviceAttestations` provided, must meet recovery quorum

**Effects:**
- Device state → Registered
- Public key updated to `newPublicKey`
- New share must be distributed

**Events:**
```typescript
event DeviceRecovered {
  deviceId: bytes32;
  owner: Address;
  newPublicKey: bytes;
  recoveredAt: uint256;
}
```

---

## 7. Device Ring Management

### 7.1 Device Ring Structure

```typescript
interface DeviceRing {
  owner: Address;

  // Threshold configuration
  threshold: uint8;             // k in k-of-n (minimum 2)
  totalDevices: uint8;          // n in k-of-n (minimum 3)

  // Device membership
  devices: bytes32[];           // Array of deviceIds

  // Share distribution
  sharesDistributed: bool;
  distributedAt?: uint256;
  keyVersion: uint256;
}
```

### 7.2 Ring Constraints (INV66)

```
∀ ring r:
  r.threshold >= 2 ∧
  r.totalDevices >= 3 ∧
  r.threshold <= r.totalDevices ∧
  r.totalDevices <= 255 ∧
  count(r.devices) = r.totalDevices ∧
  ∀ d ∈ r.devices: d.state ≠ Revoked
```

### 7.3 Minimum Configuration

| Configuration | Threshold | Total | Security Level |
|---------------|-----------|-------|----------------|
| Minimum | 2 | 3 | Basic (1 device can be lost) |
| Recommended | 3 | 5 | Standard (2 devices can be lost) |
| High Security | 4 | 7 | Enhanced (3 devices can be lost) |
| Maximum | 5 | 9 | Maximum (4 devices can be lost) |

---

## 8. Security Considerations

### 8.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Device spoofing | Cryptographic identity derivation (INV64) |
| Replay attacks | Epoch binding, nonce in attestations |
| Owner impersonation | Signature verification on all operations |
| Share extraction | ECIES encryption to device public key |
| Rogue device injection | Owner signature required for registration |

### 8.2 Key Security Properties

1. **Device Identity Non-Transferability**: DeviceId bound to owner address
2. **Presence Enforcement**: Operations require real-time presence
3. **Owner Authority**: Owner can always revoke any device
4. **Threshold Guarantee**: Vault inaccessible without k devices

### 8.3 Recommendations

- Use Hardware device type for at least one device
- Distribute devices across physical locations
- Enable recovery attestations for high-value vaults
- Regular device rotation (revoke old, add new)

---

## 9. Error Codes

| Code | Name | Description | Related Invariant |
|------|------|-------------|-------------------|
| STOR_001 | DeviceNotRegistered | Device ID not found in registry | - |
| STOR_002 | DeviceAlreadyRegistered | Device index already used by owner | - |
| STOR_003 | DeviceNotPresent | Device lacks presence in current epoch | INV65 |
| STOR_004 | DeviceRevoked | Device permanently revoked | - |
| STOR_005 | DeviceLost | Device marked as lost | - |
| STOR_009 | InsufficientDevices | Not enough devices for threshold | INV66 |
| STOR_020 | UnauthorizedDevice | Device not in vault's ring | INV65 |

---

## 10. Invariants

### INV64: Device Identity Derivation

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

### INV65: Device Presence Binding

A device MUST have valid presence to participate in vault operations.

```
∀ device d, operation o:
  o.requiresPresence = true →
    presenceState(d.owner, currentEpoch) ∈ {Declared, Validated, Finalized} ∧
    d.state = DeviceState.Present ∧
    d.currentEpochId = currentEpoch
```

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.7.1 | Initial device layer specification |

---

## 12. References

- [ephemeral.md](../governance/ephemeral.md) — Key management patterns
- [octopus.md](octopus.md) — VRF identity derivation
- [presence.md](../core/presence.md) — Presence state machine
- [message-catalog.md](../semantic/message-catalog.md) — Message envelope

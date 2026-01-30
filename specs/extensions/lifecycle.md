# 7ay Proof of Presence (PoP)
## Protocol Specification — Vault Lifecycle Management
**Version:** v0.7.5
**Status:** Draft
**Scope:** Extension (lifecycle layer)
**Depends on:** vaults.md v0.7.2, crypto.md v0.7.3, storage.md v0.7.4, devices.md v0.7.1

---

## 1. Purpose

This specification defines the **Vault Lifecycle Management** for the 7ay Presence Protocol.

The lifecycle layer manages:
- Automatic lock/unlock based on device presence
- Epoch transition handling with key rotation
- Device recovery procedures
- Emergency operations

This version does **NOT** define:
- Storage backend implementation
- Network transport
- Client UI/UX

---

## 2. Lifecycle Overview

### 2.1 Vault Lifecycle States

```
                    VAULT_CREATE
                         │
                         ▼
    ┌─────────────── [Locked] ◄─────────────────┐
    │                    │                       │
    │          threshold devices present         │
    │                    │                       │
    │                    ▼                       │
    │              [Unlocked] ──────────────────┐│
    │                    │                      ││
    │    ┌───────────────┼───────────────┐     ││
    │    │               │               │     ││
    │    ▼               ▼               ▼     ││
    │  device     epoch closes    owner lock   ││
    │  leaves                                  ││
    │    │               │               │     ││
    │    ▼               ▼               ▼     ││
    │ < threshold?   [Migrating]   [Suspended] ││
    │    │               │               │     ││
    │    │ YES           │               │     ││
    └────┴───────────────┘               │     ││
                                         │     ││
                         owner unlock ───┘     ││
                              │                ││
                              └────────────────┘│
                                                │
                    [Recovering] ───────────────┘
                         ▲
                         │
                   device recovery
```

### 2.2 State Definitions

See [vaults.md](vaults.md#41-state-enum) for the canonical VaultAccessState definition:
- **Locked**: < threshold devices present, key not reconstructed
- **Unlocked**: >= threshold devices present, key available
- **Suspended**: Owner-initiated emergency lock
- **Recovering**: Device recovery in progress
- **Migrating**: Key rotation during epoch transition

For device states, see [devices.md](devices.md#23-device-states).

---

## 3. Auto-Lock Mechanism

### 3.1 Device Departure Detection

When a device leaves the epoch (via DEVICE_LEAVE or timeout), the system checks:

```typescript
function onDeviceLeave(deviceId: bytes32, vaultId: bytes32): void {
  const vault = getVault(vaultId);
  const presentCount = countPresentDevices(vault.deviceRing);

  if (presentCount < vault.deviceRing.threshold) {
    autoLock(vault);
  }
}
```

### 3.2 Auto-Lock Procedure

```typescript
function autoLock(vault: Vault): void {
  // 1. Change state
  vault.accessState = VaultAccessState.Locked;
  vault.lastLockedAt = block.timestamp;

  // 2. Secure key destruction (INV68)
  secureZero(vault.reconstructedKey);
  vault.reconstructedKey = null;

  // 3. Clear any pending operations
  cancelPendingOperations(vault.vaultId);

  // 4. Emit event
  emit VaultAutoLocked({
    vaultId: vault.vaultId,
    reason: LockReason.ThresholdNotMet,
    presentDevices: countPresentDevices(vault.deviceRing),
    threshold: vault.deviceRing.threshold,
    timestamp: block.timestamp
  });
}
```

### 3.3 Lock Triggers

| Trigger | Condition | Behavior |
|---------|-----------|----------|
| Device Leave | `presentDevices < threshold` | Auto-lock immediately |
| Device Timeout | No heartbeat for `deviceTimeout` | Mark absent, check threshold |
| Epoch Close | Epoch transitions to Closed | Lock if `autoLockOnEpochClose` |
| Owner Request | VAULT_LOCK message | Immediate lock (Suspended state) |
| Policy Violation | Security rule violated | Immediate lock (Suspended state) |

### 3.4 Timeout Configuration

```typescript
interface TimeoutConfig {
  deviceHeartbeatInterval: uint256;   // Expected heartbeat (default: 60s)
  deviceTimeoutThreshold: uint256;    // Mark absent after (default: 180s)
  unlockSessionTimeout: uint256;      // Auto-lock after inactivity (default: 3600s)
  shareRequestTimeout: uint256;       // Share collection window (default: 30s)
}
```

---

## 4. Unlock Flow

### 4.1 Unlock Sequence Diagram

```
Device A          Device B          Device C          Vault
    │                 │                 │               │
    │─── VAULT_UNLOCK ─────────────────────────────────►│
    │                 │                 │               │
    │◄── SHARE_REQUEST (broadcast) ────────────────────│
    │                 │◄────────────────────────────────│
    │                 │                 │◄──────────────│
    │                 │                 │               │
    │─── SHARE_PROVIDE ────────────────────────────────►│
    │                 │─── SHARE_PROVIDE ──────────────►│
    │                 │                 │─── SHARE_PROVIDE ─►│
    │                 │                 │               │
    │                 │                 │    [Reconstruct Key]
    │                 │                 │               │
    │◄── VAULT_UNLOCKED ───────────────────────────────│
    │                 │◄────────────────────────────────│
    │                 │                 │◄──────────────│
```

### 4.2 Unlock Protocol

```typescript
interface UnlockSession {
  sessionId: bytes32;           // Random session identifier
  vaultId: bytes32;
  initiator: bytes32;           // Device that initiated unlock
  startedAt: uint256;
  expiresAt: uint256;

  // Share collection
  requestedDevices: bytes32[];  // Devices that received SHARE_REQUEST
  receivedShares: ShareResponse[];

  // Status
  status: UnlockStatus;
}

enum UnlockStatus {
  Pending = 0,      // Waiting for shares
  Collecting = 1,   // Actively collecting shares
  Reconstructing = 2, // Threshold met, reconstructing
  Complete = 3,     // Key reconstructed, vault unlocked
  Failed = 4,       // Timeout or error
  Cancelled = 5     // Manually cancelled
}
```

### 4.3 Share Collection

```typescript
function collectShares(session: UnlockSession): void {
  // Wait for threshold shares
  while (session.receivedShares.length < vault.threshold) {
    if (block.timestamp > session.expiresAt) {
      session.status = UnlockStatus.Failed;
      emit UnlockFailed({
        sessionId: session.sessionId,
        reason: "Timeout",
        receivedShares: session.receivedShares.length,
        requiredShares: vault.threshold
      });
      return;
    }

    // Process incoming SHARE_PROVIDE messages
    await receiveShare();
  }

  // Reconstruct key
  session.status = UnlockStatus.Reconstructing;
  reconstructKey(session);
}
```

### 4.4 Key Reconstruction

```typescript
function reconstructKey(session: UnlockSession): void {
  // Extract share values
  const shares: ShamirShare[] = session.receivedShares.map(r => ({
    index: r.shareIndex,
    value: decrypt(r.encryptedShare, session.ephemeralPrivateKey)
  }));

  // Lagrange interpolation (from crypto.md)
  const vaultKey = shamirReconstruct(shares);

  // Verify against commitment
  if (!verifyKeyCommitment(vaultKey, vault.keyCommitment)) {
    session.status = UnlockStatus.Failed;
    emit UnlockFailed({ reason: "KeyVerificationFailed" });
    return;
  }

  // Store securely (INV68: will be zeroed on lock)
  vault.reconstructedKey = vaultKey;
  vault.accessState = VaultAccessState.Unlocked;
  vault.lastUnlockedAt = block.timestamp;

  session.status = UnlockStatus.Complete;
  emit VaultUnlocked({
    vaultId: vault.vaultId,
    unlockedBy: session.initiator,
    presentDevices: countPresentDevices(vault.deviceRing)
  });
}
```

---

## 5. Epoch Transition

### 5.1 Transition Behavior

When an epoch closes, vaults have two options based on policy:

| Policy Setting | Behavior |
|----------------|----------|
| `autoLockOnEpochClose: true` | Lock vault, require re-unlock in new epoch |
| `autoLockOnEpochClose: false` | Keep unlocked if threshold met in new epoch |
| `keyRotationOnEpochChange: true` | Rotate vault key, re-encrypt all items |
| `persistDataAcrossEpochs: true` | Data survives (default for storage vaults) |

### 5.2 Key Rotation Flow

```
Epoch N (closing)              Epoch N+1 (active)
      │                              │
      ▼                              │
[Vault Unlocked]                     │
      │                              │
      │── Generate new vaultKey ────►│
      │                              │
      ▼                              │
[Migrating State]                    │
      │                              │
      │── Re-encrypt all items ─────►│
      │── Distribute new shares ────►│
      │                              │
      ▼                              ▼
[Lock old key]              [New key active]
      │                              │
      └──────────────────────────────┘
```

### 5.3 Key Rotation Protocol

```typescript
interface KeyRotation {
  vaultId: bytes32;
  oldKeyVersion: uint256;
  newKeyVersion: uint256;

  // Progress tracking
  totalItems: uint256;
  reencryptedItems: uint256;

  // New key material
  newKeyCommitment: bytes32;
  newShareCommitments: bytes32[];

  status: RotationStatus;
}

enum RotationStatus {
  Pending = 0,
  ReencryptingItems = 1,
  DistributingShares = 2,
  Complete = 3,
  Failed = 4
}
```

### 5.4 Re-encryption Process

```typescript
function rotateKey(vault: Vault, newEpochId: uint256): void {
  // 1. Generate new vault key
  const newVaultKey = hkdf_sha256(
    vault.ownerMasterSecret,
    keccak256(vault.vaultId, getEpochRandomness(newEpochId)),
    "7ay-vault-key-v1"
  );

  // 2. Create rotation session
  const rotation: KeyRotation = {
    vaultId: vault.vaultId,
    oldKeyVersion: vault.vaultKeyVersion,
    newKeyVersion: vault.vaultKeyVersion + 1,
    totalItems: vault.itemCount,
    reencryptedItems: 0,
    newKeyCommitment: pedersenCommit(newVaultKey),
    status: RotationStatus.ReencryptingItems
  };

  // 3. Set vault to migrating state
  vault.accessState = VaultAccessState.Migrating;

  // 4. Re-encrypt items (can be batched/lazy)
  for (const item of getVaultItems(vault.vaultId)) {
    reencryptItem(item, vault.reconstructedKey, newVaultKey);
    rotation.reencryptedItems++;
  }

  // 5. Distribute new shares
  rotation.status = RotationStatus.DistributingShares;
  const newShares = shamirSplit(newVaultKey, vault.threshold, vault.totalDevices);
  distributeShares(vault, newShares);

  // 6. Finalize rotation
  vault.vaultKeyVersion = rotation.newKeyVersion;
  vault.keyCommitment = rotation.newKeyCommitment;
  vault.keyRotatedAt = block.timestamp;
  secureZero(vault.reconstructedKey);
  vault.accessState = VaultAccessState.Locked;

  rotation.status = RotationStatus.Complete;
  emit KeyRotationComplete({
    vaultId: vault.vaultId,
    newKeyVersion: rotation.newKeyVersion,
    itemsReencrypted: rotation.reencryptedItems
  });
}
```

### 5.5 Lazy Re-encryption Option

For vaults with many items, re-encryption can be lazy:

```typescript
interface LazyReencryption {
  enabled: bool;
  batchSize: uint256;          // Items per batch (default: 100)
  maxConcurrentBatches: uint256; // Parallel batches (default: 4)
}

// Items marked for re-encryption
interface PendingReencryption {
  itemId: bytes32;
  oldKeyVersion: uint256;
  targetKeyVersion: uint256;
  priority: uint8;             // Higher = sooner
}
```

With lazy re-encryption:
1. New key distributed immediately
2. Items re-encrypted on-demand when accessed
3. Background process re-encrypts remaining items
4. `item.state = PendingReencryption` until complete

---

## 6. Device Recovery

### 6.1 Recovery Scenarios

| Scenario | Trigger | Resolution |
|----------|---------|------------|
| Device Lost | Owner marks device lost | Recovery protocol |
| Device Compromised | Security breach detected | Immediate revoke + recovery |
| Device Replaced | User gets new device | Register new, revoke old |
| Multi-Device Failure | Multiple devices unavailable | Threshold-based recovery |

### 6.2 Recovery Protocol (DEVICE_RECOVER)

```typescript
interface DeviceRecoverySession {
  sessionId: bytes32;
  targetDeviceId: bytes32;      // Device being recovered
  newDeviceId: bytes32;         // Replacement device
  vaultId: bytes32;

  // Authorization
  ownerSignature: bytes;

  // Device attestations (optional extra security)
  requiredAttestations: uint8;   // How many other devices must approve
  receivedAttestations: DeviceRecoveryAttestation[];

  // Progress
  status: RecoveryStatus;
  startedAt: uint256;
  completedAt?: uint256;
}

enum RecoveryStatus {
  Initiated = 0,
  AwaitingAttestations = 1,
  SharesRedistributing = 2,
  Complete = 3,
  Failed = 4,
  Cancelled = 5
}
```

### 6.3 Recovery Flow

```
Owner              Old Device       New Device       Other Devices
  │                    │                │                 │
  │── DEVICE_RECOVER ──┼────────────────┼─────────────────┼──►
  │   (mark old lost)  │                │                 │
  │                    │                │                 │
  │── DEVICE_REGISTER ─┼────────────────┼──►              │
  │   (new device)     │                │                 │
  │                    │                │                 │
  │                    │                │◄── ATTESTATION ─│
  │                    │                │    (optional)   │
  │                    │                │                 │
  │── SHARE_DISTRIBUTE ┼────────────────┼─────────────────┼──►
  │   (new shares)     │                │                 │
  │                    │                │                 │
  │                    ╳ (revoked)      │                 │
  │                                     │                 │
  │◄─────── RECOVERY_COMPLETE ──────────┼─────────────────│
```

### 6.4 Recovery Implementation

```typescript
function recoverDevice(
  targetDeviceId: bytes32,
  newDevice: DeviceRegistration,
  ownerSignature: bytes
): void {
  // 1. Verify owner authorization
  require(verifyOwnerSignature(ownerSignature, targetDeviceId, newDevice));

  // 2. Mark old device as lost/revoked
  const oldDevice = getDevice(targetDeviceId);
  oldDevice.state = DeviceState.Lost;

  // 3. Register new device
  const newDeviceId = registerDevice(newDevice);

  // 4. Get vault(s) affected
  const vaults = getVaultsForDevice(targetDeviceId);

  for (const vault of vaults) {
    // 5. Set vault to recovering state
    vault.accessState = VaultAccessState.Recovering;

    // 6. Update device ring
    removeFromRing(vault.deviceRing, targetDeviceId);
    addToRing(vault.deviceRing, newDeviceId);

    // 7. Redistribute shares (requires vault to be unlocked first)
    if (canUnlockWithRemainingDevices(vault)) {
      // Unlock with remaining devices
      const unlockSession = initiateUnlock(vault);
      await waitForUnlock(unlockSession);

      // Generate new shares with new device in ring
      const newShares = shamirSplit(
        vault.reconstructedKey,
        vault.threshold,
        vault.totalDevices
      );

      distributeShares(vault, newShares);
    } else {
      // Cannot recover automatically - need manual intervention
      emit RecoveryRequiresManualIntervention({
        vaultId: vault.vaultId,
        reason: "InsufficientDevicesForUnlock"
      });
    }

    // 8. Return to locked state
    vault.accessState = VaultAccessState.Locked;
  }

  emit DeviceRecoveryComplete({
    oldDeviceId: targetDeviceId,
    newDeviceId: newDeviceId,
    vaultsUpdated: vaults.length
  });
}
```

### 6.5 Recovery Constraints

```
∀ recovery r:
  // Owner must authorize
  verifySignature(r.ownerSignature, r.owner) ∧

  // Cannot recover already revoked device
  device(r.targetDeviceId).state ≠ Revoked ∧

  // New device must be fresh
  device(r.newDeviceId).state = None ∧

  // Threshold still satisfiable after recovery
  vault.deviceRing.totalDevices - 1 >= vault.deviceRing.threshold
```

---

## 7. Emergency Operations

### 7.1 Emergency Lock (VAULT_LOCK)

Owner or any ring device can trigger emergency lock:

```typescript
function emergencyLock(
  vaultId: bytes32,
  reason: LockReason,
  signature: bytes
): void {
  const vault = getVault(vaultId);

  // Verify authorization (owner or ring device)
  require(
    verifyOwnerSignature(signature, vaultId) ||
    verifyDeviceSignature(signature, vaultId)
  );

  // Immediate lock
  vault.accessState = VaultAccessState.Suspended;
  vault.suspendedAt = block.timestamp;
  vault.suspendReason = reason;

  // Secure key destruction
  secureZero(vault.reconstructedKey);

  emit VaultEmergencyLocked({
    vaultId: vaultId,
    reason: reason,
    lockedBy: recoverSigner(signature)
  });
}
```

### 7.2 Emergency Unlock

Unlocking a suspended vault requires owner signature:

```typescript
function emergencyUnlock(
  vaultId: bytes32,
  ownerSignature: bytes
): void {
  const vault = getVault(vaultId);

  require(vault.accessState == VaultAccessState.Suspended);
  require(verifyOwnerSignature(ownerSignature, vaultId));

  // Return to locked state (requires normal unlock flow)
  vault.accessState = VaultAccessState.Locked;
  vault.suspendedAt = null;
  vault.suspendReason = null;

  emit VaultSuspensionLifted({
    vaultId: vaultId
  });
}
```

### 7.3 Vault Destruction

Permanent vault deletion (irreversible):

```typescript
interface VaultDestructionRequest {
  vaultId: bytes32;
  ownerSignature: bytes;
  confirmationPhrase: bytes32;  // keccak256("DESTROY VAULT " + vaultId)

  // Optional: require device attestations
  deviceAttestations?: bytes[];
}

function destroyVault(request: VaultDestructionRequest): void {
  const vault = getVault(request.vaultId);

  // Verify owner
  require(verifyOwnerSignature(request.ownerSignature, request.vaultId));

  // Verify confirmation phrase
  require(request.confirmationPhrase == keccak256("DESTROY VAULT " + request.vaultId));

  // Optional: require k-of-n device confirmations
  if (vault.policy.requireDeviceConfirmationForDestruction) {
    require(request.deviceAttestations.length >= vault.threshold);
    for (const attestation of request.deviceAttestations) {
      require(verifyDeviceAttestation(attestation, "DESTROY", request.vaultId));
    }
  }

  // Secure destruction
  secureZero(vault.reconstructedKey);
  for (const item of getVaultItems(request.vaultId)) {
    secureZero(item.encryptedContent);
    deleteItem(item.itemId);
  }

  // Remove vault
  deleteVault(request.vaultId);

  emit VaultDestroyed({
    vaultId: request.vaultId,
    destroyedAt: block.timestamp
  });
}
```

---

## 8. Invariants

### 8.1 Lifecycle Invariants

**INV76: Auto-Lock on Threshold Loss**
```
∀ vault v, device d:
  d ∈ v.deviceRing ∧ d.state transitions from Present to Absent →
    let presentCount = count(d' ∈ v.deviceRing where d'.state = Present)
    presentCount < v.threshold → v.accessState = Locked within 1 block
```

**INV77: Key Destruction on Lock**
```
∀ vault v:
  v.accessState transitions to Locked|Suspended →
    v.reconstructedKey = null ∧
    secureZero(previousKeyMemory)
```

**INV78: Epoch Transition Key Rotation**
```
∀ vault v with policy.keyRotationOnEpochChange = true:
  epochTransition(oldEpoch, newEpoch) →
    v.vaultKeyVersion(newEpoch) > v.vaultKeyVersion(oldEpoch) ∧
    ∀ item i ∈ v: i.keyVersion = v.vaultKeyVersion(newEpoch) eventually
```

### 8.2 Enforcement

| Invariant | Enforcement Point | Failure Mode |
|-----------|-------------------|--------------|
| INV76 | Device leave handler | Immediate lock |
| INV77 | Lock state transition | Key zeroed |
| INV78 | Epoch close handler | Migration state |

---

## 9. Events

```typescript
// Lock events
event VaultAutoLocked {
  vaultId: bytes32;
  reason: LockReason;
  presentDevices: uint8;
  threshold: uint8;
  timestamp: uint256;
}

event VaultEmergencyLocked {
  vaultId: bytes32;
  reason: LockReason;
  lockedBy: Address;
}

event VaultSuspensionLifted {
  vaultId: bytes32;
}

// Unlock events
event VaultUnlocked {
  vaultId: bytes32;
  unlockedBy: bytes32;  // deviceId
  presentDevices: uint8;
}

event UnlockFailed {
  sessionId: bytes32;
  reason: string;
  receivedShares: uint8;
  requiredShares: uint8;
}

// Key rotation events
event KeyRotationStarted {
  vaultId: bytes32;
  oldKeyVersion: uint256;
  newKeyVersion: uint256;
  totalItems: uint256;
}

event KeyRotationComplete {
  vaultId: bytes32;
  newKeyVersion: uint256;
  itemsReencrypted: uint256;
}

// Recovery events
event DeviceRecoveryInitiated {
  oldDeviceId: bytes32;
  newDeviceId: bytes32;
  owner: Address;
}

event DeviceRecoveryComplete {
  oldDeviceId: bytes32;
  newDeviceId: bytes32;
  vaultsUpdated: uint256;
}

event RecoveryRequiresManualIntervention {
  vaultId: bytes32;
  reason: string;
}

// Destruction events
event VaultDestroyed {
  vaultId: bytes32;
  destroyedAt: uint256;
}
```

---

## 10. Security Considerations

### 10.1 Timing Attacks

| Attack | Mitigation |
|--------|------------|
| Device departure timing | Immediate threshold check |
| Unlock race condition | Session-based locking |
| Key rotation window | Migrating state blocks operations |

### 10.2 Key Material Security

- Reconstructed keys held in secure memory
- `secureZero()` called on all key material before release
- Keys never written to persistent storage
- Share responses encrypted to ephemeral keys

### 10.3 Recovery Security

- Owner signature required for all recovery
- Optional device attestation adds defense-in-depth
- Lost device shares become useless (new shares distributed)
- Revoked devices cannot participate in future unlocks

---

## 11. References

- vaults.md v0.7.2 — Vault structure and device rings
- crypto.md v0.7.3 — Shamir sharing, key reconstruction
- storage.md v0.7.4 — Storage operations
- devices.md v0.7.1 — Device management
- invariants.md v0.7.5 — Protocol invariants INV76-78

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.7.5 | Initial lifecycle management specification |

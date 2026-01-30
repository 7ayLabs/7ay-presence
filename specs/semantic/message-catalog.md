# 7ay Proof of Presence (PoP)
## Protocol Specification — Message Catalog
**Version:** v0.7.5
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** node-model.md v0.6.2, state-sync.md v0.6.1, invariants.md v0.7.5

---

## 1. Purpose

This specification defines the **Message Catalog** for the 7ay Presence Protocol's
semantic layer.

Messages are the vocabulary for off-chain node coordination. This catalog defines
all message types, their structure, validation rules, and usage.

This specification defines:
- Message envelope structure
- Message type catalog
- Validation rules per message type
- Signature and replay protection

This version does **NOT** define:
- Transport layer (TCP, UDP, WebSocket)
- Encoding format (implementation choice)
- Network topology
- Delivery guarantees

### 1.1 Architecture (7aychain)

| Component | Layer | Description |
|-----------|-------|-------------|
| Message Exchange | **Off-chain (P2P)** | Messages sent between nodes via P2P network |
| Chain Binding (INV43) | **On-chain** | `chain_id` verified against `pallet-messaging` |
| Nonce Tracking (INV25) | **On-chain** | Nonce uniqueness enforced in `pallet-messaging` |
| Signature Verification | **Off-chain** | Verified by receiving node against sender's public key |
| Epoch Reference | **On-chain** | `epochId` validated against `pallet-epochs` |
| Sender Presence | **On-chain** | Sender's presence validated against `pallet-presence` |

---

## 2. Message Envelope

### 2.1 Envelope Structure

All messages share a common envelope:

```typescript
interface MessageEnvelope {
  // Protocol version
  version: "0.6.9";

  // Message classification
  type: MessageType;

  // Sender identification
  sender: NodeIdentity;

  // Epoch context
  epochId: uint256;

  // Temporal data
  timestamp: uint256;        // Unix timestamp (seconds)

  // Replay protection
  nonce: bytes32;            // Random 32-byte nonce
  chain_id: uint64;          // Chain identifier (prevents cross-chain replay)
  block_bound: uint64;       // Message expiration block number

  // Cryptographic signature
  signature: bytes;          // ECDSA signature (65 bytes)

  // Message-specific data
  payload: MessagePayload;
}
```

### 2.2 Chain Binding (INV43)

Messages are bound to a specific chain and block range:

- `chain_id` MUST match the current chain identifier
- `block_bound` specifies the maximum block number for message validity
- Messages with `current_block > block_bound` MUST be rejected
- Recommended `block_bound` = `current_block + 100` (~20 minutes on most chains)

```
∀ msg:
  msg.chain_id == currentChainId ∧
  currentBlock <= msg.block_bound
```

### 2.3 Message Type Enum

```typescript
enum MessageType {
  // Discovery (0x01-0x0F)
  NODE_ANNOUNCE = 0x01,
  NODE_QUERY = 0x02,
  NODE_RESPONSE = 0x03,
  NODE_LEAVE = 0x04,

  // State Sync (0x10-0x1F)
  STATE_SYNC_REQUEST = 0x10,
  STATE_SYNC_RESPONSE = 0x11,
  STATE_VECTOR_CLOCK = 0x12,
  STATE_DIFF = 0x13,

  // Attestation (0x20-0x2F)
  PRESENCE_ATTESTATION = 0x20,
  VALIDATION_VOTE = 0x21,
  DISPUTE_NOTICE = 0x22,

  // Media (0x30-0x3F) — v0.6.4
  MEDIA_ANNOUNCE = 0x30,
  MEDIA_REQUEST = 0x31,
  MEDIA_RESPONSE = 0x32,
  MEDIA_REVOKE = 0x33,

  // Boomerang (0x40-0x4F) — v0.6.5
  BOOMERANG_SEND = 0x40,
  BOOMERANG_ACK = 0x41,
  BOOMERANG_RETURN = 0x42,
  BOOMERANG_COMPLETE = 0x43,

  // Autonomous (0x50-0x5F) — v0.6.6
  AUTONOMOUS_INTENT = 0x50,
  AUTONOMOUS_PATTERN = 0x51,
  AUTONOMOUS_EXECUTE = 0x52,
  AUTONOMOUS_FINALIZE = 0x53,
  AUTONOMOUS_REVOKE = 0x54,

  // Octopus (0x60-0x6F) — v0.6.7
  OCTOPUS_THRESHOLD = 0x60,
  OCTOPUS_DIVIDE = 0x61,
  OCTOPUS_SUBNODE = 0x62,
  OCTOPUS_COORDINATE = 0x63,
  OCTOPUS_MERGE = 0x64,
  OCTOPUS_STATE_SHARE = 0x65,

  // Device (0x70-0x7F) — v0.7.1
  DEVICE_REGISTER = 0x70,
  DEVICE_ENTER_EPOCH = 0x71,
  DEVICE_LEAVE = 0x72,
  DEVICE_REVOKE = 0x73,
  DEVICE_RECOVER = 0x74,
  VAULT_CREATE = 0x75,
  VAULT_CONFIGURE = 0x76,
  VAULT_UNLOCK = 0x77,
  VAULT_LOCK = 0x78,
  STORAGE_PUT = 0x79,
  STORAGE_GET = 0x7A,
  STORAGE_DELETE = 0x7B,
  STORAGE_LIST = 0x7C,
  SHARE_DISTRIBUTE = 0x7D,
  SHARE_REQUEST = 0x7E,
  SHARE_PROVIDE = 0x7F
}
```

### 2.4 Signature Scheme

All messages MUST be signed by the sender:

```
signaturePayload = keccak256(
  abi.encodePacked(
    version,           // "0.6.9"
    type,              // uint8
    sender.address,    // address
    epochId,           // uint256
    timestamp,         // uint256
    nonce,             // bytes32
    chain_id,          // uint64 (NEW: chain binding)
    block_bound,       // uint64 (NEW: expiration)
    keccak256(payload) // bytes32
  )
)

signature = ecdsaSign(signaturePayload, senderPrivateKey)
```

### 2.5 Signature Verification

```
function verifySignature(message: MessageEnvelope) → bool:
  // 1. Verify chain binding (INV43)
  if message.chain_id != currentChainId:
    return false

  // 2. Verify block bound (INV43)
  if currentBlock > message.block_bound:
    return false

  // 3. Verify signature
  signaturePayload = keccak256(abi.encodePacked(
    message.version,
    message.type,
    message.sender.address,
    message.epochId,
    message.timestamp,
    message.nonce,
    message.chain_id,
    message.block_bound,
    keccak256(message.payload)
  ))

  recoveredAddress = ecrecover(signaturePayload, message.signature)
  return recoveredAddress == message.sender.address
```

---

## 3. Discovery Messages

### 3.1 NODE_ANNOUNCE (0x01)

Broadcast node availability to the network.

```typescript
interface NodeAnnouncePayload {
  // Full node information
  node: Node;

  // Discovery endpoints (optional)
  endpoints?: string[];

  // Time-to-live in seconds
  ttl: uint256;
}
```

**Validation Rules:**
- `node.identity.address` MUST equal `sender.address`
- `node.epoch.epochId` MUST equal `epochId`
- `ttl` SHOULD be <= 3600 (1 hour)
- Epoch MUST be Active

**Usage:**
- Sent when a node joins an epoch
- Periodically re-announced before TTL expires
- Broadcast to discovery peers

### 3.2 NODE_QUERY (0x02)

Request nodes matching criteria.

```typescript
interface NodeQueryPayload {
  // Filter criteria
  filter: {
    role?: NodeRole;              // Filter by role
    capabilities?: NodeCapability[]; // Filter by capabilities
    limit?: uint256;              // Max results
  };

  // Pagination
  offset?: uint256;
}
```

**Validation Rules:**
- `limit` SHOULD be <= 100
- Sender MUST have valid presence in epoch

**Usage:**
- Request validator nodes for sync
- Discover peers in epoch
- Directed to known discovery peers

### 3.3 NODE_RESPONSE (0x03)

Response to NODE_QUERY.

```typescript
interface NodeResponsePayload {
  // Query echo (for correlation)
  queryNonce: bytes32;

  // Matching nodes
  nodes: MinimalNode[];

  // Pagination info
  total: uint256;
  hasMore: bool;
}
```

**Validation Rules:**
- `queryNonce` MUST match a pending query
- All nodes MUST have valid presence in the queried epoch
- `nodes.length` MUST be <= query limit

**Usage:**
- Response to NODE_QUERY
- Contains discovered peer information

### 3.4 NODE_LEAVE (0x04)

Announce node departure from epoch.

```typescript
interface NodeLeavePayload {
  // Reason for leaving
  reason: LeaveReason;
}

enum LeaveReason {
  VOLUNTARY = 0,      // Explicit exit
  EPOCH_CLOSING = 1,  // Epoch transitioning to Closed
  SLASHED = 2         // Actor was slashed
}
```

**Validation Rules:**
- Sender MUST have had valid presence
- Broadcast once per departure

**Usage:**
- Clean exit from epoch
- Allows peers to update node lists

---

## 4. State Sync Messages

### 4.1 STATE_SYNC_REQUEST (0x10)

Request state synchronization with a peer.

```typescript
interface StateSyncRequestPayload {
  // Sync mode
  mode: SyncMode;

  // For partial sync: starting point
  fromVector?: StateVector;

  // Requested state types
  include: StateType[];
}

enum SyncMode {
  COMPLETE = 0,   // Full state transfer
  PARTIAL = 1     // Incremental from vector
}

enum StateType {
  PRESENCES = 0,
  VALIDATIONS = 1,
  DISPUTES = 2
}
```

**Validation Rules:**
- Sender MUST be a validator (for StateSync capability)
- `fromVector` required if `mode == PARTIAL`
- Epoch MUST be Active or Closed

**Usage:**
- Validator-to-validator sync
- New validator joining epoch

### 4.2 STATE_SYNC_RESPONSE (0x11)

Response to STATE_SYNC_REQUEST.

```typescript
interface StateSyncResponsePayload {
  // Request correlation
  requestNonce: bytes32;

  // Current state vector
  currentVector: StateVector;

  // State data (based on mode)
  state?: EpochState;     // For COMPLETE mode
  diff?: StateDiff;       // For PARTIAL mode

  // Continuation
  hasMore: bool;
  continuationToken?: bytes32;
}

interface EpochState {
  epochId: uint256;
  presences: PresenceRecord[];
  validations: ValidationRecord[];
  disputes: DisputeRecord[];
}
```

**Validation Rules:**
- `requestNonce` MUST match pending request
- State data MUST be verifiable against on-chain
- Sender MUST be a validator

**Usage:**
- Complete or partial state transfer
- May require multiple responses for large states

### 4.3 STATE_VECTOR_CLOCK (0x12)

Exchange vector clock for consistency check.

```typescript
interface StateVectorClockPayload {
  // Current vector clock
  vectorClock: VectorClock;

  // State root for quick comparison
  stateRoot: bytes32;
}

interface VectorClock {
  epochId: uint256;
  entries: Map<Address, uint256>;  // node → logical timestamp
}
```

**Validation Rules:**
- Sender MUST be a validator
- `epochId` MUST match message `epochId`

**Usage:**
- Quick consistency check
- Determine sync necessity
- Detect divergence

### 4.4 STATE_DIFF (0x13)

Push incremental state update.

```typescript
interface StateDiffPayload {
  // Vector clock context
  fromVector: StateVector;
  toVector: StateVector;

  // Changes
  changes: StateChange[];
}

interface StateChange {
  type: StateChangeType;
  actor: Address;
  data: bytes;
}

enum StateChangeType {
  PRESENCE_DECLARED = 0,
  PRESENCE_VALIDATED = 1,
  PRESENCE_FINALIZED = 2,
  DISPUTE_INITIATED = 3,
  DISPUTE_VOTED = 4,
  DISPUTE_RESOLVED = 5
}
```

**Validation Rules:**
- Sender MUST be a validator
- Changes MUST be verifiable against on-chain
- `fromVector` MUST match recipient's current vector

**Usage:**
- Proactive state push
- Real-time sync updates

---

## 5. Attestation Messages

### 5.1 PRESENCE_ATTESTATION (0x20)

Validator attests to presence observation.

```typescript
interface PresenceAttestationPayload {
  // Attested presence
  actor: Address;

  // Observation details
  observedAt: uint256;
  evidenceHash: bytes32;  // Optional evidence reference
}
```

**Validation Rules:**
- Sender MUST be a validator
- `actor` MUST have presence in epoch
- `observedAt` MUST be within epoch bounds

**Usage:**
- Pre-vote attestation
- Evidence sharing

### 5.2 VALIDATION_VOTE (0x21)

Broadcast validation vote intent.

```typescript
interface ValidationVotePayload {
  // Target presence
  actor: Address;

  // Vote intent
  vote: bool;  // true = validate, false = abstain

  // Optional rationale
  rationaleHash?: bytes32;
}
```

**Validation Rules:**
- Sender MUST be a validator
- Sender MUST NOT have voted on-chain for this presence
- `actor` MUST be in Declared state

**Usage:**
- Off-chain vote coordination
- Intent signaling before on-chain tx

### 5.3 DISPUTE_NOTICE (0x22)

Broadcast dispute initiation or update.

```typescript
interface DisputeNoticePayload {
  // Disputed presence
  actor: Address;

  // Dispute details
  action: DisputeAction;
  evidenceHash: bytes32;
}

enum DisputeAction {
  INITIATED = 0,
  VOTE_CAST = 1,
  RESOLVED = 2
}
```

**Validation Rules:**
- Sender MUST be a validator (for VOTE_CAST)
- `actor` MUST have presence in epoch
- Dispute MUST exist on-chain (for updates)

**Usage:**
- Dispute coordination
- Evidence sharing
- Resolution notification

---

## 6. Device Messages (v0.7.1)

Device messages enable trusted device management for presence-based storage.
See `devices.md` for complete device specification.

### 6.1 DEVICE_REGISTER (0x70)

Register a new trusted device.

```typescript
interface DeviceRegisterPayload {
  deviceIndex: uint8;           // Unique index for this owner (0-254)
  deviceType: DeviceType;
  deviceName: string;           // Max 32 UTF-8 characters
  publicKey: bytes;             // secp256k1 compressed public key (33 bytes)
  ownerSignature: bytes;        // Owner signs: hash(deviceIndex, publicKey, epochId)
  deviceSignature: bytes;       // Device signs: hash(owner, publicKey)
  shareIndex: uint8;            // 1-based Shamir share index
}

enum DeviceType {
  Mobile = 0,
  Desktop = 1,
  Tablet = 2,
  Wearable = 3,
  Hardware = 4,
  Server = 5,
  Browser = 6
}
```

**Validation Rules:**
- Sender MUST be device owner
- Owner MUST have Validated or Finalized presence
- `deviceIndex` MUST be unique for this owner
- `shareIndex` MUST be unique within owner's device ring
- Both signatures MUST be valid

### 6.2 DEVICE_ENTER_EPOCH (0x71)

Device declares presence in an epoch.

```typescript
interface DeviceEnterEpochPayload {
  deviceId: bytes32;
  epochId: uint256;
  ownerPresenceProof: bytes;    // Signature from owner authorizing device entry
  deviceAttestation: DeviceAttestation;
}

interface DeviceAttestation {
  deviceId: bytes32;
  epochId: uint256;
  timestamp: uint256;
  capabilities: DeviceCapability[];
  deviceSignature: bytes;
}

enum DeviceCapability {
  ShareStorage = 0,
  ShareProvide = 1,
  StorageAccess = 2,
  OfflineCache = 3
}
```

**Validation Rules:**
- Device MUST be in state: Registered, Absent, or Inactive
- Owner MUST have valid presence in target epoch
- Epoch MUST be Active

### 6.3 DEVICE_LEAVE (0x72)

Device voluntarily leaves the current epoch.

```typescript
interface DeviceLeavePayload {
  deviceId: bytes32;
  epochId: uint256;
  reason: LeaveReason;
  deviceSignature?: bytes;      // Device self-signs leave
  ownerSignature?: bytes;       // Owner forces device leave
  shareDestroyed: bool;
  destructionAttestation?: bytes;
}

enum LeaveReason {
  Voluntary = 0,
  Timeout = 1,
  OwnerForced = 2,
  NetworkError = 3
}
```

**Validation Rules:**
- Device MUST be in Present state
- Either device or owner signature MUST be valid

### 6.4 DEVICE_REVOKE (0x73)

Permanently revoke a device (terminal state).

```typescript
interface DeviceRevokePayload {
  deviceId: bytes32;
  ownerSignature: bytes;
  reason: RevokeReason;
  shareDestroyedAttestation?: bytes;
}

enum RevokeReason {
  UserInitiated = 0,
  Compromised = 1,
  Lost = 2,
  Replaced = 3
}
```

**Validation Rules:**
- Owner signature MUST be valid
- Device MUST NOT already be Revoked

### 6.5 DEVICE_RECOVER (0x74)

Initiate recovery for a lost device.

```typescript
interface DeviceRecoverPayload {
  deviceId: bytes32;
  newPublicKey: bytes;
  ownerSignature: bytes;
  deviceAttestations?: DeviceRecoveryAttestation[];
}

interface DeviceRecoveryAttestation {
  attestingDeviceId: bytes32;
  targetDeviceId: bytes32;
  approves: bool;
  signature: bytes;
}
```

**Validation Rules:**
- Device MUST be in Lost state
- Owner signature MUST be valid

---

## 7. Vault Messages (v0.7.2)

Vault messages enable presence-gated encrypted storage operations.
See `vaults.md` for complete vault specification.

### 7.1 VAULT_CREATE (0x75)

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

interface VaultPolicy {
  version: "1.0.0";
  minDevices: uint8;            // Minimum devices (default: 3)
  maxDevices: uint8;            // Maximum devices (default: 9)
  minThreshold: uint8;          // Minimum threshold (default: 2)
  requireHardwareDevice: bool;
  requireDeviceDiversity: bool;
  maxStorageBytes: uint256;
  allowedMediaTypes: string[];
  maxItemSize: uint256;
  autoLockOnEpochClose: bool;
  keyRotationOnEpochChange: bool;
  persistDataAcrossEpochs: bool;
  requireZKShareProof: bool;
  requireZKPresenceProof: bool;
  requireZKAccessProof: bool;
}

interface ZKConfig {
  shareProofCircuit: string;
  presenceProofCircuit: string;
  accessProofCircuit: string;
  shareVerifyingKey: bytes;
  presenceVerifyingKey: bytes;
  accessVerifyingKey: bytes;
  provingSystem: ProvingSystem;  // Groth16, PLONK, or STARK
}
```

**Validation Rules:**
- Owner MUST have Validated or Finalized presence
- `devices.length >= 3` (or policy minimum)
- `threshold >= 2`
- `threshold <= devices.length`
- All devices MUST be registered to owner
- All device signatures MUST be valid
- `shareCommitments.length == devices.length`

### 7.2 VAULT_CONFIGURE (0x76)

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

### 7.3 VAULT_UNLOCK (0x77)

Request vault unlock (trigger share collection).
See `lifecycle.md` for complete unlock flow and key reconstruction.

```typescript
interface VaultUnlockPayload {
  // Vault context
  vaultId: bytes32;

  // Requesting device
  requestingDeviceId: bytes32;

  // Session management
  sessionId: bytes32;           // Random session identifier
  timeout: uint256;             // Timeout in seconds (default: 30)

  // Ephemeral key for share responses
  responsePublicKey: bytes;     // secp256k1 compressed (33 bytes)
                                // Devices ECIES encrypt shares to this key

  // ZK proof (if required by policy)
  presenceProof?: ZKPresenceProof;

  // Authorization
  deviceSignature: bytes;
}

interface ZKPresenceProof {
  epochId: uint256;
  membershipRoot: bytes32;
  presenceListRoot: bytes32;
  proof: bytes;
}

interface VaultUnlockResponse {
  sessionId: bytes32;
  status: UnlockStatus;
  vaultId: bytes32;

  // Success info
  unlockedAt?: uint256;
  presentDevices?: uint8;

  // Failure info
  failureReason?: string;
  receivedShares?: uint8;
  requiredShares?: uint8;
}

enum UnlockStatus {
  Pending = 0,        // Waiting for shares
  Collecting = 1,     // Actively collecting shares
  Reconstructing = 2, // Threshold met, reconstructing
  Complete = 3,       // Key reconstructed, vault unlocked
  Failed = 4,         // Timeout or error
  Cancelled = 5       // Manually cancelled
}
```

**Unlock Protocol (INV76-77):**
```
1. Requester broadcasts VAULT_UNLOCK to ring devices
2. Present devices receive SHARE_REQUEST (auto-triggered)
3. Each device responds with SHARE_PROVIDE (encrypted to responsePublicKey)
4. Requester collects ≥ threshold shares
5. Requester reconstructs vaultKey via Lagrange interpolation
6. Verify key against vault.keyCommitment
7. Set vault.accessState = Unlocked
8. Broadcast VaultUnlockResponse with Complete status
```

**Validation Rules:**
- Requesting device MUST be Present in current epoch
- Vault MUST be Locked or Suspended (not Migrating or Recovering)
- Device MUST be in vault's device ring
- `timeout` MUST be <= 300 seconds (5 minutes max)
- If policy requires: ZK presence proof MUST verify

### 7.4 VAULT_LOCK (0x78)

Manually lock vault (emergency or planned).
See `lifecycle.md` for auto-lock mechanism and key destruction.

```typescript
interface VaultLockPayload {
  // Vault context
  vaultId: bytes32;

  // Lock reason
  reason: LockReason;
  reasonDetail?: string;        // Optional description (max 256 chars)

  // Authorization (one required)
  ownerSignature?: bytes;
  deviceSignature?: bytes;
  deviceId?: bytes32;

  // Lock options
  transitionToSuspended: bool;  // true = Suspended, false = Locked
  notifyDevices: bool;          // Broadcast lock notification to ring
}

enum LockReason {
  Manual = 0,           // User-initiated lock
  Emergency = 1,        // Security concern
  DeviceLost = 2,       // Device marked as lost
  DeviceCompromised = 3, // Device suspected compromised
  PolicyViolation = 4,  // Security policy violated
  EpochClosing = 5,     // Epoch transitioning to Closed
  ThresholdLost = 6,    // Device departure caused threshold loss (auto)
  InactivityTimeout = 7 // No activity for configured period (auto)
}

interface VaultLockResponse {
  vaultId: bytes32;
  previousState: VaultAccessState;
  newState: VaultAccessState;
  lockedAt: uint256;
  reason: LockReason;
  keyDestroyed: bool;   // Confirms INV77 enforcement
}

interface VaultAutoLockedEvent {
  vaultId: bytes32;
  reason: LockReason;
  triggeringDeviceId?: bytes32;  // Device that left (if ThresholdLost)
  presentDevices: uint8;
  threshold: uint8;
  timestamp: uint256;
}
```

**Lock Behavior (INV77: Key Destruction):**
```
1. Set vault.accessState = Locked|Suspended
2. secureZero(vault.reconstructedKey)  // Secure memory wipe
3. vault.reconstructedKey = null
4. Cancel any pending operations
5. If notifyDevices: broadcast VaultAutoLockedEvent
6. Emit VaultLockResponse
```

**Validation Rules:**
- Owner signature OR device signature required
- If device: device MUST be in vault ring
- Vault MUST NOT already be in terminal state
- If transitionToSuspended: requires owner signature

### 7.5 STORAGE_PUT (0x79)

Store encrypted item in vault.
See `storage.md` for complete storage specification and key derivation.

```typescript
interface StoragePutPayload {
  // Vault context
  vaultId: bytes32;
  keyVersion: uint256;          // Must match vault's current key version

  // Item identity (INV70: epoch binding)
  itemId: bytes32;              // keccak256(vaultId, keyVersion, contentHash, createdAt)

  // Encrypted content (AES-256-GCM)
  encryptedContent: bytes;      // Encrypted with derived item key
  iv: bytes;                    // 12 bytes (GCM nonce, random per item)
  authTag: bytes;               // 16 bytes (GCM authentication tag)

  // Integrity verification (INV72)
  contentHash: bytes32;         // keccak256 of plaintext (for integrity)
  contentSize: uint256;         // Original plaintext size in bytes

  // Metadata
  metadata: ItemMetadata;

  // ZK proof (if required by policy)
  accessProof?: ZKAccessProof;

  // Authorization
  deviceId: bytes32;
  deviceSignature: bytes;
}

interface ItemMetadata {
  name: string;                 // Display name (max 256 UTF-8 chars)
  description?: string;         // Optional description (max 1024 chars)
  mediaType: string;            // MIME type (e.g., "image/png", "application/pdf")
  tags?: string[];              // Organizational tags (max 10 tags, 32 chars each)
  folder?: string;              // Virtual folder path
  createdAt: uint256;           // Unix timestamp
  customFields?: Map<string, string>; // User-defined key-value pairs
}
```

**Key Derivation (from crypto.md):**
```
itemKey = hkdf_sha256(
  vaultKey,                     // Reconstructed vault key
  keccak256(itemId),            // Item-specific salt
  "7ay-item-key-v1"             // Context string
)
```

**Encryption Process:**
```
1. Generate random 12-byte IV
2. Derive itemKey from vaultKey
3. encryptedContent = AES-256-GCM.encrypt(plaintext, itemKey, iv)
4. authTag = GCM authentication tag (16 bytes)
5. contentHash = keccak256(plaintext)
```

**Validation Rules (INV71: Access Control):**
- Vault MUST be Unlocked
- Device MUST be Present in current epoch
- Device MUST be in vault's device ring
- `keyVersion` MUST match vault's current key version
- `contentSize` MUST be <= policy.maxItemSize
- `mediaType` MUST be in policy.allowedMediaTypes
- Storage quota: `vault.storageUsed + contentSize <= vault.storageQuota`
- `itemId` MUST be correctly derived
- `authTag` MUST be exactly 16 bytes
- `iv` MUST be exactly 12 bytes

### 7.6 STORAGE_GET (0x7A)

Retrieve encrypted item from vault.
See `storage.md` for decryption and integrity verification.

```typescript
interface StorageGetPayload {
  // Request
  vaultId: bytes32;
  itemId: bytes32;

  // ZK proof (if required by policy)
  accessProof?: ZKAccessProof;

  // Authorization
  deviceId: bytes32;
  deviceSignature: bytes;
}

interface StorageGetResponse {
  // Item identity
  itemId: bytes32;
  vaultId: bytes32;
  keyVersion: uint256;

  // Encrypted content
  encryptedContent: bytes;
  iv: bytes;                    // 12 bytes
  authTag: bytes;               // 16 bytes

  // Integrity data (INV72)
  contentHash: bytes32;
  contentSize: uint256;

  // Metadata
  metadata: ItemMetadata;

  // State
  state: ItemState;
  createdAt: uint256;
  updatedAt?: uint256;

  // Re-encryption indicator
  requiresReencryption: bool;   // true if keyVersion < vault.vaultKeyVersion
}

enum ItemState {
  Active = 0,                   // Normal state, accessible
  Archived = 1,                 // Hidden from listings, still accessible
  PendingDelete = 2,            // Marked for deletion
  PendingReencryption = 3       // Needs re-encryption with new key
}
```

**Decryption Process (client-side):**
```
1. Reconstruct vaultKey (requires threshold shares)
2. Derive itemKey = hkdf_sha256(vaultKey, keccak256(itemId), "7ay-item-key-v1")
3. plaintext = AES-256-GCM.decrypt(encryptedContent, itemKey, iv, authTag)
4. Verify: keccak256(plaintext) == contentHash (INV72)
5. If mismatch: reject (integrity violation)
```

**Validation Rules (INV71: Access Control):**
- Vault MUST be Unlocked
- Device MUST be Present in current epoch
- Device MUST be in vault's device ring
- Item MUST exist and state ∈ {Active, Archived, PendingReencryption}
- If `requiresReencryption`: client SHOULD re-encrypt with current key

### 7.7 STORAGE_DELETE (0x7B)

Delete stored item from vault.
See `storage.md` for deletion states and secure erasure.

```typescript
interface StorageDeletePayload {
  // Target
  vaultId: bytes32;
  itemId: bytes32;

  // Delete options
  deleteType: DeleteType;
  reason?: string;              // Optional audit trail (max 256 chars)

  // Authorization (owner required)
  ownerSignature: bytes;
}

enum DeleteType {
  Soft = 0,                     // Mark as PendingDelete, recoverable
  Hard = 1,                     // Immediate permanent deletion
  Secure = 2                    // Hard delete + secure memory wipe
}

interface StorageDeleteResponse {
  itemId: bytes32;
  previousState: ItemState;
  newState: ItemState;
  freedBytes: uint256;
  deletedAt: uint256;
  recoverable: bool;            // true if soft delete
  recoveryDeadline?: uint256;   // Unix timestamp for soft delete expiry
}
```

**Delete Behavior:**
- **Soft (0)**: `item.state → PendingDelete`, recoverable within grace period (default 7 days)
- **Hard (1)**: Immediate removal, `vault.storageUsed -= item.contentSize`
- **Secure (2)**: Hard delete + `secureZero(encryptedContent)` attestation

**Validation Rules (INV71: Access Control):**
- Vault MUST be Unlocked
- Owner signature MUST be valid
- Item MUST exist and state ∈ {Active, Archived, PendingDelete}
- For Secure delete: SHOULD generate secure erasure attestation

### 7.8 STORAGE_LIST (0x7C)

List stored items (metadata only, no encrypted content).
See `storage.md` for storage model.

```typescript
interface StorageListPayload {
  // Vault context
  vaultId: bytes32;

  // Filtering
  filter?: ItemFilter;

  // Sorting
  sortBy?: SortField;
  sortOrder?: SortOrder;

  // Pagination
  pagination?: Pagination;

  // Authorization
  deviceId: bytes32;
  deviceSignature: bytes;
}

interface ItemFilter {
  // Content filtering
  mediaType?: string;           // Filter by MIME type (exact or prefix, e.g., "image/")
  mediaTypes?: string[];        // Filter by multiple MIME types
  tags?: string[];              // Filter by tags (AND logic)
  tagsAny?: string[];           // Filter by tags (OR logic)
  folder?: string;              // Filter by virtual folder

  // State filtering
  states?: ItemState[];         // Filter by states (default: [Active])
  includeArchived?: bool;       // Include Archived items

  // Temporal filtering
  createdAfter?: uint256;       // Unix timestamp
  createdBefore?: uint256;
  updatedAfter?: uint256;
  updatedBefore?: uint256;

  // Size filtering
  minSize?: uint256;            // Bytes
  maxSize?: uint256;

  // Search
  nameContains?: string;        // Case-insensitive name search
}

enum SortField {
  CreatedAt = 0,                // Default
  UpdatedAt = 1,
  Name = 2,
  Size = 3,
  MediaType = 4
}

enum SortOrder {
  Descending = 0,               // Default (newest first)
  Ascending = 1
}

interface Pagination {
  offset: uint256;              // Skip first N items
  limit: uint256;               // Return max N items (default: 50, max: 200)
}

interface StorageListResponse {
  // Vault info
  vaultId: bytes32;
  keyVersion: uint256;

  // Items (metadata only)
  items: ItemSummary[];

  // Pagination info
  totalCount: uint256;          // Total matching items
  returnedCount: uint256;       // Items in this response
  hasMore: bool;
  nextOffset?: uint256;         // Offset for next page

  // Stats
  totalSize: uint256;           // Total bytes of matching items
  storageUsed: uint256;         // Vault's total storage used
  storageQuota: uint256;        // Vault's storage quota
}

interface ItemSummary {
  // Identity
  itemId: bytes32;
  keyVersion: uint256;

  // Metadata
  name: string;
  description?: string;
  mediaType: string;
  contentSize: uint256;
  tags?: string[];
  folder?: string;

  // State
  state: ItemState;
  requiresReencryption: bool;

  // Timestamps
  createdAt: uint256;
  updatedAt?: uint256;

  // Note: NO encryptedContent, iv, authTag (list returns metadata only)
}
```

**Validation Rules (INV71: Access Control):**
- Vault MUST be Unlocked
- Device MUST be Present in current epoch
- Device MUST be in vault's device ring
- `pagination.limit` MUST be <= 200
- By default, only Active items returned (use `includeArchived` for others)

### 7.9 SHARE_DISTRIBUTE (0x7D)

Distribute Shamir key shares to devices after vault creation or key rotation.
See `crypto.md` for detailed cryptographic specification.

```typescript
interface ShareDistributePayload {
  // Vault context
  vaultId: bytes32;
  keyVersion: uint256;          // Increments on each rotation

  // Encrypted shares (one per device)
  encryptedShares: EncryptedDeviceShare[];

  // Verification commitments
  shareCommitments: bytes32[];  // Pedersen commitments for each share

  // Feldman VSS (optional, for verifiable sharing)
  feldmanCommitments?: bytes[]; // g^a₀, g^a₁, ..., g^aₖ₋₁

  // Authorization
  ownerSignature: bytes;
}

interface EncryptedDeviceShare {
  deviceId: bytes32;
  shareIndex: uint8;            // 1-based Shamir index
  encryptedShare: ECIESCiphertext;
}

interface ECIESCiphertext {
  ephemeralPublicKey: bytes;    // 33 bytes (compressed secp256k1)
  iv: bytes;                    // 16 bytes (AES-GCM nonce)
  ciphertext: bytes;            // Encrypted share value
  authTag: bytes;               // 16 bytes (GCM authentication tag)
}
```

**Validation Rules (INV69):**
- Owner signature MUST be valid
- Number of shares MUST equal device ring size
- Each device MUST receive exactly one share
- Share indices MUST be unique and sequential (1 to n)
- Pedersen commitments MUST be provided for each share
- If Feldman provided: commitment count MUST equal threshold

### 7.10 SHARE_REQUEST (0x7E)

Request shares from other devices to reconstruct vault key.
See `crypto.md` for key reconstruction protocol.

```typescript
interface ShareRequestPayload {
  // Vault context
  vaultId: bytes32;
  keyVersion: uint256;          // Must match current key version

  // Request metadata
  requestingDeviceId: bytes32;
  requestNonce: bytes32;        // Unique per request (prevents replay)
  requestTimestamp: uint256;

  // Ephemeral key for response encryption
  responsePublicKey: bytes;     // secp256k1 compressed (33 bytes)
                                // Providers will ECIES encrypt to this key

  // ZK proof of presence (if required by policy)
  presenceProof?: ZKPresenceProof;

  // Device signature
  deviceSignature: bytes;
}
```

**Validation Rules:**
- Requesting device MUST be Present in current epoch
- Requesting device MUST be in vault's device ring
- Request nonce MUST be unique (prevents replay)
- Key version MUST match vault's current key version
- If policy requires: ZK presence proof MUST verify

**Protocol Flow:**
1. Requester broadcasts SHARE_REQUEST to all ring devices
2. Present devices respond with SHARE_PROVIDE
3. Requester collects ≥ threshold shares
4. Requester reconstructs key via Lagrange interpolation

### 7.11 SHARE_PROVIDE (0x7F)

Provide encrypted share in response to SHARE_REQUEST.
See `crypto.md` for ECIES encryption and Feldman verification.

```typescript
interface ShareProvidePayload {
  // Request correlation
  vaultId: bytes32;
  requestNonce: bytes32;        // Echo from SHARE_REQUEST

  // Provider identification
  providingDeviceId: bytes32;
  shareIndex: uint8;            // 1-based Shamir index

  // Encrypted share (to requester's ephemeral key)
  encryptedShare: ECIESCiphertext;

  // Verification data
  shareCommitment: bytes32;     // Pedersen commitment (for verification)
  blindingFactor?: bytes32;     // Optional: reveal blinding for direct verification

  // ZK proof (if required by policy)
  shareProof?: ZKShareProof;

  // Device signature
  deviceSignature: bytes;
}

interface ZKShareProof {
  vaultId: bytes32;
  shareCommitment: bytes32;
  commitmentsRoot: bytes32;     // Merkle root of all share commitments
  epochId: uint256;
  proof: bytes;                 // Groth16/PLONK/STARK proof
}
```

**Validation Rules:**
- Providing device MUST be Present in current epoch
- Providing device MUST be in vault's device ring
- Request nonce MUST match a pending SHARE_REQUEST
- Share MUST verify against Pedersen commitment
- If Feldman available: share MUST verify against polynomial commitments
- If policy requires: ZK share proof MUST verify
- Each device provides share ONLY ONCE per request nonce

**Security Properties:**
- Share encrypted to requester's ephemeral key (forward secrecy)
- Commitment verification prevents malicious share injection
- ZK proof option hides which device provided the share

---

## 8. Message Validation

### 8.1 Common Validation

All messages MUST pass:

1. **Version check**: `version == "0.6.9"`
2. **Type validity**: `type` in defined range
3. **Epoch check**: `epochId` exists and supports signals
4. **Chain binding**: `chain_id == currentChainId` (INV43)
5. **Block bound**: `currentBlock <= block_bound` (INV43)
6. **Signature**: Valid ECDSA signature from sender
7. **Presence check**: Sender has valid presence (for most messages)
8. **Nonce check**: Nonce not previously used by sender in epoch
9. **Timestamp**: Within acceptable window (±5 minutes)

### 8.2 Validation Order

```
1. version      → MSG_008
2. type         → MSG_001
3. chain_id     → MSG_009 (INV43)
4. block_bound  → MSG_010 (INV43)
5. epochId      → MSG_004
6. signature    → MSG_002
7. presence     → MSG_005
8. nonce        → MSG_003
9. timestamp    → MSG_006
10. payload     → MSG_007
```

### 8.3 Error Responses

See `errors.md v0.6.9` for error codes:
- MSG_001: InvalidMessageType
- MSG_002: InvalidSignature
- MSG_003: NonceReused
- MSG_004: EpochMismatch
- MSG_005: SenderNotInEpoch
- MSG_006: MessageExpired
- MSG_007: InvalidPayload
- MSG_008: VersionMismatch
- MSG_009: ChainMismatch (INV43)
- MSG_010: BlockBoundExceeded (INV43)

---

## 9. Invariants

### 9.1 Message Invariants

**INV23: Epoch-Bound Messages**
All messages MUST reference a valid epoch with sufficient capability.

**INV24: Signature Validity**
Message signature MUST verify against sender's address.

**INV25: Nonce Uniqueness**
Each (sender, nonce) pair MUST be unique within an epoch.

**INV43: Chain Binding** (v0.6.9)
Messages MUST be bound to the current chain and within block bounds.

```
∀ msg:
  msg.chain_id == currentChainId ∧
  currentBlock <= msg.block_bound
```

This invariant prevents:
- **Cross-chain replay**: Messages cannot be replayed on different chains
- **Delayed replay**: Messages expire after block_bound, preventing replay attacks
- **Fork attacks**: Messages signed for one fork are invalid on others

### 9.2 Enforcement

See `invariants.md v0.6.9` for formal definitions.

---

## 10. Security Considerations

### 10.1 Replay Protection (Enhanced v0.6.9)

Replay attacks are prevented by multiple layers:
- **Unique nonce** per message (INV25)
- **Epoch binding** (messages invalid after epoch closes)
- **Timestamp validation** (±5 minute window)
- **Chain binding** via `chain_id` (INV43) — prevents cross-chain replay
- **Block bound** via `block_bound` (INV43) — prevents delayed replay

The chain binding mechanism ensures:
```
1. Messages cannot be replayed on forks or sidechains
2. Messages expire after ~100 blocks (~20 minutes)
3. Old signatures become invalid automatically
```

### 10.2 Spoofing Prevention

Sender spoofing is prevented by:
- ECDSA signature verification
- On-chain presence verification

### 10.3 Denial of Service

Mitigation:
- Rate limiting per sender
- Message size limits
- Nonce tracking bounds

---

## 11. Non-Goals

This specification explicitly does NOT define:

- Message routing or delivery
- Peer discovery protocols
- Connection management
- Encoding formats
- Compression

---

## 12. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 presence states | Used for validation |
| v0.4 validator logic | Used for role checks |
| Existing events | Not affected |
| On-chain functions | Used for verification |

---

## 13. References

- node-model.md v0.6 — Node structure
- state-sync.md v0.6 — Sync protocol
- invariants.md v0.7.5 — Protocol invariants INV19-26, INV43, INV70-78
- lifecycle.md v0.7.5 — Vault lifecycle management
- errors.md v0.6.9 — Error catalog
- presence.md v0.4 — Presence states
- validator.md v0.4 — Validator mechanics

---

## 14. Changelog

| Version | Changes |
|---------|---------|
| v0.6.2 | Initial message catalog specification |
| v0.6.4 | Added Media messages (0x30-0x33) |
| v0.6.5 | Added Boomerang messages (0x40-0x43) |
| v0.6.6 | Added Autonomous messages (0x50-0x54) |
| v0.6.7 | Added Octopus messages (0x60-0x65) |
| v0.6.9 | **Security hardening**: Added chain_id, block_bound to envelope; INV43 chain binding |
| v0.7.1 | **Device layer**: Added Device messages (0x70-0x7F) for trusted device storage |
| v0.7.2 | **Vault layer**: Added Vault/Storage message details (VAULT_CREATE, VAULT_CONFIGURE, VAULT_UNLOCK, VAULT_LOCK, STORAGE_*, SHARE_*); ZK proof integration |
| v0.7.3 | **Cryptographic layer**: Enhanced SHARE_DISTRIBUTE/REQUEST/PROVIDE with ECIES ciphertext structure, Feldman VSS, key version tracking |
| v0.7.4 | **Storage layer**: Enhanced STORAGE_PUT/GET/DELETE/LIST with AES-256-GCM encryption, key derivation, integrity verification (INV72), item states, filtering, pagination |
| v0.7.5 | **Lifecycle management**: Enhanced VAULT_UNLOCK with session management, unlock protocol, status tracking; Enhanced VAULT_LOCK with auto-lock reasons, key destruction confirmation (INV76-78) |

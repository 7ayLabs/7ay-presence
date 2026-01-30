# 7ay Proof of Presence (PoP)
## Protocol Specification — Storage Layer
**Version:** v0.7.4
**Status:** Draft
**Depends on:** vaults.md v0.7.2, crypto.md v0.7.3

> Encrypted item storage with presence-gated access and integrity verification

## 1. Overview

The Storage Layer defines how encrypted data items are stored, retrieved, and managed within presence-gated vaults. Items are encrypted with AES-256-GCM using the vault's epoch key and can only be accessed when the vault is unlocked (threshold devices present).

### 1.1 Design Principles

1. **Presence-Gated Access**: All storage operations require unlocked vault
2. **End-to-End Encryption**: Items encrypted before storage, decrypted after retrieval
3. **Integrity Verification**: Content hash ensures data hasn't been tampered with
4. **Persistent Storage**: Data survives epoch transitions via key rotation

### 1.2 Storage Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         VAULT                                   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                   ITEM INDEX                             │  │
│   │  itemId → { metadata, storageLocation, contentHash }    │  │
│   └─────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                 ENCRYPTED STORAGE                        │  │
│   │                                                          │  │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐             │  │
│   │   │ Item A   │  │ Item B   │  │ Item C   │  ...        │  │
│   │   │ AES-GCM  │  │ AES-GCM  │  │ AES-GCM  │             │  │
│   │   └──────────┘  └──────────┘  └──────────┘             │  │
│   │                                                          │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   Encryption Key: Derived from vault epoch key                  │
│   Access: Only when vault is UNLOCKED                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Storage Item Model

### 2.1 Item Structure

```typescript
interface StorageItem {
  // Identity
  itemId: bytes32;              // keccak256(vaultId, contentHash, createdAt)

  // Vault binding
  vaultId: bytes32;
  keyVersion: uint256;          // Vault key version used for encryption

  // Content
  encryptedContent: bytes;      // AES-256-GCM encrypted
  contentHash: bytes32;         // keccak256 of plaintext (for integrity)
  contentSize: uint256;         // Size in bytes (plaintext)

  // Encryption metadata
  iv: bytes;                    // 12 bytes (GCM nonce)
  authTag: bytes;               // 16 bytes (GCM authentication tag)

  // Item metadata
  metadata: ItemMetadata;

  // Timestamps
  createdAt: uint256;
  updatedAt: uint256;
  accessedAt: uint256;

  // State
  state: ItemState;
}

interface ItemMetadata {
  // Display information
  name: string;                 // Max 255 UTF-8 characters
  description?: string;         // Max 1024 UTF-8 characters

  // Content type
  mediaType: string;            // MIME type (e.g., "image/jpeg")
  extension?: string;           // File extension (e.g., "jpg")

  // Organization
  tags?: string[];              // Max 10 tags, 32 chars each
  folder?: string;              // Virtual folder path

  // Custom fields
  custom?: Map<string, string>; // Max 10 key-value pairs
}

enum ItemState {
  Active = 0,                   // Normal, accessible
  Archived = 1,                 // Hidden but not deleted
  PendingDelete = 2,            // Marked for deletion
  Deleted = 3                   // Tombstone (metadata only)
}
```

### 2.2 Item Identity Derivation

```typescript
function deriveItemId(
  vaultId: bytes32,
  contentHash: bytes32,
  createdAt: uint256
): bytes32 {
  return keccak256(abi.encodePacked(
    "7ay-item-v1",               // Domain separator
    vaultId,                     // 32 bytes
    contentHash,                 // 32 bytes
    createdAt                    // 32 bytes
  ));
}
```

### 2.3 Supported Media Types

| Category | MIME Types | Max Size |
|----------|------------|----------|
| Text | text/plain, text/markdown, application/json | 10 MB |
| Image | image/jpeg, image/png, image/gif, image/webp | 50 MB |
| Audio | audio/mpeg, audio/wav, audio/ogg | 100 MB |
| Video | video/mp4, video/webm | 500 MB |
| Document | application/pdf, application/msword | 100 MB |
| Archive | application/zip, application/gzip | 500 MB |
| Binary | application/octet-stream | 100 MB |

Default maximum item size: 100 MB (configurable via policy)

---

## 3. Encryption

### 3.1 Item Encryption Key Derivation

Each item uses a unique encryption key derived from the vault key:

```typescript
function deriveItemKey(
  vaultKey: bytes32,
  itemId: bytes32
): bytes32 {
  return hkdfExpand(
    vaultKey,
    itemId,
    "7ay-item-key-v1"
  );
}
```

### 3.2 AES-256-GCM Encryption

```typescript
interface EncryptionResult {
  ciphertext: bytes;
  iv: bytes;                    // 12 bytes
  authTag: bytes;               // 16 bytes
}

/**
 * Encrypt item content with AES-256-GCM
 * @param plaintext - Content to encrypt
 * @param key - 32-byte encryption key
 * @param aad - Additional authenticated data (itemId)
 */
function encryptItem(
  plaintext: bytes,
  key: bytes32,
  aad: bytes32
): EncryptionResult {
  // Generate random 12-byte IV (nonce)
  const iv = secureRandom(12);

  // AES-256-GCM encryption
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(aad);

  const ciphertext = Buffer.concat([
    cipher.update(plaintext),
    cipher.final()
  ]);

  const authTag = cipher.getAuthTag();

  return { ciphertext, iv, authTag };
}

/**
 * Decrypt item content with AES-256-GCM
 */
function decryptItem(
  ciphertext: bytes,
  key: bytes32,
  iv: bytes,
  authTag: bytes,
  aad: bytes32
): bytes {
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAAD(aad);
  decipher.setAuthTag(authTag);

  const plaintext = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final()  // Throws if auth tag doesn't match
  ]);

  return plaintext;
}
```

### 3.3 Encryption Security Properties

| Property | Guarantee |
|----------|-----------|
| **Confidentiality** | AES-256 provides 256-bit security |
| **Authenticity** | GCM tag verifies ciphertext integrity |
| **Non-Malleability** | Any modification invalidates auth tag |
| **Unique Keys** | Each item has unique derived key |
| **IV Uniqueness** | Random 12-byte IV per encryption |

---

## 4. Storage Operations

### 4.1 STORAGE_PUT (0x79)

Store a new item or update existing item.

```typescript
interface StoragePutPayload {
  // Vault context
  vaultId: bytes32;

  // Item identity (optional for new items)
  itemId?: bytes32;             // If provided, updates existing item

  // Encrypted content
  encryptedContent: bytes;      // AES-256-GCM encrypted
  iv: bytes;                    // 12 bytes
  authTag: bytes;               // 16 bytes

  // Integrity
  contentHash: bytes32;         // keccak256 of plaintext
  contentSize: uint256;         // Plaintext size in bytes

  // Metadata
  metadata: ItemMetadata;

  // Key version (for re-encryption detection)
  keyVersion: uint256;

  // ZK access proof (if required by policy)
  accessProof?: ZKAccessProof;

  // Device signature
  deviceId: bytes32;
  deviceSignature: bytes;
}
```

**Validation Rules (INV70, INV71)**:
- Vault MUST be Unlocked
- Device MUST be Present and in vault's device ring
- `contentSize` MUST be within policy limits
- `metadata.mediaType` MUST be in allowed types
- `keyVersion` MUST match vault's current key version
- If updating: `itemId` MUST exist and be Active/Archived
- If ZK required: `accessProof` MUST verify

**Processing Flow**:

```typescript
function processStoragePut(
  payload: StoragePutPayload,
  vault: Vault
): Result<bytes32, Error> {
  // 1. Validate vault state
  if (vault.accessState !== VaultAccessState.Unlocked) {
    return Err(STOR_007_VaultLocked);
  }

  // 2. Validate device
  if (!isDevicePresentInRing(payload.deviceId, vault)) {
    return Err(STOR_020_UnauthorizedDevice);
  }

  // 3. Validate key version
  if (payload.keyVersion !== vault.vaultKeyVersion) {
    return Err(STOR_018_KeyVersionMismatch);
  }

  // 4. Validate size
  if (payload.contentSize > vault.policy.maxItemSize) {
    return Err(STOR_016_ItemTooLarge);
  }

  // 5. Validate media type
  if (!isMediaTypeAllowed(payload.metadata.mediaType, vault.policy)) {
    return Err(STOR_017_InvalidMediaType);
  }

  // 6. Validate quota
  if (vault.storageUsed + payload.contentSize > vault.storageQuota) {
    return Err(STOR_014_StorageQuotaExceeded);
  }

  // 7. Create or update item
  const itemId = payload.itemId ?? deriveItemId(
    vault.vaultId,
    payload.contentHash,
    block.timestamp
  );

  const item: StorageItem = {
    itemId,
    vaultId: vault.vaultId,
    keyVersion: payload.keyVersion,
    encryptedContent: payload.encryptedContent,
    contentHash: payload.contentHash,
    contentSize: payload.contentSize,
    iv: payload.iv,
    authTag: payload.authTag,
    metadata: payload.metadata,
    createdAt: payload.itemId ? existing.createdAt : block.timestamp,
    updatedAt: block.timestamp,
    accessedAt: block.timestamp,
    state: ItemState.Active
  };

  // 8. Store item
  storage.put(itemId, item);

  // 9. Update vault stats
  vault.storageUsed += payload.contentSize;
  vault.itemCount++;

  // 10. Emit event
  emit ItemStored { vaultId, itemId, contentSize, mediaType };

  return Ok(itemId);
}
```

### 4.2 STORAGE_GET (0x7A)

Retrieve an encrypted item.

```typescript
interface StorageGetPayload {
  // Vault context
  vaultId: bytes32;

  // Item to retrieve
  itemId: bytes32;

  // ZK access proof (if required by policy)
  accessProof?: ZKAccessProof;

  // Device signature
  deviceId: bytes32;
  deviceSignature: bytes;
}

interface StorageGetResponse {
  // Item data
  item: StorageItem;

  // Decryption hint (not the key itself)
  keyVersion: uint256;
}
```

**Validation Rules (INV71)**:
- Vault MUST be Unlocked
- Device MUST be Present and in vault's device ring
- Item MUST exist and NOT be Deleted
- If ZK required: `accessProof` MUST verify

**Processing Flow**:

```typescript
function processStorageGet(
  payload: StorageGetPayload,
  vault: Vault
): Result<StorageGetResponse, Error> {
  // 1. Validate vault state
  if (vault.accessState !== VaultAccessState.Unlocked) {
    return Err(STOR_007_VaultLocked);
  }

  // 2. Validate device
  if (!isDevicePresentInRing(payload.deviceId, vault)) {
    return Err(STOR_020_UnauthorizedDevice);
  }

  // 3. Retrieve item
  const item = storage.get(payload.itemId);
  if (!item) {
    return Err(STOR_015_ItemNotFound);
  }

  // 4. Validate item state
  if (item.state === ItemState.Deleted) {
    return Err(STOR_015_ItemNotFound);
  }

  // 5. Update access timestamp
  item.accessedAt = block.timestamp;

  // 6. Return item
  return Ok({
    item,
    keyVersion: item.keyVersion
  });
}
```

### 4.3 Client-Side Decryption

After receiving STORAGE_GET response, client decrypts locally:

```typescript
async function retrieveAndDecrypt(
  vaultId: bytes32,
  itemId: bytes32,
  vaultKey: bytes32
): Promise<bytes> {
  // 1. Request item
  const response = await sendStorageGet({ vaultId, itemId, ... });

  // 2. Verify key version matches
  if (response.keyVersion !== currentKeyVersion) {
    throw new Error(STOR_018_KeyVersionMismatch);
  }

  // 3. Derive item key
  const itemKey = deriveItemKey(vaultKey, itemId);

  // 4. Decrypt content
  const plaintext = decryptItem(
    response.item.encryptedContent,
    itemKey,
    response.item.iv,
    response.item.authTag,
    itemId  // AAD
  );

  // 5. Verify integrity (INV72)
  const computedHash = keccak256(plaintext);
  if (computedHash !== response.item.contentHash) {
    throw new Error(STOR_019_IntegrityCheckFailed);
  }

  // 6. Cleanup
  secureZero(itemKey);

  return plaintext;
}
```

### 4.4 STORAGE_DELETE (0x7B)

Delete a stored item.

```typescript
interface StorageDeletePayload {
  // Vault context
  vaultId: bytes32;

  // Item to delete
  itemId: bytes32;

  // Deletion mode
  mode: DeleteMode;

  // Authorization (owner required)
  ownerSignature: bytes;
}

enum DeleteMode {
  Soft = 0,                     // Mark as Deleted (recoverable)
  Hard = 1                      // Permanently remove (irreversible)
}
```

**Validation Rules**:
- Vault MUST be Unlocked
- Owner signature MUST be valid
- Item MUST exist and NOT already be Deleted

**Processing Flow**:

```typescript
function processStorageDelete(
  payload: StorageDeletePayload,
  vault: Vault
): Result<void, Error> {
  // 1. Validate vault state
  if (vault.accessState !== VaultAccessState.Unlocked) {
    return Err(STOR_007_VaultLocked);
  }

  // 2. Validate owner signature
  if (!verifySignature(payload.ownerSignature, vault.owner)) {
    return Err(PRES_002_UnauthorizedActor);
  }

  // 3. Retrieve item
  const item = storage.get(payload.itemId);
  if (!item || item.state === ItemState.Deleted) {
    return Err(STOR_015_ItemNotFound);
  }

  // 4. Process deletion
  if (payload.mode === DeleteMode.Hard) {
    // Permanently remove encrypted content
    storage.delete(payload.itemId);

    // Update vault stats
    vault.storageUsed -= item.contentSize;
    vault.itemCount--;
  } else {
    // Soft delete - keep tombstone
    item.state = ItemState.Deleted;
    item.encryptedContent = null;  // Clear content
    item.updatedAt = block.timestamp;
    storage.put(payload.itemId, item);

    vault.storageUsed -= item.contentSize;
  }

  // 5. Emit event
  emit ItemDeleted { vaultId, itemId, mode };

  return Ok();
}
```

### 4.5 STORAGE_LIST (0x7C)

List items in vault (metadata only).

```typescript
interface StorageListPayload {
  // Vault context
  vaultId: bytes32;

  // Filters
  filter?: ItemFilter;

  // Pagination
  pagination?: Pagination;

  // Device signature
  deviceId: bytes32;
  deviceSignature: bytes;
}

interface ItemFilter {
  // State filter
  states?: ItemState[];         // Default: [Active]

  // Content filter
  mediaTypes?: string[];        // Filter by MIME type
  tags?: string[];              // Filter by tags (AND logic)
  folder?: string;              // Filter by folder

  // Time filter
  createdAfter?: uint256;
  createdBefore?: uint256;
  accessedAfter?: uint256;

  // Size filter
  minSize?: uint256;
  maxSize?: uint256;

  // Search
  nameContains?: string;        // Case-insensitive name search
}

interface Pagination {
  offset: uint256;              // Skip first N items
  limit: uint256;               // Return max N items (default: 50, max: 100)
  sortBy: SortField;            // Sort field
  sortOrder: SortOrder;         // Ascending/Descending
}

enum SortField {
  CreatedAt = 0,
  UpdatedAt = 1,
  AccessedAt = 2,
  Name = 3,
  Size = 4
}

enum SortOrder {
  Ascending = 0,
  Descending = 1
}

interface StorageListResponse {
  // Items (metadata only, no content)
  items: ItemSummary[];

  // Pagination info
  total: uint256;               // Total matching items
  hasMore: bool;
  nextOffset?: uint256;
}

interface ItemSummary {
  itemId: bytes32;
  metadata: ItemMetadata;
  contentSize: uint256;
  contentHash: bytes32;
  state: ItemState;
  createdAt: uint256;
  updatedAt: uint256;
  accessedAt: uint256;
}
```

**Validation Rules**:
- Vault MUST be Unlocked
- Device MUST be Present and in vault's device ring
- `pagination.limit` MUST be <= 100

---

## 5. Data Persistence

### 5.1 Epoch Transition

Data persists across epoch transitions through key rotation:

```
Epoch N                           Epoch N+1
   │                                  │
   │  vault_key_N                     │  vault_key_N+1
   │       │                          │       │
   │       ▼                          │       ▼
   │  ┌─────────┐                    │  ┌─────────┐
   │  │ Item A  │ ──── re-encrypt ────►│ Item A  │
   │  │ (key N) │                    │  │(key N+1)│
   │  └─────────┘                    │  └─────────┘
   │                                  │
```

### 5.2 Re-encryption on Key Rotation

When vault key rotates (epoch change or manual rotation):

```typescript
async function reencryptVaultItems(
  vault: Vault,
  oldKey: bytes32,
  newKey: bytes32,
  newKeyVersion: uint256
): Promise<void> {
  // 1. Get all active items
  const items = await storage.list(vault.vaultId, {
    states: [ItemState.Active, ItemState.Archived]
  });

  // 2. Re-encrypt each item
  for (const item of items) {
    // Derive old item key
    const oldItemKey = deriveItemKey(oldKey, item.itemId);

    // Decrypt with old key
    const plaintext = decryptItem(
      item.encryptedContent,
      oldItemKey,
      item.iv,
      item.authTag,
      item.itemId
    );

    // Verify integrity
    if (keccak256(plaintext) !== item.contentHash) {
      emit ReencryptionFailed { itemId: item.itemId, reason: "integrity" };
      continue;
    }

    // Derive new item key
    const newItemKey = deriveItemKey(newKey, item.itemId);

    // Re-encrypt with new key
    const { ciphertext, iv, authTag } = encryptItem(
      plaintext,
      newItemKey,
      item.itemId
    );

    // Update item
    item.encryptedContent = ciphertext;
    item.iv = iv;
    item.authTag = authTag;
    item.keyVersion = newKeyVersion;
    item.updatedAt = block.timestamp;

    await storage.put(item.itemId, item);

    // Cleanup
    secureZero(oldItemKey);
    secureZero(newItemKey);
    secureZero(plaintext);
  }

  // 3. Clear old key
  secureZero(oldKey);
}
```

### 5.3 Lazy Re-encryption (Alternative)

For large vaults, re-encryption can be lazy (on access):

```typescript
function lazyReencrypt(
  item: StorageItem,
  vault: Vault,
  currentKey: bytes32
): StorageItem {
  // Check if re-encryption needed
  if (item.keyVersion === vault.vaultKeyVersion) {
    return item;  // Already current
  }

  // Get historical key for item's version
  const oldKey = getHistoricalKey(vault, item.keyVersion);

  // Re-encrypt
  const oldItemKey = deriveItemKey(oldKey, item.itemId);
  const plaintext = decryptItem(...);

  const newItemKey = deriveItemKey(currentKey, item.itemId);
  const { ciphertext, iv, authTag } = encryptItem(plaintext, newItemKey, ...);

  // Update item
  item.encryptedContent = ciphertext;
  item.iv = iv;
  item.authTag = authTag;
  item.keyVersion = vault.vaultKeyVersion;

  storage.put(item.itemId, item);

  return item;
}
```

---

## 6. Integrity Verification (INV72)

### 6.1 Content Hash

Every item stores a hash of its plaintext content:

```typescript
contentHash = keccak256(plaintext)
```

### 6.2 Verification Flow

```
Client                              Storage
   │                                   │
   │ ───── STORAGE_GET ──────────────► │
   │                                   │
   │ ◄──── item (encrypted) ────────── │
   │                                   │
   │  1. Decrypt locally               │
   │  2. Compute hash of plaintext     │
   │  3. Compare with item.contentHash │
   │                                   │
   │  hash matches? → Content valid    │
   │  hash mismatch → STOR_019 error   │
```

### 6.3 Integrity Invariant (INV72)

```
FOR ALL storage operations (GET):
  let plaintext = decrypt(item.encryptedContent, itemKey)
  keccak256(plaintext) = item.contentHash
```

If integrity check fails:
- Return `STOR_019_IntegrityCheckFailed`
- Log violation for audit
- Do NOT return corrupted content to user

---

## 7. Storage Quotas

### 7.1 Quota Model

```typescript
interface StorageQuota {
  // Total limits
  maxBytes: uint256;            // Total storage bytes
  maxItems: uint256;            // Total item count

  // Per-item limits
  maxItemSize: uint256;         // Max single item size

  // Type-specific limits
  maxImageSize?: uint256;
  maxVideoSize?: uint256;
  maxDocumentSize?: uint256;
}
```

### 7.2 Default Quotas

| Tier | Total Storage | Max Items | Max Item Size |
|------|---------------|-----------|---------------|
| Free | 100 MB | 100 | 10 MB |
| Basic | 1 GB | 1,000 | 50 MB |
| Pro | 10 GB | 10,000 | 100 MB |
| Enterprise | 100 GB | 100,000 | 500 MB |

### 7.3 Quota Enforcement

```typescript
function checkQuota(
  vault: Vault,
  newItemSize: uint256
): Result<void, Error> {
  const quota = vault.policy.storageQuota;

  // Check total bytes
  if (vault.storageUsed + newItemSize > quota.maxBytes) {
    return Err(STOR_014_StorageQuotaExceeded);
  }

  // Check item count
  if (vault.itemCount >= quota.maxItems) {
    return Err(STOR_014_StorageQuotaExceeded);
  }

  // Check item size
  if (newItemSize > quota.maxItemSize) {
    return Err(STOR_016_ItemTooLarge);
  }

  return Ok();
}
```

---

## 8. Invariants

### 8.1 INV70: Storage Epoch Binding

Items MUST be encrypted with the current epoch's vault key.

```
FOR ALL items i in vault v:
  i.keyVersion = v.vaultKeyVersion OR
  i is pending re-encryption
```

### 8.2 INV71: Storage Access Control

PUT/GET/DELETE operations MUST require unlocked vault state.

```
FOR ALL storage operations op:
  op.type IN {PUT, GET, DELETE, LIST} IMPLIES
    vault(op.vaultId).accessState = Unlocked AND
    device(op.deviceId).state = Present AND
    device(op.deviceId) IN vault.deviceRing
```

### 8.3 INV72: Storage Data Integrity

Decrypted content MUST verify against stored content hash.

```
FOR ALL items i:
  let plaintext = decrypt(i.encryptedContent, deriveItemKey(vaultKey, i.itemId))
  keccak256(plaintext) = i.contentHash
```

---

## 9. Security Considerations

### 9.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Storage server compromise | Items encrypted client-side with vault key |
| Content tampering | GCM auth tag + content hash verification |
| Metadata leakage | Metadata encrypted within item |
| Access pattern analysis | ZK access proofs hide which items accessed |
| Key extraction from memory | Secure zero after use |
| Replay of old items | Key version prevents old ciphertext injection |

### 9.2 Security Properties

| Property | Mechanism |
|----------|-----------|
| Confidentiality | AES-256-GCM encryption |
| Integrity | GCM auth tag + keccak256 hash |
| Authenticity | Device signatures on operations |
| Forward secrecy | Key rotation on epoch change |
| Access control | Vault unlock threshold |

### 9.3 Recommendations

1. **Client-side encryption**: Always encrypt before sending to storage
2. **Verify on read**: Always verify content hash after decryption
3. **Rotate keys**: Enable automatic key rotation on epoch change
4. **Audit logging**: Log all storage operations for forensics
5. **ZK access proofs**: Enable for sensitive vaults to hide access patterns

---

## 10. Error Codes

| Code | Name | Description | Invariant |
|------|------|-------------|-----------|
| STOR_014 | StorageQuotaExceeded | Storage limit reached | - |
| STOR_015 | ItemNotFound | Item ID not found | - |
| STOR_016 | ItemTooLarge | Exceeds max item size | - |
| STOR_017 | InvalidMediaType | MIME type not allowed | - |
| STOR_018 | KeyVersionMismatch | Item encrypted with old key | INV70 |
| STOR_019 | IntegrityCheckFailed | Content hash mismatch | INV72 |

---

## 11. Changelog

| Version | Changes |
|---------|---------|
| v0.7.4 | Initial storage layer specification |

---

## 12. References

- [vaults.md](vaults.md) — Vault specification
- [crypto.md](crypto.md) — Cryptographic layer
- [AES-GCM](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf) — NIST SP 800-38D
- [HKDF](https://tools.ietf.org/html/rfc5869) — Key derivation

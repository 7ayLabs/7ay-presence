# 7ay Proof of Presence (PoP)
## Protocol Specification — Ephemeral Media
**Version:** v0.6.4
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** message-catalog.md v0.6.2, node-model.md v0.6.2, ephemeral.md v0.5

---

## 1. Purpose

This specification defines **Ephemeral Media** support for the 7ay Presence Protocol's
semantic layer.

Ephemeral Media enables nodes to share images and audio content that exists only
during the active epoch, following the same lifecycle as ephemeral data governance.

This specification defines:
- Supported media types and constraints
- Media policy schema extension
- Media lifecycle and propagation
- Message types for media exchange
- Validation rules and invariants

This version does **NOT** define:
- Storage implementation
- Encoding/compression algorithms
- Streaming protocols
- Content moderation

---

## 2. Prerequisites

### 2.1 Epoch Capability

Ephemeral Media requires epochs with `PresenceWithEphemeralData` capability:

```
epochCapability(epochId) == PresenceWithEphemeralData
```

Epochs with lower capabilities (`PresenceOnly`, `PresenceWithSignals`) do not
support media sharing.

### 2.2 Presence State

Only nodes with valid presence can share or receive media:

```
presenceState(actor, epochId) ∈ {Declared, Validated, Finalized}
```

---

## 3. Media Types

### 3.1 Supported Formats

**Image Formats:**

| Format | MIME Type | Max Size | Notes |
|--------|-----------|----------|-------|
| JPEG | image/jpeg | 5 MB | Lossy compression |
| PNG | image/png | 5 MB | Lossless, transparency |
| WebP | image/webp | 5 MB | Modern format |

**Audio Formats:**

| Format | MIME Type | Max Size | Max Duration | Notes |
|--------|-----------|----------|--------------|-------|
| MP3 | audio/mp3 | 10 MB | 60 sec | Wide compatibility |
| AAC | audio/aac | 10 MB | 60 sec | Better quality |
| Opus | audio/opus | 10 MB | 60 sec | Low latency |

### 3.2 Media Metadata

```typescript
interface MediaMetadata {
  // Unique identifier
  mediaId: bytes32;           // keccak256(sender || epochId || timestamp || contentHash)

  // Content identification
  contentHash: bytes32;       // keccak256 of media content
  contentType: string;        // MIME type
  contentSize: uint256;       // Size in bytes

  // Media-specific
  width?: uint256;            // Image width (pixels)
  height?: uint256;           // Image height (pixels)
  duration?: uint256;         // Audio duration (seconds)

  // Lifecycle
  createdAt: uint256;         // Unix timestamp
  ttl: uint256;               // Time-to-live (seconds)
  expiresAt: uint256;         // createdAt + ttl

  // Origin
  sender: Address;
  epochId: uint256;
}
```

---

## 4. Media Policy

### 4.1 Policy Schema Extension

The epoch's data policy hash can reference a media policy:

```typescript
interface MediaPolicy {
  // Version
  version: "1.0.0";

  // Allowed types
  allowedImageTypes: string[];    // e.g., ["image/jpeg", "image/png"]
  allowedAudioTypes: string[];    // e.g., ["audio/mp3", "audio/opus"]

  // Size constraints
  maxImageSize: uint256;          // Max image size in bytes
  maxAudioSize: uint256;          // Max audio size in bytes

  // Duration constraints
  maxAudioDuration: uint256;      // Max audio duration in seconds

  // Lifecycle
  maxTTL: uint256;                // Max TTL in seconds

  // Propagation
  propagationScope: PropagationScope;
}
```

### 4.2 Default Policy

If no explicit media policy is defined, defaults apply:

```json
{
  "version": "1.0.0",
  "allowedImageTypes": ["image/jpeg", "image/png", "image/webp"],
  "allowedAudioTypes": ["audio/mp3", "audio/aac", "audio/opus"],
  "maxImageSize": 5242880,
  "maxAudioSize": 10485760,
  "maxAudioDuration": 60,
  "maxTTL": 3600,
  "propagationScope": "LocalOnly"
}
```

### 4.3 Policy Validation

Media MUST comply with policy:

```
function validateMedia(media: Media, policy: MediaPolicy) → bool:
  // Type check
  if media.isImage:
    if media.contentType not in policy.allowedImageTypes:
      return false
    if media.contentSize > policy.maxImageSize:
      return false

  if media.isAudio:
    if media.contentType not in policy.allowedAudioTypes:
      return false
    if media.contentSize > policy.maxAudioSize:
      return false
    if media.duration > policy.maxAudioDuration:
      return false

  // TTL check
  if media.ttl > policy.maxTTL:
    return false

  return true
```

---

## 5. Media Messages

### 5.1 Message Type Enum Extension

```typescript
enum MessageType {
  // ... existing types (0x01-0x22)

  // Media (0x30-0x3F)
  MEDIA_ANNOUNCE = 0x30,
  MEDIA_REQUEST = 0x31,
  MEDIA_RESPONSE = 0x32,
  MEDIA_REVOKE = 0x33
}
```

### 5.2 MEDIA_ANNOUNCE (0x30)

Announce media availability to peers.

```typescript
interface MediaAnnouncePayload {
  // Media metadata
  metadata: MediaMetadata;

  // Optional preview (for images)
  thumbnail?: bytes;            // Base64 encoded thumbnail (max 10KB)

  // Availability
  available: bool;              // true = available, false = unavailable
}
```

**Validation Rules:**
- Sender MUST have valid presence in epoch
- `metadata.epochId` MUST equal message `epochId`
- `metadata.sender` MUST equal message sender
- Epoch MUST have `PresenceWithEphemeralData` capability
- Media MUST comply with epoch policy

**Usage:**
- Announce new media to peers
- Update availability status
- Share thumbnail for preview

### 5.3 MEDIA_REQUEST (0x31)

Request media content from a peer.

```typescript
interface MediaRequestPayload {
  // Target media
  mediaId: bytes32;

  // Request options
  offset?: uint256;             // For chunked transfer
  limit?: uint256;              // Max bytes to return
}
```

**Validation Rules:**
- Sender MUST have valid presence in epoch
- `mediaId` MUST reference announced media
- Epoch MUST be Active

**Usage:**
- Request full media content
- Request media chunk (for large files)

### 5.4 MEDIA_RESPONSE (0x32)

Deliver media content in response to request.

```typescript
interface MediaResponsePayload {
  // Request correlation
  requestNonce: bytes32;

  // Media identification
  mediaId: bytes32;

  // Content delivery
  content: bytes;               // Media content (or chunk)
  offset: uint256;              // Offset of this chunk
  totalSize: uint256;           // Total content size

  // Verification
  contentHash: bytes32;         // Hash of full content (not chunk)

  // Chunking info
  isComplete: bool;             // true if this completes transfer
}
```

**Validation Rules:**
- `requestNonce` MUST match pending request
- `contentHash` MUST match announced metadata
- Sender MUST be media owner
- Content MUST match hash when complete

**Usage:**
- Deliver complete media
- Deliver media chunk

### 5.5 MEDIA_REVOKE (0x33)

Revoke/delete media before TTL expires.

```typescript
interface MediaRevokePayload {
  // Target media
  mediaId: bytes32;

  // Revocation reason
  reason: RevokeReason;
}

enum RevokeReason {
  OWNER_REQUESTED = 0,          // Owner wants to delete
  POLICY_VIOLATION = 1,         // Violates policy
  EPOCH_CLOSING = 2             // Epoch transitioning
}
```

**Validation Rules:**
- Sender MUST be media owner (for OWNER_REQUESTED)
- Sender MUST be validator (for POLICY_VIOLATION)

**Usage:**
- Owner deletes media
- Validator removes policy-violating media

---

## 6. Media Lifecycle

### 6.1 Lifecycle States

```
            MEDIA_ANNOUNCE
    ─────────────────────────► Available
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
         TTL Expired         MEDIA_REVOKE         Epoch Closed
              │                    │                    │
              └────────────────────┼────────────────────┘
                                   │
                                   ▼
                              Unavailable
```

### 6.2 State Transitions

| From | Event | To |
|------|-------|-----|
| (none) | MEDIA_ANNOUNCE | Available |
| Available | TTL expires | Unavailable |
| Available | MEDIA_REVOKE | Unavailable |
| Available | Epoch closes | Unavailable |

### 6.3 Temporal Constraints

Media follows ephemeral data temporal boundaries:

```
media.available ⟹
  block.timestamp < media.expiresAt ∧
  epochState(media.epochId) == Active
```

When epoch transitions from Active:
- All media becomes immediately unavailable
- MEDIA_REQUEST returns error
- No new MEDIA_ANNOUNCE accepted

---

## 7. Propagation

### 7.1 Propagation Scope

Media propagation follows ephemeral data scope:

```typescript
enum PropagationScope {
  None = 0,           // No propagation (peer-to-peer only)
  LocalOnly = 1,      // Same epoch participants
  AdjacentSubEpochs = 2  // To sub-epochs (if supported)
}
```

### 7.2 Propagation Rules

- `None`: Media only shared via direct MEDIA_REQUEST
- `LocalOnly`: MEDIA_ANNOUNCE broadcast to epoch peers
- `AdjacentSubEpochs`: MEDIA_ANNOUNCE forwarded to sub-epochs

### 7.3 Caching

Nodes MAY cache media locally:
- Cache MUST respect TTL
- Cache MUST be cleared on epoch close
- Cache MUST be cleared on MEDIA_REVOKE

---

## 8. Invariants

### 8.1 Media Invariants

**INV27: Media Epoch Binding**
All media MUST be bound to exactly one epoch with `PresenceWithEphemeralData` capability.

```
∀ media:
  media.epochId ∈ existingEpochs ∧
  epochCapability(media.epochId) == PresenceWithEphemeralData
```

**INV28: Media Policy Compliance**
Media MUST comply with the epoch's data policy constraints.

```
∀ media, epochId:
  validateMedia(media, getPolicy(epochId)) == true
```

**INV29: Media Temporal Boundary**
Media MUST NOT be accessible after epoch transition from Active.

```
∀ media, epochId:
  epochState(epochId) != Active ⟹
    media.accessible == false
```

### 8.2 Enforcement

See `invariants.md v0.6.4` for formal definitions.

---

## 9. Error Codes

### 9.1 Media Errors

| Code | Name | Description |
|------|------|-------------|
| MEDIA_001 | InvalidMediaType | Unsupported media format |
| MEDIA_002 | MediaTooLarge | Content exceeds size limit |
| MEDIA_003 | MediaExpired | TTL has expired |
| MEDIA_004 | MediaPolicyViolation | Violates epoch media policy |
| MEDIA_005 | MediaEpochMismatch | Epoch lacks PresenceWithEphemeralData |
| MEDIA_006 | MediaNotFound | Media not available |

### 9.2 Error Priority

```
1. MediaEpochMismatch  → MEDIA_005
2. MediaPolicyViolation → MEDIA_004
3. InvalidMediaType    → MEDIA_001
4. MediaTooLarge       → MEDIA_002
5. MediaExpired        → MEDIA_003
6. MediaNotFound       → MEDIA_006
```

---

## 10. Security Considerations

### 10.1 Content Verification

Media content MUST be verified:
- Hash verification on receipt
- Size verification against metadata
- Type verification (magic bytes)

### 10.2 Resource Exhaustion

Mitigation:
- Size limits per media type
- Rate limiting per sender
- TTL enforcement
- Epoch scoping

### 10.3 Privacy

- Media is ephemeral (not persisted after epoch)
- No on-chain content storage
- Content hashes only (not content) in messages

---

## 11. Non-Goals

This specification explicitly does NOT define:

- Storage backend implementation
- Compression algorithms
- Streaming protocols
- Content delivery networks
- Content moderation/filtering
- Digital rights management

---

## 12. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.6 message envelope | Used for all media messages |
| v0.5 ephemeral data | Media follows same temporal rules |
| PresenceWithEphemeralData | Required for media support |
| Existing message types | Unchanged |

---

## 13. References

- message-catalog.md v0.6.2 — Message envelope structure
- node-model.md v0.6.2 — Node capabilities
- ephemeral.md v0.5 — Ephemeral data governance
- invariants.md v0.6.4 — Protocol invariants INV27-29
- errors.md v0.6.4 — Error catalog

---

## 14. Changelog

| Version | Changes |
|---------|---------|
| v0.6.4 | Initial ephemeral media specification |

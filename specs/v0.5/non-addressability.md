# 7ay Proof of Presence (PoP)
## Protocol Specification — Non-Addressability of Ephemeral Data
**Version:** v0.5.5 (subversion within v0.5 specification track)
**Status:** Draft
**Scope:** Specification only (no behavioral changes)
**Depends on:** epoch.md v0.2, presence.md v0.4

---

## 1. Purpose

This specification defines the **non-addressability** property of ephemeral
data in the 7ay Presence Protocol.

Non-addressability ensures that ephemeral data cannot be referenced,
linked, or retrieved outside its immediate context.

This document defines:
- What non-addressability means
- Why it is required
- Prohibited patterns
- Enforcement guidance

This document does NOT:
- Define storage implementation
- Define transport mechanisms
- Change existing protocol behavior

---

## 2. Definition

### 2.1 Non-Addressability

**Non-addressability** is the property that ephemeral data MUST NOT have
any stable identifier, URI, content hash, or reference that allows access
from outside its immediate execution context.

In formal terms:
```
FOR ALL ephemeral data d:
  NOT EXISTS identifier i:
    resolve(i) → d outside context(d)
```

### 2.2 Context Boundary

The "immediate context" is defined as:
- The active epoch
- Actors with valid presence in that epoch
- The current temporal window (epoch Active state)

---

## 3. Prohibited Patterns

### 3.1 Stable URIs

Ephemeral data MUST NOT have URIs:

```
❌ PROHIBITED:
  https://example.com/data/epoch/123/message/456
  ipfs://Qm.../ephemeral-data
  did:7ay:epoch:123:data:456
```

### 3.2 Content Hashes

Ephemeral data MUST NOT be content-addressed:

```
❌ PROHIBITED:
  data_hash = keccak256(ephemeral_content)
  reference = sha256(ephemeral_message)
```

Content hashes create stable references that survive data destruction.

### 3.3 Database Keys

Ephemeral data MUST NOT have persistent keys:

```
❌ PROHIBITED:
  database.store(epoch_123_message_456, data)
  cache.set("user:alice:epoch:123:msg:1", content)
```

### 3.4 External References

Ephemeral data MUST NOT be referenced externally:

```
❌ PROHIBITED:
  "See message 456 from epoch 123"
  citation: { epoch: 123, message: 456 }
  link: /epochs/123/data/456
```

---

## 4. Rationale

### 4.1 Ephemerality Enforcement

Non-addressability supports true ephemerality:
- If data cannot be addressed, it cannot be retrieved after destruction
- No "resurrection" via cached references
- No forensic reconstruction via identifiers

### 4.2 Privacy Protection

Non-addressability protects privacy:
- No linkability between sessions
- No correlation via stable identifiers
- No tracking through reference patterns

### 4.3 Compliance Support

Non-addressability aids compliance:
- Data cannot be subpoenaed by reference
- No audit trail of specific content
- "Right to be forgotten" is architecturally enforced

---

## 5. Permitted Patterns

### 5.1 Ephemeral Session Tokens

Temporary, non-persistent tokens are permitted:

```
✓ PERMITTED:
  session_token = random_bytes(32)  // Expires with epoch
```

These MUST be:
- Generated fresh for each session
- Destroyed when epoch terminates
- Not logged or persisted

### 5.2 In-Memory References

Transient in-memory references are permitted:

```
✓ PERMITTED:
  current_message = receive()  // No stable ID
  process(current_message)
  current_message = null  // Reference gone
```

### 5.3 Temporal Ordering

Non-identifying temporal markers are permitted:

```
✓ PERMITTED:
  sequence_number = 1, 2, 3...  // Within session only
  timestamp = now()  // Not a stable reference
```

---

## 6. Invariants

### 6.1 INV-ADDR1: No Stable Identifiers

```
FOR ALL ephemeral data d:
  NOT EXISTS stable_id(d)
```

### 6.2 INV-ADDR2: No External Resolution

```
FOR ALL references r, contexts c1, c2 where c1 ≠ c2:
  resolve(r, c1) = d IMPLIES resolve(r, c2) = undefined
```

### 6.3 INV-ADDR3: No Post-Termination Access

```
FOR ALL epochs e, data d in e:
  terminate(e) IMPLIES NOT EXISTS path_to(d)
```

---

## 7. Implementation Guidance

### 7.1 No Persistent Storage

Ephemeral data MUST NOT be written to:
- Databases (SQL, NoSQL)
- File systems
- Distributed storage (IPFS, S3)
- Blockchain or logs

### 7.2 No Logging

Ephemeral data content MUST NOT appear in:
- Application logs
- Debug output
- Metrics payloads
- Error reports

### 7.3 Memory Management

Implementations SHOULD:
- Use memory-only buffers
- Zero memory on deallocation
- Avoid swap file exposure

---

## 8. Verification

### 8.1 Static Analysis

Code review SHOULD verify:
- No persistent write operations for ephemeral data
- No hash computation on ephemeral content
- No URI generation for ephemeral data

### 8.2 Runtime Verification

Systems SHOULD verify:
- No references survive epoch termination
- No data accessible after context exit
- No stable identifiers in network traffic

---

## 9. Non-Goals

This specification explicitly does NOT define:
- Encryption requirements
- Transport security
- Key management
- Memory protection mechanisms

---

## 10. Backwards Compatibility

This specification is additive:
- Does not change existing data handling
- Applies only to new ephemeral data capability
- No migration required

---

## 11. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- model.md — Core entities

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.5.5 | Initial non-addressability specification |

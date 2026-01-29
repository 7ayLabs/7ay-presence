# 7ay Proof of Presence (PoP)
## Protocol Specification — Ephemeral Data Governance
**Version:** v0.6 (consolidated from v0.5)
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
- Encryption schemes or key management
- Network topology or routing
- SDK or client behavior
- Storage mechanisms

The Ephemeral Data Governance Layer exists solely to **govern data lifecycle**,
not to enable communication features.

Implementations MUST follow this specification to be considered compliant.

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

```solidity
enum EpochCapability {
    PresenceOnly,             // 0 - Default, v0.4 compatible
    PresenceWithSignals,      // 1 - Presence + signal emission
    PresenceWithEphemeralData // 2 - Full ephemeral data support
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
```solidity
bytes32 dataPolicyHash;  // keccak256 of full policy
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
```solidity
bytes32 dataPolicyHash;  // keccak256 of full policy JSON
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

---

## 8. Functions

### 8.1 Epoch Creation (v0.5)

```solidity
function createEpochWithCapability(
    uint256 epochId,
    uint256 startTime,
    uint256 endTime,
    EpochCapability capability,
    bytes32 dataPolicyHash
) external;
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

```solidity
function epochCapability(uint256 epochId) external view returns (EpochCapability);
function epochDataPolicyHash(uint256 epochId) external view returns (bytes32);
function supportsEphemeralData(uint256 epochId) external view returns (bool);
```

Rules:
- `epochCapability` returns `PresenceOnly` (0) for non-existent epochs
- `epochDataPolicyHash` returns `bytes32(0)` for non-existent epochs
- `supportsEphemeralData` returns `true` only if epoch exists AND capability is `PresenceWithEphemeralData`

---

## 9. Events

### 9.1 EpochCreatedV2

Emitted when an epoch is created (v0.5).

```solidity
event EpochCreatedV2(
    uint256 indexed epochId,
    uint256 startTime,
    uint256 endTime,
    EpochCapability capability,
    bytes32 dataPolicyHash
);
```

### 9.2 Legacy Compatibility

The legacy `EpochCreated` event MUST also be emitted for backwards compatibility:

```solidity
event EpochCreated(uint256 indexed epochId, uint256 startTime, uint256 endTime);
```

---

## 10. Errors

### 10.1 InvalidCapability

Raised when capability value is invalid.

```solidity
error InvalidCapability();
```

### 10.2 InvalidDataPolicyHash

Raised when data policy hash is required but not provided.

```solidity
error InvalidDataPolicyHash();
```

---

## 11. Invariants

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

### 11.3 Enforcement Model

| Invariant | Enforcement |
|-----------|-------------|
| INV14 | Off-chain (epoch state check) |
| INV15 | Off-chain (key destruction) |
| INV16 | Off-chain (access revocation) |
| INV17 | On-chain (orthogonal design) |
| INV18 | Off-chain (no permanent storage) |

---

## 12. Storage

### 12.1 On-Chain Storage

```solidity
// Existing (unchanged)
mapping(uint256 => Epoch) private _epochs;

// New (v0.5)
mapping(uint256 => EpochCapability) private _epochCapabilities;
mapping(uint256 => bytes32) private _epochDataPolicyHashes;
```

### 12.2 ABI Safety

The `Epoch` struct is NOT modified. New fields are stored in separate
mappings to maintain ABI compatibility with v0.4 clients.

---

## 13. Explicit Non-Goals

This version explicitly does NOT:

- Define messaging or chat systems
- Define transport layers or mesh networking
- Define encryption primitives
- Define client or SDK behavior
- Guarantee data delivery or reachability
- Store ephemeral data on-chain

Any such mechanisms exist outside the protocol scope.

---

## 14. Backwards Compatibility

| Aspect | Approach |
|--------|----------|
| Epoch struct | Unchanged |
| createEpoch() | Still works, defaults to PresenceOnly |
| Events | Dual emission (v0.5 + legacy) |
| PresenceRegistry | No changes required |
| ValidatorRegistry | No changes required |

---

## 15. Configuration

| Parameter | Default | Range | Mutable |
|-----------|---------|-------|---------|
| capability | PresenceOnly | 0-2 | No (immutable) |
| dataPolicyHash | bytes32(0) | any | No (immutable) |

---

## 16. Compliance

An implementation is considered compliant if and only if:
- All v0.4 invariants (1-13) hold
- All v0.5 invariants (14-18) hold
- All required events are emitted correctly
- All error conditions are handled per specification
- Epoch struct remains unchanged (ABI safety)

---

## 17. Versioning

| Version | Changes |
|---------|---------|
| v0.5 | Ephemeral Data Governance Layer |

---

## 18. References

- epoch.md v0.2 — Epoch specification
- presence.md v0.4 — Presence specification
- validator.md v0.4 — Validator specification
- errors.md v0.5 — Error catalog

---

## 19. Closing Statement

> The 7ay Presence Protocol does not transmit or store data.
> It defines the conditions under which data may temporarily exist.
> When presence ends, data ceases to exist as well.

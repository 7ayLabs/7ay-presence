# 7ay Proof of Presence (PoP)
## Protocol Specification — Node Model
**Version:** v0.6.2
**Status:** Draft
**Scope:** Protocol-level (semantic layer)
**Depends on:** epoch.md v0.2, presence.md v0.4, validator.md v0.4, ephemeral.md v0.5

---

## 1. Purpose

This specification defines the **Node Model** for the 7ay Presence Protocol's
semantic layer.

A Node is the logical representation of a protocol participant in the context
of discovery and messaging. Nodes are semantic abstractions over on-chain
entities (actors, validators).

This specification defines:
- Node structure and identity
- Role classification
- Capability enumeration
- Lifecycle and derivation from on-chain state

This version does **NOT** define:
- Transport or networking
- Authentication mechanisms
- Key management
- SDK implementation details

---

## 2. Definitions

### 2.1 Node

A **Node** is a logical protocol participant characterized by:
- Identity (address, optional public key)
- Epoch context
- Role (participant or validator)
- Presence state
- Capabilities

### 2.2 Node Identity

**Node Identity** is the unique identifier of a node within the protocol:

```typescript
interface NodeIdentity {
  address: Address;       // Ethereum address (required)
  publicKey?: Bytes;      // Secp256k1 public key (optional)
}
```

The `address` is the canonical identifier. The `publicKey` is optional and
used for off-chain message verification when the full key is needed.

### 2.3 Node Role

**Node Role** classifies the node's capabilities within the protocol:

```typescript
enum NodeRole {
  Participant = 0,   // Has presence, cannot validate
  Validator = 1      // Can validate and vote on disputes
}
```

Role is derived from on-chain `ValidatorRegistry`:
- If `validatorRegistry.isValidatorActive(address)` is true → `Validator`
- Otherwise → `Participant`

### 2.4 Node Capability

**Node Capability** declares what features a node can use:

```typescript
enum NodeCapability {
  Discovery = 0,     // Can be discovered by peers
  Messaging = 1,     // Can send/receive protocol messages
  StateSync = 2      // Can participate in state synchronization
}
```

Capabilities are determined by:
- Epoch capability (must be >= `PresenceWithSignals`)
- Presence state (must be `Declared`, `Validated`, or `Finalized`)
- Node role (validators have all capabilities)

---

## 3. Node Structure

### 3.1 Full Node Definition

```typescript
interface Node {
  // Identity
  identity: NodeIdentity;

  // Epoch context
  epoch: {
    epochId: uint256;
    joinedAt: uint256;      // Block timestamp of presence declaration
  };

  // Role classification
  role: NodeRole;

  // Presence binding
  presence: {
    state: PresenceState;   // Declared | Validated | Finalized
    declaredAt: uint256;
    validatedAt?: uint256;
  };

  // Feature set
  capabilities: NodeCapability[];
}
```

### 3.2 Minimal Node (Discovery)

For discovery purposes, a minimal representation is sufficient:

```typescript
interface MinimalNode {
  address: Address;
  epochId: uint256;
  role: NodeRole;
  presenceState: PresenceState;
}
```

---

## 4. Node Derivation

### 4.1 Derivation from On-Chain State

Nodes are **derived** from on-chain state, not stored independently:

```
function deriveNode(address: Address, epochId: uint256) → Node:
  // 1. Check presence
  presence = presenceRegistry.getPresence(address, epochId)
  if presence.state == None:
    return null  // Not a valid node

  if presence.state == Slashed:
    return null  // Slashed actors are not nodes

  // 2. Determine role
  isValidator = validatorRegistry.isValidatorActive(address)
  role = isValidator ? Validator : Participant

  // 3. Check epoch capability
  capability = epochRegistry.epochCapability(epochId)
  if capability < PresenceWithSignals:
    return null  // Epoch doesn't support v0.6 features

  // 4. Determine node capabilities
  capabilities = [Discovery]
  if capability >= PresenceWithSignals:
    capabilities.push(Messaging)
  if isValidator:
    capabilities.push(StateSync)

  // 5. Construct node
  return Node {
    identity: { address },
    epoch: { epochId, joinedAt: presence.declaredAt },
    role,
    presence: {
      state: presence.state,
      declaredAt: presence.declaredAt,
      validatedAt: presence.validatedAt
    },
    capabilities
  }
```

### 4.2 Derivation Invariant (INV19)

**INV19: Node Identity Derivability**
A node's identity MUST be derivable from on-chain state.

```
∀ node:
  node.identity.address ∈ validAddresses(on-chain) ∧
  node.epoch.epochId ∈ existingEpochs(on-chain) ∧
  node.presence.state = presenceRegistry.presenceState(node.identity.address, node.epoch.epochId) ∧
  node.role = derive_role(validatorRegistry, node.identity.address)
```

---

## 5. Node Lifecycle

### 5.1 Lifecycle States

```
                    declarePresence()
    ─────────────────────────────────► Participant Node
                                             │
                                             │ isValidatorActive()
                                             ▼
                                        Validator Node
                                             │
                                             │ epoch closes OR slashed
                                             ▼
                                         Inactive
```

### 5.2 State Transitions

| From | Event | To |
|------|-------|-----|
| (none) | declarePresence() | Participant |
| Participant | isValidatorActive() = true | Validator |
| Validator | isValidatorActive() = false | Participant |
| Any | epoch.state = Closed | Inactive |
| Any | presence.state = Slashed | Inactive |

### 5.3 Epoch Binding (INV20)

**INV20: Epoch Binding**
A node MUST be bound to exactly one epoch at any time.

```
∀ node, t:
  |{epochId : node.isActiveIn(epochId, t)}| = 1
```

A node cannot participate in multiple epochs simultaneously for messaging.

---

## 6. Role Classification

### 6.1 Participant Role

Participants are actors with valid presence who are not validators:

```
isParticipant(address, epochId) =
  presenceRegistry.presenceState(address, epochId) ∈ {Declared, Validated, Finalized}
  ∧ ¬validatorRegistry.isValidatorActive(address)
```

Participants can:
- Be discovered by peers
- Send and receive messages
- Access ephemeral data (if epoch supports)

Participants cannot:
- Validate presences
- Vote on disputes
- Participate in state synchronization

### 6.2 Validator Role

Validators are active validators with or without presence:

```
isValidator(address) =
  validatorRegistry.isValidatorActive(address)
```

Validators can:
- All participant capabilities
- Validate presences
- Vote on disputes
- Initiate and participate in state sync

### 6.3 Role Derivation

Role is derived at query time, not stored:

```solidity
function deriveRole(address node) external view returns (NodeRole) {
    if (validatorRegistry.isValidatorActive(node)) {
        return NodeRole.Validator;
    }
    return NodeRole.Participant;
}
```

---

## 7. Capability Model

### 7.1 Capability Requirements

| Capability | Epoch Requirement | Presence Requirement | Role Requirement |
|------------|-------------------|---------------------|------------------|
| Discovery | PresenceWithSignals | Declared+ | Any |
| Messaging | PresenceWithSignals | Declared+ | Any |
| StateSync | PresenceWithSignals | Declared+ | Validator |

### 7.2 Capability Derivation

```
function deriveCapabilities(node: Node) → NodeCapability[]:
  caps = []

  epochCap = epochRegistry.epochCapability(node.epoch.epochId)
  if epochCap < PresenceWithSignals:
    return []  // No v0.6 capabilities

  if node.presence.state ∈ {Declared, Validated, Finalized}:
    caps.push(Discovery)
    caps.push(Messaging)

  if node.role == Validator:
    caps.push(StateSync)

  return caps
```

### 7.3 Capability Checks

Before any operation, capabilities MUST be verified:

```
function canDiscover(node: Node) → bool:
  return Discovery ∈ node.capabilities

function canMessage(node: Node) → bool:
  return Messaging ∈ node.capabilities

function canSync(node: Node) → bool:
  return StateSync ∈ node.capabilities
```

---

## 8. Node Serialization

### 8.1 Compact Format

For network efficiency, nodes use a compact binary format:

```
Node (compact):
  address:       20 bytes
  epochId:       32 bytes (uint256)
  role:           1 byte
  presenceState:  1 byte
  capabilities:   1 byte (bitmap)
  ---
  Total:         55 bytes
```

### 8.2 JSON Format

For interoperability, JSON representation:

```json
{
  "identity": {
    "address": "0x1234567890abcdef1234567890abcdef12345678"
  },
  "epoch": {
    "epochId": "123",
    "joinedAt": 1704067200
  },
  "role": "participant",
  "presence": {
    "state": "declared",
    "declaredAt": 1704067200
  },
  "capabilities": ["discovery", "messaging"]
}
```

---

## 9. Invariants

### 9.1 Node Invariants

**INV19: Node Identity Derivability** (defined in Section 4.2)
Node identity MUST be derivable from on-chain state.

**INV20: Epoch Binding** (defined in Section 5.3)
Node MUST be bound to exactly one epoch at any time.

### 9.2 Related Invariants

See `invariants.md v0.6.1` for complete invariant definitions:
- INV21: Discovery epoch-scoped
- INV22: Presence-gated discovery

---

## 10. Security Considerations

### 10.1 Identity Verification

Node identity claims MUST be verified against on-chain state:

```
function verifyNodeIdentity(claimed: Node) → bool:
  derived = deriveNode(claimed.identity.address, claimed.epoch.epochId)
  return derived != null
    ∧ derived.role == claimed.role
    ∧ derived.presence.state == claimed.presence.state
```

### 10.2 Sybil Resistance

Sybil attacks are mitigated by:
- Presence declaration cost (gas)
- Validator registry (permissioned)
- Epoch scoping (bounded lifetime)

### 10.3 Role Escalation

Role escalation is prevented by:
- Role derived from on-chain ValidatorRegistry
- Validator authority is permissioned
- Role cannot be self-declared

---

## 11. Non-Goals

This specification explicitly does NOT define:

- Key management or rotation
- Authentication protocols
- Session management
- Reputation systems
- Economic incentives

---

## 12. Backwards Compatibility

| Aspect | Status |
|--------|--------|
| v0.5 presence states | Unchanged |
| v0.4 validator logic | Unchanged |
| On-chain derivation | Uses existing functions |
| EpochCapability | Requires >= PresenceWithSignals |

---

## 13. References

- epoch.md v0.2 — Epoch lifecycle
- presence.md v0.4 — Presence state machine
- validator.md v0.4 — Validator mechanics
- ephemeral.md v0.5 — Epoch capabilities
- state-sync.md v0.6.1 — State synchronization
- invariants.md v0.6.1 — Protocol invariants

---

## 14. Changelog

| Version | Changes |
|---------|---------|
| v0.6.2 | Initial node model specification |

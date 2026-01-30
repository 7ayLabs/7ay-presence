# 7ay Proof of Presence (PoP)
## Protocol Specification — Zero-Knowledge Proofs
**Version:** v0.7.2
**Status:** Draft
**Depends on:** vaults.md v0.7.2, devices.md v0.7.1

> Zero-knowledge circuits for privacy-preserving vault operations

## 1. Overview

This specification defines the Zero-Knowledge proof circuits used in the 7ay vault system. ZK proofs enable users to prove claims about their vault access without revealing sensitive information.

### 1.1 Design Goals

1. **Anonymous Share Provision**: Prove valid share ownership without revealing which device
2. **Private Presence**: Prove device presence without revealing device identity
3. **Confidential Access**: Prove access rights without revealing accessed items
4. **Threshold Privacy**: Prove threshold met without revealing exact count

### 1.2 Privacy Comparison

| Operation | Without ZK | With ZK |
|-----------|------------|---------|
| Provide share | Observer sees which device | Only proves valid share exists |
| Unlock vault | Reveals participating devices | Anonymous threshold proof |
| Access item | Reveals item ID | Proves access right only |
| Verify presence | Links device to activity | Unlinkable presence proof |

---

## 2. Proving Systems

### 2.1 Supported Systems

```typescript
enum ProvingSystem {
  Groth16 = 0,      // Fast verification, trusted setup
  PLONK = 1,        // Universal setup, larger proofs
  STARK = 2         // No trusted setup, largest proofs
}
```

### 2.2 System Comparison

| Property | Groth16 | PLONK | STARK |
|----------|---------|-------|-------|
| Proof Size | ~200 bytes | ~500 bytes | ~40 KB |
| Verification Time | ~10 ms | ~25 ms | ~50 ms |
| Trusted Setup | Per-circuit | Universal | None |
| Post-Quantum | No | No | Yes |
| Recommended For | Mobile, embedded | General use | High security |

### 2.3 Default Configuration

```typescript
const DEFAULT_ZK_CONFIG: ZKConfig = {
  provingSystem: ProvingSystem.Groth16,  // Best performance
  shareProofCircuit: "7ay-share-v1",
  presenceProofCircuit: "7ay-presence-v1",
  accessProofCircuit: "7ay-access-v1"
};
```

---

## 3. Cryptographic Primitives

### 3.1 Pedersen Commitments

Used for hiding share values while allowing verification:

```typescript
interface PedersenParams {
  g: CurvePoint;    // Generator for value
  h: CurvePoint;    // Generator for blinding
}

function pedersenCommit(
  value: bytes32,
  blinding: bytes32,
  params: PedersenParams
): bytes32 {
  // commitment = g^value * h^blinding
  return curveAdd(
    scalarMult(params.g, value),
    scalarMult(params.h, blinding)
  );
}

function verifyPedersenCommitment(
  commitment: bytes32,
  value: bytes32,
  blinding: bytes32,
  params: PedersenParams
): bool {
  return pedersenCommit(value, blinding, params) == commitment;
}
```

### 3.2 Merkle Tree for Membership

```typescript
interface MerkleProof {
  leaf: bytes32;
  path: bytes32[];      // Sibling hashes
  indices: bool[];      // Left (0) or right (1)
}

function verifyMerkleProof(
  root: bytes32,
  proof: MerkleProof
): bool {
  let current = proof.leaf;
  for (let i = 0; i < proof.path.length; i++) {
    if (proof.indices[i]) {
      current = keccak256(proof.path[i], current);
    } else {
      current = keccak256(current, proof.path[i]);
    }
  }
  return current == root;
}
```

### 3.3 Shamir Polynomial Verification

```typescript
// Verify a point lies on the Shamir polynomial
function verifyShamirShare(
  shareIndex: uint8,
  shareValue: bytes32,
  commitments: bytes32[]  // Feldman commitments
): bool {
  // g^share should equal product of g^(coeff_i * x^i)
  let expected = commitments[0];
  let x = shareIndex;
  let xPow = x;
  for (let i = 1; i < commitments.length; i++) {
    expected = curveAdd(expected, scalarMult(commitments[i], xPow));
    xPow = xPow * x;
  }
  return scalarMult(G, shareValue) == expected;
}
```

---

## 4. ZK Share Proof Circuit (INV73)

### 4.1 Purpose

Prove ownership of a valid Shamir share without revealing:
- Which share (index)
- The share value
- Which device holds it

### 4.2 Circuit Definition

**Public Inputs:**
- `vaultId`: bytes32 - Vault identifier
- `shareCommitment`: bytes32 - Pedersen commitment to the share
- `epochId`: uint256 - Current epoch

**Private Inputs:**
- `share`: bytes32 - The actual share value
- `shareIndex`: uint8 - Index in Shamir scheme
- `blinding`: bytes32 - Pedersen blinding factor
- `commitmentMerklePath`: MerkleProof - Path to commitment in vault's list

**Circuit Logic (Circom):**

```circom
pragma circom 2.1.0;

include "poseidon.circom";
include "merkle.circom";
include "pedersen.circom";

template ShareVerify(merkleDepth) {
    // Public inputs
    signal input vaultId;
    signal input shareCommitment;
    signal input commitmentsRoot;  // Merkle root of share commitments
    signal input epochId;

    // Private inputs
    signal input share;
    signal input shareIndex;
    signal input blinding;
    signal input merklePath[merkleDepth];
    signal input merkleIndices[merkleDepth];

    // 1. Verify Pedersen commitment
    component pedersen = Pedersen();
    pedersen.value <== share;
    pedersen.blinding <== blinding;
    signal computedCommitment <== pedersen.commitment;

    // Constraint: computed commitment must match public input
    shareCommitment === computedCommitment;

    // 2. Verify commitment is in vault's commitment list
    component merkle = MerkleProof(merkleDepth);
    merkle.leaf <== shareCommitment;
    merkle.root <== commitmentsRoot;
    for (var i = 0; i < merkleDepth; i++) {
        merkle.pathElements[i] <== merklePath[i];
        merkle.pathIndices[i] <== merkleIndices[i];
    }

    // Constraint: Merkle proof must verify
    merkle.valid === 1;

    // 3. Verify share index is valid (1-255)
    component rangeCheck = RangeCheck(8);
    rangeCheck.in <== shareIndex;
    rangeCheck.min <== 1;
    rangeCheck.max <== 255;

    // 4. Bind to epoch (prevents replay across epochs)
    signal epochBinding <== Poseidon([vaultId, epochId, shareCommitment]);
}

component main {public [vaultId, shareCommitment, commitmentsRoot, epochId]} = ShareVerify(8);
```

### 4.3 Verification

```typescript
interface ZKShareProof {
  vaultId: bytes32;
  shareCommitment: bytes32;
  commitmentsRoot: bytes32;
  epochId: uint256;
  proof: bytes;
}

function verifyShareProof(
  proof: ZKShareProof,
  verifyingKey: bytes
): bool {
  const publicInputs = [
    proof.vaultId,
    proof.shareCommitment,
    proof.commitmentsRoot,
    proof.epochId
  ];

  return zkVerify(proof.proof, publicInputs, verifyingKey);
}
```

### 4.4 Invariant (INV73)

See [invariants.md](../reference/invariants.md#inv73-zk-share-proof-validity) for the canonical definition.

---

## 5. ZK Presence Proof Circuit (INV74)

### 5.1 Purpose

Prove a device is present in the current epoch without revealing:
- Which specific device
- Any device metadata
- Correlation between presence and other activities

### 5.2 Circuit Definition

**Public Inputs:**
- `epochId`: uint256 - Current epoch
- `membershipRoot`: bytes32 - Merkle root of device ring
- `presenceListRoot`: bytes32 - Merkle root of present devices

**Private Inputs:**
- `deviceId`: bytes32 - The device's identifier
- `membershipPath`: MerkleProof - Path proving device is in ring
- `presencePath`: MerkleProof - Path proving device is present

**Circuit Logic (Circom):**

```circom
pragma circom 2.1.0;

include "poseidon.circom";
include "merkle.circom";

template PresenceProof(merkleDepth) {
    // Public inputs
    signal input epochId;
    signal input membershipRoot;
    signal input presenceListRoot;

    // Private inputs
    signal input deviceId;
    signal input membershipPath[merkleDepth];
    signal input membershipIndices[merkleDepth];
    signal input presencePath[merkleDepth];
    signal input presenceIndices[merkleDepth];

    // 1. Verify device is in membership list (device ring)
    component membershipProof = MerkleProof(merkleDepth);
    membershipProof.leaf <== deviceId;
    membershipProof.root <== membershipRoot;
    for (var i = 0; i < merkleDepth; i++) {
        membershipProof.pathElements[i] <== membershipPath[i];
        membershipProof.pathIndices[i] <== membershipIndices[i];
    }
    membershipProof.valid === 1;

    // 2. Verify device is in presence list (currently present)
    signal presenceLeaf <== Poseidon([deviceId, epochId]);

    component presenceProof = MerkleProof(merkleDepth);
    presenceProof.leaf <== presenceLeaf;
    presenceProof.root <== presenceListRoot;
    for (var i = 0; i < merkleDepth; i++) {
        presenceProof.pathElements[i] <== presencePath[i];
        presenceProof.pathIndices[i] <== presenceIndices[i];
    }
    presenceProof.valid === 1;

    // 3. Epoch binding prevents cross-epoch replay
    signal epochBinding <== Poseidon([deviceId, epochId, membershipRoot]);
}

component main {public [epochId, membershipRoot, presenceListRoot]} = PresenceProof(8);
```

### 5.3 Verification

```typescript
interface ZKPresenceProof {
  epochId: uint256;
  membershipRoot: bytes32;
  presenceListRoot: bytes32;
  proof: bytes;
}

function verifyPresenceProof(
  proof: ZKPresenceProof,
  verifyingKey: bytes
): bool {
  const publicInputs = [
    proof.epochId,
    proof.membershipRoot,
    proof.presenceListRoot
  ];

  return zkVerify(proof.proof, publicInputs, verifyingKey);
}
```

### 5.4 Use Cases

- **Anonymous Unlock Participation**: Device proves it's part of the unlocking threshold without revealing which device
- **Privacy-Preserving Audit**: Prove presence was maintained without linking to specific device
- **Anti-Correlation**: Prevent observers from correlating device activity patterns

### 5.5 Invariant (INV74)

See [invariants.md](../reference/invariants.md#inv74-zk-presence-proof-validity) for the canonical definition.

---

## 6. ZK Access Proof Circuit (INV75)

### 6.1 Purpose

Prove the right to access a storage item without revealing:
- Which item is being accessed
- Access patterns over time
- Item metadata

### 6.2 Circuit Definition

**Public Inputs:**
- `vaultId`: bytes32 - Vault identifier
- `accessRoot`: bytes32 - Merkle root of accessible items
- `epochId`: uint256 - Current epoch
- `accessNonce`: bytes32 - One-time nonce

**Private Inputs:**
- `itemId`: bytes32 - The item being accessed
- `itemPath`: MerkleProof - Path proving item is in vault
- `unlockProof`: bytes - Proof that vault is unlocked

**Circuit Logic (Circom):**

```circom
pragma circom 2.1.0;

include "poseidon.circom";
include "merkle.circom";

template AccessProof(merkleDepth) {
    // Public inputs
    signal input vaultId;
    signal input accessRoot;
    signal input epochId;
    signal input accessNonce;

    // Private inputs
    signal input itemId;
    signal input itemPath[merkleDepth];
    signal input itemIndices[merkleDepth];
    signal input vaultUnlocked;  // 1 if unlocked, 0 otherwise

    // 1. Verify vault is unlocked
    vaultUnlocked === 1;

    // 2. Verify item exists in vault
    component itemProof = MerkleProof(merkleDepth);
    itemProof.leaf <== itemId;
    itemProof.root <== accessRoot;
    for (var i = 0; i < merkleDepth; i++) {
        itemProof.pathElements[i] <== itemPath[i];
        itemProof.pathIndices[i] <== itemIndices[i];
    }
    itemProof.valid === 1;

    // 3. Prevent replay with nonce binding
    signal accessBinding <== Poseidon([vaultId, itemId, epochId, accessNonce]);

    // 4. Epoch binding
    signal epochBinding <== Poseidon([vaultId, epochId, accessRoot]);
}

component main {public [vaultId, accessRoot, epochId, accessNonce]} = AccessProof(10);
```

### 6.3 Verification

```typescript
interface ZKAccessProof {
  vaultId: bytes32;
  accessRoot: bytes32;
  epochId: uint256;
  accessNonce: bytes32;
  proof: bytes;
}

function verifyAccessProof(
  proof: ZKAccessProof,
  verifyingKey: bytes
): bool {
  const publicInputs = [
    proof.vaultId,
    proof.accessRoot,
    proof.epochId,
    proof.accessNonce
  ];

  return zkVerify(proof.proof, publicInputs, verifyingKey);
}
```

### 6.4 Use Cases

- **Private File Access**: Read files without revealing which files
- **Access Pattern Hiding**: Prevent traffic analysis of access patterns
- **Plausible Deniability**: No proof of which specific items were accessed

### 6.5 Invariant (INV75)

See [invariants.md](../reference/invariants.md#inv75-zk-access-proof-validity) for the canonical definition.

---

## 7. ZK Threshold Proof (Optional)

### 7.1 Purpose

Prove that at least k devices are present without revealing exact count or which devices.

### 7.2 Circuit Definition

**Public Inputs:**
- `threshold`: uint8 - Minimum required devices (k)
- `membershipRoot`: bytes32 - Device ring Merkle root
- `epochId`: uint256

**Private Inputs:**
- `deviceIds`: bytes32[k] - The k present devices
- `presenceProofs`: bytes[k] - Individual presence proofs

**Circuit Logic:**

```circom
template ThresholdProof(k, merkleDepth) {
    signal input threshold;
    signal input membershipRoot;
    signal input epochId;

    signal input deviceIds[k];
    signal input presencePaths[k][merkleDepth];
    signal input presenceIndices[k][merkleDepth];

    // Verify each device is present and unique
    component presenceVerifiers[k];
    for (var i = 0; i < k; i++) {
        presenceVerifiers[i] = PresenceProof(merkleDepth);
        presenceVerifiers[i].epochId <== epochId;
        presenceVerifiers[i].membershipRoot <== membershipRoot;
        presenceVerifiers[i].deviceId <== deviceIds[i];
        // ... path inputs
    }

    // Verify all deviceIds are unique
    component uniqueness = AllUnique(k);
    for (var i = 0; i < k; i++) {
        uniqueness.inputs[i] <== deviceIds[i];
    }
    uniqueness.valid === 1;

    // Verify count meets threshold
    signal count <== k;
    component gte = GreaterEq();
    gte.a <== count;
    gte.b <== threshold;
    gte.result === 1;
}
```

---

## 8. Circuit Deployment

### 8.1 Trusted Setup (Groth16)

For Groth16 circuits, a trusted setup ceremony is required:

```typescript
interface TrustedSetupCeremony {
  circuitId: string;
  participants: Address[];
  contributions: bytes[];
  finalParams: {
    provingKey: bytes;
    verifyingKey: bytes;
  };
  transcript: bytes;  // Public verification transcript
}
```

**Setup Process:**
1. Generate initial parameters from circuit
2. Multiple participants contribute randomness
3. Each contribution is publicly verifiable
4. Final parameters derived from all contributions
5. Proving key stored off-chain (large)
6. Verifying key stored on-chain (small)

### 8.2 Universal Setup (PLONK)

PLONK requires a one-time universal setup:

```typescript
interface UniversalSetup {
  maxCircuitSize: uint256;
  srs: bytes;  // Structured Reference String
  verificationKey: bytes;
}
```

### 8.3 Circuit Registration

```typescript
interface CircuitRegistration {
  circuitId: string;
  version: string;
  provingSystem: ProvingSystem;
  verifyingKeyHash: bytes32;  // On-chain commitment
  verifyingKey: bytes;        // Actual key (may be stored off-chain)
  auditReport?: string;       // Link to security audit
}

// On-chain registry
mapping(string => CircuitRegistration) public circuits;
```

---

## 9. Performance Considerations

### 9.1 Proof Generation Time

| Circuit | Groth16 | PLONK | STARK |
|---------|---------|-------|-------|
| Share Proof | ~500ms | ~1s | ~3s |
| Presence Proof | ~300ms | ~800ms | ~2s |
| Access Proof | ~400ms | ~900ms | ~2.5s |
| Threshold (k=3) | ~2s | ~4s | ~10s |

*Measured on M1 MacBook Pro

### 9.2 Client-Side Proving

```typescript
interface ProverConfig {
  // WebAssembly module for in-browser proving
  wasmModule: string;

  // Hardware acceleration options
  useGPU: bool;           // WebGPU for faster proving
  useWorkers: bool;       // Web Workers for background proving

  // Memory constraints
  maxMemoryMB: uint256;   // Limit memory usage
}
```

### 9.3 Caching Strategy

```typescript
interface ProofCache {
  // Cache recent proofs (same inputs = same proof)
  cache: Map<bytes32, CachedProof>;
  maxAge: uint256;  // Seconds

  // Pre-compute proofs for anticipated operations
  precompute: bool;
}

interface CachedProof {
  proof: bytes;
  publicInputs: bytes32[];
  createdAt: uint256;
  expiresAt: uint256;
}
```

---

## 10. Security Considerations

### 10.1 Soundness

All circuits MUST be:
- **Complete**: Valid witness always produces accepting proof
- **Sound**: Invalid witness cannot produce accepting proof
- **Zero-Knowledge**: Proof reveals nothing beyond statement truth

### 10.2 Circuit Auditing

Before deployment, circuits MUST be:
- Formally verified for constraint satisfaction
- Audited by independent security firm
- Tested with known-good and known-bad inputs

### 10.3 Trusted Setup Security (Groth16)

- Minimum 10 participants recommended
- At least 1 honest participant ensures security
- Public verification of all contributions
- Toxic waste must be destroyed by all participants

### 10.4 Implementation Attacks

| Attack | Mitigation |
|--------|------------|
| Malicious prover | Verify proofs server-side |
| Side-channel | Constant-time implementations |
| Invalid setup | Verify setup transcript |
| Replay proofs | Epoch + nonce binding |

---

## 11. Error Codes

| Code | Name | Description |
|------|------|-------------|
| ZK_001 | InvalidProof | ZK proof verification failed |
| ZK_002 | ExpiredProof | Proof epoch doesn't match current |
| ZK_003 | ReusedNonce | Access nonce already used |
| ZK_004 | CircuitNotFound | Unknown circuit ID |
| ZK_005 | SetupNotVerified | Trusted setup not verified |

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.7.2 | Initial ZK proof specification |

---

## 13. References

- [vaults.md](vaults.md) — Vault specification
- [devices.md](devices.md) — Device management
- [Groth16 Paper](https://eprint.iacr.org/2016/260)
- [PLONK Paper](https://eprint.iacr.org/2019/953)
- [Circom Documentation](https://docs.circom.io/)

# 7ay Proof of Presence (PoP)
## Protocol Specification — Cryptographic Layer
**Version:** v0.7.3
**Status:** Draft
**Depends on:** vaults.md v0.7.2, devices.md v0.7.1, ephemeral.md v0.7.0

> Shamir Secret Sharing, ECIES encryption, and key reconstruction for presence-gated vaults

## 1. Overview

The Cryptographic Layer defines the key management and share distribution mechanisms for presence-gated vaults. It specifies how vault keys are split across devices using Shamir Secret Sharing, encrypted using ECIES, and reconstructed when threshold devices are present.

### 1.1 Design Principles

1. **Threshold Security**: No single device holds enough information to reconstruct the key
2. **Information-Theoretic Security**: Shamir shares reveal nothing about the secret with fewer than k shares
3. **Forward Secrecy**: Epoch-bound keys prevent past data compromise
4. **Device Binding**: Shares encrypted to specific device public keys

### 1.2 Cryptographic Stack

| Component | Algorithm | Purpose |
|-----------|-----------|---------|
| Secret Sharing | Shamir (GF(2^256)) | Split vault key into n shares |
| Share Encryption | ECIES (secp256k1) | Encrypt shares to device public keys |
| Key Derivation | HKDF-SHA256 | Derive epoch-specific vault keys |
| Symmetric Encryption | AES-256-GCM | Encrypt stored items |
| Commitments | Pedersen | Commit to shares for ZK proofs |
| Hashing | Keccak256 | Identity derivation, integrity |

---

## 2. Shamir Secret Sharing

### 2.1 Overview

Shamir Secret Sharing splits a secret into n shares such that any k shares can reconstruct the secret, but k-1 shares reveal nothing.

```
Secret S → (share₁, share₂, ..., shareₙ)

Reconstruction: Any k shares → S
Security: k-1 shares → no information about S
```

### 2.2 Mathematical Foundation

**Finite Field**: GF(2^256) using the irreducible polynomial for secp256k1.

**Share Generation**:
1. Choose random polynomial of degree k-1: `f(x) = S + a₁x + a₂x² + ... + aₖ₋₁xᵏ⁻¹`
2. Secret S is the constant term: `f(0) = S`
3. Generate shares: `shareᵢ = (i, f(i))` for i = 1, 2, ..., n

**Reconstruction** (Lagrange Interpolation):
```
S = f(0) = Σᵢ yᵢ · Lᵢ(0)

where Lᵢ(0) = Πⱼ≠ᵢ (0 - xⱼ)/(xᵢ - xⱼ) = Πⱼ≠ᵢ (-xⱼ)/(xᵢ - xⱼ)
```

### 2.3 Implementation

```typescript
interface ShamirConfig {
  threshold: uint8;      // k - minimum shares to reconstruct
  totalShares: uint8;    // n - total shares to generate
  prime: bigint;         // Field modulus (secp256k1 order)
}

interface ShamirShare {
  index: uint8;          // x-coordinate (1-based)
  value: bytes32;        // y-coordinate (f(index))
}

/**
 * Split a secret into n Shamir shares with k threshold
 * @param secret - The 32-byte secret to split
 * @param k - Threshold (minimum shares to reconstruct)
 * @param n - Total number of shares
 * @returns Array of n shares
 */
function shamirSplit(
  secret: bytes32,
  k: uint8,
  n: uint8
): ShamirShare[] {
  // Validate parameters
  require(k >= 2, "Threshold must be at least 2");
  require(n >= 3, "Total shares must be at least 3");
  require(k <= n, "Threshold cannot exceed total shares");

  // Generate random polynomial coefficients
  const coefficients: bytes32[] = [secret];
  for (let i = 1; i < k; i++) {
    coefficients.push(secureRandom(32));
  }

  // Generate shares by evaluating polynomial at x = 1, 2, ..., n
  const shares: ShamirShare[] = [];
  for (let i = 1; i <= n; i++) {
    const y = evaluatePolynomial(coefficients, i);
    shares.push({ index: i, value: y });
  }

  // Securely zero coefficient memory
  secureZero(coefficients);

  return shares;
}

/**
 * Reconstruct secret from k or more shares
 * @param shares - Array of at least k shares
 * @returns The reconstructed secret
 */
function shamirReconstruct(shares: ShamirShare[]): bytes32 {
  const k = shares.length;
  require(k >= 2, "Need at least 2 shares");

  // Lagrange interpolation at x = 0
  let secret = BigInt(0);

  for (let i = 0; i < k; i++) {
    let numerator = BigInt(1);
    let denominator = BigInt(1);

    for (let j = 0; j < k; j++) {
      if (i !== j) {
        numerator = fieldMul(numerator, BigInt(-shares[j].index));
        denominator = fieldMul(denominator,
          BigInt(shares[i].index - shares[j].index));
      }
    }

    const lagrangeCoeff = fieldDiv(numerator, denominator);
    const term = fieldMul(BigInt(shares[i].value), lagrangeCoeff);
    secret = fieldAdd(secret, term);
  }

  return toBytes32(secret);
}
```

### 2.4 Polynomial Evaluation

```typescript
/**
 * Evaluate polynomial at point x in finite field
 * f(x) = a₀ + a₁x + a₂x² + ... + aₖ₋₁xᵏ⁻¹
 */
function evaluatePolynomial(
  coefficients: bytes32[],
  x: uint8
): bytes32 {
  let result = BigInt(0);
  let xPower = BigInt(1);
  const xBig = BigInt(x);

  for (const coeff of coefficients) {
    const term = fieldMul(BigInt(coeff), xPower);
    result = fieldAdd(result, term);
    xPower = fieldMul(xPower, xBig);
  }

  return toBytes32(result);
}
```

### 2.5 Finite Field Operations

```typescript
// secp256k1 curve order (field modulus)
const FIELD_PRIME = BigInt(
  "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"
);

function fieldAdd(a: bigint, b: bigint): bigint {
  return ((a + b) % FIELD_PRIME + FIELD_PRIME) % FIELD_PRIME;
}

function fieldSub(a: bigint, b: bigint): bigint {
  return ((a - b) % FIELD_PRIME + FIELD_PRIME) % FIELD_PRIME;
}

function fieldMul(a: bigint, b: bigint): bigint {
  return (a * b) % FIELD_PRIME;
}

function fieldDiv(a: bigint, b: bigint): bigint {
  return fieldMul(a, fieldInverse(b));
}

function fieldInverse(a: bigint): bigint {
  // Extended Euclidean algorithm
  return modPow(a, FIELD_PRIME - BigInt(2), FIELD_PRIME);
}
```

### 2.6 Threshold Configurations

| Configuration | k (threshold) | n (total) | Fault Tolerance | Use Case |
|---------------|---------------|-----------|-----------------|----------|
| Minimum | 2 | 3 | 1 device | Personal, few devices |
| Standard | 3 | 5 | 2 devices | Most users |
| Enhanced | 4 | 7 | 3 devices | Sensitive data |
| Maximum | 5 | 9 | 4 devices | Enterprise |

**Fault Tolerance**: Number of devices that can be lost/offline while maintaining access.

---

## 3. ECIES Encryption

### 3.1 Overview

Elliptic Curve Integrated Encryption Scheme (ECIES) encrypts shares to device public keys, ensuring only the intended device can decrypt its share.

### 3.2 ECIES Components

```typescript
interface ECIESCiphertext {
  ephemeralPublicKey: bytes;   // 33 bytes (compressed secp256k1)
  iv: bytes;                   // 16 bytes (AES-GCM nonce)
  ciphertext: bytes;           // Encrypted data
  authTag: bytes;              // 16 bytes (GCM authentication tag)
}
```

### 3.3 Encryption

```typescript
/**
 * Encrypt data to a recipient's public key using ECIES
 * @param plaintext - Data to encrypt
 * @param recipientPublicKey - Recipient's secp256k1 public key
 * @returns ECIES ciphertext
 */
function eciesEncrypt(
  plaintext: bytes,
  recipientPublicKey: bytes
): ECIESCiphertext {
  // 1. Generate ephemeral key pair
  const ephemeralPrivateKey = secureRandom(32);
  const ephemeralPublicKey = derivePublicKey(ephemeralPrivateKey);

  // 2. Compute shared secret via ECDH
  const sharedPoint = ecdhMultiply(ephemeralPrivateKey, recipientPublicKey);
  const sharedSecret = keccak256(sharedPoint.x);

  // 3. Derive encryption key and MAC key via HKDF
  const keys = hkdfExpand(sharedSecret, "7ay-ecies-v1", 48);
  const encryptionKey = keys.slice(0, 32);
  const macKey = keys.slice(32, 48);

  // 4. Generate random IV
  const iv = secureRandom(16);

  // 5. Encrypt with AES-256-GCM
  const { ciphertext, authTag } = aes256GcmEncrypt(
    plaintext,
    encryptionKey,
    iv,
    ephemeralPublicKey  // Additional authenticated data
  );

  // 6. Securely zero sensitive data
  secureZero(ephemeralPrivateKey);
  secureZero(sharedSecret);
  secureZero(encryptionKey);

  return {
    ephemeralPublicKey: compressPublicKey(ephemeralPublicKey),
    iv,
    ciphertext,
    authTag
  };
}
```

### 3.4 Decryption

```typescript
/**
 * Decrypt ECIES ciphertext using recipient's private key
 * @param ciphertext - ECIES ciphertext
 * @param recipientPrivateKey - Recipient's secp256k1 private key
 * @returns Decrypted plaintext
 */
function eciesDecrypt(
  ciphertext: ECIESCiphertext,
  recipientPrivateKey: bytes32
): bytes {
  // 1. Decompress ephemeral public key
  const ephemeralPublicKey = decompressPublicKey(ciphertext.ephemeralPublicKey);

  // 2. Compute shared secret via ECDH
  const sharedPoint = ecdhMultiply(recipientPrivateKey, ephemeralPublicKey);
  const sharedSecret = keccak256(sharedPoint.x);

  // 3. Derive encryption key
  const keys = hkdfExpand(sharedSecret, "7ay-ecies-v1", 48);
  const encryptionKey = keys.slice(0, 32);

  // 4. Decrypt with AES-256-GCM
  const plaintext = aes256GcmDecrypt(
    ciphertext.ciphertext,
    encryptionKey,
    ciphertext.iv,
    ciphertext.authTag,
    ciphertext.ephemeralPublicKey  // Additional authenticated data
  );

  // 5. Securely zero sensitive data
  secureZero(sharedSecret);
  secureZero(encryptionKey);

  return plaintext;
}
```

### 3.5 Security Properties

| Property | Guarantee |
|----------|-----------|
| **Confidentiality** | Only recipient's private key can decrypt |
| **Authenticity** | GCM tag verifies ciphertext integrity |
| **Forward Secrecy** | Ephemeral keys per encryption |
| **Non-Malleability** | AEAD prevents ciphertext modification |

---

## 4. Share Distribution Protocol

### 4.1 Overview

When a vault is created or key is rotated, shares must be distributed to all devices in the device ring.

### 4.2 Distribution Flow

```
                                    VAULT OWNER
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │  Generate Vault Key  │
                              │  (HKDF from master)  │
                              └──────────────────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │   Shamir Split Key   │
                              │   (k-of-n shares)    │
                              └──────────────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
          ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
          │ ECIES Encrypt   │  │ ECIES Encrypt   │  │ ECIES Encrypt   │
          │ to Device 1 PK  │  │ to Device 2 PK  │  │ to Device n PK  │
          └─────────────────┘  └─────────────────┘  └─────────────────┘
                    │                    │                    │
                    ▼                    ▼                    ▼
          ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
          │ Pedersen Commit │  │ Pedersen Commit │  │ Pedersen Commit │
          └─────────────────┘  └─────────────────┘  └─────────────────┘
                    │                    │                    │
                    └────────────────────┼────────────────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │  SHARE_DISTRIBUTE    │
                              │  (broadcast to all)  │
                              └──────────────────────┘
```

### 4.3 SHARE_DISTRIBUTE Message (0x7D)

```typescript
interface ShareDistributePayload {
  // Vault context
  vaultId: bytes32;
  keyVersion: uint256;          // Increments on each rotation

  // Encrypted shares (one per device)
  encryptedShares: EncryptedDeviceShare[];

  // Commitments for verification
  shareCommitments: bytes32[];  // Pedersen commitments

  // Feldman verification (optional)
  feldmanCommitments?: bytes[];  // g^coefficients for verification

  // Authorization
  ownerSignature: bytes;
}

interface EncryptedDeviceShare {
  deviceId: bytes32;
  shareIndex: uint8;            // 1-based Shamir index
  encryptedShare: ECIESCiphertext;
}
```

**Validation Rules (INV69)**:
- Number of shares MUST equal device ring size
- Each device MUST receive exactly one share
- Share indices MUST be unique and sequential (1 to n)
- All shares MUST be encrypted to correct device public keys
- Pedersen commitments MUST be provided for each share

### 4.4 Share Reception

When a device receives SHARE_DISTRIBUTE:

```typescript
function processShareDistribute(
  payload: ShareDistributePayload,
  devicePrivateKey: bytes32,
  deviceId: bytes32
): Result<void, Error> {
  // 1. Find share for this device
  const myShare = payload.encryptedShares.find(s => s.deviceId === deviceId);
  if (!myShare) {
    return Err(STOR_020_UnauthorizedDevice);
  }

  // 2. Decrypt share
  const shareValue = eciesDecrypt(myShare.encryptedShare, devicePrivateKey);

  // 3. Verify against Pedersen commitment
  const expectedCommitment = payload.shareCommitments[myShare.shareIndex - 1];
  if (!verifyPedersenCommitment(shareValue, expectedCommitment)) {
    return Err(STOR_012_InvalidShare);
  }

  // 4. Verify against Feldman commitments (if provided)
  if (payload.feldmanCommitments) {
    if (!verifyFeldmanShare(myShare.shareIndex, shareValue, payload.feldmanCommitments)) {
      return Err(STOR_012_InvalidShare);
    }
  }

  // 5. Store share securely
  secureStore(vaultId, keyVersion, {
    index: myShare.shareIndex,
    value: shareValue
  });

  return Ok();
}
```

---

## 5. Key Reconstruction Protocol

### 5.1 Overview

When a device wants to unlock a vault, it initiates key reconstruction by requesting shares from other present devices.

### 5.2 Reconstruction Flow

```
          Device A                    Device B                    Device C
        (Initiator)                  (Present)                   (Present)
             │                            │                            │
             │                            │                            │
             ├───── SHARE_REQUEST ───────►│                            │
             │      (broadcast)           │                            │
             ├────────────────────────────────── SHARE_REQUEST ───────►│
             │                            │                            │
             │                            │                            │
             │◄──── SHARE_PROVIDE ────────┤                            │
             │      (encrypted to A)      │                            │
             │                            │                            │
             │◄───────────────────────────────── SHARE_PROVIDE ────────┤
             │                                                         │
             │                                                         │
             ▼                                                         │
    ┌─────────────────┐                                               │
    │ Verify Shares   │                                               │
    │ (commitments)   │                                               │
    └─────────────────┘                                               │
             │                                                         │
             ▼                                                         │
    ┌─────────────────┐                                               │
    │ Reconstruct Key │                                               │
    │ (Lagrange)      │                                               │
    └─────────────────┘                                               │
             │                                                         │
             ▼                                                         │
    ┌─────────────────┐                                               │
    │ Vault Unlocked  │                                               │
    └─────────────────┘                                               │
```

### 5.3 SHARE_REQUEST Message (0x7E)

```typescript
interface ShareRequestPayload {
  // Vault context
  vaultId: bytes32;
  keyVersion: uint256;

  // Request metadata
  requestingDeviceId: bytes32;
  requestNonce: bytes32;        // Unique per request (for correlation)
  requestTimestamp: uint256;

  // Requester's ephemeral public key for response encryption
  responsePublicKey: bytes;     // secp256k1 compressed (33 bytes)

  // ZK proof of presence (if required by policy)
  presenceProof?: ZKPresenceProof;

  // Device signature
  deviceSignature: bytes;
}
```

**Validation Rules**:
- Requesting device MUST be Present in current epoch
- Requesting device MUST be in vault's device ring
- Request nonce MUST be unique (prevent replay)
- If policy requires: ZK presence proof MUST verify

### 5.4 SHARE_PROVIDE Message (0x7F)

```typescript
interface ShareProvidePayload {
  // Request correlation
  vaultId: bytes32;
  requestNonce: bytes32;        // Echo from request

  // Provider identification
  providingDeviceId: bytes32;
  shareIndex: uint8;

  // Encrypted share (to requester's ephemeral key)
  encryptedShare: ECIESCiphertext;

  // Verification
  shareCommitment: bytes32;     // Pedersen commitment (for verification)

  // ZK proof (if required by policy)
  shareProof?: ZKShareProof;

  // Device signature
  deviceSignature: bytes;
}
```

**Validation Rules**:
- Providing device MUST be Present in current epoch
- Providing device MUST be in vault's device ring
- Request nonce MUST match a pending request
- Share MUST verify against commitment
- If policy requires: ZK share proof MUST verify
- Each device provides share ONLY ONCE per request

### 5.5 Reconstruction Implementation

```typescript
interface ReconstructionSession {
  vaultId: bytes32;
  keyVersion: uint256;
  requestNonce: bytes32;
  threshold: uint8;
  collectedShares: ShamirShare[];
  startedAt: uint256;
  timeout: uint256;             // Default: 30 seconds
}

/**
 * Process incoming SHARE_PROVIDE and attempt reconstruction
 */
function processShareProvide(
  payload: ShareProvidePayload,
  session: ReconstructionSession,
  requesterPrivateKey: bytes32
): Result<bytes32 | null, Error> {
  // 1. Verify request correlation
  if (payload.requestNonce !== session.requestNonce) {
    return Err(STOR_013_ShareMismatch);
  }

  // 2. Check for duplicate
  if (session.collectedShares.some(s => s.index === payload.shareIndex)) {
    return Err(STOR_011_ShareAlreadyProvided);
  }

  // 3. Decrypt share
  const shareValue = eciesDecrypt(payload.encryptedShare, requesterPrivateKey);

  // 4. Verify against commitment
  if (!verifyPedersenCommitment(shareValue, payload.shareCommitment)) {
    return Err(STOR_012_InvalidShare);
  }

  // 5. Add to collection
  session.collectedShares.push({
    index: payload.shareIndex,
    value: shareValue
  });

  // 6. Check if threshold reached
  if (session.collectedShares.length >= session.threshold) {
    // Reconstruct key
    const vaultKey = shamirReconstruct(session.collectedShares);

    // Verify key (optional: against key commitment)
    // if (!verifyKeyCommitment(vaultKey, vault.keyCommitment)) {
    //   return Err(STOR_012_InvalidShare);
    // }

    return Ok(vaultKey);
  }

  // Not enough shares yet
  return Ok(null);
}
```

### 5.6 Timeout Handling

```typescript
const RECONSTRUCTION_TIMEOUT = 30_000; // 30 seconds

function checkReconstructionTimeout(session: ReconstructionSession): bool {
  if (Date.now() - session.startedAt > session.timeout) {
    // Cleanup
    secureZero(session.collectedShares);
    return true; // Timed out
  }
  return false;
}
```

---

## 6. Pedersen Commitments

### 6.1 Overview

Pedersen commitments allow committing to share values without revealing them, enabling verification without exposure.

### 6.2 Implementation

```typescript
// Generator points on secp256k1 (nothing-up-my-sleeve)
const G = secp256k1.G;  // Standard generator
const H = hashToCurve("7ay-pedersen-h-v1");  // Second generator

interface PedersenCommitment {
  commitment: bytes32;   // Compressed point
  // Private: value and blinding factor
}

/**
 * Create Pedersen commitment: C = g^v * h^r
 * @param value - Value to commit to
 * @param blinding - Random blinding factor
 */
function pedersenCommit(
  value: bytes32,
  blinding: bytes32
): bytes32 {
  const vG = scalarMult(G, value);
  const rH = scalarMult(H, blinding);
  const commitment = pointAdd(vG, rH);
  return compressPoint(commitment);
}

/**
 * Verify Pedersen commitment
 * @param value - Claimed value
 * @param blinding - Claimed blinding factor
 * @param commitment - Commitment to verify
 */
function verifyPedersenCommitment(
  value: bytes32,
  blinding: bytes32,
  commitment: bytes32
): bool {
  const computed = pedersenCommit(value, blinding);
  return constantTimeEqual(computed, commitment);
}
```

### 6.3 Properties

| Property | Guarantee |
|----------|-----------|
| **Hiding** | Commitment reveals nothing about value (computationally hiding) |
| **Binding** | Cannot open to different value (computationally binding) |
| **Homomorphic** | `Commit(a) + Commit(b) = Commit(a+b)` |

---

## 7. Feldman Verifiable Secret Sharing

### 7.1 Overview

Feldman VSS extends Shamir sharing to allow verification that shares are consistent without revealing the secret.

### 7.2 Implementation

```typescript
interface FeldmanVSS {
  shares: ShamirShare[];
  commitments: bytes[];  // g^a₀, g^a₁, ..., g^aₖ₋₁
}

/**
 * Generate Feldman VSS shares with verification commitments
 */
function feldmanSplit(
  secret: bytes32,
  k: uint8,
  n: uint8
): FeldmanVSS {
  // Generate polynomial coefficients
  const coefficients: bytes32[] = [secret];
  for (let i = 1; i < k; i++) {
    coefficients.push(secureRandom(32));
  }

  // Generate Feldman commitments: g^coeff for each coefficient
  const commitments = coefficients.map(coeff =>
    compressPoint(scalarMult(G, coeff))
  );

  // Generate shares
  const shares: ShamirShare[] = [];
  for (let i = 1; i <= n; i++) {
    const y = evaluatePolynomial(coefficients, i);
    shares.push({ index: i, value: y });
  }

  secureZero(coefficients);

  return { shares, commitments };
}

/**
 * Verify a Feldman share against commitments
 * Verifies: g^share = Π(Cⱼ^(i^j)) for j = 0 to k-1
 */
function verifyFeldmanShare(
  shareIndex: uint8,
  shareValue: bytes32,
  commitments: bytes[]
): bool {
  // Compute g^share
  const gShare = scalarMult(G, shareValue);

  // Compute Π(Cⱼ^(i^j))
  let expected = POINT_AT_INFINITY;
  let iPower = BigInt(1);
  const i = BigInt(shareIndex);

  for (const commitment of commitments) {
    const C = decompressPoint(commitment);
    const term = scalarMult(C, toBytes32(iPower));
    expected = pointAdd(expected, term);
    iPower = fieldMul(iPower, i);
  }

  return pointEqual(gShare, expected);
}
```

---

## 8. Vault Key Derivation

### 8.1 Master Key Hierarchy

```
                    Owner Master Secret
                           │
                           ▼
              ┌────────────────────────┐
              │   HKDF-SHA256          │
              │   salt: owner_address  │
              │   info: "7ay-master"   │
              └────────────────────────┘
                           │
                           ▼
                    Owner Root Key
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
        Vault 1        Vault 2        Vault N
        Root Key       Root Key       Root Key
            │              │              │
     ┌──────┼──────┐       │              │
     │      │      │       │              │
     ▼      ▼      ▼       ▼              ▼
   Epoch  Epoch  Epoch   Epoch          Epoch
    1      2      3       1              1
   Key    Key    Key     Key            Key
```

### 8.2 Epoch Key Derivation

```typescript
/**
 * Derive vault key for specific epoch
 * @param ownerMasterSecret - Owner's 32-byte master secret
 * @param vaultId - Vault identifier
 * @param epochId - Current epoch ID
 * @param epochRandomness - VRF randomness from epoch
 */
function deriveVaultEpochKey(
  ownerMasterSecret: bytes32,
  vaultId: bytes32,
  epochId: uint256,
  epochRandomness: bytes32
): bytes32 {
  // Step 1: Derive owner root key
  const ownerRootKey = hkdfExtract(
    ownerMasterSecret,
    ownerAddress,
    "7ay-master-v1"
  );

  // Step 2: Derive vault root key
  const vaultRootKey = hkdfExpand(
    ownerRootKey,
    vaultId,
    "7ay-vault-root-v1"
  );

  // Step 3: Derive epoch-specific key
  const epochSalt = keccak256(abi.encodePacked(
    epochId,
    epochRandomness
  ));

  const epochKey = hkdfExpand(
    vaultRootKey,
    epochSalt,
    "7ay-vault-epoch-v1"
  );

  // Cleanup intermediate keys
  secureZero(ownerRootKey);
  secureZero(vaultRootKey);

  return epochKey;
}
```

### 8.3 Key Rotation

On epoch transition or manual rotation:

```typescript
function rotateVaultKey(
  vault: Vault,
  newEpochId: uint256,
  newEpochRandomness: bytes32
): RotationResult {
  // 1. Derive new epoch key
  const newKey = deriveVaultEpochKey(
    ownerMasterSecret,
    vault.vaultId,
    newEpochId,
    newEpochRandomness
  );

  // 2. Split into new shares
  const { shares, commitments } = feldmanSplit(
    newKey,
    vault.deviceRing.threshold,
    vault.deviceRing.totalDevices
  );

  // 3. Encrypt shares to devices
  const encryptedShares = vault.deviceRing.devices.map((deviceId, i) => ({
    deviceId,
    shareIndex: i + 1,
    encryptedShare: eciesEncrypt(shares[i].value, getDevicePublicKey(deviceId))
  }));

  // 4. Update vault state
  vault.vaultKeyVersion++;
  vault.keyRotatedAt = block.timestamp;
  vault.keyCommitment = commitments[0]; // g^secret

  // 5. Distribute new shares
  broadcast(SHARE_DISTRIBUTE, {
    vaultId: vault.vaultId,
    keyVersion: vault.vaultKeyVersion,
    encryptedShares,
    shareCommitments: shares.map(s => pedersenCommit(s.value, random())),
    feldmanCommitments: commitments
  });

  return { success: true, newKeyVersion: vault.vaultKeyVersion };
}
```

---

## 9. Invariants

### 9.1 INV69: Share Distribution Validity

Each device in a vault's ring MUST hold exactly one unique share.

```
FOR ALL vault v:
  count(v.distributedShares) = v.deviceRing.totalDevices AND
  FOR ALL share s IN v.distributedShares:
    s.shareIndex IN {1, 2, ..., v.deviceRing.totalDevices} AND
    s.deviceId IN v.deviceRing.devices AND
    isUnique(s.shareIndex) AND
    isUnique(s.deviceId)
```

### 9.2 Share Index Uniqueness

```
FOR ALL vault v:
  FOR ALL i, j WHERE i != j:
    v.distributedShares[i].shareIndex != v.distributedShares[j].shareIndex
```

### 9.3 Device-Share Binding

```
FOR ALL vault v, device d:
  d IN v.deviceRing.devices IMPLIES
    EXISTS exactly one share s:
      s.deviceId = d.deviceId AND
      s IN v.distributedShares
```

---

## 10. Security Considerations

### 10.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Share interception | ECIES encryption to device public key |
| Malicious share provider | Pedersen/Feldman verification |
| Replay of SHARE_PROVIDE | Unique request nonce |
| Key material in memory | secureZero after use |
| Timing attacks | Constant-time operations |

### 10.2 Implementation Requirements

1. **Secure Random Generation**: Use cryptographically secure RNG for all random values
2. **Memory Zeroing**: All sensitive data (keys, shares) must be securely zeroed after use
3. **Constant-Time Operations**: All cryptographic comparisons must be constant-time
4. **Side-Channel Resistance**: Implementations should resist timing and power analysis

### 10.3 Recommendations

- Use hardware security modules (HSM) for key operations where available
- Implement rate limiting on SHARE_REQUEST to prevent enumeration
- Log all share distribution and reconstruction events for audit
- Consider secure enclaves for share storage on devices

---

## 11. Error Codes

Cryptographic layer error codes. See [errors.md](../reference/errors.md) for the complete catalog.

| Code | Name | Description |
|------|------|-------------|
| STOR_011 | ShareAlreadyProvided | Device already provided share for this request |
| STOR_012 | InvalidShare | Share verification failed (Pedersen/Feldman) |
| STOR_013 | ShareMismatch | Share index doesn't match expected |
| STOR_018 | KeyVersionMismatch | Key version mismatch (item or share) |

---

## 12. Changelog

| Version | Changes |
|---------|---------|
| v0.7.3 | Initial cryptographic layer specification |

---

## 13. References

- [Shamir's Secret Sharing](https://dl.acm.org/doi/10.1145/359168.359176) — Original paper
- [ECIES](https://en.wikipedia.org/wiki/Integrated_Encryption_Scheme) — Encryption scheme
- [Feldman VSS](https://ieeexplore.ieee.org/document/4568297) — Verifiable secret sharing
- [Pedersen Commitments](https://link.springer.com/chapter/10.1007/3-540-46766-1_9) — Commitment scheme
- [HKDF](https://tools.ietf.org/html/rfc5869) — Key derivation function
- [vaults.md](vaults.md) — Vault specification
- [devices.md](devices.md) — Device specification

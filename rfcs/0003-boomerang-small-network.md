# RFC-0003: Boomerang Small Network Fallback

| Field | Value |
|-------|-------|
| **RFC** | 0003 |
| **Title** | Small Network Fallback Mode for Boomerang Routing |
| **Author** | 7ayLabs Security Council |
| **Status** | Draft |
| **Created** | 2026-01-29 |
| **Updated** | 2026-01-29 |
| **Requires** | None |
| **Supersedes** | None |

---

## Abstract

This RFC addresses a protocol deadlock in boomerang routing when operating in sparse networks. INV30 (Path Divergence) requires that return paths differ from forward paths by at least one intermediate node, which is impossible in networks with fewer than 5 active nodes. This proposal introduces a "small network mode" with explicit fallback verification, allowing boomerang routing to function in testnets, development environments, and early-stage production networks while maintaining security through enhanced verification requirements.

---

## Motivation

### Problem Statement

Boomerang routing (v0.6.9) requires path divergence:

```
Forward: A → B → C
Return:  A ← D ← C  (D ≠ B, satisfies INV30)
```

**In a 4-node network:**
```
Nodes: [A, B, C, D]
Forward: A → B → C
Return options:
  - A ← B ← C (same as forward, violates INV30)
  - A ← D ← C (if D exists and is not B, OK)
  - A ← C (direct, OK if B was the only intermediary)
```

**In a 3-node network:**
```
Nodes: [A, B, C]
Forward: A → B → C
Return options:
  - A ← B ← C (ONLY option, violates INV30)
```

The protocol becomes unusable in small networks, blocking testnets and development.

### Goals

1. Enable boomerang routing in networks with < 5 nodes
2. Maintain security through enhanced verification
3. Make small network mode explicit and transparent
4. Allow graceful transition as networks grow

### Non-Goals

1. Weakening security for large networks
2. Removing INV30 entirely
3. Automatic mode switching without explicit configuration

---

## Specification

### Overview

The solution introduces:
1. **Network Density Detection** — Automatic detection of small networks
2. **Small Network Mode** — Explicit flag enabling same-path fallback
3. **Enhanced Verification** — Additional checks for fallback mode
4. **Mode Transparency** — Explicit declaration in BOOMERANG_COMPLETE

### Detailed Design

#### Configuration

```rust
pub struct BoomerangConfig {
    // Existing (v0.6.9)
    pub base_timeout_seconds: u64,
    pub adaptive_timeout: bool,
    pub max_timeout_extension: u64,
    pub network_latency_percentile: u8,

    // NEW (v0.7.0)
    /// Minimum nodes required for standard path divergence
    pub small_network_threshold: u8,  // Default: 5

    /// Allow same-path return in small networks
    pub allow_same_path_fallback: bool,  // Default: true

    /// Verification level for fallback mode
    pub fallback_verification_level: VerificationLevel,  // Default: Enhanced
}

impl Default for BoomerangConfig {
    fn default() -> Self {
        Self {
            base_timeout_seconds: 60,
            adaptive_timeout: false,
            max_timeout_extension: 60,
            network_latency_percentile: 95,
            small_network_threshold: 5,
            allow_same_path_fallback: true,
            fallback_verification_level: VerificationLevel::Enhanced,
        }
    }
}
```

#### Verification Levels

```rust
pub enum VerificationLevel {
    /// Standard INV30 enforcement (path must diverge)
    Standard,

    /// Same path allowed with additional timestamp and signature checks
    Enhanced,

    /// Same path allowed with validator attestation required
    Maximum,
}
```

#### Network Density Detection

```rust
pub fn detect_network_mode(epoch_id: u128) -> NetworkMode {
    let active_nodes = get_active_node_count(epoch_id);

    if active_nodes >= config.small_network_threshold {
        NetworkMode::Standard
    } else if config.allow_same_path_fallback {
        NetworkMode::SmallNetwork
    } else {
        NetworkMode::Disabled  // Boomerang not available
    }
}

pub enum NetworkMode {
    Standard,      // Normal INV30 enforcement
    SmallNetwork,  // Fallback mode active
    Disabled,      // Boomerang routing unavailable
}
```

#### Updated INV30

```
INV30 (Updated v0.7.0): Path Divergence with Fallback

∀ boomerang b:
  LET mode = detect_network_mode(b.epoch_id)
  IN
    CASE mode OF
      Standard →
        b.forwardPath.intermediates ≠ b.returnPath.intermediates

      SmallNetwork →
        b.smallNetworkMode = true ∧
        b.verificationLevel >= config.fallback_verification_level ∧
        b.BOOMERANG_COMPLETE.smallNetworkMode = true

      Disabled →
        REJECT b
```

#### Enhanced Verification

When `smallNetworkMode = true`, additional checks apply:

```rust
pub fn verify_small_network_boomerang(
    boomerang: &Boomerang,
) -> Result<(), Error> {
    ensure!(boomerang.small_network_mode, Error::InvalidMode);

    match config.fallback_verification_level {
        VerificationLevel::Enhanced => {
            // 1. All hops must have unique timestamps (no replay)
            verify_unique_timestamps(&boomerang.hops)?;

            // 2. Each hop signature must include boomerang_id
            verify_hop_signatures_include_id(&boomerang.hops, boomerang.id)?;

            // 3. Round-trip time must be within reasonable bounds
            let rtt = boomerang.completed_at - boomerang.sent_at;
            ensure!(rtt >= MIN_EXPECTED_RTT, Error::SuspiciouslyFastRTT);
            ensure!(rtt <= MAX_EXPECTED_RTT, Error::RTTTooSlow);

            // 4. Destination must confirm receipt with fresh nonce
            verify_fresh_ack_nonce(&boomerang.ack)?;
        }
        VerificationLevel::Maximum => {
            // All Enhanced checks plus:

            // 5. At least one validator must attest to the boomerang
            verify_validator_attestation(&boomerang)?;
        }
        _ => {}
    }

    Ok(())
}

// Timing bounds for Enhanced verification
pub const MIN_EXPECTED_RTT: u64 = 100;    // 100ms minimum
pub const MAX_EXPECTED_RTT: u64 = 30_000; // 30s maximum
```

#### Updated BOOMERANG_COMPLETE

```typescript
interface BoomerangCompletePayload {
  // Existing fields
  boomerangId: bytes32;
  completedAt: uint256;
  totalHops: uint256;
  roundTripTime: uint256;
  forwardPathHash: bytes32;
  returnPathHash: bytes32;
  pathsDivergent: bool;

  // NEW (v0.7.0)
  smallNetworkMode: bool;           // True if fallback was used
  verificationLevel: uint8;         // 0=Standard, 1=Enhanced, 2=Maximum
  validatorAttestation?: bytes;     // Required if Maximum level
}
```

#### BOOMERANG_ACK Update

```typescript
interface BoomerangAckPayload {
  // Existing fields
  boomerangId: bytes32;
  originalSendNonce: bytes32;
  receivedAt: uint256;
  innerPayloadHash: bytes32;
  returnPath: Address[];

  // NEW (v0.7.0)
  freshNonce: bytes32;              // Unique nonce for this ack
  networkMode: NetworkMode;         // Detected at ack time
}
```

#### Invariants

| Invariant | Description |
|-----------|-------------|
| INV54 | **Small Network Detection**: `activeNodeCount < threshold → smallNetworkMode = true` |
| INV55 | **Fallback Path Verification**: `smallNetworkMode → verificationLevel >= Enhanced` |
| INV56 | **Mode Transparency**: `smallNetworkMode MUST be explicit in BOOMERANG_COMPLETE` |

**Formal Definitions:**

```
INV54: Small Network Detection
∀ boomerang b in epoch e:
  active_node_count(e) < small_network_threshold →
    b.smallNetworkMode = true

INV55: Fallback Path Verification
∀ boomerang b where b.smallNetworkMode = true:
  b.verificationLevel >= config.fallback_verification_level

INV56: Mode Transparency
∀ boomerang b where state(b) = Complete:
  b.BOOMERANG_COMPLETE.smallNetworkMode = b.smallNetworkMode
```

#### Error Conditions

| Code | Name | Description |
|------|------|-------------|
| BOOM_010 | SmallNetworkNotAllowed | Fallback disabled but network too small |
| BOOM_011 | MissingSmallNetworkFlag | Same path used without smallNetworkMode |
| BOOM_012 | InsufficientVerification | Verification level below required |
| BOOM_013 | SuspiciousRTT | Round-trip time outside bounds |
| BOOM_014 | MissingValidatorAttestation | Maximum level requires attestation |

---

## Backwards Compatibility

### Impact Assessment

| Component | Impact | Migration Required |
|-----------|--------|-------------------|
| BOOMERANG_COMPLETE | Minor | Yes (new fields) |
| BOOMERANG_ACK | Minor | Yes (new fields) |
| INV30 | Updated | Documentation only |
| Path validation | Updated | Yes (new logic) |

### Migration Path

1. **v0.7.0-alpha**: New fields optional, old messages accepted
2. **v0.7.0-beta**: New fields required, fallback enabled
3. **v0.7.0**: Full enforcement

---

## Security Considerations

### Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| Same-path replay | Medium | Medium | Fresh nonce, timestamp checks |
| Fake small network claim | Low | High | On-chain node count verification |
| Validator collusion | Low | Medium | Multiple attestations, reputation |

### Mitigations

1. **Replay Prevention**: Fresh nonce in ACK, unique timestamps per hop
2. **Network Claim Verification**: Node count derived from on-chain presence
3. **Timing Analysis**: RTT bounds detect instant fake round-trips

### Security Tradeoffs

| Mode | Security Level | Availability |
|------|----------------|--------------|
| Standard | High | Requires 5+ nodes |
| Enhanced | Medium-High | Works with 3+ nodes |
| Maximum | High | Works with 3+ nodes, requires validator |

---

## References

- [specs/extensions/boomerang.md](../specs/extensions/boomerang.md) — Boomerang specification
- [specs/reference/invariants.md](../specs/reference/invariants.md) — INV30-33

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-29 | 7ayLabs Security Council | Initial draft |

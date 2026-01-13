# Boomerang Routing Flow Diagram

## Overview

Boomerang routing ensures message delivery verification through path divergence.
Messages travel to their destination and return via a different path.

---

## Basic Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BOOMERANG CYCLE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   FORWARD PATH                                                          │
│   ════════════                                                          │
│                                                                         │
│      Origin            Intermediary           Destination               │
│        [A] ──────────────► [B] ──────────────► [C]                     │
│                                                  │                      │
│                     BOOMERANG_SEND (0x40)        │                      │
│                     ─────────────────────►       │                      │
│                                                  │                      │
│                                                  ▼                      │
│                                           BOOMERANG_ACK (0x41)          │
│                                           (declares return path)        │
│                                                  │                      │
│   RETURN PATH (DIVERGENT)                        │                      │
│   ═══════════════════════                        │                      │
│                                                  │                      │
│        [A] ◄────────────── [D] ◄────────────────┘                      │
│         │                                                               │
│         │              BOOMERANG_RETURN (0x42)                          │
│         │              ◄─────────────────────                           │
│         │                                                               │
│         ▼                                                               │
│   BOOMERANG_COMPLETE (0x43)                                             │
│   (cycle verified)                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## State Machine

```
                              BOOMERANG_SEND
                 ────────────────────────────────► Pending
                                                      │
           ┌──────────────────────────────────────────┼──────────────────┐
           │                                          │                  │
           ▼                                          ▼                  ▼
     BOOMERANG_ACK                             Timeout expires        Error
           │                                          │                  │
           ▼                                          ▼                  ▼
    AwaitingReturn                                 Timeout            Failed
           │                                       (terminal)        (terminal)
           │
           ▼
    BOOMERANG_RETURN
    (each hop signed)
           │
           ▼
    BOOMERANG_COMPLETE
           │
           ▼
       Complete
      (terminal)
```

---

## Path Divergence (INV30)

### Valid Examples

**Example 1: Different Intermediary**
```
Forward: A → B → C
Return:  A ← D ← C   ✓ (D ≠ B)
```

**Example 2: Different Path Length**
```
Forward: A → B → C → D
Return:  A ← E ← D   ✓ (E not in {B, C})
```

**Example 3: Direct Return**
```
Forward: A → B → C
Return:  A ← C       ✓ (no intermediaries vs B)
```

### Invalid Example

```
Forward: A → B → C
Return:  A ← B ← C   ✗ (same path reversed - BOOM_001)
```

---

## Hop Verification Chain (INV33)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       VERIFICATION CHAIN                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Hop 0 (Destination → First Return Node)                               │
│   ┌────────────────────────────────────────┐                           │
│   │ previousHash: 0x0000...0000            │                           │
│   │ forwarder: 0xCCCC (destination)        │                           │
│   │ forwardedAt: T1                        │                           │
│   │ signature: sign(hash(boomerangId,      │                           │
│   │            forwarder, prevHash, T1))   │                           │
│   └────────────────────────────────────────┘                           │
│                        │                                                │
│                        ▼                                                │
│   Hop 1 (First Return Node → Second)                                    │
│   ┌────────────────────────────────────────┐                           │
│   │ previousHash: hash(Hop0)               │                           │
│   │ forwarder: 0xDDDD                      │                           │
│   │ forwardedAt: T2                        │                           │
│   │ signature: sign(hash(boomerangId,      │                           │
│   │            forwarder, prevHash, T2))   │                           │
│   └────────────────────────────────────────┘                           │
│                        │                                                │
│                        ▼                                                │
│   Hop N (Last Node → Origin)                                            │
│   ┌────────────────────────────────────────┐                           │
│   │ previousHash: hash(HopN-1)             │                           │
│   │ forwarder: 0xEEEE                      │                           │
│   │ forwardedAt: TN                        │                           │
│   │ signature: sign(hash(boomerangId,      │                           │
│   │            forwarder, prevHash, TN))   │                           │
│   └────────────────────────────────────────┘                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Timeout Handling (INV31)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       TIMEOUT FLOW                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   sentAt ──────────────────────────────────────► sentAt + timeout       │
│      │                                                  │               │
│      │         VALID WINDOW (max 300s)                  │               │
│      │    ◄─────────────────────────────────────►       │               │
│      │                                                  │               │
│      │    ┌─── BOOMERANG_ACK must arrive ───┐          │               │
│      │    │                                  │          │               │
│      │    │    ┌─ BOOMERANG_RETURN ─┐       │          │               │
│      │    │    │                    │       │          │               │
│      │    │    │  ┌─ COMPLETE ─┐    │       │          │               │
│      │    │    │  │            │    │       │          │               │
│      ▼    ▼    ▼  ▼            ▼    ▼       ▼          ▼               │
│   ───●────●────●──●────────────●────●───────●──────────X───────────►   │
│      │                                                  │    time      │
│   Pending                                            Timeout           │
│                                                                         │
│   If COMPLETE not received by timeout:                                  │
│   - State → Timeout                                                     │
│   - Partial hops discarded                                              │
│   - Sender MAY retry with new boomerangId                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Message Sequence Diagram

```
    Origin [A]          Intermediary [B]      Destination [C]      Alt Path [D]
        │                     │                     │                    │
        │   BOOMERANG_SEND    │                     │                    │
        │────────────────────►│                     │                    │
        │                     │   BOOMERANG_SEND    │                    │
        │                     │────────────────────►│                    │
        │                     │                     │                    │
        │                     │                     │ (process message)  │
        │                     │                     │ (select return     │
        │                     │                     │  path via D)       │
        │                     │                     │                    │
        │                     │   BOOMERANG_ACK     │                    │
        │◄────────────────────┼─────────────────────│                    │
        │                     │                     │                    │
        │ (state: AwaitingReturn)                   │                    │
        │                     │                     │   BOOMERANG_RETURN │
        │                     │                     │───────────────────►│
        │                     │                     │                    │
        │                     │                     │  (D signs hop)     │
        │                     │                     │                    │
        │                           BOOMERANG_RETURN                     │
        │◄───────────────────────────────────────────────────────────────│
        │                                                                │
        │ (verify hop chain)                                             │
        │ (verify path divergence)                                       │
        │                                                                │
        │   BOOMERANG_COMPLETE (broadcast)                               │
        │────────────────────►────────────────────────────────────────►  │
        │                                                                │
        │ (state: Complete)                                              │
        │                                                                │
```

---

## Error Scenarios

### BOOM_001: PathNotDivergent

```
Forward: A → B → C
Return:  A ← B ← C   ✗

Error at BOOMERANG_ACK validation:
- returnPath contains same intermediaries as forward path
- Message rejected, no BOOMERANG_RETURN initiated
```

### BOOM_002: BoomerangTimeout

```
sentAt: T
timeout: 60s

T+60s: No BOOMERANG_COMPLETE received
       State → Timeout
       No partial state persisted
```

### BOOM_003: InvalidHopSignature

```
Hop verification fails:
- ecrecover(signature) ≠ hop.forwarder
- BOOMERANG_RETURN rejected
- Forwarding node considered potentially malicious
```

### BOOM_004: BoomerangAborted

```
Mid-cycle abort scenarios:
- Node in return path goes offline
- Epoch closes during cycle
- Destination revokes presence
```

### BOOM_005: InvalidReturnPath

```
Return path validation fails:
- Node in returnPath has no presence
- Node in returnPath is slashed
- BOOMERANG_ACK rejected
```

---

## Invariant Summary

| ID | Name | Enforcement Point |
|----|------|-------------------|
| INV30 | Path Divergence | BOOMERANG_ACK validation |
| INV31 | Boomerang Timeout | Origin timeout check |
| INV32 | Boomerang Atomicity | State machine design |
| INV33 | Verification Chain | BOOMERANG_RETURN validation |

---

## References

- boomerang.md v0.6.5 — Full specification
- message-catalog.md v0.6.2 — Message envelope structure
- invariants.md v0.6.5 — Protocol invariants INV30-33

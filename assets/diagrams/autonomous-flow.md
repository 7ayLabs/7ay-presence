# Autonomous Transactions Flow Diagram

## Overview

Autonomous Transactions enable trusted, recurring actions through a hybrid
on-chain/off-chain model with validator finalization.

---

## Complete Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  AUTONOMOUS TRANSACTION LIFECYCLE                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   PHASE 1: INTENT DECLARATION                                          │
│   ═══════════════════════════                                          │
│                                                                         │
│   Actor                          On-Chain                               │
│     │                               │                                   │
│     │ commitAutonomousIntent()      │                                   │
│     │──────────────────────────────►│                                   │
│     │                               │                                   │
│     │ ◄── intentHash stored ────────│                                   │
│     │                               │                                   │
│     │                                                                   │
│     │   AUTONOMOUS_INTENT (0x50)                                        │
│     │────────────────────────────────────────────►  Validators          │
│     │                                                    │              │
│     │                                                    │              │
│   PHASE 2: PATTERN RECOGNITION                           │              │
│   ════════════════════════════                           │              │
│                                                          │              │
│     │                                                    │              │
│     │   Regular actions (e.g., daily votes)             │              │
│     │───────────────────────────────────────────────────►│              │
│     │                                                    │              │
│     │                          Pattern observed          │              │
│     │                          (frequency tracking)      │              │
│     │                                                    │              │
│     │                                                    ▼              │
│     │                                              Threshold Met?       │
│     │                                                    │              │
│     │                            ┌───────────────────────┼───────────┐  │
│     │                            │ YES                   │ NO        │  │
│     │                            ▼                       ▼           │  │
│     │               AUTONOMOUS_PATTERN (0x51)        Inactive        │  │
│     │◄──────────────────────────────────────────────────┘            │  │
│     │                                                                │  │
│   State: Eligible                                                    │  │
│                                                                      │  │
│   PHASE 3: AUTONOMOUS EXECUTION                                      │  │
│   ═════════════════════════════                                      │  │
│                                                                      │  │
│     │                                                                │  │
│     │   Execute action matching intent                               │  │
│     │                                                                │  │
│     │   AUTONOMOUS_EXECUTE (0x52)                                    │  │
│     │────────────────────────────────────────────────►  Validators   │  │
│     │                                                      │         │  │
│     │                                                      │         │  │
│   PHASE 4: FINALIZATION                                    │         │  │
│   ═════════════════════════                                │         │  │
│                                                            │         │  │
│     │                                                      ▼         │  │
│     │                                              Validate execution│  │
│     │                                                      │         │  │
│     │                                                      ▼         │  │
│     │                                         AUTONOMOUS_FINALIZE    │  │
│     │                                              (0x53)            │  │
│     │◄─────────────────────────────────────────────────────┘         │  │
│     │                                                                │  │
│     │                              Quorum reached?                   │  │
│     │                                    │                           │  │
│     │                   ┌────────────────┼────────────────┐          │  │
│     │                   │ YES            │ NO             │          │  │
│     │                   ▼                ▼                │          │  │
│     │              Finalized          Rejected            │          │  │
│                                                                      │  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## State Machine

```
            AUTONOMOUS_INTENT
   ─────────────────────────────────► Declared
                                          │
        ┌─────────────────────────────────┼─────────────────────────┐
        │                                 │                         │
        │                                 ▼                         │
        │                        AUTONOMOUS_PATTERN                 │
        │                        (threshold met)                    │
        │                                 │                         │
        │                   ┌─────────────┼─────────────┐           │
        │                   │ YES         │ NO          │           │
        │                   ▼             ▼             │           │
        │               Eligible       Inactive         │           │
        │                   │                           │           │
        │                   ▼                           │           │
        │          AUTONOMOUS_EXECUTE                   │           │
        │                   │                           │           │
        │                   ▼                           │           │
        │          AUTONOMOUS_FINALIZE                  │           │
        │                   │                           │           │
        │         ┌─────────┴─────────┐                 │           │
        │         │ Quorum   │ No     │                 │           │
        │         ▼          ▼        │                 │           │
        │     Finalized   Rejected    │                 │           │
        │                             │                 │           │
        │                             │                 │           │
        │         AUTONOMOUS_REVOKE   │                 │           │
        │◄────────────────────────────┴─────────────────┘           │
        │                                                           │
        ▼                                                           │
     Revoked ◄──────────────────────────────────────────────────────┘
```

---

## Pattern Recognition Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       PATTERN RECOGNITION                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Observation Window (default: 1 hour)                                  │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                                                                 │   │
│   │   Action 1    Action 2    Action 3    Action 4    Action 5     │   │
│   │      ●───────────●───────────●───────────●───────────●          │   │
│   │      │           │           │           │           │          │   │
│   │   T+0min     T+12min     T+24min     T+36min     T+48min       │   │
│   │                                                                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Threshold Check:                                                      │
│   ┌─────────────────────────────────────────┐                          │
│   │ FREQUENCY: 5 actions in 1 hour         │ ✓ Pattern Met            │
│   │ Observed:  5 actions in 48 minutes     │                          │
│   └─────────────────────────────────────────┘                          │
│                                                                         │
│   Validators Agree:                                                     │
│   ┌─────────────────────────────────────────┐                          │
│   │ Validator 1: ✓ Pattern observed         │                          │
│   │ Validator 2: ✓ Pattern observed         │                          │
│   │ Validator 3: ✓ Pattern observed         │  → Quorum: ELIGIBLE      │
│   └─────────────────────────────────────────┘                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Finalization Voting

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       FINALIZATION VOTING                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Execution Received                                                    │
│   ──────────────────                                                    │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                                                                 │   │
│   │   executionId: 0xabc...                                        │   │
│   │   intentId: 0x123...                                           │   │
│   │   actionHash: 0xdef...                                         │   │
│   │   executedAt: 1700000000                                       │   │
│   │                                                                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│                              │                                          │
│                              ▼                                          │
│                                                                         │
│   Validator Votes (60 second window)                                    │
│   ──────────────────────────────────                                    │
│                                                                         │
│   ┌────────────────┬────────────────┬────────────────┐                 │
│   │  Validator 1   │  Validator 2   │  Validator 3   │                 │
│   ├────────────────┼────────────────┼────────────────┤                 │
│   │   APPROVE ✓    │   APPROVE ✓    │   ABSTAIN ○    │                 │
│   │   T+10s        │   T+25s        │   T+40s        │                 │
│   └────────────────┴────────────────┴────────────────┘                 │
│                                                                         │
│                              │                                          │
│                              ▼                                          │
│                                                                         │
│   Quorum Check: 2/3 APPROVE (67%)                                       │
│   ─────────────────────────────────                                     │
│                                                                         │
│   Result: FINALIZED                                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Epoch Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       EPOCH LIFECYCLE                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Epoch N (Active)                                                      │
│   ════════════════                                                      │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                                                                 │   │
│   │   T+0d                           T+7d                           │   │
│   │   ────●────────────────────────────●────────────────────────    │   │
│   │       │                            │                            │   │
│   │       │  Intent declares           │                            │   │
│   │       │  Patterns form             │                            │   │
│   │       │  Executions finalize       │                            │   │
│   │       │                            │                            │   │
│   │       │                            │  Epoch closes              │   │
│   │       │                            │  All intents → Revoked     │   │
│   │       │                            │  Pattern data cleared      │   │
│   │                                                                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Epoch N+1 (New)                                                       │
│   ═══════════════                                                       │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                                                                 │   │
│   │   • No carryover of intents                                    │   │
│   │   • No carryover of patterns                                   │   │
│   │   • Actor must redeclare intent                                │   │
│   │   • Pattern recognition restarts                               │   │
│   │                                                                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Sequence Diagram

```
    Actor              On-Chain           Validators           Pattern Store
      │                    │                  │                      │
      │ commitIntent()     │                  │                      │
      │───────────────────►│                  │                      │
      │                    │                  │                      │
      │ ◄── hash stored ───│                  │                      │
      │                    │                  │                      │
      │ AUTONOMOUS_INTENT  │                  │                      │
      │───────────────────────────────────────►│                      │
      │                    │                  │                      │
      │                    │                  │ track pattern        │
      │                    │                  │─────────────────────►│
      │                    │                  │                      │
      │ (regular actions over time...)        │                      │
      │───────────────────────────────────────►│                      │
      │                    │                  │ update frequency     │
      │                    │                  │─────────────────────►│
      │                    │                  │                      │
      │                    │                  │ threshold met!       │
      │                    │                  │◄─────────────────────│
      │                    │                  │                      │
      │ AUTONOMOUS_PATTERN │                  │                      │
      │◄──────────────────────────────────────│                      │
      │                    │                  │                      │
      │ (state: Eligible)  │                  │                      │
      │                    │                  │                      │
      │ AUTONOMOUS_EXECUTE │                  │                      │
      │───────────────────────────────────────►│                      │
      │                    │                  │                      │
      │                    │                  │ validate             │
      │                    │                  │                      │
      │ AUTONOMOUS_FINALIZE│                  │                      │
      │◄──────────────────────────────────────│ (quorum votes)       │
      │                    │                  │                      │
      │ (state: Finalized) │                  │                      │
      │                    │                  │                      │
```

---

## Invariant Summary

| ID | Name | Enforcement Point |
|----|------|-------------------|
| INV34 | Intent Presence | Intent declaration |
| INV35 | Pattern Threshold | Pattern recognition |
| INV36 | Validator Finalization | Execution finalization |
| INV37 | Epoch Scope | All state transitions |

---

## References

- autonomous.md v0.6.6 — Full specification
- validator.md v0.4 — Validator mechanics
- message-catalog.md v0.6.2 — Message envelope

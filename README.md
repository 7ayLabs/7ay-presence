# 7ay Presence Protocol

**Canonical specification for Proof of Presence (PoP)**

---

## Purpose

This repository defines, formalizes, and freezes the technical truth of the 7ay Proof of Presence protocol.

**This repository defines WHAT Proof of Presence is.**

- Not how it is used
- Not how it is executed
- Not how it is consumed

---

## Contents

```
specs/
  presence.md      # Protocol specification (canonical rules)
  model.md         # Conceptual system model
  errors.md        # Error specification (custom errors)

contracts/
  interfaces/
    IPresenceRegistry.sol   # Canonical interface
  core/
    PresenceRegistry.sol    # Reference implementation (MVP)

test/
  PresenceRegistry.invariants.t.sol   # Invariant verification
```

---

## Specification Documents

| Document | Purpose |
|----------|---------|
| [specs/presence.md](specs/presence.md) | Formal protocol rules, states, lifecycle, and invariants |
| [specs/model.md](specs/model.md) | Conceptual model: entities, relationships, and state behavior |
| [specs/errors.md](specs/errors.md) | Canonical error definitions and handling rules |

---

## Core Concepts

### Presence

A protocol-level assertion that an actor participated in a defined context during a specific epoch, validated according to protocol rules.

### Actor

An identifiable participant. An actor MUST NOT have more than one finalized presence per epoch.

### Epoch

A discrete, monotonically increasing time window during which presence can be declared and validated.

---

## MVP Invariants

The following invariants MUST NEVER be violated:

1. An actor MUST NOT have more than one finalized presence per epoch.
2. A finalized presence MUST NOT be reverted.
3. Presence state transitions MUST be deterministic and idempotent.
4. Only the actor itself MAY finalize its own presence.
5. Finalizing presence for one actor MUST NOT affect any other actor.
6. Finalizing presence in one epoch MUST NOT affect any other epoch.
7. A finalized presence MUST NOT transition back to None.

---

## MVP Scope

**On-chain (in scope):**
- Acceptance-only presence finalization
- States: `{None, Finalized}`
- Deterministic and idempotent behavior

**Off-chain / Future (out of scope):**
- Presence lifecycle states (Declared, Validated, Expired, Slashed)
- Validators, quorum, disputes, or slashing
- Epoch lifecycle management

---

## Verification

```shell
forge build
forge test -vvv
```

---

## License

MIT

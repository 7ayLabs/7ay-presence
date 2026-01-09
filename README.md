# 7ay Presence Protocol

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-blue.svg)](https://mariadb.com/bsl11/)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.28-blue)](https://docs.soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://book.getfoundry.sh/)

This repository contains the public specification and reference materials for the 7ay Presence Protocol, originally designed by Zaid Arath.

The protocol is source-available under the Business Source License (BSL 1.1).
Non-commercial use, research, and integration are permitted.
Commercial use requires a separate license from 7ayLabs.

## Current Version

The protocol is currently at **v0.3**, which includes the declaration layer with `declarePresence()` and the `Declared` state.

| Version | Status | Scope |
|---------|--------|-------|
| v0.1 | Complete | Presence finalization (None → Finalized) |
| v0.2 | Complete | Epoch lifecycle (Scheduled → Active → Closed → Finalized) |
| v0.3 | Complete | Declaration layer (declarePresence, Declared state) |
| v0.4+ | Roadmap | Validators, disputes, slashing |

## Usage

If you just want to read the specification, the canonical documents are:

- [specs/v0.3/presence.md](specs/v0.3/presence.md) — Declaration layer specification
- [specs/v0.2/epoch.md](specs/v0.2/epoch.md) — Epoch lifecycle specification
- [specs/model.md](specs/model.md) — Conceptual model

However, if you want to run the reference implementation:

```bash
git clone https://github.com/7ay/7ay-presence.git
cd 7ay-presence
forge build
forge test -vvv
```

## Core Concepts

**Presence** — A protocol-level assertion that an actor participated in a defined context during a specific epoch, validated according to protocol rules.

**Actor** — An identifiable participant. An actor MUST NOT have more than one finalized presence per epoch.

**Epoch** — A discrete, monotonically increasing time window during which presence can be declared and validated.

## State Machine

```
None ──declarePresence()──► Declared ──finalizePresence()──► Finalized
  │                                                              ▲
  └────────────────finalizePresence() (legacy)───────────────────┘
```

## Invariants

1. An actor MUST NOT have more than one finalized presence per epoch
2. A finalized presence MUST NOT be reverted
3. Presence state transitions MUST be deterministic and idempotent
4. Only the actor itself MAY declare/finalize its own presence
5. Actor isolation: finalizing for one actor MUST NOT affect others
6. Epoch isolation: finalizing in one epoch MUST NOT affect others
7. State monotonicity: None → Declared → Finalized
8. Declaration/finalization only during Active epochs

## Versions

The previous protocol versions are available in the `specs/` directory:

- `specs/v0.1/` — MVP presence specification
- `specs/v0.2/` — Epoch lifecycle specification
- `specs/v0.3/` — Declaration layer specification (current)

## License

This project is licensed under the **Business Source License 1.1**.

- **Non-commercial use**: Permitted without restriction
- **Research & education**: Permitted
- **Commercial use**: Requires explicit license from 7ayLabs

On **January 8, 2030**, the license automatically converts to **Apache License 2.0**.



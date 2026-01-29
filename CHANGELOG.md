# Changelog

All notable changes to the 7ay Presence Protocol specification.

## [0.6.8] - 2026-01-29

### Changed
- Consolidated v0.1-v0.5 specifications into v0.6
- Archived Solidity reference implementation
- Added RFC governance process

### Added
- `specs/reference/overview.md` — Protocol vision
- `specs/reference/model.md` — Core protocol model
- `specs/core/presence.md` — Consolidated presence specification
- `specs/core/epochs.md` — Epoch lifecycle
- `specs/core/actors.md` — Actor identity and scope
- `specs/core/validators.md` — Validator management
- `specs/core/disputes.md` — Dispute resolution
- `specs/governance/ephemeral.md` — Ephemeral data governance
- `specs/governance/capabilities.md` — Capability system
- `specs/governance/policies.md` — Data policies
- `specs/reference/state-machine.md` — Unified state transitions
- `specs/reference/substrate.md` — Substrate implementation notes
- `rfcs/README.md` — RFC governance process
- `rfcs/0000-template.md` — RFC template

### Removed
- Solidity contracts (preserved in `archive/v0.6.7-solidity-reference`)
- Foundry test suite (preserved in archive)

## [0.6.7] - 2025-01-15

### Added
- Octopus Scaling (dynamic node division)
- INV38-42 (octopus invariants)
- OCTO_001-006 error codes
- Message types 0x60-0x65

## [0.6.6] - 2025-01-10

### Added
- Autonomous Transactions (pattern-based execution)
- INV34-37 (autonomous invariants)
- AUTO_001-006 error codes
- Message types 0x50-0x54

## [0.6.5] - 2025-01-05

### Added
- Boomerang Routing (return path verification)
- INV30-33 (boomerang invariants)
- BOOM_001-005 error codes
- Message types 0x40-0x43

## [0.6.4] - 2024-12-20

### Added
- Ephemeral Media (images/audio within epochs)
- INV27-29 (media invariants)
- MEDIA_001-006 error codes
- Message types 0x30-0x33

## [0.6.0-0.3] - 2024-12-01

### Added
- Semantic Protocol Extension
- Node discovery and messaging
- State synchronization
- INV19-26 (semantic layer invariants)
- Message types 0x01-0x22

## [0.5.0] - 2024-11-01

### Added
- Ephemeral Data Governance
- EpochCapability system
- EpochDataPolicy constraints
- INV14-18 (ephemeral invariants)

## [0.4.0] - 2024-10-01

### Added
- Validator management
- Quorum validation
- Dispute resolution
- Slashing mechanism
- INV7-13 (validation invariants)

## [0.3.0] - 2024-09-01

### Added
- Declaration layer
- `declarePresence` function
- Declared state

## [0.2.0] - 2024-08-01

### Added
- Epoch lifecycle
- Epoch states: Scheduled → Active → Closed → Finalized

## [0.1.0] - 2024-07-01

### Added
- Initial presence specification
- Presence states: None → Finalized
- INV1-6 (presence invariants)

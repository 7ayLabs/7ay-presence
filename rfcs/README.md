# 7ay Presence Protocol — RFC Process

## 1. Overview

This document defines the Request for Comments (RFC) process for the 7ay Presence Protocol. RFCs provide a structured mechanism for proposing, discussing, and ratifying protocol modifications through decentralized governance.

## 2. Scope

### 2.1 Changes Requiring RFC

The following modifications MUST be proposed through an RFC:

| Category | Examples |
|----------|----------|
| Invariant modifications | Adding, removing, or altering INV1-42+ |
| State machine changes | New states, transitions, or terminal conditions |
| Capability extensions | New EpochCapability values |
| Message type additions | New entries in MessageType enum (0x00-0xFF) |
| Breaking changes | Any modification affecting backwards compatibility |
| Economic parameters | Quorum thresholds, dispute windows |

### 2.2 Changes NOT Requiring RFC

| Category | Examples |
|----------|----------|
| Documentation fixes | Typos, grammar, formatting |
| Clarifications | Non-semantic improvements to existing text |
| Implementation notes | Substrate/Rust guidance updates |
| Test case additions | New test scenarios without spec changes |

## 3. RFC Lifecycle

### 3.1 State Diagram

```
                                    ┌─────────────┐
                                    │  Withdrawn  │
                                    └──────▲──────┘
                                           │
┌────────┐    ┌────────┐    ┌────────┐    │    ┌──────────┐    ┌─────────────┐
│ Draft  │───►│ Review │───►│ Voting │────┼───►│ Accepted │───►│ Implemented │
└────────┘    └────────┘    └────────┘    │    └──────────┘    └─────────────┘
                                          │
                                    ┌─────▼─────┐
                                    │  Rejected │
                                    └───────────┘
```

### 3.2 State Definitions

| State | Definition | Duration |
|-------|------------|----------|
| Draft | Author is actively developing the proposal | No limit |
| Review | Open for public comment and technical review | Minimum 7 days |
| Voting | On-chain DAO vote in progress | Governance-defined |
| Accepted | Approved by governance, awaiting implementation | No limit |
| Implemented | Merged into specification | Terminal |
| Rejected | Not approved by governance | Terminal |
| Withdrawn | Author has retracted the proposal | Terminal |

## 4. Submission Requirements

### 4.1 Process

1. Fork the `7ay-presence` repository
2. Create RFC file: `rfcs/NNNN-descriptive-title.md`
3. Use template: `rfcs/0000-template.md`
4. Submit Pull Request targeting `develop` branch
5. Request review from protocol maintainers

### 4.2 Numbering Convention

- Sequential four-digit identifier (0001, 0002, ...)
- Lowercase kebab-case title
- Format: `NNNN-short-descriptive-title.md`

### 4.3 Required Sections

All RFCs MUST include:
- Summary (single paragraph)
- Motivation (problem statement)
- Specification (technical details)
- Backwards Compatibility analysis
- Security Considerations

## 5. Governance Integration

### 5.1 DAO Voting

RFCs transitioning to Voting state are subject to on-chain governance:
- Voting mechanism defined by 7ay DAO governance contracts
- Quorum and approval thresholds per governance parameters
- Vote weight determined by governance token holdings

### 5.2 Implementation Authority

Upon acceptance:
- Protocol maintainers are authorized to implement changes
- Implementation MUST match accepted RFC specification
- Deviations require new RFC or RFC amendment

## 6. Amendments

### 6.1 Amending Accepted RFCs

Modifications to accepted but unimplemented RFCs:
- Minor changes: PR to existing RFC with maintainer approval
- Major changes: New RFC superseding original

### 6.2 Amending Implemented RFCs

Changes to implemented specifications:
- MUST follow full RFC process
- Reference original RFC in "Supersedes" field

## 7. References

- 7ay DAO Governance: governance contracts (TODO: add canonical link)
- Protocol Specifications: `specs/README.md`
- RFC Template: `rfcs/0000-template.md`

# Security Policy

## Scope

This policy covers the 7ay Presence Protocol specification. For implementation-specific vulnerabilities, contact the relevant implementation maintainers.

## Reporting Vulnerabilities

### Process

1. **Do not** disclose publicly
2. Email: security@7aylabs.com
3. Include:
   - Affected specification section
   - Description of the vulnerability
   - Potential impact assessment
   - Suggested mitigation (if any)

### Response Timeline

| Stage | Timeframe |
|-------|-----------|
| Acknowledgment | 48 hours |
| Initial assessment | 7 days |
| Resolution timeline | 14 days |
| Public disclosure | After fix or 90 days |

## Vulnerability Categories

### Specification Vulnerabilities

- Invariant violations (INV1-42)
- State machine inconsistencies
- Race conditions in state transitions
- Incomplete error handling

### Implementation Guidance

- Ambiguous requirements
- Missing edge cases
- Security-critical clarifications

## Recognition

Valid vulnerability reports may be acknowledged in the changelog. Monetary rewards are at the discretion of 7ayLabs.

## Safe Harbor

Security research conducted in good faith under this policy is authorized. We will not pursue legal action for research that:

- Follows this disclosure process
- Avoids privacy violations
- Does not disrupt services
- Does not access production data

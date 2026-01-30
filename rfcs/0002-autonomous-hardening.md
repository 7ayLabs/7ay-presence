# RFC-0002: Autonomous Transaction Hardening

| Field | Value |
|-------|-------|
| **RFC** | 0002 |
| **Title** | Progressive Thresholds and Reputation Scoring for Autonomous Transactions |
| **Author** | 7ayLabs Security Council |
| **Status** | Draft |
| **Created** | 2026-01-29 |
| **Updated** | 2026-01-29 |
| **Requires** | RFC-0001 |
| **Supersedes** | None |

---

## Abstract

This RFC enhances the autonomous transaction system (v0.6.6) with progressive pattern thresholds, reputation scoring, and cooldown penalties. Instead of a flat 5 actions/hour threshold for all actors, this proposal introduces a tiered system where actors build reputation through successful executions and lose reputation through rejections. Higher reputation unlocks higher autonomous transaction limits, creating a natural Sybil-resistant meritocracy.

---

## Motivation

### Problem Statement

The current autonomous transaction system has several weaknesses:

1. **Flat Threshold**: All actors have the same 5/hour pattern threshold regardless of history
2. **No Reputation**: New actors and established actors are treated identically
3. **No Penalty for Abuse**: Rejected intents carry no consequence beyond the rejection itself
4. **Sybil Vulnerability**: Attackers can create many identities to multiply their autonomous capacity

### Goals

1. Implement progressive thresholds based on actor reputation
2. Create a reputation scoring system (0-100)
3. Add cooldown penalties for rejected autonomous intents
4. Integrate validator reputation for finalization decisions
5. Reduce Sybil attack effectiveness

### Non-Goals

1. Cross-epoch reputation persistence (addressed in RFC-0005)
2. Reputation delegation or transfer
3. Reputation marketplace

---

## Specification

### Overview

The hardening system consists of:
1. **Reputation Score** (0-100) tracked per actor per epoch
2. **Progressive Tiers** that unlock higher thresholds
3. **Cooldown Mechanism** that penalizes abuse
4. **Validator Integration** for finalization voting

### Detailed Design

#### Reputation Score

```rust
pub struct ReputationScore {
    /// Actor address
    pub actor: AccountId,

    /// Epoch ID (reputation is epoch-scoped)
    pub epoch_id: u128,

    /// Current reputation score (0-100)
    pub score: u8,

    /// Total successful autonomous executions
    pub successful_executions: u32,

    /// Total rejected intents
    pub rejections: u32,

    /// Consecutive rejections (resets on success)
    pub consecutive_rejections: u8,

    /// Timestamp when cooldown expires (0 if no cooldown)
    pub cooldown_until: u64,

    /// Last activity timestamp
    pub last_activity: u64,
}

impl Default for ReputationScore {
    fn default() -> Self {
        Self {
            actor: Default::default(),
            epoch_id: 0,
            score: 50,  // Start at neutral
            successful_executions: 0,
            rejections: 0,
            consecutive_rejections: 0,
            cooldown_until: 0,
            last_activity: 0,
        }
    }
}
```

#### Progressive Tiers

| Tier | Score Range | Threshold | Cooldown Multiplier |
|------|-------------|-----------|---------------------|
| 1 (Restricted) | 0-30 | 5/hour | 2x |
| 2 (Basic) | 31-60 | 20/hour | 1x |
| 3 (Enhanced) | 61-90 | 50/hour | 0.5x |
| 4 (Trusted) | 91-100 | 100/hour | 0.25x |

```rust
pub fn get_tier(score: u8) -> Tier {
    match score {
        0..=30 => Tier::Restricted,
        31..=60 => Tier::Basic,
        61..=90 => Tier::Enhanced,
        91..=100 => Tier::Trusted,
        _ => Tier::Restricted,  // Safety fallback
    }
}

pub fn get_threshold(tier: Tier) -> u32 {
    match tier {
        Tier::Restricted => 5,
        Tier::Basic => 20,
        Tier::Enhanced => 50,
        Tier::Trusted => 100,
    }
}
```

#### Reputation Changes

| Event | Score Change | Notes |
|-------|--------------|-------|
| Successful execution | +1 | Capped at 100 |
| Rejected intent | -5 | Minimum 0 |
| Revoked intent | -10 | Actor-initiated |
| Cooldown violation | -20 | Attempted action during cooldown |
| Validator finalization | +2 | Bonus for validator-approved |

```rust
pub fn update_reputation(
    actor: &AccountId,
    event: ReputationEvent,
) -> Result<u8, Error> {
    let mut rep = Reputation::<T>::get(actor).unwrap_or_default();

    match event {
        ReputationEvent::SuccessfulExecution => {
            rep.score = rep.score.saturating_add(1).min(100);
            rep.successful_executions += 1;
            rep.consecutive_rejections = 0;  // Reset streak
        }
        ReputationEvent::Rejection => {
            rep.score = rep.score.saturating_sub(5);
            rep.rejections += 1;
            rep.consecutive_rejections += 1;
            rep.cooldown_until = calculate_cooldown(rep.consecutive_rejections);
        }
        ReputationEvent::Revocation => {
            rep.score = rep.score.saturating_sub(10);
        }
        ReputationEvent::CooldownViolation => {
            rep.score = rep.score.saturating_sub(20);
        }
        ReputationEvent::ValidatorFinalized => {
            rep.score = rep.score.saturating_add(2).min(100);
        }
    }

    rep.last_activity = now();
    Reputation::<T>::insert(actor, rep.clone());

    Ok(rep.score)
}
```

#### Cooldown Mechanism

Cooldown uses exponential backoff:

```rust
pub fn calculate_cooldown(consecutive_rejections: u8) -> u64 {
    if consecutive_rejections == 0 {
        return 0;
    }

    // Base: 60 seconds (1 minute)
    // Multiplier: 2^(consecutive-1)
    // Max: 86400 seconds (24 hours)

    let base: u64 = 60;
    let multiplier = 2u64.pow((consecutive_rejections - 1) as u32);
    let cooldown = base.saturating_mul(multiplier);

    cooldown.min(86400)
}

// Examples:
// 1 rejection: 60s (1 min)
// 2 rejections: 120s (2 min)
// 3 rejections: 240s (4 min)
// 4 rejections: 480s (8 min)
// 5 rejections: 960s (16 min)
// 10 rejections: 30720s (8.5 hours)
// 11+ rejections: 86400s (24 hours, capped)
```

**Tier-based Cooldown Multiplier:**

```rust
pub fn apply_tier_multiplier(base_cooldown: u64, tier: Tier) -> u64 {
    match tier {
        Tier::Restricted => base_cooldown * 2,
        Tier::Basic => base_cooldown,
        Tier::Enhanced => base_cooldown / 2,
        Tier::Trusted => base_cooldown / 4,
    }
}
```

#### Intent Validation (Updated)

```rust
pub fn validate_autonomous_intent(
    actor: &AccountId,
    intent: &AutonomousIntent,
) -> Result<(), Error> {
    let rep = Reputation::<T>::get(actor).unwrap_or_default();

    // 1. Check cooldown
    if now() < rep.cooldown_until {
        // Cooldown violation attempt
        update_reputation(actor, ReputationEvent::CooldownViolation)?;
        return Err(Error::CooldownActive);
    }

    // 2. Get tier and threshold
    let tier = get_tier(rep.score);
    let threshold = get_threshold(tier);

    // 3. Check pattern meets tier threshold
    match &intent.pattern {
        Pattern::Frequency { actions_per_hour, .. } => {
            ensure!(*actions_per_hour <= threshold, Error::ThresholdExceeded);
        }
        Pattern::Periodic { executions, .. } => {
            // Periodic has different calculation
            ensure!(*executions <= threshold / 2, Error::ThresholdExceeded);
        }
        Pattern::Conditional { max_triggers, .. } => {
            ensure!(*max_triggers <= threshold / 5, Error::ThresholdExceeded);
        }
    }

    // 4. Check rate limit for current hour
    let hourly_count = get_hourly_intent_count(actor)?;
    ensure!(hourly_count < threshold, Error::HourlyLimitExceeded);

    Ok(())
}
```

#### Validator Integration

Validators consider reputation when voting on finalization:

```rust
pub fn should_approve_finalization(
    intent: &AutonomousIntent,
    actor_reputation: &ReputationScore,
) -> bool {
    // Auto-approve for trusted actors with clean history
    if actor_reputation.score >= 90 && actor_reputation.consecutive_rejections == 0 {
        return true;
    }

    // Require manual review for restricted actors
    if actor_reputation.score <= 30 {
        return false;  // Requires manual validator vote
    }

    // Standard approval for basic/enhanced
    // (Actual voting logic depends on intent specifics)
    true
}
```

#### Invariants

| Invariant | Description |
|-----------|-------------|
| INV50 | **Reputation Range**: `∀ actor: 0 <= reputation(actor) <= 100` |
| INV51 | **Reputation Impact**: `rejection → reputation -= 5 (minimum 0)` |
| INV52 | **Progressive Threshold**: `threshold = f(tier(reputation))` |
| INV53 | **Cooldown Enforcement**: `cooldown_violation → -20 reputation` |

**Formal Definitions:**

```
INV50: Reputation Range
∀ actor a, epoch e:
  0 <= reputation(a, e).score <= 100

INV51: Reputation Impact
∀ rejection_event(actor):
  reputation'(actor) = max(0, reputation(actor) - 5)

INV52: Progressive Threshold
∀ intent i from actor a:
  i.threshold <= get_threshold(get_tier(reputation(a)))

INV53: Cooldown Enforcement
∀ action during cooldown:
  reputation'(actor) = max(0, reputation(actor) - 20)
  action is REJECTED
```

#### Error Conditions

| Code | Name | Description |
|------|------|-------------|
| AUTO_010 | CooldownActive | Action attempted during cooldown |
| AUTO_011 | ThresholdExceeded | Intent exceeds tier threshold |
| AUTO_012 | HourlyLimitExceeded | Hourly intent count exceeded |
| AUTO_013 | ReputationTooLow | Action requires higher reputation |

---

## Backwards Compatibility

### Impact Assessment

| Component | Impact | Migration Required |
|-----------|--------|-------------------|
| AutonomousIntent struct | Minor | No |
| Pattern validation | Breaking | Yes |
| Intent finalization | Minor | No |

### Migration Path

1. **Phase 1**: Deploy reputation tracking (passive)
2. **Phase 2**: Enable progressive thresholds (with 30-day grace period)
3. **Phase 3**: Full enforcement

During grace period, existing intents continue with legacy 5/hour threshold.

---

## Security Considerations

### Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| Sybil attack | High | Medium | Presence requirement, slow reputation building |
| Reputation grinding | Medium | Low | Diminishing returns, epoch reset |
| Cooldown evasion | Low | Medium | Address-bound cooldown |

### Mitigations

1. **Sybil Resistance**: Creating new identities means starting at score 50, not 100
2. **Grinding Prevention**: +1 per success means 50 successful executions to reach Trusted
3. **Evasion Prevention**: Cooldown tied to address, not intent

---

## References

- [specs/extensions/autonomous.md](../specs/extensions/autonomous.md) — Current autonomous spec
- [RFC-0001](0001-validator-security-model.md) — Validator security (reputation integration)

---

## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-29 | 7ayLabs Security Council | Initial draft |

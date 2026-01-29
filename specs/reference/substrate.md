# 7ay Proof of Presence (PoP)
## Substrate Implementation Notes
**Version:** v0.6
**Status:** Draft
**Scope:** Implementation guidance for Rust/Substrate

---

## 1. Purpose

This document provides guidance for implementing the 7ay Presence Protocol
in Rust using the Substrate framework.

> **Note:** Unlike other spec files which use clean Rust examples, this document
> intentionally uses Substrate FRAME macros (`#[pallet::*]`) as it serves as
> implementation guidance for the Substrate target platform.

---

## 2. Pallet Mapping

| Spec | Pallet | Storage |
|------|--------|---------|
| presence.md | `pallet-presence` | Presences, ValidationVotes |
| epochs.md | `pallet-epochs` | Epochs, Capabilities, Policies |
| validators.md | `pallet-validators` | Validators, Quorum |
| disputes.md | `pallet-disputes` | Disputes, DisputeVotes |
| node-model.md | `pallet-discovery` | NodeRegistry |

---

## 3. Type Mappings

### 3.1 Core Substrate Types

| Concept | Substrate Type | Notes |
|---------|----------------|-------|
| Account/Address | `AccountId` | 32 bytes, SS58 encoded |
| Large Integer | `u128` or `U256` | Use `u128` for most cases |
| Hash/Identifier | `H256` or `[u8; 32]` | 32-byte hash |
| Key-Value Store | `StorageMap<K, V>` | Single-key mapping |
| Nested Mapping | `StorageDoubleMap<K1, K2, V>` | Two-key mapping |
| Current Time | `pallet_timestamp::Pallet::<T>::now()` | Unix timestamp |
| Transaction Sender | `ensure_signed(origin)?` | Extracts AccountId from origin |

### 3.2 Enums

```rust
#[derive(Clone, Encode, Decode, Eq, PartialEq, RuntimeDebug, TypeInfo, MaxEncodedLen)]
pub enum PresenceState {
    None,
    Declared,
    Validated,
    Finalized,
    Slashed,
}

#[derive(Clone, Encode, Decode, Eq, PartialEq, RuntimeDebug, TypeInfo, MaxEncodedLen)]
pub enum EpochState {
    None,
    Scheduled,
    Active,
    Closed,
    Finalized,
}

#[derive(Clone, Encode, Decode, Eq, PartialEq, RuntimeDebug, TypeInfo, MaxEncodedLen)]
pub enum EpochCapability {
    PresenceOnly,
    PresenceWithSignals,
    PresenceWithEphemeralData,
}
```

---

## 4. Storage Patterns

### 4.1 Single Values

```rust
#[pallet::storage]
pub type DisputeWindow<T> = StorageValue<_, u64, ValueQuery>;
```

### 4.2 Simple Maps

```rust
#[pallet::storage]
pub type Epochs<T: Config> = StorageMap<
    _,
    Blake2_128Concat,
    u128,  // epoch_id
    Epoch<T>,
    OptionQuery,
>;
```

### 4.3 Double Maps (Epoch-Scoped Data)

```rust
#[pallet::storage]
pub type Presences<T: Config> = StorageDoubleMap<
    _,
    Blake2_128Concat,
    T::AccountId,  // actor
    Blake2_128Concat,
    u128,          // epoch_id
    PresenceState,
    ValueQuery,
>;
```

---

## 5. Error Handling

### 5.1 Substrate Error Patterns

| Pattern | Substrate | Notes |
|---------|-----------|-------|
| Condition check | `ensure!(condition, Error::<T>::Message)` | Macro for conditional error |
| Explicit error | `return Err(Error::<T>::ErrorName.into())` | Return typed error |
| Option unwrap | `value.ok_or(Error::<T>::NotFound)?` | Convert Option to Result |

### 5.2 Error Definition

```rust
#[pallet::error]
pub enum Error<T> {
    InvalidActor,
    UnauthorizedActor,
    InvalidEpoch,
    EpochNotActive,
    PresenceSlashed,
    CallerNotValidator,
    ValidatorAlreadyVoted,
    // ... etc
}
```

---

## 6. Events

```rust
#[pallet::event]
#[pallet::generate_deposit(pub(super) fn deposit_event)]
pub enum Event<T: Config> {
    PresenceDeclared {
        actor: T::AccountId,
        epoch_id: u128,
    },
    PresenceValidated {
        actor: T::AccountId,
        epoch_id: u128,
        validator_count: u32,
    },
    PresenceFinalized {
        actor: T::AccountId,
        epoch_id: u128,
    },
    PresenceSlashed {
        actor: T::AccountId,
        epoch_id: u128,
        challenger: T::AccountId,
    },
    // ... etc
}
```

---

## 7. Dispatchable Functions

```rust
#[pallet::call]
impl<T: Config> Pallet<T> {
    #[pallet::weight(T::WeightInfo::declare_presence())]
    pub fn declare_presence(
        origin: OriginFor<T>,
        epoch_id: u128,
    ) -> DispatchResult {
        let actor = ensure_signed(origin)?;

        ensure!(epoch_id != 0, Error::<T>::InvalidEpoch);
        ensure!(
            Self::is_epoch_active(epoch_id),
            Error::<T>::EpochNotActive
        );

        // ... implementation

        Self::deposit_event(Event::PresenceDeclared { actor, epoch_id });
        Ok(())
    }
}
```

---

## 8. Weights and Benchmarks

All extrinsics MUST have weights. Use Substrate benchmarking:

```rust
#[pallet::weight_info]
pub trait WeightInfo {
    fn declare_presence() -> Weight;
    fn validate_presence() -> Weight;
    fn finalize_presence() -> Weight;
    fn initiate_dispute() -> Weight;
    fn vote_on_dispute() -> Weight;
    fn resolve_dispute() -> Weight;
}
```

---

## 9. Testing

### 9.1 Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use frame_support::{assert_ok, assert_noop};

    #[test]
    fn declare_presence_works() {
        new_test_ext().execute_with(|| {
            assert_ok!(Presence::declare_presence(
                RuntimeOrigin::signed(ALICE),
                EPOCH_1
            ));
        });
    }
}
```

### 9.2 Invariant Tests

Implement invariant checks as runtime assertions or separate test modules.

---

## 10. Migration Considerations

### 10.1 Implementation Checklist

- Implement all invariants (INV1-45)
- Follow error priority ordering in error handling
- Emit events matching specification structure for indexers
- Use consistent naming across pallets

### 10.2 Storage Versioning

Use `#[pallet::storage_version]` for upgrades:

```rust
const STORAGE_VERSION: StorageVersion = StorageVersion::new(1);

#[pallet::pallet]
#[pallet::storage_version(STORAGE_VERSION)]
pub struct Pallet<T>(_);
```

---

## 11. References

- [Substrate Developer Hub](https://docs.substrate.io/)
- [FRAME Pallets](https://docs.substrate.io/reference/frame-pallets/)
- [Polkadot-SDK](https://github.com/paritytech/polkadot-sdk)

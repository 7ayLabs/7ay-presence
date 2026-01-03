// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { PresenceRegistry } from "../contracts/core/PresenceRegistry.sol";
import { IPresenceRegistry } from "../contracts/interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistryInvariants
 * @notice Protocol invariants for the 7ay PoP
 *
 * @dev
 * These invariants define the security, correctness, and semantic boundaries
 * of the MVP acceptance-only Presence protocol.
 *
 * Any invariant violation represents a protocol-level failure,
 * not a unit-test failure.
 *
 * Scope:
 * - MVP only (acceptance-only, no lifecycle states)
 * - On-chain persistence limited to {None, Finalized}
 * - No validators, quorum, slashing, or expiration
 *
 * Specification references:
 * - specs/presence.md (MVP profile)
 * - specs/model.md (conceptual model)
 *
 * Testing philosophy:
 * - Property-based (global truths)
 * - Deterministic
 * - Sequence-independent
 */
contract PresenceRegistryInvariants is Test {
    IPresenceRegistry internal registry;

    address internal actor;
    uint256 internal epochId;

    // Test harness initialization for protocol invariants
    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));
        // A single actor and epoch are intentionally used to isolate
        // protocol invariants from scenario-specific behavior.
        actor = address(0xA11CE);
        epochId = 1;
    }

    // === MVP INVARIANTS (MVP — Enforced) ===

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #1 (MVP — Enforced)
      Only {None, Finalized} presence states are ever reachable (protocol rule)
    //////////////////////////////////////////////////////////////*/

    function invariant_singleFinalizedPresencePerEpoch() external {
        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);
        assertTrue(
            state == IPresenceRegistry.PresenceState.None ||
            state == IPresenceRegistry.PresenceState.Finalized
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #2 (MVP — Enforced)
      Finalized presence state is strictly immutable (protocol rule)
    //////////////////////////////////////////////////////////////*/

    function invariant_finalizedPresenceIsImmutable() external {
        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);
        assertTrue(
            state == IPresenceRegistry.PresenceState.Finalized
        );

        // Repeated finalize calls do not change the state
        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
        IPresenceRegistry.PresenceState stateAfter =
            registry.presenceState(actor, epochId);
        assertTrue(
            stateAfter == IPresenceRegistry.PresenceState.Finalized
        );
    }
    /*//////////////////////////////////////////////////////////////
                        INVARIANT #3 (MVP — Enforced)
      Finalization is idempotent and deterministic (protocol rule)
    //////////////////////////////////////////////////////////////*/
    function invariant_deterministicFinalization() external {
        // Call finalizePresence twice, ensuring both times the state is Finalized
        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
        IPresenceRegistry.PresenceState state1 =
            registry.presenceState(actor, epochId);
        assertTrue(
            state1 == IPresenceRegistry.PresenceState.Finalized
        );

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
        IPresenceRegistry.PresenceState state2 =
            registry.presenceState(actor, epochId);
        assertTrue(
            state2 == IPresenceRegistry.PresenceState.Finalized
        );
    }

    // === ADDITIONAL MVP PROTOCOL INVARIANTS (MVP — Enforced) ===

    /// Invariant — Actor Authorization Binding
    /// Presence finalization MUST be authorized exclusively by the actor itself.
    /// No other address can ever finalize presence for another actor.
    function invariant_onlyActorCanFinalizePresence() external {
        address attacker = address(0xBEEF);

        vm.prank(attacker);
        try registry.finalizePresence(actor, epochId) {
            // If this succeeds, invariant is violated
            assertTrue(false);
        } catch {
            // Expected: cannot finalize for another actor
            assertTrue(true);
        }
    }

    /// Invariant — Actor Isolation
    /// Finalizing presence for one actor MUST NEVER affect the presence state of any other actor.
    function invariant_actorIsolation() external {
        address actor2 = address(0xB0B);

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        assertTrue(
            registry.presenceState(actor, epochId)
                == IPresenceRegistry.PresenceState.Finalized
        );
        assertTrue(
            registry.presenceState(actor2, epochId)
                == IPresenceRegistry.PresenceState.None
        );
    }

    /// Invariant — Epoch Isolation
    /// Finalizing presence in one epoch MUST NEVER affect any other epoch for the same actor.
    function invariant_epochIsolation() external {
        vm.prank(actor);
        registry.finalizePresence(actor, 1);

        assertTrue(
            registry.presenceState(actor, 1)
                == IPresenceRegistry.PresenceState.Finalized
        );
        assertTrue(
            registry.presenceState(actor, 2)
                == IPresenceRegistry.PresenceState.None
        );
    }

    /// Invariant — Monotonicity of Finalized State
    /// Once presence is finalized, it MUST NEVER revert to None.
    function invariant_finalizedIsMonotonic() external {
        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);

        assertTrue(
            state == IPresenceRegistry.PresenceState.Finalized
        );
    }
}
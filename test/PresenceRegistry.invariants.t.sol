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

    // === MVP INVARIANTS (Enforced) ===
    // Reference: specs/presence.md Section 7, specs/model.md Section 5

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #1
      An actor MUST NOT have more than one finalized presence per epoch.
      Only {None, Finalized} presence states are ever reachable.
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
                        INVARIANT #2
      A finalized presence MUST NOT be reverted.
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
                        INVARIANT #3
      Presence state transitions MUST be deterministic and idempotent.
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

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #4
      Only the actor itself MAY finalize its own presence.
    //////////////////////////////////////////////////////////////*/

    function invariant_onlyActorCanFinalizePresence() external {
        address attacker = address(0xBEEF);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.UnauthorizedActor.selector,
                attacker,
                actor
            )
        );
        registry.finalizePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #5
      Finalizing presence for one actor MUST NOT affect any other actor.
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #6
      Finalizing presence in one epoch MUST NOT affect any other epoch.
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #7
      A finalized presence MUST NOT transition back to None.
    //////////////////////////////////////////////////////////////*/

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
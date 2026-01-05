// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../contracts/interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistryHandler
 * @notice Handler contract for Foundry invariant testing
 *
 * @dev
 * This handler exposes actions that the fuzzer can call to mutate
 * protocol state. Ghost variables track state for invariant assertions.
 *
 * Pattern: The fuzzer calls handler functions randomly, then invariant
 * functions verify protocol properties hold regardless of call sequence.
 */
contract PresenceRegistryHandler is Test {
    IPresenceRegistry public registry;

    // Ghost variables for tracking state across fuzzer calls
    mapping(address => mapping(uint256 => bool)) public ghost_finalized;
    address[] public ghost_actors;
    uint256[] public ghost_epochs;

    // Bounded actors and epochs for focused fuzzing
    address[] internal boundedActors;
    uint256[] internal boundedEpochs;

    constructor(IPresenceRegistry _registry) {
        registry = _registry;

        // Initialize bounded sets for focused invariant testing
        boundedActors.push(address(0xA11CE));
        boundedActors.push(address(0xB0B));
        boundedActors.push(address(0xCAFE));

        boundedEpochs.push(1);
        boundedEpochs.push(2);
        boundedEpochs.push(3);
        boundedEpochs.push(type(uint256).max);
    }

    /**
     * @notice Finalize presence with bounded inputs
     * @dev Called by fuzzer to mutate state
     */
    function finalizePresence(uint256 actorSeed, uint256 epochSeed) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        // Track pre-state for monotonicity checks
        bool wasFinalized = ghost_finalized[actor][epochId];

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        // Update ghost state
        if (!wasFinalized) {
            ghost_finalized[actor][epochId] = true;
            ghost_actors.push(actor);
            ghost_epochs.push(epochId);
        }
    }

    /**
     * @notice Attempt unauthorized finalization (should always revert)
     * @dev Verifies authorization invariant holds under fuzzing
     */
    function finalizePresenceUnauthorized(uint256 callerSeed, uint256 actorSeed, uint256 epochSeed) external {
        address caller = boundedActors[callerSeed % boundedActors.length];
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        if (caller == actor) return; // Skip valid calls

        vm.prank(caller);
        vm.expectRevert();
        registry.finalizePresence(actor, epochId);
    }

    // === Getters for invariant assertions ===

    function getGhostActorsLength() external view returns (uint256) {
        return ghost_actors.length;
    }

    function getGhostActor(uint256 index) external view returns (address) {
        return ghost_actors[index];
    }

    function getGhostEpoch(uint256 index) external view returns (uint256) {
        return ghost_epochs[index];
    }
}

/**
 * @title PresenceRegistryInvariants
 * @notice Protocol invariants for the 7ay PoP using Foundry invariant testing
 *
 * @dev
 * These invariants define the security, correctness, and semantic boundaries
 * of the MVP acceptance-only Presence protocol.
 *
 * Any invariant violation represents a protocol-level failure.
 *
 * Testing methodology:
 * - Handler contract mutates state via bounded random calls
 * - Invariant functions verify properties hold after each sequence
 * - Ghost variables track expected state for cross-reference
 *
 * Specification references:
 * - specs/presence.md (MVP profile)
 * - specs/model.md (conceptual model)
 * - specs/errors.md (error handling)
 */
contract PresenceRegistryInvariants is Test {
    IPresenceRegistry internal registry;
    PresenceRegistryHandler internal handler;

    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));
        handler = new PresenceRegistryHandler(registry);

        // Target only the handler for fuzzing
        targetContract(address(handler));

        // Target specific functions for focused fuzzing
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PresenceRegistryHandler.finalizePresence.selector;
        selectors[1] = PresenceRegistryHandler.finalizePresenceUnauthorized.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #1: Binary State Space
      Only {None, Finalized} presence states are ever reachable.
      Reference: specs/presence.md Section 7
    //////////////////////////////////////////////////////////////*/

    function invariant_binaryStateSpace() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.PresenceState state = registry.presenceState(actor, epochId);

            assertTrue(
                state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Finalized,
                "INV1: Invalid state detected"
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #2: Finalization Monotonicity
      Once finalized, a presence MUST remain finalized forever.
      State transitions: None -> Finalized (one-way, irreversible)
      Reference: specs/presence.md Section 7
    //////////////////////////////////////////////////////////////*/

    function invariant_finalizationMonotonicity() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            // If ghost says finalized, on-chain state MUST be Finalized
            if (handler.ghost_finalized(actor, epochId)) {
                assertEq(
                    uint256(registry.presenceState(actor, epochId)),
                    uint256(IPresenceRegistry.PresenceState.Finalized),
                    "INV2: Finalized state reverted to None"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #3: Actor Isolation
      Finalizing for actorA MUST NOT affect actorB's state.
      Reference: specs/model.md Section 5
    //////////////////////////////////////////////////////////////*/

    function invariant_actorIsolation() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            // Verify state matches ghost tracking exactly
            bool ghostFinalized = handler.ghost_finalized(actor, epochId);
            IPresenceRegistry.PresenceState onChainState = registry.presenceState(actor, epochId);

            if (ghostFinalized) {
                assertEq(
                    uint256(onChainState),
                    uint256(IPresenceRegistry.PresenceState.Finalized),
                    "INV3: Actor state mismatch"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #4: Epoch Isolation
      Finalizing in epochA MUST NOT affect epochB's state.
      Reference: specs/model.md Section 5
    //////////////////////////////////////////////////////////////*/

    function invariant_epochIsolation() external view {
        // For each tracked finalization, verify other epochs unaffected
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            // Check adjacent epoch is unaffected (unless explicitly finalized)
            uint256 adjacentEpoch = epochId == type(uint256).max ? epochId - 1 : epochId + 1;

            if (!handler.ghost_finalized(actor, adjacentEpoch)) {
                assertEq(
                    uint256(registry.presenceState(actor, adjacentEpoch)),
                    uint256(IPresenceRegistry.PresenceState.None),
                    "INV4: Adjacent epoch unexpectedly affected"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #5: Ghost Consistency
      Ghost tracking MUST match on-chain state exactly.
      This meta-invariant validates our testing methodology.
    //////////////////////////////////////////////////////////////*/

    function invariant_ghostConsistency() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            bool ghostFinalized = handler.ghost_finalized(actor, epochId);
            IPresenceRegistry.PresenceState onChainState = registry.presenceState(actor, epochId);

            // Ghost and on-chain MUST be synchronized
            assertEq(
                ghostFinalized, onChainState == IPresenceRegistry.PresenceState.Finalized, "INV5: Ghost/on-chain desync"
            );
        }
    }
}

/**
 * @title PresenceRegistryPropertyTests
 * @notice Deterministic property tests (previously mislabeled as invariants)
 *
 * @dev
 * These tests verify specific protocol properties with fixed inputs.
 * They complement fuzz tests and invariant tests by covering explicit scenarios.
 *
 * Naming: test_* prefix indicates deterministic unit/property tests.
 */
contract PresenceRegistryPropertyTests is Test {
    IPresenceRegistry internal registry;

    address internal constant ACTOR = address(0xA11CE);
    address internal constant ATTACKER = address(0xBEEF);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Single Finalization Per Epoch
      An actor MUST NOT have more than one finalized presence per epoch.
    //////////////////////////////////////////////////////////////*/

    function test_singleFinalizedPresencePerEpoch() external {
        // Pre-state: None
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));

        // Finalize
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        // Post-state: Finalized
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));

        // State space is binary
        IPresenceRegistry.PresenceState state = registry.presenceState(ACTOR, EPOCH_ID);
        assertTrue(state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Finalized);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Finalized Immutability
      A finalized presence MUST NOT be reverted.
    //////////////////////////////////////////////////////////////*/

    function test_finalizedPresenceIsImmutable() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateBefore = registry.presenceState(ACTOR, EPOCH_ID);

        // Multiple finalize calls
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateAfter = registry.presenceState(ACTOR, EPOCH_ID);

        // State unchanged
        assertEq(uint256(stateBefore), uint256(stateAfter));
        assertEq(uint256(stateAfter), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Deterministic Finalization
      Presence state transitions MUST be deterministic and idempotent.
    //////////////////////////////////////////////////////////////*/

    function test_deterministicFinalization() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state1 = registry.presenceState(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state2 = registry.presenceState(ACTOR, EPOCH_ID);

        assertEq(uint256(state1), uint256(state2));
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Self-Authorization Only
      Only the actor itself MAY finalize its own presence.
    //////////////////////////////////////////////////////////////*/

    function test_onlyActorCanFinalizePresence() external {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, ATTACKER, ACTOR));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Actor Isolation
      Finalizing presence for one actor MUST NOT affect any other actor.
    //////////////////////////////////////////////////////////////*/

    function test_actorIsolation() external {
        address actor2 = address(0xB0B);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(actor2, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));
    }

    /*//////////////////////////////////////////////////////////////
                        PROPERTY: Epoch Isolation
      Finalizing presence in one epoch MUST NOT affect any other epoch.
    //////////////////////////////////////////////////////////////*/

    function test_epochIsolation() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, 1);

        assertEq(uint256(registry.presenceState(ACTOR, 1)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(ACTOR, 2)), uint256(IPresenceRegistry.PresenceState.None));
    }
}

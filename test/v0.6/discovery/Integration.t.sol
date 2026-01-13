// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title DiscoveryIntegrationTests
 * @notice Integration tests for v0.6 Node Discovery semantics
 * @dev Tests INV21 (Epoch Scoping) and INV22 (Presence-Gated Discovery)
 *
 * Spec: specs/v0.6/discovery.md
 *
 * These tests validate the on-chain components that support node discovery:
 * - Presence verification for discovered nodes
 * - Epoch scoping of presence states
 * - Validator role verification
 * - Discovery-relevant state transitions
 */
contract DiscoveryIntegrationTests is Test {
    IPresenceRegistry internal presenceRegistry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;

    EpochRegistry internal _epochRegistry;
    ValidatorRegistry internal _validatorRegistry;
    PresenceRegistry internal _presenceRegistry;

    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);
    address internal constant VALIDATOR_4 = address(0x1004);

    address internal constant PARTICIPANT_A = address(0x2001);
    address internal constant PARTICIPANT_B = address(0x2002);
    address internal constant PARTICIPANT_C = address(0x2003);

    uint256 internal constant EPOCH_42 = 42;
    uint256 internal constant EPOCH_43 = 43;

    function setUp() public {
        _epochRegistry = new EpochRegistry(AUTHORITY);
        _validatorRegistry = new ValidatorRegistry(AUTHORITY);
        _presenceRegistry = new PresenceRegistry(
            IEpochRegistry(address(_epochRegistry)), IValidatorRegistry(address(_validatorRegistry)), 0
        );

        epochRegistry = IEpochRegistry(address(_epochRegistry));
        validatorRegistry = IValidatorRegistry(address(_validatorRegistry));
        presenceRegistry = IPresenceRegistry(address(_presenceRegistry));

        // Setup epochs with PresenceWithSignals capability
        vm.startPrank(AUTHORITY);
        _epochRegistry.createEpochWithCapability(
            EPOCH_42,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0)
        );
        _epochRegistry.createEpochWithCapability(
            EPOCH_43,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0)
        );

        // Register 4 validators: minimum 3 required + 1 for removal testing
        // With 4 validators, quorum is ceil(4 * 67 / 100) = 3
        _validatorRegistry.addValidator(VALIDATOR_1);
        _validatorRegistry.addValidator(VALIDATOR_2);
        _validatorRegistry.addValidator(VALIDATOR_3);
        _validatorRegistry.addValidator(VALIDATOR_4);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    INV21: EPOCH SCOPING TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that presence is epoch-scoped (INV21)
     * @dev A node's presence in one epoch does not affect other epochs
     */
    function test_INV21_presenceEpochScoped() public {
        // Participant A declares in epoch 42
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        // Verify presence in epoch 42
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_42)),
            uint256(IPresenceRegistry.PresenceState.Declared),
            "Should have Declared presence in epoch 42"
        );

        // Verify NO presence in epoch 43 (epoch scoping)
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_43)),
            uint256(IPresenceRegistry.PresenceState.None),
            "Should have no presence in epoch 43"
        );
    }

    /**
     * @notice Test that discovery queries must respect epoch boundaries
     * @dev Simulates discovery verification for nodes in different epochs
     */
    function test_INV21_discoveryEpochFiltering() public {
        // Setup: A in epoch 42, B in epoch 43
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        // Warp to epoch 43 start
        vm.warp(block.timestamp + 1 days);

        vm.prank(PARTICIPANT_B);
        presenceRegistry.declarePresence(PARTICIPANT_B, EPOCH_43);

        // Discovery for epoch 42 should find A, not B
        IPresenceRegistry.PresenceState stateA42 = presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_42);
        IPresenceRegistry.PresenceState stateB42 = presenceRegistry.presenceState(PARTICIPANT_B, EPOCH_42);

        assertTrue(stateA42 != IPresenceRegistry.PresenceState.None, "A should be discoverable in epoch 42");
        assertEq(
            uint256(stateB42), uint256(IPresenceRegistry.PresenceState.None), "B should NOT be discoverable in epoch 42"
        );

        // Discovery for epoch 43 should find B, not A
        IPresenceRegistry.PresenceState stateA43 = presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_43);
        IPresenceRegistry.PresenceState stateB43 = presenceRegistry.presenceState(PARTICIPANT_B, EPOCH_43);

        assertEq(
            uint256(stateA43), uint256(IPresenceRegistry.PresenceState.None), "A should NOT be discoverable in epoch 43"
        );
        assertTrue(stateB43 != IPresenceRegistry.PresenceState.None, "B should be discoverable in epoch 43");
    }

    /**
     * @notice Test that same address can have different states in different epochs
     */
    function test_INV21_multiEpochParticipation() public {
        // Declare in epoch 42
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        // Validate in epoch 42
        _validatePresence(PARTICIPANT_A, EPOCH_42);

        // Warp and declare in epoch 43
        vm.warp(block.timestamp + 1 days);
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_43);

        // Different states in different epochs
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_42)),
            uint256(IPresenceRegistry.PresenceState.Validated),
            "Should be Validated in epoch 42"
        );
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_43)),
            uint256(IPresenceRegistry.PresenceState.Declared),
            "Should be Declared in epoch 43"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    INV22: PRESENCE-GATED DISCOVERY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that only nodes with valid presence are discoverable (INV22)
     * @dev Valid states: Declared, Validated, Finalized
     */
    function test_INV22_validPresenceStatesDiscoverable() public {
        // Test Declared state
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Declared should be discoverable");

        // Test Validated state
        _validatePresence(PARTICIPANT_A, EPOCH_42);
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Validated should be discoverable");
    }

    /**
     * @notice Test that None state is not discoverable
     */
    function test_INV22_noneStateNotDiscoverable() public {
        // No presence declared
        assertFalse(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "None state should NOT be discoverable");
    }

    /**
     * @notice Test that Slashed state is not discoverable
     */
    function test_INV22_slashedStateNotDiscoverable() public {
        // Setup: Declare and validate
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);
        _validatePresence(PARTICIPANT_A, EPOCH_42);

        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Should be discoverable before slash");

        // Initiate and uphold dispute to slash
        vm.prank(PARTICIPANT_B);
        presenceRegistry.initiateDispute(PARTICIPANT_A, EPOCH_42, bytes32("evidence"));

        // With 4 validators, quorum is ceil(4 * 67 / 100) = 3
        vm.prank(VALIDATOR_1);
        presenceRegistry.voteOnDispute(PARTICIPANT_A, EPOCH_42, true);
        vm.prank(VALIDATOR_2);
        presenceRegistry.voteOnDispute(PARTICIPANT_A, EPOCH_42, true);
        vm.prank(VALIDATOR_3);
        presenceRegistry.voteOnDispute(PARTICIPANT_A, EPOCH_42, true);

        // Resolve dispute (upheld = slashed)
        presenceRegistry.resolveDispute(PARTICIPANT_A, EPOCH_42);

        assertFalse(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Slashed state should NOT be discoverable");
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATOR ROLE VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test validator role verification for discovery
     * @dev Validators have special priority in discovery
     */
    function test_validatorRoleVerification() public {
        // VALIDATOR_1 is registered validator
        assertTrue(validatorRegistry.isValidatorActive(VALIDATOR_1), "VALIDATOR_1 should be active");

        // PARTICIPANT_A is not a validator
        assertFalse(validatorRegistry.isValidatorActive(PARTICIPANT_A), "PARTICIPANT_A should not be validator");
    }

    /**
     * @notice Test validator presence in discovery context
     */
    function test_validatorWithPresence() public {
        // Validator declares presence
        vm.prank(VALIDATOR_1);
        presenceRegistry.declarePresence(VALIDATOR_1, EPOCH_42);

        // Verify both presence and validator status
        assertTrue(_isDiscoverable(VALIDATOR_1, EPOCH_42), "Validator should be discoverable");
        assertTrue(validatorRegistry.isValidatorActive(VALIDATOR_1), "Should verify as validator");
    }

    /**
     * @notice Test removed validator is not discoverable as validator
     */
    function test_removedValidatorRole() public {
        // Validator declares and then is removed
        vm.prank(VALIDATOR_1);
        presenceRegistry.declarePresence(VALIDATOR_1, EPOCH_42);

        vm.prank(AUTHORITY);
        _validatorRegistry.removeValidator(VALIDATOR_1);

        // Still discoverable but NOT as validator
        assertTrue(_isDiscoverable(VALIDATOR_1, EPOCH_42), "Should still be discoverable");
        assertFalse(validatorRegistry.isValidatorActive(VALIDATOR_1), "Should NOT verify as validator anymore");
    }

    /*//////////////////////////////////////////////////////////////
                    EPOCH CAPABILITY CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that discovery requires PresenceWithSignals capability
     * @dev Nodes should check epoch capability before announcing
     */
    function test_epochCapabilityForDiscovery() public {
        // Epoch 42 has PresenceWithSignals
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(EPOCH_42);
        assertEq(uint256(cap), uint256(IEpochRegistry.EpochCapability.PresenceWithSignals), "Should have signals cap");

        // Can declare presence (discovery prerequisite)
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Discovery should work with signals cap");
    }

    /**
     * @notice Test presence-only epoch has limited discovery
     */
    function test_presenceOnlyEpoch() public {
        uint256 EPOCH_44 = 44;

        // Create epoch with PresenceOnly capability
        vm.prank(AUTHORITY);
        _epochRegistry.createEpochWithCapability(
            EPOCH_44,
            block.timestamp + 2 days,
            block.timestamp + 3 days,
            IEpochRegistry.EpochCapability.PresenceOnly,
            bytes32(0)
        );

        // Warp to epoch 44
        vm.warp(block.timestamp + 2 days);

        // Can still declare presence
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_44);

        // Presence exists but signaling features limited
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(EPOCH_44);
        assertEq(uint256(cap), uint256(IEpochRegistry.EpochCapability.PresenceOnly), "Should have presence-only cap");
    }

    /*//////////////////////////////////////////////////////////////
                    DISCOVERY STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test complete discovery-relevant lifecycle
     */
    function test_discoveryLifecycle() public {
        // Phase 1: Not discoverable (no presence)
        assertFalse(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Phase 1: Not discoverable");

        // Phase 2: Declared (discoverable)
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Phase 2: Discoverable after declare");

        // Phase 3: Validated (still discoverable)
        _validatePresence(PARTICIPANT_A, EPOCH_42);
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Phase 3: Discoverable after validate");

        // Phase 4: Finalized (still discoverable)
        // Close epoch first
        vm.warp(block.timestamp + 1 days + 1);

        presenceRegistry.finalizePresence(PARTICIPANT_A, EPOCH_42);
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Phase 4: Discoverable after finalize");
    }

    /**
     * @notice Test verification timing - periodic re-verification
     */
    function test_periodicVerification() public {
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        // Initial verification
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Initial: discoverable");

        // Simulate time passing (5 minutes - recommended verification interval)
        vm.warp(block.timestamp + 5 minutes);

        // Re-verification should still pass
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "After 5 min: still discoverable");

        // Get validated
        _validatePresence(PARTICIPANT_A, EPOCH_42);

        // Another 5 minutes
        vm.warp(block.timestamp + 5 minutes);

        // Still discoverable with updated state
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "After validation: still discoverable");
    }

    /*//////////////////////////////////////////////////////////////
                    MULTI-PARTICIPANT SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test discovery with multiple participants
     */
    function test_multipleParticipants() public {
        // All three declare
        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        vm.prank(PARTICIPANT_B);
        presenceRegistry.declarePresence(PARTICIPANT_B, EPOCH_42);

        vm.prank(PARTICIPANT_C);
        presenceRegistry.declarePresence(PARTICIPANT_C, EPOCH_42);

        // All discoverable
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "A discoverable");
        assertTrue(_isDiscoverable(PARTICIPANT_B, EPOCH_42), "B discoverable");
        assertTrue(_isDiscoverable(PARTICIPANT_C, EPOCH_42), "C discoverable");

        // Validate only A and B
        _validatePresence(PARTICIPANT_A, EPOCH_42);
        _validatePresence(PARTICIPANT_B, EPOCH_42);

        // All still discoverable, but different states
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_A, EPOCH_42)),
            uint256(IPresenceRegistry.PresenceState.Validated)
        );
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_B, EPOCH_42)),
            uint256(IPresenceRegistry.PresenceState.Validated)
        );
        assertEq(
            uint256(presenceRegistry.presenceState(PARTICIPANT_C, EPOCH_42)),
            uint256(IPresenceRegistry.PresenceState.Declared)
        );
    }

    /**
     * @notice Test mixed validators and participants
     */
    function test_mixedValidatorsAndParticipants() public {
        // Validators and participants declare
        vm.prank(VALIDATOR_1);
        presenceRegistry.declarePresence(VALIDATOR_1, EPOCH_42);

        vm.prank(PARTICIPANT_A);
        presenceRegistry.declarePresence(PARTICIPANT_A, EPOCH_42);

        // Both discoverable
        assertTrue(_isDiscoverable(VALIDATOR_1, EPOCH_42), "Validator discoverable");
        assertTrue(_isDiscoverable(PARTICIPANT_A, EPOCH_42), "Participant discoverable");

        // Role verification differentiates them
        assertTrue(validatorRegistry.isValidatorActive(VALIDATOR_1), "Validator role verified");
        assertFalse(validatorRegistry.isValidatorActive(PARTICIPANT_A), "Participant not validator");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if node is discoverable (INV22 implementation)
     * @dev Discoverable states: Declared, Validated, Finalized
     */
    function _isDiscoverable(address actor, uint256 epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    /**
     * @notice Validate presence with quorum (3 votes required with 4 validators)
     * @dev Assumes 4 active validators with 67% threshold: ceil(4 * 67 / 100) = 3
     */
    function _validatePresence(address actor, uint256 epochId) internal {
        vm.prank(VALIDATOR_1);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_2);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_3);
        presenceRegistry.validatePresence(actor, epochId);
    }
}

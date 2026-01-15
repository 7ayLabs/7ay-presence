// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title StateSyncReconciliationTests
 * @notice Tests for v0.6 state synchronization reconciliation semantics
 * @dev Spec: specs/v0.6/state-sync.md Section 4
 *
 * These tests verify that the on-chain state provides a deterministic
 * source of truth for off-chain state reconciliation.
 */
contract StateSyncReconciliationTests is Test {
    IEpochRegistry internal epochRegistry;
    IPresenceRegistry internal presenceRegistry;
    IValidatorRegistry internal validatorRegistry;

    address internal epochAuthority = address(0xE001);
    address internal validatorAuthority = address(0xA077);

    address internal validator1 = address(0x1001);
    address internal validator2 = address(0x1002);
    address internal validator3 = address(0x1003);

    address internal actor1 = address(0xA11C1);
    address internal actor2 = address(0xA11C2);
    address internal actor3 = address(0xA11C3);

    uint256 internal epochId = 1;

    function setUp() external {
        // Deploy registries
        epochRegistry = IEpochRegistry(address(new EpochRegistry(epochAuthority)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(validatorAuthority)));
        presenceRegistry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        // Bootstrap validators
        vm.startPrank(validatorAuthority);
        validatorRegistry.addValidator(validator1);
        validatorRegistry.addValidator(validator2);
        validatorRegistry.addValidator(validator3);
        vm.stopPrank();

        // Create epoch with signals capability (required for v0.6)
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0) // Optional for signals
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DETERMINISM TESTS (INV26)
    //////////////////////////////////////////////////////////////*/

    /// @dev INV26: On-chain presence state is deterministic source of truth
    function test_reconciliation_presenceStateIsDeterministic() external {
        // Actor declares presence
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        // Query state - should be deterministic
        IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(actor1, epochId);
        IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(actor1, epochId);

        assertEq(uint256(state1), uint256(state2), "INV26: State queries must be deterministic");
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Declared), "State should be Declared");
    }

    /// @dev INV26: Validation count is deterministic
    function test_reconciliation_validationCountIsDeterministic() external {
        // Setup: declare and validate
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        vm.prank(validator1);
        presenceRegistry.validatePresence(actor1, epochId);

        // Query count - should be deterministic
        IPresenceRegistry.Presence memory presence1 = presenceRegistry.getPresence(actor1, epochId);
        IPresenceRegistry.Presence memory presence2 = presenceRegistry.getPresence(actor1, epochId);

        assertEq(presence1.validationCount, presence2.validationCount, "INV26: Validation count must be deterministic");
        assertEq(presence1.validationCount, 1, "Should have 1 vote");
    }

    /// @dev INV26: Multiple actors' states are independently deterministic
    function test_reconciliation_multipleActorsAreDeterministic() external {
        // Declare multiple actors
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        vm.prank(actor2);
        presenceRegistry.declarePresence(actor2, epochId);

        vm.prank(actor3);
        presenceRegistry.declarePresence(actor3, epochId);

        // Validate actor1 with all 3 validators (quorum = 3)
        vm.prank(validator1);
        presenceRegistry.validatePresence(actor1, epochId);
        vm.prank(validator2);
        presenceRegistry.validatePresence(actor1, epochId);
        vm.prank(validator3);
        presenceRegistry.validatePresence(actor1, epochId);

        // Query all states
        IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(actor1, epochId);
        IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(actor2, epochId);
        IPresenceRegistry.PresenceState state3 = presenceRegistry.presenceState(actor3, epochId);

        // actor1 should be Validated (3 votes = quorum)
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Validated), "Actor1 should be Validated");
        assertEq(uint256(state2), uint256(IPresenceRegistry.PresenceState.Declared), "Actor2 should be Declared");
        assertEq(uint256(state3), uint256(IPresenceRegistry.PresenceState.Declared), "Actor3 should be Declared");
    }

    /*//////////////////////////////////////////////////////////////
                    STATE DERIVATION TESTS (INV19)
    //////////////////////////////////////////////////////////////*/

    /// @dev INV19: Node identity (presence state) is derivable from on-chain
    function test_reconciliation_nodeStateDerivableFromOnChain() external {
        // Before declaration - None state
        IPresenceRegistry.PresenceState stateBefore = presenceRegistry.presenceState(actor1, epochId);
        assertEq(uint256(stateBefore), uint256(IPresenceRegistry.PresenceState.None), "Should be None before declare");

        // Declare
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        // After declaration - Declared state
        IPresenceRegistry.PresenceState stateAfter = presenceRegistry.presenceState(actor1, epochId);
        assertEq(
            uint256(stateAfter), uint256(IPresenceRegistry.PresenceState.Declared), "Should be Declared after declare"
        );
    }

    /// @dev INV19: Validator role is derivable from on-chain
    function test_reconciliation_validatorRoleDerivableFromOnChain() external {
        // Check validator status
        bool isValidator1Active = validatorRegistry.isValidatorActive(validator1);
        bool isValidator2Active = validatorRegistry.isValidatorActive(validator2);
        bool isActorValidator = validatorRegistry.isValidatorActive(actor1);

        assertTrue(isValidator1Active, "Validator1 should be active");
        assertTrue(isValidator2Active, "Validator2 should be active");
        assertFalse(isActorValidator, "Actor1 should not be a validator");
    }

    /*//////////////////////////////////////////////////////////////
                    EPOCH CAPABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev v0.6 requires PresenceWithSignals or higher
    function test_reconciliation_epochCapabilityCheck() external {
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId);
        assertEq(
            uint256(cap),
            uint256(IEpochRegistry.EpochCapability.PresenceWithSignals),
            "Epoch should have PresenceWithSignals capability"
        );
    }

    /// @dev Epochs with PresenceOnly are not suitable for v0.6 sync features
    function test_reconciliation_presenceOnlyEpochCapability() external {
        uint256 presenceOnlyEpochId = 2;

        vm.prank(epochAuthority);
        epochRegistry.createEpoch(presenceOnlyEpochId, block.timestamp, block.timestamp + 1 days);

        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(presenceOnlyEpochId);
        assertEq(uint256(cap), uint256(IEpochRegistry.EpochCapability.PresenceOnly), "Default should be PresenceOnly");
    }

    /*//////////////////////////////////////////////////////////////
                    QUORUM VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Quorum size is deterministically derivable
    function test_reconciliation_quorumSizeIsDeterministic() external {
        uint256 quorum1 = validatorRegistry.quorumSize();
        uint256 quorum2 = validatorRegistry.quorumSize();

        assertEq(quorum1, quorum2, "Quorum size must be deterministic");
        // With 3 validators at 67%: ceil(3 * 67 / 100) = ceil(2.01) = 3
        assertEq(quorum1, 3, "Quorum should be 3 for 3 validators at 67%");
    }

    /// @dev Active validator count is deterministic
    function test_reconciliation_activeValidatorCountIsDeterministic() external {
        uint256 count1 = validatorRegistry.activeValidatorCount();
        uint256 count2 = validatorRegistry.activeValidatorCount();

        assertEq(count1, count2, "Active validator count must be deterministic");
        assertEq(count1, 3, "Should have 3 active validators");
    }

    /*//////////////////////////////////////////////////////////////
                    VOTE TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Vote tracking is deterministic
    function test_reconciliation_voteTrackingIsDeterministic() external {
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        vm.prank(validator1);
        presenceRegistry.validatePresence(actor1, epochId);

        // Check vote status
        bool hasVoted1 = presenceRegistry.hasValidatorVotedForPresence(validator1, actor1, epochId);
        bool hasVoted2 = presenceRegistry.hasValidatorVotedForPresence(validator2, actor1, epochId);

        assertTrue(hasVoted1, "Validator1 should have voted");
        assertFalse(hasVoted2, "Validator2 should not have voted");
    }

    /*//////////////////////////////////////////////////////////////
                    DISPUTE STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Dispute state is deterministic
    function test_reconciliation_disputeStateIsDeterministic() external {
        vm.prank(actor1);
        presenceRegistry.declarePresence(actor1, epochId);

        // Before dispute
        IPresenceRegistry.Dispute memory disputeBefore = presenceRegistry.getDispute(actor1, epochId);
        assertEq(
            uint256(disputeBefore.status),
            uint256(IPresenceRegistry.DisputeStatus.None),
            "Should be None before dispute"
        );

        // Initiate dispute
        bytes32 evidenceHash = keccak256("evidence");
        vm.prank(validator1);
        presenceRegistry.initiateDispute(actor1, epochId, evidenceHash);

        // After dispute
        IPresenceRegistry.Dispute memory disputeAfter = presenceRegistry.getDispute(actor1, epochId);
        assertEq(
            uint256(disputeAfter.status),
            uint256(IPresenceRegistry.DisputeStatus.Pending),
            "Should be Pending after dispute"
        );
        assertEq(disputeAfter.evidenceHash, evidenceHash, "Evidence hash should match");
    }

    /*//////////////////////////////////////////////////////////////
                    EPOCH STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Epoch state is deterministic
    function test_reconciliation_epochStateIsDeterministic() external {
        IEpochRegistry.EpochState state1 = epochRegistry.epochState(epochId);
        IEpochRegistry.EpochState state2 = epochRegistry.epochState(epochId);

        assertEq(uint256(state1), uint256(state2), "Epoch state must be deterministic");
        assertEq(uint256(state1), uint256(IEpochRegistry.EpochState.Active), "Should be Active");
    }

    /// @dev Epoch bounds are deterministic
    function test_reconciliation_epochBoundsAreDeterministic() external {
        (uint256 start1, uint256 end1) = epochRegistry.epochBounds(epochId);
        (uint256 start2, uint256 end2) = epochRegistry.epochBounds(epochId);

        assertEq(start1, start2, "Start time must be deterministic");
        assertEq(end1, end2, "End time must be deterministic");
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz: Any actor's presence state is deterministically queryable
    function testFuzz_reconciliation_presenceQueryDeterministic(address actor) external {
        vm.assume(actor != address(0));

        IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(actor, epochId);
        IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(actor, epochId);

        assertEq(uint256(state1), uint256(state2), "Presence state query must be deterministic");
    }

    /// @dev Fuzz: Any epoch's capability is deterministically queryable
    function testFuzz_reconciliation_capabilityQueryDeterministic(uint256 anyEpochId) external {
        IEpochRegistry.EpochCapability cap1 = epochRegistry.epochCapability(anyEpochId);
        IEpochRegistry.EpochCapability cap2 = epochRegistry.epochCapability(anyEpochId);

        assertEq(uint256(cap1), uint256(cap2), "Capability query must be deterministic");
    }
}

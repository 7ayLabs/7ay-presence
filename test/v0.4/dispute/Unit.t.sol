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
 * @title DisputeUnitTests
 * @notice Unit tests for dispute mechanism
 * @dev Spec: specs/v0.4/presence.md
 */
contract DisputeUnitTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;

    address internal constant AUTHORITY = address(0xA077);
    address internal constant ACTOR = address(0xA11CE);
    address internal constant CHALLENGER = address(0xC4A1);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    uint256 internal constant EPOCH_ID = 1;
    bytes32 internal constant EVIDENCE_HASH = keccak256("evidence");

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(EPOCH_ID, block.timestamp, block.timestamp + 1 days);
        validatorRegistry.addValidator(VALIDATOR_1);
        validatorRegistry.addValidator(VALIDATOR_2);
        validatorRegistry.addValidator(VALIDATOR_3);
        vm.stopPrank();
    }

    function _declarePresence() internal {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    function _declareAndValidate() internal {
        _declarePresence();

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIATE DISPUTE
    //////////////////////////////////////////////////////////////*/

    function test_initiateDispute_onDeclared() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Pending));
        assertEq(dispute.challenger, CHALLENGER);
        assertEq(dispute.evidenceHash, EVIDENCE_HASH);
        assertTrue(dispute.initiatedAt > 0);
    }

    function test_initiateDispute_onValidated() external {
        _declareAndValidate();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Pending));
    }

    function test_initiateDispute_emitsEvent() external {
        _declarePresence();

        vm.expectEmit(true, true, true, true);
        emit IPresenceRegistry.DisputeInitiated(ACTOR, EPOCH_ID, CHALLENGER, EVIDENCE_HASH);

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);
    }

    function test_initiateDispute_rejectsNone() external {
        vm.prank(CHALLENGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.InvalidPresenceState.selector,
                ACTOR,
                EPOCH_ID,
                IPresenceRegistry.PresenceState.None,
                IPresenceRegistry.PresenceState.Declared
            )
        );
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);
    }

    function test_initiateDispute_rejectsDuplicate() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(CHALLENGER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.DisputeAlreadyExists.selector, ACTOR, EPOCH_ID));
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);
    }

    function test_initiateDispute_rejectsClosedWindow() external {
        _declarePresence();

        // Warp past dispute window (epoch end + 1 day window)
        vm.warp(block.timestamp + 3 days);

        vm.prank(CHALLENGER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.DisputeWindowClosed.selector, EPOCH_ID));
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);
    }

    function test_initiateDispute_rejectsInvalidActor() external {
        vm.prank(CHALLENGER);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.initiateDispute(address(0), EPOCH_ID, EVIDENCE_HASH);
    }

    function test_initiateDispute_rejectsInvalidEpoch() external {
        vm.prank(CHALLENGER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.initiateDispute(ACTOR, 0, EVIDENCE_HASH);
    }

    /*//////////////////////////////////////////////////////////////
                            VOTE ON DISPUTE
    //////////////////////////////////////////////////////////////*/

    function test_voteOnDispute_upholdVote() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(dispute.votesFor, 1);
        assertEq(dispute.votesAgainst, 0);
        assertTrue(registry.hasValidatorVotedOnDispute(VALIDATOR_1, ACTOR, EPOCH_ID));
    }

    function test_voteOnDispute_rejectVote() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(dispute.votesFor, 0);
        assertEq(dispute.votesAgainst, 1);
    }

    function test_voteOnDispute_emitsEvent() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.expectEmit(true, true, true, true);
        emit IPresenceRegistry.DisputeVote(ACTOR, EPOCH_ID, VALIDATOR_1, true);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
    }

    function test_voteOnDispute_rejectsNonValidator() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.CallerNotValidator.selector, address(0xBEEF)));
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
    }

    function test_voteOnDispute_rejectsDoubleVote() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        vm.prank(VALIDATOR_1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.ValidatorAlreadyVotedOnDispute.selector, VALIDATOR_1, ACTOR, EPOCH_ID
            )
        );
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
    }

    function test_voteOnDispute_rejectsNoDispute() external {
        _declarePresence();

        vm.prank(VALIDATOR_1);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.DisputeNotFound.selector, ACTOR, EPOCH_ID));
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLVE DISPUTE
    //////////////////////////////////////////////////////////////*/

    function test_resolveDispute_upheld_slashesPresence() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        // Majority votes to uphold
        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Check dispute status
        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Upheld));

        // Check presence slashed
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Slashed));
    }

    function test_resolveDispute_rejected_preservesPresence() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        // Majority votes against
        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Check dispute status
        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Rejected));

        // Presence still Declared
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function test_resolveDispute_emitsEvents_upheld() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.DisputeResolved(ACTOR, EPOCH_ID, IPresenceRegistry.DisputeStatus.Upheld);

        vm.expectEmit(true, true, true, true);
        emit IPresenceRegistry.PresenceSlashedEvent(ACTOR, EPOCH_ID, CHALLENGER);

        registry.resolveDispute(ACTOR, EPOCH_ID);
    }

    function test_resolveDispute_emitsEvents_rejected() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.DisputeResolved(ACTOR, EPOCH_ID, IPresenceRegistry.DisputeStatus.Rejected);

        registry.resolveDispute(ACTOR, EPOCH_ID);
    }

    function test_resolveDispute_silentIfNoQuorum() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        // Only 2 votes (need 3 for quorum)
        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        // No revert, but no state change
        registry.resolveDispute(ACTOR, EPOCH_ID);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(ACTOR, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Pending));
    }

    function test_resolveDispute_rejectsNoDispute() external {
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.DisputeNotFound.selector, ACTOR, EPOCH_ID));
        registry.resolveDispute(ACTOR, EPOCH_ID);
    }

    function test_resolveDispute_rejectsAlreadyResolved() external {
        _declarePresence();

        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Try to resolve again
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.DisputeNotPending.selector, ACTOR, EPOCH_ID));
        registry.resolveDispute(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            SLASHED STATE
    //////////////////////////////////////////////////////////////*/

    function test_slashed_blocksDeclare() external {
        _declarePresence();

        // Slash via dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Try to declare again
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceSlashed.selector, ACTOR, EPOCH_ID));
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    function test_slashed_blocksValidate() external {
        _declarePresence();

        // Slash via dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Try to validate
        vm.prank(VALIDATOR_1);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceSlashed.selector, ACTOR, EPOCH_ID));
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    function test_slashed_blocksFinalize() external {
        _declarePresence();

        // Slash via dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Warp to closed epoch
        vm.warp(block.timestamp + 2 days);

        // Try to finalize
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceSlashed.selector, ACTOR, EPOCH_ID));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    function test_slashed_blocksNewDispute() external {
        _declarePresence();

        // Slash via dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, true);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Try to initiate another dispute
        vm.prank(CHALLENGER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceSlashed.selector, ACTOR, EPOCH_ID));
        registry.initiateDispute(ACTOR, EPOCH_ID, keccak256("new evidence"));
    }

    /*//////////////////////////////////////////////////////////////
                        PENDING DISPUTE BLOCKS FINALIZE
    //////////////////////////////////////////////////////////////*/

    function test_pendingDispute_blocksFinalize() external {
        _declareAndValidate();

        // Initiate dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        // Warp to closed epoch
        vm.warp(block.timestamp + 2 days);

        // Try to finalize with pending dispute
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceNotFinalizable.selector, ACTOR, EPOCH_ID));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    function test_rejectedDispute_allowsFinalize() external {
        _declareAndValidate();

        // Initiate and reject dispute
        vm.prank(CHALLENGER);
        registry.initiateDispute(ACTOR, EPOCH_ID, EVIDENCE_HASH);

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(ACTOR, EPOCH_ID, false);

        registry.resolveDispute(ACTOR, EPOCH_ID);

        // Warp to closed epoch
        vm.warp(block.timestamp + 2 days);

        // Now can finalize
        registry.finalizePresence(ACTOR, EPOCH_ID);
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }
}

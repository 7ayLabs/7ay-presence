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
 * @title DisputeFuzzTests
 * @notice Property-based fuzz tests for dispute mechanism
 * @dev Spec: specs/v0.4/presence.md
 */
contract DisputeFuzzTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;

    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    uint256 internal constant EPOCH_ID = 1;

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

    function _declarePresence(address actor) internal {
        vm.prank(actor);
        registry.declarePresence(actor, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            INITIATE DISPUTE FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_initiateDispute(address actor, address challenger, bytes32 evidenceHash) external {
        vm.assume(actor != address(0));
        vm.assume(challenger != address(0));

        _declarePresence(actor);

        vm.prank(challenger);
        registry.initiateDispute(actor, EPOCH_ID, evidenceHash);

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, EPOCH_ID);
        assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Pending));
        assertEq(dispute.challenger, challenger);
        assertEq(dispute.evidenceHash, evidenceHash);
    }

    function testFuzz_initiateDispute_rejectsZeroActor(address challenger, bytes32 evidenceHash) external {
        vm.assume(challenger != address(0));

        vm.prank(challenger);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.initiateDispute(address(0), EPOCH_ID, evidenceHash);
    }

    /*//////////////////////////////////////////////////////////////
                            VOTE FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_voteOnDispute_votesAccumulate(bool v1Vote, bool v2Vote, bool v3Vote) external {
        address actor = address(0xA11CE);
        _declarePresence(actor);

        vm.prank(address(0xC4A1));
        registry.initiateDispute(actor, EPOCH_ID, keccak256("evidence"));

        uint256 expectedFor;
        uint256 expectedAgainst;

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(actor, EPOCH_ID, v1Vote);
        if (v1Vote) expectedFor++;
        else expectedAgainst++;

        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(actor, EPOCH_ID, v2Vote);
        if (v2Vote) expectedFor++;
        else expectedAgainst++;

        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(actor, EPOCH_ID, v3Vote);
        if (v3Vote) expectedFor++;
        else expectedAgainst++;

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, EPOCH_ID);
        assertEq(dispute.votesFor, expectedFor);
        assertEq(dispute.votesAgainst, expectedAgainst);
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLUTION FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_resolveDispute_outcomeMatchesVotes(bool v1Vote, bool v2Vote, bool v3Vote) external {
        address actor = address(0xA11CE);
        _declarePresence(actor);

        vm.prank(address(0xC4A1));
        registry.initiateDispute(actor, EPOCH_ID, keccak256("evidence"));

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(actor, EPOCH_ID, v1Vote);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(actor, EPOCH_ID, v2Vote);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(actor, EPOCH_ID, v3Vote);

        registry.resolveDispute(actor, EPOCH_ID);

        uint256 votesFor = (v1Vote ? 1 : 0) + (v2Vote ? 1 : 0) + (v3Vote ? 1 : 0);
        uint256 votesAgainst = 3 - votesFor;

        IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, EPOCH_ID);

        if (votesFor > votesAgainst) {
            assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Upheld));
            assertEq(uint256(registry.presenceState(actor, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Slashed));
        } else {
            assertEq(uint256(dispute.status), uint256(IPresenceRegistry.DisputeStatus.Rejected));
            assertEq(uint256(registry.presenceState(actor, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ERROR PRIORITY FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_errorPriority_invalidActorFirst(uint256 epochId, bytes32 evidence) external {
        vm.assume(epochId != 0);

        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.initiateDispute(address(0), epochId, evidence);
    }

    function testFuzz_errorPriority_invalidEpochSecond(address actor, bytes32 evidence) external {
        vm.assume(actor != address(0));

        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.initiateDispute(actor, 0, evidence);
    }

    /*//////////////////////////////////////////////////////////////
                            DISPUTE ISOLATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_disputeIsolation(address actorA, address actorB) external {
        vm.assume(actorA != address(0));
        vm.assume(actorB != address(0));
        vm.assume(actorA != actorB);

        _declarePresence(actorA);
        _declarePresence(actorB);

        // Dispute only actorA
        vm.prank(address(0xC4A1));
        registry.initiateDispute(actorA, EPOCH_ID, keccak256("evidence"));

        // Resolve with uphold
        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(actorA, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(actorA, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(actorA, EPOCH_ID, true);

        registry.resolveDispute(actorA, EPOCH_ID);

        // actorA slashed, actorB unaffected
        assertEq(uint256(registry.presenceState(actorA, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Slashed));
        assertEq(uint256(registry.presenceState(actorB, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    /*//////////////////////////////////////////////////////////////
                            SLASHED TERMINAL
    //////////////////////////////////////////////////////////////*/

    function testFuzz_slashedIsTerminal(address actor, address challenger) external {
        vm.assume(actor != address(0));
        vm.assume(challenger != address(0));

        _declarePresence(actor);

        // Slash
        vm.prank(challenger);
        registry.initiateDispute(actor, EPOCH_ID, keccak256("evidence"));

        vm.prank(VALIDATOR_1);
        registry.voteOnDispute(actor, EPOCH_ID, true);
        vm.prank(VALIDATOR_2);
        registry.voteOnDispute(actor, EPOCH_ID, true);
        vm.prank(VALIDATOR_3);
        registry.voteOnDispute(actor, EPOCH_ID, true);

        registry.resolveDispute(actor, EPOCH_ID);

        // Verify slashed
        assertEq(uint256(registry.presenceState(actor, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Slashed));

        // Verify terminal - cannot declare
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceSlashed.selector, actor, EPOCH_ID));
        registry.declarePresence(actor, EPOCH_ID);
    }
}

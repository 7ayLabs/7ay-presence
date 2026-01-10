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
 * @title PresenceValidationTests
 * @notice Tests for validator quorum-based presence validation
 * @dev Spec: specs/v0.4/presence.md
 */
contract PresenceValidationTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;

    address internal constant AUTHORITY = address(0xA077);
    address internal constant ACTOR = address(0xA11CE);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);
    address internal constant NON_VALIDATOR = address(0xBEEF);

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

    /*//////////////////////////////////////////////////////////////
                            BASIC VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_validatePresence_requiresDeclared() external {
        // Try to validate without declaration
        vm.prank(VALIDATOR_1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.InvalidPresenceState.selector,
                ACTOR,
                EPOCH_ID,
                IPresenceRegistry.PresenceState.None,
                IPresenceRegistry.PresenceState.Declared
            )
        );
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    function test_validatePresence_singleVote() external {
        // Declare first
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Single validation vote
        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);

        // Still Declared (quorum not reached)
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));

        // Check vote recorded
        assertTrue(registry.hasValidatorVotedForPresence(VALIDATOR_1, ACTOR, EPOCH_ID));
        assertFalse(registry.hasValidatorVotedForPresence(VALIDATOR_2, ACTOR, EPOCH_ID));
    }

    function test_validatePresence_quorumReached() external {
        // Declare first
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Validate with quorum (3 validators, 67% = 3 needed)
        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);

        // Still Declared after 2 votes
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));

        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);

        // Now Validated
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Validated));
    }

    function test_validatePresence_emitsVoteEvent() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.expectEmit(true, true, true, true);
        emit IPresenceRegistry.PresenceValidationVote(ACTOR, EPOCH_ID, VALIDATOR_1, 1, 3);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    function test_validatePresence_emitsValidatedEvent() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceValidated(ACTOR, EPOCH_ID, 3);

        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION ERRORS
    //////////////////////////////////////////////////////////////*/

    function test_validatePresence_rejectsNonValidator() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.prank(NON_VALIDATOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.CallerNotValidator.selector, NON_VALIDATOR));
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    function test_validatePresence_rejectsDoubleVote() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_1);
        vm.expectRevert(
            abi.encodeWithSelector(IPresenceRegistry.ValidatorAlreadyVoted.selector, VALIDATOR_1, ACTOR, EPOCH_ID)
        );
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    function test_validatePresence_rejectsInvalidActor() external {
        vm.prank(VALIDATOR_1);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.validatePresence(address(0), EPOCH_ID);
    }

    function test_validatePresence_rejectsInvalidEpoch() external {
        vm.prank(VALIDATOR_1);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.validatePresence(ACTOR, 0);
    }

    function test_validatePresence_rejectsInactiveEpoch() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Warp to closed epoch
        vm.warp(block.timestamp + 2 days);

        vm.prank(VALIDATOR_1);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, EPOCH_ID));
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            PRESENCE DATA
    //////////////////////////////////////////////////////////////*/

    function test_getPresence_returnsCorrectData() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.Presence memory presence = registry.getPresence(ACTOR, EPOCH_ID);
        assertEq(uint256(presence.state), uint256(IPresenceRegistry.PresenceState.Declared));
        assertEq(presence.validationCount, 0);
        assertTrue(presence.declaredAt > 0);
        assertEq(presence.validatedAt, 0);

        // After validation
        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);

        presence = registry.getPresence(ACTOR, EPOCH_ID);
        assertEq(uint256(presence.state), uint256(IPresenceRegistry.PresenceState.Validated));
        assertEq(presence.validationCount, 3);
        assertTrue(presence.validatedAt > 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ERROR PRIORITY
    //////////////////////////////////////////////////////////////*/

    function test_errorPriority_invalidActorFirst() external {
        vm.prank(VALIDATOR_1);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.validatePresence(address(0), 999);
    }

    function test_errorPriority_invalidEpochSecond() external {
        vm.prank(VALIDATOR_1);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.validatePresence(ACTOR, 0);
    }

    function test_errorPriority_epochNotActiveBeforeCallerNotValidator() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Warp to closed epoch
        vm.warp(block.timestamp + 2 days);

        // Non-validator tries to validate in closed epoch
        // EpochNotActive should come before CallerNotValidator
        vm.prank(NON_VALIDATOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, EPOCH_ID));
        registry.validatePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_validationCountIncrementsCorrectly(uint8 validatorCount) external {
        validatorCount = uint8(bound(validatorCount, 0, 3));

        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        address[3] memory validators = [VALIDATOR_1, VALIDATOR_2, VALIDATOR_3];

        for (uint256 i = 0; i < validatorCount; i++) {
            vm.prank(validators[i]);
            registry.validatePresence(ACTOR, EPOCH_ID);
        }

        IPresenceRegistry.Presence memory presence = registry.getPresence(ACTOR, EPOCH_ID);
        assertEq(presence.validationCount, validatorCount);
    }
}

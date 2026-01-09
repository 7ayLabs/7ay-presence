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
 * @title PresenceRegistryDeclarationTests
 * @notice Declaration layer tests for presence v0.3
 * @dev Spec: specs/v0.3/presence.md
 */
contract PresenceRegistryDeclarationTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant ACTOR = address(0xA11CE);
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

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructorRejectsZeroEpochRegistry() external {
        vm.expectRevert(IPresenceRegistry.InvalidEpochRegistry.selector);
        new PresenceRegistry(IEpochRegistry(address(0)), validatorRegistry, 0);
    }

    function test_constructorRejectsZeroValidatorRegistry() external {
        vm.expectRevert(IPresenceRegistry.InvalidValidatorRegistry.selector);
        new PresenceRegistry(epochRegistry, IValidatorRegistry(address(0)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC
    //////////////////////////////////////////////////////////////*/

    function test_declarePresence_fromNone() external {
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));

        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function test_declarePresence_emitsEvent() external {
        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceDeclared(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            IDEMPOTENCY
    //////////////////////////////////////////////////////////////*/

    function test_declarePresence_idempotent_whenDeclared() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.recordLogs();
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function test_declarePresence_idempotent_whenValidated() external {
        // Declare and validate to Validated state
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Validated));

        vm.recordLogs();
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Validated));
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    function test_declarePresence_reverts_invalidActor() external {
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), EPOCH_ID);
    }

    function test_declarePresence_reverts_unauthorizedActor() external {
        address attacker = address(0xBEEF);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, attacker, ACTOR));
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    function test_declarePresence_reverts_invalidEpoch() external {
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.declarePresence(ACTOR, 0);
    }

    function test_declarePresence_reverts_epochNotActive() external {
        uint256 nonExistentEpoch = 999;

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, nonExistentEpoch));
        registry.declarePresence(ACTOR, nonExistentEpoch);
    }

    function test_declarePresence_reverts_epochScheduled() external {
        uint256 futureEpoch = 10;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(futureEpoch, block.timestamp + 1 hours, block.timestamp + 2 hours);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, futureEpoch));
        registry.declarePresence(ACTOR, futureEpoch);
    }

    function test_declarePresence_reverts_epochClosed() external {
        vm.warp(block.timestamp + 2 days);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, EPOCH_ID));
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION (v0.4 FLOW)
    //////////////////////////////////////////////////////////////*/

    function test_finalizePresence_fromValidated() external {
        // Declare
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Validate with quorum
        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Validated));

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        // Finalize
        registry.finalizePresence(ACTOR, EPOCH_ID);
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_finalizePresence_reverts_notValidated() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceNotFinalizable.selector, ACTOR, EPOCH_ID));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    function test_finalizePresence_reverts_epochStillActive() external {
        // Declare and validate
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(ACTOR, EPOCH_ID);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(ACTOR, EPOCH_ID);

        // Try to finalize while epoch is still active
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.PresenceNotFinalizable.selector, ACTOR, EPOCH_ID));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_declarePresence(address actor, uint256 epochId) external {
        vm.assume(actor != address(0));
        vm.assume(epochId != 0);
        vm.assume(epochId != EPOCH_ID);

        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);

        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function testFuzz_declareAndValidate(address actor, uint256 epochId) external {
        vm.assume(actor != address(0));
        vm.assume(epochId != 0);
        vm.assume(epochId != EPOCH_ID);

        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);

        vm.prank(actor);
        registry.declarePresence(actor, epochId);
        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Declared));

        // Validate with quorum
        vm.prank(VALIDATOR_1);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(actor, epochId);

        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Validated));
    }

    /*//////////////////////////////////////////////////////////////
                            ERROR PRIORITY
    //////////////////////////////////////////////////////////////*/

    function test_errorPriority_invalidActorFirst() external {
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), 999);
    }

    function test_errorPriority_unauthorizedBeforeEpoch() external {
        address attacker = address(0xBEEF);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, attacker, ACTOR));
        registry.declarePresence(ACTOR, 999);
    }

    function test_errorPriority_invalidEpochBeforeNotActive() external {
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.declarePresence(ACTOR, 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title PresenceRegistryDeclarationTests
 * @notice Declaration layer tests for the 7ay PoP v0.3
 *
 * @dev
 * Tests for declarePresence() function and Declared state.
 *
 * Specification: specs/v0.3/presence.md
 */
contract PresenceRegistryDeclarationTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant ACTOR = address(0xA11CE);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry)));

        // Create active epoch
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(EPOCH_ID, block.timestamp, block.timestamp + 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                        DECLARATION: Basic
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
                        DECLARATION: Idempotency
    //////////////////////////////////////////////////////////////*/

    function test_declarePresence_idempotent_whenDeclared() external {
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        vm.recordLogs();
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // No event emitted on idempotent call
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        // State unchanged
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function test_declarePresence_idempotent_whenFinalized() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        vm.recordLogs();
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);

        // No event, no revert
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        // State still Finalized
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                        DECLARATION: Errors
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
        // Create future epoch
        uint256 futureEpoch = 10;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(futureEpoch, block.timestamp + 1 hours, block.timestamp + 2 hours);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, futureEpoch));
        registry.declarePresence(ACTOR, futureEpoch);
    }

    function test_declarePresence_reverts_epochClosed() external {
        // Warp to after epoch end
        vm.warp(block.timestamp + 2 days);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, EPOCH_ID));
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        FINALIZATION: From Declared
    //////////////////////////////////////////////////////////////*/

    function test_finalizePresence_fromDeclared() external {
        // Declare first
        vm.prank(ACTOR);
        registry.declarePresence(ACTOR, EPOCH_ID);
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Declared));

        // Then finalize
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_finalizePresence_fromNone_legacy() external {
        // Direct finalization (legacy path)
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_finalizePresence_reverts_epochNotActive() external {
        // Warp to after epoch end
        vm.warp(block.timestamp + 2 days);

        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.EpochNotActive.selector, EPOCH_ID));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Declaration
    //////////////////////////////////////////////////////////////*/

    function testFuzz_declarePresence(address actor, uint256 epochId) external {
        vm.assume(actor != address(0));
        vm.assume(epochId != 0);
        vm.assume(epochId != EPOCH_ID); // Don't conflict with setUp epoch

        // Create active epoch
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);

        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    function testFuzz_declareAndFinalize(address actor, uint256 epochId) external {
        vm.assume(actor != address(0));
        vm.assume(epochId != 0);
        vm.assume(epochId != EPOCH_ID);

        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);

        vm.prank(actor);
        registry.declarePresence(actor, epochId);
        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Declared));

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
        assertEq(uint256(registry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR PRIORITY
    //////////////////////////////////////////////////////////////*/

    function test_errorPriority_invalidActorFirst() external {
        // InvalidActor checked before EpochNotActive
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), 999);
    }

    function test_errorPriority_unauthorizedBeforeEpoch() external {
        address attacker = address(0xBEEF);

        // UnauthorizedActor checked before EpochNotActive
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, attacker, ACTOR));
        registry.declarePresence(ACTOR, 999);
    }

    function test_errorPriority_invalidEpochBeforeNotActive() external {
        // InvalidEpoch (epochId == 0) checked before EpochNotActive
        vm.prank(ACTOR);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.declarePresence(ACTOR, 0);
    }
}

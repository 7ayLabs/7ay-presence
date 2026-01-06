// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../contracts/interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistryEventTests
 * @notice Event emission tests for the 7ay PoP
 *
 * @dev
 * Event tests verify correct event emission per protocol specification.
 * Events are critical for off-chain indexing and auditability.
 *
 * Specification references:
 * - specs/presence.md Section 6 (Events)
 */
contract PresenceRegistryEventTests is Test {
    IPresenceRegistry internal registry;

    address internal actor;
    uint256 internal epochId;

    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));
        actor = address(0xA11CE);
        epochId = 1;
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: PresenceFinalized
      MUST emit exactly once per (actor, epochId) state transition.
    //////////////////////////////////////////////////////////////*/

    function test_emitsPresenceFinalized() external {
        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceFinalized(actor, epochId);

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: Indexed Parameters
      Event MUST have actor and epochId as indexed parameters.
    //////////////////////////////////////////////////////////////*/

    function test_eventIndexedParameters() external {
        vm.recordLogs();

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("PresenceFinalized(address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(actor))));
        assertEq(logs[0].topics[2], bytes32(epochId));
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: Idempotent Call
      MUST NOT emit event on idempotent (already finalized) call.
    //////////////////////////////////////////////////////////////*/

    function test_noEventOnIdempotentCall() external {
        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        vm.recordLogs();

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: Multiple Actors
      Each actor finalization MUST emit its own event.
    //////////////////////////////////////////////////////////////*/

    function test_multipleActorsEmitSeparateEvents() external {
        address actor1 = address(0x1);
        address actor2 = address(0x2);

        vm.recordLogs();

        vm.prank(actor1);
        registry.finalizePresence(actor1, epochId);

        vm.prank(actor2);
        registry.finalizePresence(actor2, epochId);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(actor1))));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(actor2))));
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: Multiple Epochs
      Each epoch finalization MUST emit its own event.
    //////////////////////////////////////////////////////////////*/

    function test_multipleEpochsEmitSeparateEvents() external {
        vm.recordLogs();

        vm.prank(actor);
        registry.finalizePresence(actor, 1);

        vm.prank(actor);
        registry.finalizePresence(actor, 2);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].topics[2], bytes32(uint256(1)));
        assertEq(logs[1].topics[2], bytes32(uint256(2)));
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT: Fuzz Emission
      Event MUST emit with correct parameters for any valid input.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_eventEmission(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceFinalized(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);
    }
}

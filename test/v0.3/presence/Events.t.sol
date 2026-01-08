// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title PresenceRegistryEventTests
 * @notice Event emission tests for presence lifecycle
 * @dev Spec: specs/v0.3/presence.md
 */
contract PresenceRegistryEventTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    address internal constant AUTHORITY = address(0xA077);

    address internal actor;
    uint256 internal epochId;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry)));
        actor = address(0xA11CE);
        epochId = 1;

        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);
    }

    function _createActiveEpoch(uint256 _epochId) internal {
        if (_epochId == 0 || epochRegistry.epochState(_epochId) != IEpochRegistry.EpochState.None) return;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(_epochId, block.timestamp, block.timestamp + 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsPresenceFinalized() external {
        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceFinalized(actor, epochId);

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);
    }

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
                            IDEMPOTENCY
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
                            MULTIPLE ACTORS
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
                            MULTIPLE EPOCHS
    //////////////////////////////////////////////////////////////*/

    function test_multipleEpochsEmitSeparateEvents() external {
        _createActiveEpoch(2);

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
                            FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_eventEmission(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        _createActiveEpoch(fuzzEpochId);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceFinalized(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);
    }
}

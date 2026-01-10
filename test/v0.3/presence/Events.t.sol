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
 * @title PresenceRegistryEventTests
 * @notice Event emission tests for presence lifecycle (updated for v0.4)
 * @dev Spec: specs/v0.4/presence.md
 */
contract PresenceRegistryEventTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    address internal actor;
    uint256 internal epochId;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));
        actor = address(0xA11CE);
        epochId = 1;

        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(epochId, block.timestamp, block.timestamp + 1 days);
        validatorRegistry.addValidator(VALIDATOR_1);
        validatorRegistry.addValidator(VALIDATOR_2);
        validatorRegistry.addValidator(VALIDATOR_3);
        vm.stopPrank();
    }

    function _createActiveEpoch(uint256 _epochId) internal {
        if (_epochId == 0 || epochRegistry.epochState(_epochId) != IEpochRegistry.EpochState.None) return;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(_epochId, block.timestamp, block.timestamp + 1 days);
    }

    function _declareAndValidate(address _actor, uint256 _epochId) internal {
        vm.prank(_actor);
        registry.declarePresence(_actor, _epochId);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(_actor, _epochId);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(_actor, _epochId);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(_actor, _epochId);
    }

    /*//////////////////////////////////////////////////////////////
                            DECLARED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsPresenceDeclared() external {
        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceDeclared(actor, epochId);

        vm.prank(actor);
        registry.declarePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsPresenceValidated() external {
        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(actor, epochId);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceValidated(actor, epochId, 3);

        vm.prank(VALIDATOR_3);
        registry.validatePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsPresenceFinalized() external {
        _declareAndValidate(actor, epochId);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, false, true);
        emit IPresenceRegistry.PresenceFinalized(actor, epochId);

        registry.finalizePresence(actor, epochId);
    }

    function test_eventIndexedParameters() external {
        _declareAndValidate(actor, epochId);
        vm.warp(block.timestamp + 2 days);

        vm.recordLogs();
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

    function test_noEventOnIdempotentDeclare() external {
        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        vm.recordLogs();

        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function test_noEventOnIdempotentFinalize() external {
        _declareAndValidate(actor, epochId);
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(actor, epochId);

        vm.recordLogs();
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
        registry.declarePresence(actor1, epochId);

        vm.prank(actor2);
        registry.declarePresence(actor2, epochId);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(actor1))));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(actor2))));
    }
}

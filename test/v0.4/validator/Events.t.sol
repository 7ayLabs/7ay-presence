// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title ValidatorRegistryEventTests
 * @notice Event emission tests for validator registry
 * @dev Spec: specs/v0.4/validator.md
 */
contract ValidatorRegistryEventTests is Test {
    IValidatorRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);
    address internal constant VALIDATOR_4 = address(0x1004);

    function setUp() external {
        registry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR ADDED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsValidatorAdded() external {
        vm.expectEmit(true, false, false, true);
        emit IValidatorRegistry.ValidatorAdded(VALIDATOR_1, block.timestamp);

        vm.prank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);
    }

    function test_validatorAdded_indexedParameters() external {
        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("ValidatorAdded(address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(VALIDATOR_1))));
    }

    function testFuzz_emitsValidatorAdded(address validator) external {
        vm.assume(validator != address(0));

        vm.expectEmit(true, false, false, true);
        emit IValidatorRegistry.ValidatorAdded(validator, block.timestamp);

        vm.prank(AUTHORITY);
        registry.addValidator(validator);
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR REMOVED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsValidatorRemoved() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);

        vm.expectEmit(true, false, false, true);
        emit IValidatorRegistry.ValidatorRemoved(VALIDATOR_4, block.timestamp);

        registry.removeValidator(VALIDATOR_4);
        vm.stopPrank();
    }

    function test_validatorRemoved_indexedParameters() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);

        vm.recordLogs();
        registry.removeValidator(VALIDATOR_4);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("ValidatorRemoved(address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(VALIDATOR_4))));
    }

    function testFuzz_emitsValidatorRemoved(address validator) external {
        vm.assume(validator != address(0));
        vm.assume(validator != VALIDATOR_1 && validator != VALIDATOR_2 && validator != VALIDATOR_3);

        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(validator);

        vm.expectEmit(true, false, false, true);
        emit IValidatorRegistry.ValidatorRemoved(validator, block.timestamp);

        registry.removeValidator(validator);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    QUORUM THRESHOLD UPDATED EVENT
    //////////////////////////////////////////////////////////////*/

    function test_emitsQuorumThresholdUpdated() external {
        vm.expectEmit(false, false, false, true);
        emit IValidatorRegistry.QuorumThresholdUpdated(67, 51);

        vm.prank(AUTHORITY);
        registry.setQuorumThreshold(51);
    }

    function test_quorumThresholdUpdated_values() external {
        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.setQuorumThreshold(80);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("QuorumThresholdUpdated(uint256,uint256)"));

        (uint256 oldThreshold, uint256 newThreshold) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(oldThreshold, 67);
        assertEq(newThreshold, 80);
    }

    function testFuzz_emitsQuorumThresholdUpdated(uint256 threshold) external {
        vm.assume(threshold >= 1 && threshold <= 100);

        vm.expectEmit(false, false, false, true);
        emit IValidatorRegistry.QuorumThresholdUpdated(67, threshold);

        vm.prank(AUTHORITY);
        registry.setQuorumThreshold(threshold);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _addMinimumValidators() internal {
        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);
        registry.addValidator(VALIDATOR_2);
        registry.addValidator(VALIDATOR_3);
        vm.stopPrank();
    }
}

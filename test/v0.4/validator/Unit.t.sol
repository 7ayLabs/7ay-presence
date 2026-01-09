// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title ValidatorRegistryUnitTests
 * @notice Unit tests for validator specification compliance
 * @dev Spec: specs/v0.4/validator.md
 */
contract ValidatorRegistryUnitTests is Test {
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
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructorRejectsZeroAuthority() external {
        vm.expectRevert(IValidatorRegistry.InvalidValidatorAuthority.selector);
        new ValidatorRegistry(address(0));
    }

    function test_constructorSetsAuthority() external view {
        assertEq(registry.validatorAuthority(), AUTHORITY);
    }

    function test_constructorSetsDefaultQuorumThreshold() external view {
        assertEq(registry.quorumThreshold(), 67);
    }

    function test_constructorSetsMinimumValidators() external view {
        assertEq(registry.minimumValidators(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                            ADD VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function test_addValidator_success() external {
        vm.prank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);

        assertEq(uint256(registry.validatorStatus(VALIDATOR_1)), uint256(IValidatorRegistry.ValidatorStatus.Active));
        assertTrue(registry.isValidatorActive(VALIDATOR_1));
        assertEq(registry.activeValidatorCount(), 1);
    }

    function test_addValidator_rejectsZeroAddress() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IValidatorRegistry.InvalidValidator.selector);
        registry.addValidator(address(0));
    }

    function test_addValidator_rejectsNonAuthority() external {
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorRegistry.UnauthorizedValidatorAuthority.selector, address(0xBAD), AUTHORITY
            )
        );
        registry.addValidator(VALIDATOR_1);
    }

    function test_addValidator_rejectsDuplicate() external {
        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);

        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.ValidatorAlreadyExists.selector, VALIDATOR_1));
        registry.addValidator(VALIDATOR_1);
        vm.stopPrank();
    }

    function test_addValidator_multipleValidators() external {
        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);
        registry.addValidator(VALIDATOR_2);
        registry.addValidator(VALIDATOR_3);
        vm.stopPrank();

        assertEq(registry.activeValidatorCount(), 3);
        assertTrue(registry.isValidatorActive(VALIDATOR_1));
        assertTrue(registry.isValidatorActive(VALIDATOR_2));
        assertTrue(registry.isValidatorActive(VALIDATOR_3));
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function test_removeValidator_success() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);
        registry.removeValidator(VALIDATOR_4);
        vm.stopPrank();

        assertEq(uint256(registry.validatorStatus(VALIDATOR_4)), uint256(IValidatorRegistry.ValidatorStatus.Removed));
        assertFalse(registry.isValidatorActive(VALIDATOR_4));
        assertEq(registry.activeValidatorCount(), 3);
    }

    function test_removeValidator_rejectsZeroAddress() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IValidatorRegistry.InvalidValidator.selector);
        registry.removeValidator(address(0));
    }

    function test_removeValidator_rejectsNonAuthority() external {
        _addMinimumValidators();

        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorRegistry.UnauthorizedValidatorAuthority.selector, address(0xBAD), AUTHORITY
            )
        );
        registry.removeValidator(VALIDATOR_1);
    }

    function test_removeValidator_rejectsNotFound() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.ValidatorNotFound.selector, VALIDATOR_1));
        registry.removeValidator(VALIDATOR_1);
    }

    function test_removeValidator_rejectsBelowMinimum() external {
        _addMinimumValidators();

        vm.prank(AUTHORITY);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.InsufficientValidators.selector, 3, 3));
        registry.removeValidator(VALIDATOR_1);
    }

    function test_removeValidator_rejectsAlreadyRemoved() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);
        registry.removeValidator(VALIDATOR_4);

        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.ValidatorNotActive.selector, VALIDATOR_4));
        registry.removeValidator(VALIDATOR_4);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            QUORUM
    //////////////////////////////////////////////////////////////*/

    function test_setQuorumThreshold_success() external {
        vm.prank(AUTHORITY);
        registry.setQuorumThreshold(51);

        assertEq(registry.quorumThreshold(), 51);
    }

    function test_setQuorumThreshold_rejectsZero() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.InvalidQuorumThreshold.selector, 0));
        registry.setQuorumThreshold(0);
    }

    function test_setQuorumThreshold_rejectsAbove100() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.InvalidQuorumThreshold.selector, 101));
        registry.setQuorumThreshold(101);
    }

    function test_setQuorumThreshold_rejectsNonAuthority() external {
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorRegistry.UnauthorizedValidatorAuthority.selector, address(0xBAD), AUTHORITY
            )
        );
        registry.setQuorumThreshold(51);
    }

    function test_quorumSize_withZeroValidators() external view {
        assertEq(registry.quorumSize(), 1);
    }

    function test_quorumSize_withThreeValidators() external {
        _addMinimumValidators();

        // 3 * 67 / 100 = 2.01 -> ceil = 3
        // Using (3 * 67 + 99) / 100 = (201 + 99) / 100 = 3
        assertEq(registry.quorumSize(), 3);
    }

    function test_quorumSize_withFiveValidators() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);
        registry.addValidator(address(0x1005));
        vm.stopPrank();

        // 5 * 67 / 100 = 3.35 -> ceil = 4
        // Using (5 * 67 + 99) / 100 = (335 + 99) / 100 = 4
        assertEq(registry.quorumSize(), 4);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_getValidator_returnsData() external {
        vm.prank(AUTHORITY);
        registry.addValidator(VALIDATOR_1);

        IValidatorRegistry.Validator memory v = registry.getValidator(VALIDATOR_1);
        assertEq(uint256(v.status), uint256(IValidatorRegistry.ValidatorStatus.Active));
        assertEq(v.registeredAt, block.timestamp);
        assertEq(v.removedAt, 0);
    }

    function test_getActiveValidators_returnsAll() external {
        _addMinimumValidators();

        address[] memory validators = registry.getActiveValidators();
        assertEq(validators.length, 3);
    }

    function test_getActiveValidators_excludesRemoved() external {
        _addMinimumValidators();

        vm.startPrank(AUTHORITY);
        registry.addValidator(VALIDATOR_4);
        registry.removeValidator(VALIDATOR_4);
        vm.stopPrank();

        address[] memory validators = registry.getActiveValidators();
        assertEq(validators.length, 3);

        for (uint256 i = 0; i < validators.length; i++) {
            assertTrue(validators[i] != VALIDATOR_4);
        }
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

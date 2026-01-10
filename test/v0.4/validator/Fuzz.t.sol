// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title ValidatorRegistryFuzzTests
 * @notice Property-based tests for validator registry
 * @dev Spec: specs/v0.4/validator.md
 */
contract ValidatorRegistryFuzzTests is Test {
    IValidatorRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        registry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                            ADD VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzz_addValidator(address validator) external {
        vm.assume(validator != address(0));

        vm.prank(AUTHORITY);
        registry.addValidator(validator);

        assertTrue(registry.isValidatorActive(validator));
        assertEq(registry.activeValidatorCount(), 1);
    }

    function testFuzz_addValidator_incrementsCount(uint8 count) external {
        vm.assume(count > 0 && count <= 20);

        vm.startPrank(AUTHORITY);
        for (uint8 i = 0; i < count; i++) {
            registry.addValidator(address(uint160(i + 1)));
        }
        vm.stopPrank();

        assertEq(registry.activeValidatorCount(), count);
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzz_removeValidator_decrementCount(uint8 extraValidators) external {
        vm.assume(extraValidators > 0 && extraValidators <= 10);

        vm.startPrank(AUTHORITY);

        // Add minimum validators
        registry.addValidator(address(0x1));
        registry.addValidator(address(0x2));
        registry.addValidator(address(0x3));

        // Add extra validators
        for (uint8 i = 0; i < extraValidators; i++) {
            registry.addValidator(address(uint160(100 + i)));
        }

        uint256 initialCount = registry.activeValidatorCount();
        assertEq(initialCount, 3 + extraValidators);

        // Remove extra validators
        for (uint8 i = 0; i < extraValidators; i++) {
            registry.removeValidator(address(uint160(100 + i)));
        }

        vm.stopPrank();

        assertEq(registry.activeValidatorCount(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                            QUORUM
    //////////////////////////////////////////////////////////////*/

    function testFuzz_setQuorumThreshold(uint256 threshold) external {
        vm.assume(threshold >= 1 && threshold <= 100);

        vm.prank(AUTHORITY);
        registry.setQuorumThreshold(threshold);

        assertEq(registry.quorumThreshold(), threshold);
    }

    function testFuzz_setQuorumThreshold_rejectsInvalid(uint256 threshold) external {
        vm.assume(threshold == 0 || threshold > 100);

        vm.prank(AUTHORITY);
        vm.expectRevert(abi.encodeWithSelector(IValidatorRegistry.InvalidQuorumThreshold.selector, threshold));
        registry.setQuorumThreshold(threshold);
    }

    function testFuzz_quorumSize_calculation(uint8 validatorCount, uint8 threshold) external {
        vm.assume(validatorCount >= 1 && validatorCount <= 20);
        vm.assume(threshold >= 1 && threshold <= 100);

        vm.startPrank(AUTHORITY);

        registry.setQuorumThreshold(threshold);

        for (uint8 i = 0; i < validatorCount; i++) {
            registry.addValidator(address(uint160(i + 1)));
        }

        vm.stopPrank();

        uint256 expectedQuorum = (uint256(validatorCount) * uint256(threshold) + 99) / 100;
        assertEq(registry.quorumSize(), expectedQuorum);
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR PRIORITY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_addValidator_errorPriority_invalidFirst(address caller) external {
        vm.assume(caller != address(0) && caller != AUTHORITY);

        // InvalidValidator (priority 1) should be checked before UnauthorizedValidatorAuthority (priority 2)
        vm.prank(caller);
        vm.expectRevert(IValidatorRegistry.InvalidValidator.selector);
        registry.addValidator(address(0));
    }

    function testFuzz_removeValidator_errorPriority_invalidFirst(address caller) external {
        vm.assume(caller != address(0) && caller != AUTHORITY);

        // InvalidValidator (priority 1) should be checked before UnauthorizedValidatorAuthority (priority 2)
        vm.prank(caller);
        vm.expectRevert(IValidatorRegistry.InvalidValidator.selector);
        registry.removeValidator(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        STATUS TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_statusTransition_noneToActive(address validator) external {
        vm.assume(validator != address(0));

        assertEq(uint256(registry.validatorStatus(validator)), uint256(IValidatorRegistry.ValidatorStatus.None));

        vm.prank(AUTHORITY);
        registry.addValidator(validator);

        assertEq(uint256(registry.validatorStatus(validator)), uint256(IValidatorRegistry.ValidatorStatus.Active));
    }

    function testFuzz_statusTransition_activeToRemoved(address validator) external {
        vm.assume(validator != address(0));
        vm.assume(validator != address(0x1) && validator != address(0x2) && validator != address(0x3));

        vm.startPrank(AUTHORITY);

        // Add minimum validators
        registry.addValidator(address(0x1));
        registry.addValidator(address(0x2));
        registry.addValidator(address(0x3));

        // Add and remove test validator
        registry.addValidator(validator);
        assertEq(uint256(registry.validatorStatus(validator)), uint256(IValidatorRegistry.ValidatorStatus.Active));

        registry.removeValidator(validator);
        assertEq(uint256(registry.validatorStatus(validator)), uint256(IValidatorRegistry.ValidatorStatus.Removed));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        GET ACTIVE VALIDATORS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_getActiveValidators_correctLength(uint8 count) external {
        vm.assume(count >= 1 && count <= 15);

        vm.startPrank(AUTHORITY);
        for (uint8 i = 0; i < count; i++) {
            registry.addValidator(address(uint160(i + 1)));
        }
        vm.stopPrank();

        address[] memory validators = registry.getActiveValidators();
        assertEq(validators.length, count);
    }
}

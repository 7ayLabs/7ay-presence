// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title ValidatorRegistryHandler
 * @notice Handler contract for Foundry invariant testing
 */
contract ValidatorRegistryHandler is Test {
    IValidatorRegistry public registry;
    address public authority;

    mapping(address => bool) public ghost_added;
    mapping(address => bool) public ghost_removed;
    address[] public ghost_validators;

    address[] internal boundedValidators;

    constructor(IValidatorRegistry _registry, address _authority) {
        registry = _registry;
        authority = _authority;

        boundedValidators.push(address(0x1));
        boundedValidators.push(address(0x2));
        boundedValidators.push(address(0x3));
        boundedValidators.push(address(0x4));
        boundedValidators.push(address(0x5));
        boundedValidators.push(address(0x6));
        boundedValidators.push(address(0x7));
        boundedValidators.push(address(0x8));
    }

    function addValidator(uint256 validatorSeed) external {
        address validator = boundedValidators[validatorSeed % boundedValidators.length];

        if (ghost_added[validator]) return;

        vm.prank(authority);
        registry.addValidator(validator);

        ghost_added[validator] = true;
        ghost_validators.push(validator);
    }

    function removeValidator(uint256 validatorSeed) external {
        if (ghost_validators.length == 0) return;

        address validator = ghost_validators[validatorSeed % ghost_validators.length];

        if (ghost_removed[validator]) return;
        if (!ghost_added[validator]) return;

        // Check if we can remove (above minimum)
        if (registry.activeValidatorCount() <= registry.minimumValidators()) return;

        vm.prank(authority);
        registry.removeValidator(validator);

        ghost_removed[validator] = true;
    }

    function setQuorumThreshold(uint256 thresholdSeed) external {
        uint256 threshold = (thresholdSeed % 100) + 1; // 1-100

        vm.prank(authority);
        registry.setQuorumThreshold(threshold);
    }

    function getGhostValidatorsLength() external view returns (uint256) {
        return ghost_validators.length;
    }

    function getGhostValidator(uint256 index) external view returns (address) {
        return ghost_validators[index];
    }

    function getActiveCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < ghost_validators.length; i++) {
            if (ghost_added[ghost_validators[i]] && !ghost_removed[ghost_validators[i]]) {
                count++;
            }
        }
        return count;
    }
}

/**
 * @title ValidatorRegistryInvariants
 * @notice Protocol invariants for validator registry
 * @dev Spec: specs/v0.4/validator.md Section 9
 */
contract ValidatorRegistryInvariants is Test {
    IValidatorRegistry internal registry;
    ValidatorRegistryHandler internal handler;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IValidatorRegistry(address(new ValidatorRegistry(authority)));
        handler = new ValidatorRegistryHandler(registry, authority);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ValidatorRegistryHandler.addValidator.selector;
        selectors[1] = ValidatorRegistryHandler.removeValidator.selector;
        selectors[2] = ValidatorRegistryHandler.setQuorumThreshold.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV1: Each address maps to at most one validator record
    function invariant_validatorUniqueness() external view {
        uint256 len = handler.getGhostValidatorsLength();
        for (uint256 i = 0; i < len; i++) {
            address validator = handler.getGhostValidator(i);
            if (handler.ghost_added(validator)) {
                IValidatorRegistry.Validator memory v = registry.getValidator(validator);
                assertTrue(
                    v.status == IValidatorRegistry.ValidatorStatus.Active
                        || v.status == IValidatorRegistry.ValidatorStatus.Removed,
                    "INV1: Invalid status for added validator"
                );
            }
        }
    }

    /// @dev INV2: Active count matches ghost tracking
    function invariant_activeCountAccuracy() external view {
        uint256 ghostActive = handler.getActiveCount();
        uint256 registryActive = registry.activeValidatorCount();

        assertEq(registryActive, ghostActive, "INV2: Active count mismatch");
    }

    /// @dev INV3: Once Removed, cannot become Active again
    function invariant_statusMonotonicity() external view {
        uint256 len = handler.getGhostValidatorsLength();
        for (uint256 i = 0; i < len; i++) {
            address validator = handler.getGhostValidator(i);
            if (handler.ghost_removed(validator)) {
                IValidatorRegistry.ValidatorStatus status = registry.validatorStatus(validator);
                assertEq(
                    uint256(status), uint256(IValidatorRegistry.ValidatorStatus.Removed), "INV3: Removed changed"
                );
            }
        }
    }

    /// @dev INV4: Quorum size is always achievable and >= 1
    function invariant_achievableQuorum() external view {
        uint256 quorum = registry.quorumSize();
        uint256 activeCount = registry.activeValidatorCount();

        assertTrue(quorum >= 1, "INV4: Quorum must be >= 1");

        if (activeCount > 0) {
            assertTrue(quorum <= activeCount, "INV4: Quorum must be achievable");
        }
    }

    /// @dev INV5: Quorum threshold is valid (1-100)
    function invariant_validThreshold() external view {
        uint256 threshold = registry.quorumThreshold();
        assertTrue(threshold >= 1 && threshold <= 100, "INV5: Invalid threshold");
    }

    /// @dev INV6: Active validators list matches count
    function invariant_activeValidatorsListConsistency() external view {
        address[] memory activeList = registry.getActiveValidators();
        uint256 activeCount = registry.activeValidatorCount();

        assertEq(activeList.length, activeCount, "INV6: List length mismatch");

        for (uint256 i = 0; i < activeList.length; i++) {
            assertTrue(registry.isValidatorActive(activeList[i]), "INV6: Non-active in list");
        }
    }
}

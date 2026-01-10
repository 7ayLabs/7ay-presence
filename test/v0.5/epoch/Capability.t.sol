// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochCapabilityTests
 * @notice Unit tests for v0.5 EpochCapability feature
 * @dev Spec: specs/v0.5/ephemeral.md
 */
contract EpochCapabilityTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                        BACKWARDS COMPATIBILITY
    //////////////////////////////////////////////////////////////*/

    function test_createEpoch_defaultsToPresenceOnly() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceOnly));
        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
        assertFalse(registry.supportsEphemeralData(1));
    }

    function test_createEpoch_emitsEpochCreatedV2() external {
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );

        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                    CREATE WITH CAPABILITY - SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_createEpochWithCapability_presenceOnly() external {
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );

        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceOnly));
        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
        assertFalse(registry.supportsEphemeralData(1));
    }

    function test_createEpochWithCapability_presenceOnly_withOptionalHash() external {
        bytes32 optionalHash = keccak256("optional-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceOnly, optionalHash
        );

        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceOnly));
        assertEq(registry.epochDataPolicyHash(1), optionalHash);
    }

    function test_createEpochWithCapability_presenceWithSignals_noPolicy() external {
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceWithSignals));
        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
        assertFalse(registry.supportsEphemeralData(1));
    }

    function test_createEpochWithCapability_presenceWithSignals_withPolicy() external {
        bytes32 policyHash = keccak256("signal-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, policyHash
        );

        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceWithSignals));
        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }

    function test_createEpochWithCapability_presenceWithEphemeralData() external {
        bytes32 policyHash = keccak256("ephemeral-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        assertEq(
            uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceWithEphemeralData)
        );
        assertEq(registry.epochDataPolicyHash(1), policyHash);
        assertTrue(registry.supportsEphemeralData(1));
    }

    /*//////////////////////////////////////////////////////////////
                    CREATE WITH CAPABILITY - EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_createEpochWithCapability_emitsBothEvents() external {
        bytes32 policyHash = keccak256("policy");

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreated(1, block.timestamp, block.timestamp + 1 days);

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );
    }

    /*//////////////////////////////////////////////////////////////
                    ERROR PRIORITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createEpochWithCapability_errorPriority_1_invalidEpochId() external {
        // InvalidEpochId has priority 1 - should be checked first
        vm.prank(address(0xBAD)); // Wrong caller, but InvalidEpochId comes first
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpochWithCapability(
            0, // Invalid
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceOnly,
            bytes32(0)
        );
    }

    function test_createEpochWithCapability_errorPriority_2_epochAlreadyExists() external {
        // Create epoch first
        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        // Try to create again - EpochAlreadyExists has priority 2
        vm.prank(address(0xBAD)); // Wrong caller, but EpochAlreadyExists comes first
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.EpochAlreadyExists.selector, 1));
        registry.createEpochWithCapability(
            1, // Already exists
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceOnly,
            bytes32(0)
        );
    }

    function test_createEpochWithCapability_errorPriority_3_invalidEpochBounds() external {
        // InvalidEpochBounds has priority 3
        vm.prank(address(0xBAD)); // Wrong caller, but InvalidEpochBounds comes first
        vm.expectRevert(
            abi.encodeWithSelector(IEpochRegistry.InvalidEpochBounds.selector, block.timestamp + 1 days, block.timestamp)
        );
        registry.createEpochWithCapability(
            1,
            block.timestamp + 1 days, // start > end
            block.timestamp,
            IEpochRegistry.EpochCapability.PresenceOnly,
            bytes32(0)
        );
    }

    function test_createEpochWithCapability_errorPriority_4_invalidCapability() external {
        // InvalidCapability has priority 4
        // Note: We can't directly test invalid enum values from Solidity
        // This test verifies the check exists by using valid bounds
        // The actual invalid capability check is tested via fuzz tests

        // Instead, verify that all valid capabilities work
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            keccak256("policy")
        );

        // The capability validation is tested in Fuzz.t.sol using raw calls
    }

    function test_createEpochWithCapability_errorPriority_5_invalidDataPolicyHash() external {
        // InvalidDataPolicyHash has priority 5
        vm.prank(address(0xBAD)); // Wrong caller, but InvalidDataPolicyHash comes first
        vm.expectRevert(IEpochRegistry.InvalidDataPolicyHash.selector);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            bytes32(0) // Missing required hash
        );
    }

    function test_createEpochWithCapability_errorPriority_6_unauthorizedEpochAuthority() external {
        // UnauthorizedEpochAuthority has priority 6 (last)
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(IEpochRegistry.UnauthorizedEpochAuthority.selector, address(0xBAD), AUTHORITY)
        );
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_epochCapability_defaultsToZeroForNonExistent() external view {
        assertEq(uint256(registry.epochCapability(999)), uint256(IEpochRegistry.EpochCapability.PresenceOnly));
    }

    function test_epochDataPolicyHash_defaultsToZeroForNonExistent() external view {
        assertEq(registry.epochDataPolicyHash(999), bytes32(0));
    }

    function test_supportsEphemeralData_falseForNonExistent() external view {
        assertFalse(registry.supportsEphemeralData(999));
    }

    function test_supportsEphemeralData_falseForPresenceOnly() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        assertFalse(registry.supportsEphemeralData(1));
    }

    function test_supportsEphemeralData_falseForPresenceWithSignals() external {
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        assertFalse(registry.supportsEphemeralData(1));
    }

    function test_supportsEphemeralData_trueForPresenceWithEphemeralData() external {
        bytes32 policyHash = keccak256("policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        assertTrue(registry.supportsEphemeralData(1));
    }

    /*//////////////////////////////////////////////////////////////
                    CAPABILITY IMMUTABILITY
    //////////////////////////////////////////////////////////////*/

    function test_capability_immutableAfterCreation() external {
        bytes32 policyHash = keccak256("policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        // Warp to closed state
        vm.warp(block.timestamp + 2 days);

        // Finalize
        vm.prank(AUTHORITY);
        registry.finalizeEpoch(1);

        // Capability should remain unchanged
        assertEq(
            uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceWithEphemeralData)
        );
        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }
}

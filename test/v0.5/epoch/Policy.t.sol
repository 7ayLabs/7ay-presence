// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochPolicyTests
 * @notice Unit tests for v0.5 EpochDataPolicy (hash-based) feature
 * @dev Spec: specs/v0.5/ephemeral.md
 */
contract EpochPolicyTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                    POLICY HASH STORAGE
    //////////////////////////////////////////////////////////////*/

    function test_dataPolicyHash_storedCorrectly() external {
        bytes32 expectedHash = keccak256(abi.encodePacked('{"version":"1.0.0","retentionWindow":3600}'));

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            expectedHash
        );

        assertEq(registry.epochDataPolicyHash(1), expectedHash);
    }

    function test_dataPolicyHash_zeroForPresenceOnly() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
    }

    function test_dataPolicyHash_zeroAllowedForSignals() external {
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
        assertEq(uint256(registry.epochCapability(1)), uint256(IEpochRegistry.EpochCapability.PresenceWithSignals));
    }

    function test_dataPolicyHash_requiredForEphemeralData() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IEpochRegistry.InvalidDataPolicyHash.selector);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            bytes32(0) // Missing required hash
        );
    }

    function test_dataPolicyHash_nonZeroAllowedForSignals() external {
        bytes32 optionalHash = keccak256("signal-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            optionalHash
        );

        assertEq(registry.epochDataPolicyHash(1), optionalHash);
    }

    /*//////////////////////////////////////////////////////////////
                    POLICY HASH IMMUTABILITY
    //////////////////////////////////////////////////////////////*/

    function test_dataPolicyHash_immutableAfterCreation() external {
        bytes32 policyHash = keccak256("policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        // Warp and finalize
        vm.warp(block.timestamp + 2 days);
        vm.prank(AUTHORITY);
        registry.finalizeEpoch(1);

        // Hash should remain unchanged
        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }

    function test_dataPolicyHash_persistsThroughStateTransitions() external {
        bytes32 policyHash = keccak256("persistent-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        // Scheduled state
        assertEq(uint256(registry.epochState(1)), uint256(IEpochRegistry.EpochState.Scheduled));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Active state
        vm.warp(block.timestamp + 1 hours + 30 minutes);
        assertEq(uint256(registry.epochState(1)), uint256(IEpochRegistry.EpochState.Active));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Closed state
        vm.warp(block.timestamp + 2 hours);
        assertEq(uint256(registry.epochState(1)), uint256(IEpochRegistry.EpochState.Closed));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Finalized state
        vm.prank(AUTHORITY);
        registry.finalizeEpoch(1);
        assertEq(uint256(registry.epochState(1)), uint256(IEpochRegistry.EpochState.Finalized));
        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }

    /*//////////////////////////////////////////////////////////////
                    POLICY HASH SEMANTICS
    //////////////////////////////////////////////////////////////*/

    function test_policyHash_zeroMeansNoPolicyCommitted() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        // bytes32(0) = "no policy committed"
        bytes32 hash = registry.epochDataPolicyHash(1);
        assertEq(hash, bytes32(0));
    }

    function test_policyHash_nonZeroIndicatesCommittedPolicy() external {
        bytes32 policyHash = keccak256("committed-policy");

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        // Non-zero = policy committed
        assertNotEq(registry.epochDataPolicyHash(1), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE EPOCHS
    //////////////////////////////////////////////////////////////*/

    function test_differentEpochs_differentPolicies() external {
        bytes32 policy1 = keccak256("policy-1");
        bytes32 policy2 = keccak256("policy-2");

        vm.startPrank(AUTHORITY);

        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policy1
        );

        registry.createEpochWithCapability(
            2,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policy2
        );

        vm.stopPrank();

        assertEq(registry.epochDataPolicyHash(1), policy1);
        assertEq(registry.epochDataPolicyHash(2), policy2);
        assertNotEq(policy1, policy2);
    }

    function test_mixedCapabilities_differentPolicies() external {
        bytes32 ephemeralPolicy = keccak256("ephemeral");

        vm.startPrank(AUTHORITY);

        // PresenceOnly - no policy
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        // PresenceWithSignals - optional policy (none)
        registry.createEpochWithCapability(
            2, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // PresenceWithEphemeralData - required policy
        registry.createEpochWithCapability(
            3,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            ephemeralPolicy
        );

        vm.stopPrank();

        assertEq(registry.epochDataPolicyHash(1), bytes32(0));
        assertEq(registry.epochDataPolicyHash(2), bytes32(0));
        assertEq(registry.epochDataPolicyHash(3), ephemeralPolicy);

        assertFalse(registry.supportsEphemeralData(1));
        assertFalse(registry.supportsEphemeralData(2));
        assertTrue(registry.supportsEphemeralData(3));
    }
}

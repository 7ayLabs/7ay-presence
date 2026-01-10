// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochCapabilityFuzzTests
 * @notice Property-based tests for v0.5 EpochCapability
 * @dev Spec: specs/v0.5/ephemeral.md
 */
contract EpochCapabilityFuzzTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                    CAPABILITY FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_createEpochWithCapability_presenceOnly(uint256 epochId, uint256 startOffset, uint256 duration)
        external
    {
        vm.assume(epochId != 0);
        vm.assume(startOffset < 365 days);
        vm.assume(duration > 0 && duration < 365 days);

        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );

        assertEq(uint256(registry.epochCapability(epochId)), uint256(IEpochRegistry.EpochCapability.PresenceOnly));
        assertEq(registry.epochDataPolicyHash(epochId), bytes32(0));
        assertFalse(registry.supportsEphemeralData(epochId));
    }

    function testFuzz_createEpochWithCapability_presenceWithSignals(
        uint256 epochId,
        uint256 startOffset,
        uint256 duration,
        bytes32 optionalHash
    ) external {
        vm.assume(epochId != 0);
        vm.assume(startOffset < 365 days);
        vm.assume(duration > 0 && duration < 365 days);

        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, optionalHash
        );

        assertEq(
            uint256(registry.epochCapability(epochId)), uint256(IEpochRegistry.EpochCapability.PresenceWithSignals)
        );
        assertEq(registry.epochDataPolicyHash(epochId), optionalHash);
        assertFalse(registry.supportsEphemeralData(epochId));
    }

    function testFuzz_createEpochWithCapability_presenceWithEphemeralData(
        uint256 epochId,
        uint256 startOffset,
        uint256 duration,
        bytes32 policyHash
    ) external {
        vm.assume(epochId != 0);
        vm.assume(startOffset < 365 days);
        vm.assume(duration > 0 && duration < 365 days);
        vm.assume(policyHash != bytes32(0)); // Required for ephemeral data

        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );

        assertEq(
            uint256(registry.epochCapability(epochId)),
            uint256(IEpochRegistry.EpochCapability.PresenceWithEphemeralData)
        );
        assertEq(registry.epochDataPolicyHash(epochId), policyHash);
        assertTrue(registry.supportsEphemeralData(epochId));
    }

    /*//////////////////////////////////////////////////////////////
                    POLICY HASH FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_dataPolicyHash_anyValidHash(bytes32 policyHash) external {
        vm.assume(policyHash != bytes32(0));

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        );

        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }

    function testFuzz_dataPolicyHash_optionalForSignals(bytes32 anyHash) external {
        // Any hash (including zero) should be valid for signals
        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, anyHash
        );

        assertEq(registry.epochDataPolicyHash(1), anyHash);
    }

    /*//////////////////////////////////////////////////////////////
                    ERROR PRIORITY FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_errorPriority_invalidEpochIdFirst(address caller, uint8 capabilityValue, bytes32 hash) external {
        vm.assume(caller != address(0));

        // InvalidEpochId should always come first
        vm.prank(caller);
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpochWithCapability(
            0, // Invalid epochId
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability(capabilityValue % 3),
            hash
        );
    }

    function testFuzz_invalidCapability_causesRevert(address caller, uint8 invalidCapability) external {
        vm.assume(caller != address(0));
        vm.assume(invalidCapability > 2);

        // Note: In Solidity 0.8+, the EVM validates enum values during ABI decoding
        // Invalid enum values cause a Panic(0x21) - "enum conversion error"
        // This happens before our InvalidCapability check can run
        // The check exists for defense-in-depth but can't be triggered via normal calls

        vm.prank(caller);
        (bool success,) = address(registry)
            .call(
                abi.encodeWithSelector(
                    IEpochRegistry.createEpochWithCapability.selector,
                    1,
                    block.timestamp,
                    block.timestamp + 1 days,
                    invalidCapability,
                    bytes32(0)
                )
            );

        // Call should fail (EVM enum validation)
        assertFalse(success, "Call should fail with invalid enum");
    }

    function testFuzz_errorPriority_invalidDataPolicyHashBeforeAuth(address caller) external {
        vm.assume(caller != AUTHORITY);

        // InvalidDataPolicyHash should come before UnauthorizedEpochAuthority
        vm.prank(caller);
        vm.expectRevert(IEpochRegistry.InvalidDataPolicyHash.selector);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            bytes32(0) // Missing required hash
        );
    }

    /*//////////////////////////////////////////////////////////////
                    CAPABILITY IMMUTABILITY FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_capabilityImmutable_throughStateTransitions(uint8 capabilityValue, bytes32 hash) external {
        vm.assume(capabilityValue <= 2);

        IEpochRegistry.EpochCapability capability = IEpochRegistry.EpochCapability(capabilityValue);
        bytes32 policyHash = hash;

        // Require hash for ephemeral data
        if (capability == IEpochRegistry.EpochCapability.PresenceWithEphemeralData && policyHash == bytes32(0)) {
            policyHash = keccak256("default-policy");
        }

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, block.timestamp + 1 hours, block.timestamp + 2 hours, capability, policyHash
        );

        // Check through all state transitions
        assertEq(uint256(registry.epochCapability(1)), uint256(capability));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Warp to active
        vm.warp(block.timestamp + 1 hours + 30 minutes);
        assertEq(uint256(registry.epochCapability(1)), uint256(capability));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Warp to closed
        vm.warp(block.timestamp + 2 hours);
        assertEq(uint256(registry.epochCapability(1)), uint256(capability));
        assertEq(registry.epochDataPolicyHash(1), policyHash);

        // Finalize
        vm.prank(AUTHORITY);
        registry.finalizeEpoch(1);
        assertEq(uint256(registry.epochCapability(1)), uint256(capability));
        assertEq(registry.epochDataPolicyHash(1), policyHash);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE EPOCHS FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_multipleEpochs_independentCapabilities(
        uint256 epochId1,
        uint256 epochId2,
        uint8 cap1,
        uint8 cap2,
        bytes32 hash1,
        bytes32 hash2
    ) external {
        vm.assume(epochId1 != 0 && epochId2 != 0);
        vm.assume(epochId1 != epochId2);
        vm.assume(cap1 <= 2 && cap2 <= 2);

        IEpochRegistry.EpochCapability capability1 = IEpochRegistry.EpochCapability(cap1);
        IEpochRegistry.EpochCapability capability2 = IEpochRegistry.EpochCapability(cap2);

        bytes32 policyHash1 = hash1;
        bytes32 policyHash2 = hash2;

        // Adjust hashes if needed for ephemeral data
        if (capability1 == IEpochRegistry.EpochCapability.PresenceWithEphemeralData && policyHash1 == bytes32(0)) {
            policyHash1 = keccak256("policy1");
        }
        if (capability2 == IEpochRegistry.EpochCapability.PresenceWithEphemeralData && policyHash2 == bytes32(0)) {
            policyHash2 = keccak256("policy2");
        }

        vm.startPrank(AUTHORITY);

        registry.createEpochWithCapability(
            epochId1, block.timestamp, block.timestamp + 1 days, capability1, policyHash1
        );

        registry.createEpochWithCapability(
            epochId2, block.timestamp, block.timestamp + 1 days, capability2, policyHash2
        );

        vm.stopPrank();

        // Verify independence
        assertEq(uint256(registry.epochCapability(epochId1)), uint256(capability1));
        assertEq(uint256(registry.epochCapability(epochId2)), uint256(capability2));
        assertEq(registry.epochDataPolicyHash(epochId1), policyHash1);
        assertEq(registry.epochDataPolicyHash(epochId2), policyHash2);
    }

    /*//////////////////////////////////////////////////////////////
                    SUPPORTS EPHEMERAL DATA FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_supportsEphemeralData_onlyForEphemeralCapability(uint8 capabilityValue, bytes32 hash) external {
        vm.assume(capabilityValue <= 2);

        IEpochRegistry.EpochCapability capability = IEpochRegistry.EpochCapability(capabilityValue);
        bytes32 policyHash = hash;

        if (capability == IEpochRegistry.EpochCapability.PresenceWithEphemeralData && policyHash == bytes32(0)) {
            policyHash = keccak256("required-policy");
        }

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(1, block.timestamp, block.timestamp + 1 days, capability, policyHash);

        bool shouldSupport = (capability == IEpochRegistry.EpochCapability.PresenceWithEphemeralData);
        assertEq(registry.supportsEphemeralData(1), shouldSupport);
    }
}

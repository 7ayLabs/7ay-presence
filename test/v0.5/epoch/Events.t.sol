// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochCapabilityEventsTests
 * @notice Event emission tests for v0.5 EpochCapability
 * @dev Spec: specs/v0.5/ephemeral.md Section 9
 */
contract EpochCapabilityEventsTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                    EPOCH CREATED V2 EVENT
    //////////////////////////////////////////////////////////////*/

    function test_createEpoch_emitsEpochCreatedV2() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0));

        vm.prank(AUTHORITY);
        registry.createEpoch(1, startTime, endTime);
    }

    function test_createEpoch_emitsBothEvents() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;

        // EpochCreatedV2 first
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0));

        // EpochCreated second (legacy)
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreated(1, startTime, endTime);

        vm.prank(AUTHORITY);
        registry.createEpoch(1, startTime, endTime);
    }

    function test_createEpochWithCapability_presenceOnly_emitsEpochCreatedV2() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0));

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0));
    }

    function test_createEpochWithCapability_presenceWithSignals_emitsEpochCreatedV2() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;
        bytes32 policyHash = keccak256("signal-policy");

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, policyHash
        );

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, policyHash
        );
    }

    function test_createEpochWithCapability_presenceWithEphemeralData_emitsEpochCreatedV2() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;
        bytes32 policyHash = keccak256("ephemeral-policy");

        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );
    }

    function test_createEpochWithCapability_emitsBothEvents() external {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 1 days;
        bytes32 policyHash = keccak256("policy");

        // EpochCreatedV2 first
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );

        // EpochCreated second (legacy)
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreated(1, startTime, endTime);

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );
    }

    /*//////////////////////////////////////////////////////////////
                    EVENT PARAMETER VERIFICATION
    //////////////////////////////////////////////////////////////*/

    function test_epochCreatedV2_epochIdIndexed() external {
        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find EpochCreatedV2 event
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0]
                    == keccak256("EpochCreatedV2(uint256,uint256,uint256,uint8,bytes32)")
            ) {
                // First topic after selector is indexed epochId
                assertEq(entries[i].topics[1], bytes32(uint256(1)));
                found = true;
                break;
            }
        }

        assertTrue(found, "EpochCreatedV2 event not emitted");
    }

    function test_epochCreatedV2_allParametersCorrect() external {
        uint256 startTime = block.timestamp + 100;
        uint256 endTime = block.timestamp + 200;
        bytes32 policyHash = keccak256("test-policy");

        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            42, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, policyHash
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find EpochCreatedV2 event and verify parameters
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0]
                    == keccak256("EpochCreatedV2(uint256,uint256,uint256,uint8,bytes32)")
            ) {
                // Indexed epochId
                assertEq(entries[i].topics[1], bytes32(uint256(42)));

                // Decode non-indexed parameters from data
                (uint256 decodedStart, uint256 decodedEnd, uint8 decodedCap, bytes32 decodedHash) =
                    abi.decode(entries[i].data, (uint256, uint256, uint8, bytes32));

                assertEq(decodedStart, startTime);
                assertEq(decodedEnd, endTime);
                assertEq(decodedCap, uint8(IEpochRegistry.EpochCapability.PresenceWithEphemeralData));
                assertEq(decodedHash, policyHash);
                break;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE EPOCHS EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_multipleEpochs_eachEmitsCorrectEvents() external {
        bytes32 policy1 = keccak256("policy1");
        bytes32 policy2 = keccak256("policy2");

        vm.startPrank(AUTHORITY);

        // First epoch - PresenceOnly
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            1, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        // Second epoch - PresenceWithSignals
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            2, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, policy1
        );
        registry.createEpochWithCapability(
            2, block.timestamp, block.timestamp + 1 days, IEpochRegistry.EpochCapability.PresenceWithSignals, policy1
        );

        // Third epoch - PresenceWithEphemeralData
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreatedV2(
            3,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policy2
        );
        registry.createEpochWithCapability(
            3,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policy2
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    BACKWARDS COMPATIBILITY
    //////////////////////////////////////////////////////////////*/

    function test_legacyEpochCreated_stillEmitted() external {
        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.createEpochWithCapability(
            1,
            block.timestamp,
            block.timestamp + 1 days,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            keccak256("policy")
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundLegacy = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("EpochCreated(uint256,uint256,uint256)")) {
                foundLegacy = true;
                break;
            }
        }

        assertTrue(foundLegacy, "Legacy EpochCreated event should still be emitted");
    }

    function test_eventOrder_v2BeforeLegacy() external {
        vm.recordLogs();

        vm.prank(AUTHORITY);
        registry.createEpoch(1, block.timestamp, block.timestamp + 1 days);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 v2Selector = keccak256("EpochCreatedV2(uint256,uint256,uint256,uint8,bytes32)");
        bytes32 legacySelector = keccak256("EpochCreated(uint256,uint256,uint256)");

        int256 v2Index = -1;
        int256 legacyIndex = -1;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == v2Selector) {
                v2Index = int256(i);
            }
            if (entries[i].topics[0] == legacySelector) {
                legacyIndex = int256(i);
            }
        }

        assertTrue(v2Index >= 0, "EpochCreatedV2 not found");
        assertTrue(legacyIndex >= 0, "EpochCreated not found");
        assertTrue(v2Index < legacyIndex, "EpochCreatedV2 should be emitted before EpochCreated");
    }
}

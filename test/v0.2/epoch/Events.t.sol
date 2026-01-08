// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistryEventTests
 * @notice Event emission tests for epoch lifecycle
 * @dev Spec: specs/v0.2/epoch.md Section 6
 */
contract EpochRegistryEventTests is Test {
    IEpochRegistry internal registry;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(authority)));
    }

    function test_emitsEpochCreated() external {
        vm.prank(authority);
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreated(1, block.timestamp + 100, block.timestamp + 200);
        registry.createEpoch(1, block.timestamp + 100, block.timestamp + 200);
    }

    function test_emitsEpochFinalized() external {
        vm.prank(authority);
        registry.createEpoch(1, block.timestamp, block.timestamp + 100);

        vm.warp(block.timestamp + 101);

        vm.prank(authority);
        vm.expectEmit(true, false, false, false);
        emit IEpochRegistry.EpochFinalized(1);
        registry.finalizeEpoch(1);
    }

    function testFuzz_eventEmission(uint256 epochId, uint256 duration) external {
        vm.assume(epochId != 0);
        vm.assume(duration > 0 && duration < 365 days);

        uint256 startTime = block.timestamp + 50;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        vm.expectEmit(true, false, false, true);
        emit IEpochRegistry.EpochCreated(epochId, startTime, endTime);
        registry.createEpoch(epochId, startTime, endTime);
    }
}

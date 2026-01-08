// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistryFuzzTests
 * @notice Property-based fuzz tests for epoch lifecycle
 * @dev Spec: specs/v0.2/epoch.md
 */
contract EpochRegistryFuzzTests is Test {
    IEpochRegistry internal registry;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(authority)));
    }

    /*//////////////////////////////////////////////////////////////
                            CREATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_createEpoch(uint256 epochId, uint256 startOffset, uint256 duration) external {
        vm.assume(epochId != 0);
        vm.assume(startOffset < 365 days);
        vm.assume(duration > 0 && duration < 365 days);

        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        registry.createEpoch(epochId, startTime, endTime);

        IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);
        assertTrue(epoch.exists);
        assertEq(epoch.startTime, startTime);
        assertEq(epoch.endTime, endTime);
        assertFalse(epoch.finalized);
    }

    /*//////////////////////////////////////////////////////////////
                            STATE TRANSITIONS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_stateTransitions(uint256 epochId, uint256 duration) external {
        vm.assume(epochId != 0);
        vm.assume(duration > 100 && duration < 365 days);

        uint256 startTime = block.timestamp + 50;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        registry.createEpoch(epochId, startTime, endTime);

        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Scheduled));

        vm.warp(startTime);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Active));
        assertTrue(registry.isEpochActive(epochId));

        vm.warp(endTime);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Closed));
        assertFalse(registry.isEpochActive(epochId));

        vm.prank(authority);
        registry.finalizeEpoch(epochId);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORITY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_unauthorizedCreate(address caller, uint256 epochId) external {
        vm.assume(caller != authority);
        vm.assume(caller != address(0));
        vm.assume(epochId != 0);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.UnauthorizedEpochAuthority.selector, caller, authority));
        registry.createEpoch(epochId, block.timestamp + 100, block.timestamp + 200);
    }

    function testFuzz_unauthorizedFinalize(address caller, uint256 epochId) external {
        vm.assume(caller != authority);
        vm.assume(caller != address(0));
        vm.assume(epochId != 0);

        vm.prank(authority);
        registry.createEpoch(epochId, block.timestamp, block.timestamp + 100);
        vm.warp(block.timestamp + 101);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.UnauthorizedEpochAuthority.selector, caller, authority));
        registry.finalizeEpoch(epochId);
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_epochAlreadyExists(uint256 epochId) external {
        vm.assume(epochId != 0);

        vm.startPrank(authority);
        registry.createEpoch(epochId, block.timestamp + 100, block.timestamp + 200);

        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.EpochAlreadyExists.selector, epochId));
        registry.createEpoch(epochId, block.timestamp + 300, block.timestamp + 400);
        vm.stopPrank();
    }

    function testFuzz_invalidBounds_equal(uint256 epochId, uint256 time) external {
        vm.assume(epochId != 0);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.InvalidEpochBounds.selector, time, time));
        registry.createEpoch(epochId, time, time);
    }

    function testFuzz_invalidBounds_reversed(uint256 epochId, uint256 startTime, uint256 endTime) external {
        vm.assume(epochId != 0);
        vm.assume(startTime > endTime);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.InvalidEpochBounds.selector, startTime, endTime));
        registry.createEpoch(epochId, startTime, endTime);
    }

    function testFuzz_epochNotFound(uint256 epochId) external {
        vm.assume(epochId != 0);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.EpochNotFound.selector, epochId));
        registry.finalizeEpoch(epochId);
    }

    function testFuzz_epochNotClosed(uint256 epochId) external {
        vm.assume(epochId != 0);

        vm.prank(authority);
        registry.createEpoch(epochId, block.timestamp + 100, block.timestamp + 200);

        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(IEpochRegistry.EpochNotClosed.selector, epochId, IEpochRegistry.EpochState.Scheduled)
        );
        registry.finalizeEpoch(epochId);
    }
}

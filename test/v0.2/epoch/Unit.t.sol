// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistryUnitTests
 * @notice Unit tests for epoch specification compliance
 * @dev Spec: specs/v0.2/epoch.md
 */
contract EpochRegistryUnitTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_epochZeroRejected() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpoch(0, block.timestamp + 100, block.timestamp + 200);
    }

    function test_nonExistentEpochReturnsNone() external view {
        IEpochRegistry.EpochState state = registry.epochState(999);
        assertEq(uint256(state), uint256(IEpochRegistry.EpochState.None));
    }

    function test_constructorRejectsZeroAuthority() external {
        vm.expectRevert(IEpochRegistry.InvalidEpochAuthority.selector);
        new EpochRegistry(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    function test_fullLifecycle() external {
        uint256 startTime = block.timestamp + 100;
        uint256 endTime = block.timestamp + 200;

        vm.prank(AUTHORITY);
        registry.createEpoch(EPOCH_ID, startTime, endTime);

        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Scheduled));

        (uint256 start, uint256 end) = registry.epochBounds(EPOCH_ID);
        assertEq(start, startTime);
        assertEq(end, endTime);

        vm.warp(startTime);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Active));

        vm.warp(endTime);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Closed));

        vm.prank(AUTHORITY);
        registry.finalizeEpoch(EPOCH_ID);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Finalized));

        IEpochRegistry.Epoch memory epoch = registry.getEpoch(EPOCH_ID);
        assertTrue(epoch.finalized);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function test_authorityIsImmutable() external view {
        assertEq(registry.epochAuthority(), AUTHORITY);
    }

    function test_isEpochActiveConvenience() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(EPOCH_ID, block.timestamp + 100, block.timestamp + 200);

        assertFalse(registry.isEpochActive(EPOCH_ID));

        vm.warp(block.timestamp + 100);
        assertTrue(registry.isEpochActive(EPOCH_ID));

        vm.warp(block.timestamp + 200);
        assertFalse(registry.isEpochActive(EPOCH_ID));
    }

    function test_invalidEpochId() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpoch(0, block.timestamp + 100, block.timestamp + 200);
    }
}

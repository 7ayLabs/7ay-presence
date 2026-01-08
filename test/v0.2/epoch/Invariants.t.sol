// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistryHandler
 * @notice Handler contract for Foundry invariant testing
 */
contract EpochRegistryHandler is Test {
    IEpochRegistry public registry;
    address public authority;

    mapping(uint256 => bool) public ghost_created;
    mapping(uint256 => bool) public ghost_finalized;
    uint256[] public ghost_epochIds;

    uint256[] internal boundedEpochIds;

    constructor(IEpochRegistry _registry, address _authority) {
        registry = _registry;
        authority = _authority;

        boundedEpochIds.push(1);
        boundedEpochIds.push(2);
        boundedEpochIds.push(3);
        boundedEpochIds.push(100);
    }

    function createEpoch(uint256 epochSeed, uint256 durationSeed) external {
        uint256 epochId = boundedEpochIds[epochSeed % boundedEpochIds.length];
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_created[epochId]) return;

        uint256 startTime = block.timestamp + 10;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        registry.createEpoch(epochId, startTime, endTime);

        ghost_created[epochId] = true;
        ghost_epochIds.push(epochId);
    }

    function finalizeEpoch(uint256 epochSeed) external {
        if (ghost_epochIds.length == 0) return;

        uint256 epochId = ghost_epochIds[epochSeed % ghost_epochIds.length];

        if (ghost_finalized[epochId]) return;
        if (!ghost_created[epochId]) return;

        IEpochRegistry.EpochState state = registry.epochState(epochId);
        if (state != IEpochRegistry.EpochState.Closed) return;

        vm.prank(authority);
        registry.finalizeEpoch(epochId);

        ghost_finalized[epochId] = true;
    }

    function warpTime(uint256 secondsSeed) external {
        uint256 warpSeconds = (secondsSeed % 2000) + 1;
        vm.warp(block.timestamp + warpSeconds);
    }

    function getGhostEpochIdsLength() external view returns (uint256) {
        return ghost_epochIds.length;
    }

    function getGhostEpochId(uint256 index) external view returns (uint256) {
        return ghost_epochIds[index];
    }
}

/**
 * @title EpochRegistryInvariants
 * @notice Protocol invariants for epoch lifecycle
 * @dev Spec: specs/v0.2/epoch.md Section 8
 */
contract EpochRegistryInvariants is Test {
    IEpochRegistry internal registry;
    EpochRegistryHandler internal handler;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(authority)));
        handler = new EpochRegistryHandler(registry, authority);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = EpochRegistryHandler.createEpoch.selector;
        selectors[1] = EpochRegistryHandler.finalizeEpoch.selector;
        selectors[2] = EpochRegistryHandler.warpTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV1: Each epochId maps to at most one epoch
    function invariant_epochUniqueness() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            if (handler.ghost_created(epochId)) {
                IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);
                assertTrue(epoch.exists, "INV1: Ghost/storage mismatch");
            }
        }
    }

    /// @dev INV2: startTime < endTime for all epochs
    function invariant_boundValidity() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);
            if (epoch.exists) {
                assertTrue(epoch.startTime < epoch.endTime, "INV2: Invalid bounds");
            }
        }
    }

    /// @dev INV3: Finalized epoch never transitions
    function invariant_monotonicFinalization() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            if (handler.ghost_finalized(epochId)) {
                IEpochRegistry.EpochState state = registry.epochState(epochId);
                assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Finalized), "INV3: Finalized changed");
            }
        }
    }

    /// @dev INV4: State = f(storage, block.timestamp)
    function invariant_stateConsistency() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);

            if (!epoch.exists) {
                assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.None), "INV4: None");
                continue;
            }

            if (epoch.finalized) {
                assertEq(
                    uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Finalized), "INV4: Finalized"
                );
                continue;
            }

            IEpochRegistry.EpochState state = registry.epochState(epochId);
            if (block.timestamp < epoch.startTime) {
                assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Scheduled), "INV4: Scheduled");
            } else if (block.timestamp < epoch.endTime) {
                assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Active), "INV4: Active");
            } else {
                assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Closed), "INV4: Closed");
            }
        }
    }
}

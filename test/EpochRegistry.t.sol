// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistryHandler
 * @notice Handler contract for Foundry invariant testing
 *
 * @dev
 * This handler exposes actions that the fuzzer can call to mutate
 * epoch state. Ghost variables track state for invariant assertions.
 */
contract EpochRegistryHandler is Test {
    IEpochRegistry public registry;
    address public authority;

    // Ghost variables for tracking state
    mapping(uint256 => bool) public ghost_created;
    mapping(uint256 => bool) public ghost_finalized;
    uint256[] public ghost_epochIds;

    // Bounded inputs for focused fuzzing
    uint256[] internal boundedEpochIds;

    constructor(IEpochRegistry _registry, address _authority) {
        registry = _registry;
        authority = _authority;

        boundedEpochIds.push(1);
        boundedEpochIds.push(2);
        boundedEpochIds.push(3);
        boundedEpochIds.push(100);
    }

    /**
     * @notice Create epoch with bounded inputs
     */
    function createEpoch(uint256 epochSeed, uint256 durationSeed) external {
        uint256 epochId = boundedEpochIds[epochSeed % boundedEpochIds.length];
        uint256 duration = (durationSeed % 1000) + 100; // 100-1100 seconds

        if (ghost_created[epochId]) return;

        uint256 startTime = block.timestamp + 10;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        registry.createEpoch(epochId, startTime, endTime);

        ghost_created[epochId] = true;
        ghost_epochIds.push(epochId);
    }

    /**
     * @notice Finalize epoch (must warp time first)
     */
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

    /**
     * @notice Warp time forward
     */
    function warpTime(uint256 secondsSeed) external {
        uint256 warpSeconds = (secondsSeed % 2000) + 1;
        vm.warp(block.timestamp + warpSeconds);
    }

    // === Getters ===

    function getGhostEpochIdsLength() external view returns (uint256) {
        return ghost_epochIds.length;
    }

    function getGhostEpochId(uint256 index) external view returns (uint256) {
        return ghost_epochIds[index];
    }
}

/**
 * @title EpochRegistryInvariants
 * @notice Protocol invariants for the 7ay Epoch Registry
 *
 * @dev
 * These invariants verify epoch lifecycle correctness.
 * Reference: specs/epoch.md Section 8
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

    /*//////////////////////////////////////////////////////////////
                    INVARIANT #1: Epoch Uniqueness
      Each epochId MUST map to at most one epoch.
    //////////////////////////////////////////////////////////////*/

    function invariant_epochUniqueness() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);

            // If ghost says created, epoch must exist
            if (handler.ghost_created(epochId)) {
                IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);
                assertTrue(epoch.exists, "INV1: Ghost/storage mismatch");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT #2: Bound Validity
      startTime < endTime MUST hold for all epochs.
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                    INVARIANT #3: Monotonic Finalization
      A finalized epoch MUST NOT transition to any other state.
    //////////////////////////////////////////////////////////////*/

    function invariant_monotonicFinalization() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);

            if (handler.ghost_finalized(epochId)) {
                IEpochRegistry.EpochState state = registry.epochState(epochId);
                assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Finalized), "INV3: Finalized state changed");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT #4: State Consistency
      Epoch state MUST be computable deterministically.
    //////////////////////////////////////////////////////////////*/

    function invariant_stateConsistency() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);

            if (!epoch.exists) {
                assertEq(
                    uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.None), "INV4: None state"
                );
                continue;
            }

            if (epoch.finalized) {
                assertEq(
                    uint256(registry.epochState(epochId)),
                    uint256(IEpochRegistry.EpochState.Finalized),
                    "INV4: Finalized"
                );
                continue;
            }

            // Non-finalized existing epoch
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

/**
 * @title EpochRegistryFuzzTests
 * @notice Property-based fuzz tests for epoch lifecycle
 */
contract EpochRegistryFuzzTests is Test {
    IEpochRegistry internal registry;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(authority)));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Epoch Creation
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
                        FUZZ: State Transitions
    //////////////////////////////////////////////////////////////*/

    function testFuzz_stateTransitions(uint256 epochId, uint256 duration) external {
        vm.assume(epochId != 0);
        vm.assume(duration > 100 && duration < 365 days);

        uint256 startTime = block.timestamp + 50;
        uint256 endTime = startTime + duration;

        vm.prank(authority);
        registry.createEpoch(epochId, startTime, endTime);

        // State: Scheduled
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Scheduled));

        // Warp to Active
        vm.warp(startTime);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Active));
        assertTrue(registry.isEpochActive(epochId));

        // Warp to Closed
        vm.warp(endTime);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Closed));
        assertFalse(registry.isEpochActive(epochId));

        // Finalize
        vm.prank(authority);
        registry.finalizeEpoch(epochId);
        assertEq(uint256(registry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Finalized));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Authority Enforcement
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

        // Create and close epoch first
        vm.prank(authority);
        registry.createEpoch(epochId, block.timestamp, block.timestamp + 100);
        vm.warp(block.timestamp + 101);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.UnauthorizedEpochAuthority.selector, caller, authority));
        registry.finalizeEpoch(epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Error Conditions
    //////////////////////////////////////////////////////////////*/

    function testFuzz_epochAlreadyExists(uint256 epochId) external {
        vm.assume(epochId != 0);

        vm.startPrank(authority);
        registry.createEpoch(epochId, block.timestamp + 100, block.timestamp + 200);

        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.EpochAlreadyExists.selector, epochId));
        registry.createEpoch(epochId, block.timestamp + 300, block.timestamp + 400);
        vm.stopPrank();
    }

    function testFuzz_invalidBounds(uint256 epochId, uint256 time) external {
        vm.assume(epochId != 0);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IEpochRegistry.InvalidEpochBounds.selector, time, time));
        registry.createEpoch(epochId, time, time); // startTime == endTime
    }

    function test_invalidEpochId() external {
        vm.prank(authority);
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpoch(0, block.timestamp + 100, block.timestamp + 200);
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

        // Epoch is Scheduled, not Closed
        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(IEpochRegistry.EpochNotClosed.selector, epochId, IEpochRegistry.EpochState.Scheduled)
        );
        registry.finalizeEpoch(epochId);
    }
}

/**
 * @title EpochRegistryEventTests
 * @notice Event emission tests for epoch lifecycle
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

/**
 * @title EpochRegistryPropertyTests
 * @notice Deterministic property tests for epoch specification compliance
 */
contract EpochRegistryPropertyTests is Test {
    IEpochRegistry internal registry;
    address internal constant AUTHORITY = address(0xA077);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
    }

    function test_epochZeroRejected() external {
        vm.prank(AUTHORITY);
        vm.expectRevert(IEpochRegistry.InvalidEpochId.selector);
        registry.createEpoch(0, block.timestamp + 100, block.timestamp + 200);
    }

    function test_nonExistentEpochReturnsNone() external view {
        IEpochRegistry.EpochState state = registry.epochState(999);
        assertEq(uint256(state), uint256(IEpochRegistry.EpochState.None));
    }

    function test_fullLifecycle() external {
        uint256 startTime = block.timestamp + 100;
        uint256 endTime = block.timestamp + 200;

        // Create
        vm.prank(AUTHORITY);
        registry.createEpoch(EPOCH_ID, startTime, endTime);

        // Verify Scheduled
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Scheduled));

        // Verify bounds
        (uint256 start, uint256 end) = registry.epochBounds(EPOCH_ID);
        assertEq(start, startTime);
        assertEq(end, endTime);

        // Transition to Active
        vm.warp(startTime);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Active));

        // Transition to Closed
        vm.warp(endTime);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Closed));

        // Finalize
        vm.prank(AUTHORITY);
        registry.finalizeEpoch(EPOCH_ID);
        assertEq(uint256(registry.epochState(EPOCH_ID)), uint256(IEpochRegistry.EpochState.Finalized));

        // Verify immutability
        IEpochRegistry.Epoch memory epoch = registry.getEpoch(EPOCH_ID);
        assertTrue(epoch.finalized);
    }

    function test_authorityIsImmutable() external view {
        assertEq(registry.epochAuthority(), AUTHORITY);
    }

    function test_isEpochActiveConvenience() external {
        vm.prank(AUTHORITY);
        registry.createEpoch(EPOCH_ID, block.timestamp + 100, block.timestamp + 200);

        assertFalse(registry.isEpochActive(EPOCH_ID)); // Scheduled

        vm.warp(block.timestamp + 100);
        assertTrue(registry.isEpochActive(EPOCH_ID)); // Active

        vm.warp(block.timestamp + 200);
        assertFalse(registry.isEpochActive(EPOCH_ID)); // Closed
    }
}

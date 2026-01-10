// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title EpochCapabilityHandler
 * @notice Handler for v0.5 capability invariant testing
 */
contract EpochCapabilityHandler is Test {
    IEpochRegistry public registry;
    address public authority;

    // Ghost state tracking
    mapping(uint256 => IEpochRegistry.EpochCapability) public ghost_capability;
    mapping(uint256 => bytes32) public ghost_policyHash;
    mapping(uint256 => bool) public ghost_created;
    uint256[] public ghost_epochIds;

    constructor(IEpochRegistry _registry, address _authority) {
        registry = _registry;
        authority = _authority;
    }

    function createEpochPresenceOnly(uint256 epochSeed, uint256 durationSeed) external {
        uint256 epochId = (epochSeed % 100) + 1;
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_created[epochId]) return;

        vm.prank(authority);
        try registry.createEpoch(epochId, block.timestamp + 10, block.timestamp + 10 + duration) {
            ghost_created[epochId] = true;
            ghost_capability[epochId] = IEpochRegistry.EpochCapability.PresenceOnly;
            ghost_policyHash[epochId] = bytes32(0);
            ghost_epochIds.push(epochId);
        } catch {}
    }

    function createEpochWithSignals(uint256 epochSeed, uint256 durationSeed, bytes32 optionalHash) external {
        uint256 epochId = (epochSeed % 100) + 1;
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_created[epochId]) return;

        vm.prank(authority);
        try registry.createEpochWithCapability(
            epochId,
            block.timestamp + 10,
            block.timestamp + 10 + duration,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            optionalHash
        ) {
            ghost_created[epochId] = true;
            ghost_capability[epochId] = IEpochRegistry.EpochCapability.PresenceWithSignals;
            ghost_policyHash[epochId] = optionalHash;
            ghost_epochIds.push(epochId);
        } catch {}
    }

    function createEpochWithEphemeralData(uint256 epochSeed, uint256 durationSeed, bytes32 policyHash) external {
        uint256 epochId = (epochSeed % 100) + 1;
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_created[epochId]) return;
        if (policyHash == bytes32(0)) return; // Required for ephemeral data

        vm.prank(authority);
        try registry.createEpochWithCapability(
            epochId,
            block.timestamp + 10,
            block.timestamp + 10 + duration,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        ) {
            ghost_created[epochId] = true;
            ghost_capability[epochId] = IEpochRegistry.EpochCapability.PresenceWithEphemeralData;
            ghost_policyHash[epochId] = policyHash;
            ghost_epochIds.push(epochId);
        } catch {}
    }

    function warpTime(uint256 secondsSeed) external {
        uint256 warpSeconds = (secondsSeed % 2000) + 1;
        vm.warp(block.timestamp + warpSeconds);
    }

    function finalizeEpoch(uint256 epochSeed) external {
        uint256 epochId = (epochSeed % 100) + 1;

        if (!ghost_created[epochId]) return;

        IEpochRegistry.EpochState state = registry.epochState(epochId);
        if (state != IEpochRegistry.EpochState.Closed) return;

        vm.prank(authority);
        try registry.finalizeEpoch(epochId) {} catch {}
    }

    function getGhostEpochIdsLength() external view returns (uint256) {
        return ghost_epochIds.length;
    }

    function getGhostEpochId(uint256 index) external view returns (uint256) {
        return ghost_epochIds[index];
    }
}

/**
 * @title EpochV05Invariants
 * @notice Protocol invariants for v0.5 capability features
 * @dev Spec: specs/v0.5/ephemeral.md Section 11
 */
contract EpochV05Invariants is Test {
    IEpochRegistry internal registry;
    EpochCapabilityHandler internal handler;
    address internal authority = address(0xA077);

    function setUp() external {
        registry = IEpochRegistry(address(new EpochRegistry(authority)));
        handler = new EpochCapabilityHandler(registry, authority);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = EpochCapabilityHandler.createEpochPresenceOnly.selector;
        selectors[1] = EpochCapabilityHandler.createEpochWithSignals.selector;
        selectors[2] = EpochCapabilityHandler.createEpochWithEphemeralData.selector;
        selectors[3] = EpochCapabilityHandler.warpTime.selector;
        selectors[4] = EpochCapabilityHandler.finalizeEpoch.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV-CAP1: Capability is immutable once set
    function invariant_capabilityImmutable() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.EpochCapability ghostCap = handler.ghost_capability(epochId);
            IEpochRegistry.EpochCapability onChainCap = registry.epochCapability(epochId);

            assertEq(uint256(ghostCap), uint256(onChainCap), "INV-CAP1: Capability changed");
        }
    }

    /// @dev INV-CAP2: Policy hash is immutable once set
    function invariant_policyHashImmutable() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            bytes32 ghostHash = handler.ghost_policyHash(epochId);
            bytes32 onChainHash = registry.epochDataPolicyHash(epochId);

            assertEq(ghostHash, onChainHash, "INV-CAP2: Policy hash changed");
        }
    }

    /// @dev INV-CAP3: supportsEphemeralData consistency
    function invariant_supportsEphemeralDataConsistency() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.EpochCapability cap = registry.epochCapability(epochId);
            bool hasEphemeralSupport = registry.supportsEphemeralData(epochId);

            if (cap == IEpochRegistry.EpochCapability.PresenceWithEphemeralData) {
                assertTrue(hasEphemeralSupport, "INV-CAP3: Should support ephemeral data");
            } else {
                assertFalse(hasEphemeralSupport, "INV-CAP3: Should not support ephemeral data");
            }
        }
    }

    /// @dev INV-CAP4: Capability valid range (0-2)
    function invariant_capabilityValidRange() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            uint256 capValue = uint256(registry.epochCapability(epochId));

            assertTrue(capValue <= 2, "INV-CAP4: Capability out of range");
        }
    }

    /// @dev INV17: Ephemeral Data MUST NOT influence presence state (orthogonality)
    /// Note: This tests that epoch state machine works independently of capability
    function invariant_capabilityOrthogonalToEpochState() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);
            IEpochRegistry.Epoch memory epoch = registry.getEpoch(epochId);

            // Epoch struct should remain unchanged regardless of capability
            assertTrue(epoch.exists, "INV17: Epoch should exist");
            assertTrue(epoch.startTime < epoch.endTime, "INV17: Epoch bounds valid");

            // State machine works regardless of capability
            IEpochRegistry.EpochState state = registry.epochState(epochId);
            assertTrue(
                state == IEpochRegistry.EpochState.Scheduled || state == IEpochRegistry.EpochState.Active
                    || state == IEpochRegistry.EpochState.Closed || state == IEpochRegistry.EpochState.Finalized,
                "INV17: State should be valid"
            );
        }
    }

    /// @dev INV-CAP5: Ghost tracking consistency
    function invariant_ghostTrackingConsistency() external view {
        uint256 len = handler.getGhostEpochIdsLength();
        for (uint256 i = 0; i < len; i++) {
            uint256 epochId = handler.getGhostEpochId(i);

            assertTrue(handler.ghost_created(epochId), "INV-CAP5: Ghost created should be true");
            assertTrue(registry.getEpoch(epochId).exists, "INV-CAP5: On-chain epoch should exist");
        }
    }
}

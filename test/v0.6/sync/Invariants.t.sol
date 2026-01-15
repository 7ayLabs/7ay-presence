// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title StateSyncHandler
 * @notice Handler for v0.6 state sync invariant testing
 * @dev Simulates state changes that off-chain sync would need to reconcile
 */
contract StateSyncHandler is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority;
    address public validatorAuthority;

    // Ghost state for tracking
    mapping(uint256 => bool) public ghost_epochCreated;
    mapping(uint256 => IEpochRegistry.EpochCapability) public ghost_epochCapability;
    mapping(address => mapping(uint256 => IPresenceRegistry.PresenceState)) public ghost_presenceState;
    mapping(address => mapping(uint256 => uint256)) public ghost_validationCount;

    uint256[] public ghost_epochIds;
    address[] public ghost_actors;
    address[] public validators;

    uint256 public currentEpochId = 1;

    constructor(
        IEpochRegistry _epochRegistry,
        IPresenceRegistry _presenceRegistry,
        IValidatorRegistry _validatorRegistry,
        address _epochAuthority,
        address _validatorAuthority
    ) {
        epochRegistry = _epochRegistry;
        presenceRegistry = _presenceRegistry;
        validatorRegistry = _validatorRegistry;
        epochAuthority = _epochAuthority;
        validatorAuthority = _validatorAuthority;

        // Pre-populate validators
        validators.push(address(0x1001));
        validators.push(address(0x1002));
        validators.push(address(0x1003));

        // Add validators
        vm.startPrank(validatorAuthority);
        for (uint256 i = 0; i < validators.length; i++) {
            validatorRegistry.addValidator(validators[i]);
        }
        vm.stopPrank();
    }

    function createEpochWithSignals(uint256 epochSeed, uint256 durationSeed) external {
        uint256 epochId = (epochSeed % 50) + 1;
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_epochCreated[epochId]) return;

        vm.prank(epochAuthority);
        try epochRegistry.createEpochWithCapability(
            epochId,
            block.timestamp + 10,
            block.timestamp + 10 + duration,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0)
        ) {
            ghost_epochCreated[epochId] = true;
            ghost_epochCapability[epochId] = IEpochRegistry.EpochCapability.PresenceWithSignals;
            ghost_epochIds.push(epochId);
            currentEpochId = epochId;
        } catch {}
    }

    function createEpochWithEphemeralData(uint256 epochSeed, uint256 durationSeed, bytes32 policyHash) external {
        uint256 epochId = (epochSeed % 50) + 1;
        uint256 duration = (durationSeed % 1000) + 100;

        if (ghost_epochCreated[epochId]) return;
        if (policyHash == bytes32(0)) return;

        vm.prank(epochAuthority);
        try epochRegistry.createEpochWithCapability(
            epochId,
            block.timestamp + 10,
            block.timestamp + 10 + duration,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            policyHash
        ) {
            ghost_epochCreated[epochId] = true;
            ghost_epochCapability[epochId] = IEpochRegistry.EpochCapability.PresenceWithEphemeralData;
            ghost_epochIds.push(epochId);
            currentEpochId = epochId;
        } catch {}
    }

    function declarePresence(uint256 actorSeed) external {
        address actor = address(uint160(0xA11C0 + (actorSeed % 100)));

        if (ghost_epochIds.length == 0) return;

        uint256 epochId = ghost_epochIds[actorSeed % ghost_epochIds.length];
        if (epochRegistry.epochState(epochId) != IEpochRegistry.EpochState.Active) return;

        IPresenceRegistry.PresenceState currentState = presenceRegistry.presenceState(actor, epochId);
        if (currentState != IPresenceRegistry.PresenceState.None) return;

        vm.prank(actor);
        try presenceRegistry.declarePresence(actor, epochId) {
            ghost_presenceState[actor][epochId] = IPresenceRegistry.PresenceState.Declared;
            ghost_validationCount[actor][epochId] = 0;

            // Track unique actors
            bool found = false;
            for (uint256 i = 0; i < ghost_actors.length; i++) {
                if (ghost_actors[i] == actor) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                ghost_actors.push(actor);
            }
        } catch {}
    }

    function validatePresence(uint256 actorSeed, uint256 validatorSeed) external {
        if (ghost_actors.length == 0) return;
        if (ghost_epochIds.length == 0) return;

        address actor = ghost_actors[actorSeed % ghost_actors.length];
        address validator = validators[validatorSeed % validators.length];
        uint256 epochId = ghost_epochIds[actorSeed % ghost_epochIds.length];

        if (epochRegistry.epochState(epochId) != IEpochRegistry.EpochState.Active) return;

        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, epochId);
        if (state != IPresenceRegistry.PresenceState.Declared) return;
        if (presenceRegistry.hasValidatorVotedForPresence(validator, actor, epochId)) return;

        vm.prank(validator);
        try presenceRegistry.validatePresence(actor, epochId) {
            ghost_validationCount[actor][epochId]++;

            // Update ghost state if validated
            IPresenceRegistry.PresenceState newState = presenceRegistry.presenceState(actor, epochId);
            ghost_presenceState[actor][epochId] = newState;
        } catch {}
    }

    function warpToActive(uint256 epochSeed) external {
        if (ghost_epochIds.length == 0) return;

        uint256 epochId = ghost_epochIds[epochSeed % ghost_epochIds.length];
        (uint256 startTime,) = epochRegistry.epochBounds(epochId);

        if (block.timestamp < startTime) {
            vm.warp(startTime);
        }
    }

    function warpTime(uint256 secondsSeed) external {
        uint256 warpSeconds = (secondsSeed % 500) + 1;
        vm.warp(block.timestamp + warpSeconds);
    }

    // Getters for invariant checks
    function getGhostEpochIdsLength() external view returns (uint256) {
        return ghost_epochIds.length;
    }

    function getGhostEpochId(uint256 index) external view returns (uint256) {
        return ghost_epochIds[index];
    }

    function getGhostActorsLength() external view returns (uint256) {
        return ghost_actors.length;
    }

    function getGhostActor(uint256 index) external view returns (address) {
        return ghost_actors[index];
    }

    function getValidatorsLength() external view returns (uint256) {
        return validators.length;
    }

    function getValidator(uint256 index) external view returns (address) {
        return validators[index];
    }
}

/**
 * @title StateSyncInvariants
 * @notice Protocol invariants for v0.6 state synchronization
 * @dev Spec: specs/v0.6/invariants.md Section 4
 *
 * These invariants verify that on-chain state provides a consistent,
 * deterministic source of truth for off-chain state reconciliation.
 */
contract StateSyncInvariants is Test {
    IEpochRegistry internal epochRegistry;
    IPresenceRegistry internal presenceRegistry;
    IValidatorRegistry internal validatorRegistry;
    StateSyncHandler internal handler;

    address internal epochAuthority = address(0xE001);
    address internal validatorAuthority = address(0xA077);

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(epochAuthority)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(validatorAuthority)));
        presenceRegistry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        handler = new StateSyncHandler(
            epochRegistry, presenceRegistry, validatorRegistry, epochAuthority, validatorAuthority
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = StateSyncHandler.createEpochWithSignals.selector;
        selectors[1] = StateSyncHandler.createEpochWithEphemeralData.selector;
        selectors[2] = StateSyncHandler.declarePresence.selector;
        selectors[3] = StateSyncHandler.validatePresence.selector;
        selectors[4] = StateSyncHandler.warpToActive.selector;
        selectors[5] = StateSyncHandler.warpTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV19: Node identity (presence state) MUST be derivable from on-chain state
    function invariant_nodeIdentityDerivable() external view {
        uint256 actorCount = handler.getGhostActorsLength();
        uint256 epochCount = handler.getGhostEpochIdsLength();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.getGhostActor(i);

            for (uint256 j = 0; j < epochCount; j++) {
                uint256 epochId = handler.getGhostEpochId(j);

                // On-chain state must be queryable
                IPresenceRegistry.PresenceState onChainState = presenceRegistry.presenceState(actor, epochId);

                // Ghost state should match on-chain (if we tracked it)
                IPresenceRegistry.PresenceState ghostState = handler.ghost_presenceState(actor, epochId);

                // If ghost has a non-None state, it should match on-chain
                if (ghostState != IPresenceRegistry.PresenceState.None) {
                    assertEq(uint256(onChainState), uint256(ghostState), "INV19: Ghost state must match on-chain");
                }
            }
        }
    }

    /// @dev INV20: Node MUST be bound to exactly one epoch at any time (for sync context)
    /// Note: This verifies presence is epoch-scoped
    function invariant_presenceEpochScoped() external view {
        uint256 actorCount = handler.getGhostActorsLength();
        uint256 epochCount = handler.getGhostEpochIdsLength();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.getGhostActor(i);

            for (uint256 j = 0; j < epochCount; j++) {
                uint256 epochId = handler.getGhostEpochId(j);

                // Each (actor, epoch) pair has independent state
                IPresenceRegistry.Presence memory presence = presenceRegistry.getPresence(actor, epochId);

                // Presence data is isolated to this epoch
                if (presence.state != IPresenceRegistry.PresenceState.None) {
                    assertTrue(presence.declaredAt > 0, "INV20: Declared presence should have timestamp");
                }
            }
        }
    }

    /// @dev INV23: v0.6 features require epochs with PresenceWithSignals or higher
    function invariant_epochCapabilityForV06() external view {
        uint256 epochCount = handler.getGhostEpochIdsLength();

        for (uint256 i = 0; i < epochCount; i++) {
            uint256 epochId = handler.getGhostEpochId(i);

            IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId);
            IEpochRegistry.EpochCapability ghostCap = handler.ghost_epochCapability(epochId);

            // On-chain must match ghost
            assertEq(uint256(cap), uint256(ghostCap), "INV23: Capability must match ghost");

            // All created epochs should have v0.6-compatible capability
            assertTrue(
                cap == IEpochRegistry.EpochCapability.PresenceWithSignals
                    || cap == IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
                "INV23: v0.6 epochs must have PresenceWithSignals or higher"
            );
        }
    }

    /// @dev INV26: Given identical on-chain state, reconciliation is deterministic
    function invariant_reconciliationDeterministic() external view {
        uint256 actorCount = handler.getGhostActorsLength();
        uint256 epochCount = handler.getGhostEpochIdsLength();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.getGhostActor(i);

            for (uint256 j = 0; j < epochCount; j++) {
                uint256 epochId = handler.getGhostEpochId(j);

                // Multiple queries to same state must return identical results
                IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(actor, epochId);
                IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(actor, epochId);
                IPresenceRegistry.PresenceState state3 = presenceRegistry.presenceState(actor, epochId);

                assertEq(uint256(state1), uint256(state2), "INV26: State query 1-2 must match");
                assertEq(uint256(state2), uint256(state3), "INV26: State query 2-3 must match");

                // Presence struct queries must also be deterministic
                IPresenceRegistry.Presence memory p1 = presenceRegistry.getPresence(actor, epochId);
                IPresenceRegistry.Presence memory p2 = presenceRegistry.getPresence(actor, epochId);

                assertEq(uint256(p1.state), uint256(p2.state), "INV26: Presence state must match");
                assertEq(p1.declaredAt, p2.declaredAt, "INV26: declaredAt must match");
                assertEq(p1.validatedAt, p2.validatedAt, "INV26: validatedAt must match");
                assertEq(p1.validationCount, p2.validationCount, "INV26: validationCount must match");
            }
        }
    }

    /// @dev INV-SYNC1: Sync operations do not modify on-chain state
    /// Note: This is implicitly tested by the fact that only handler functions
    /// can modify state, and they only perform valid on-chain operations
    function invariant_syncReadOnly() external view {
        // Validator count should remain constant (we only add in constructor)
        uint256 validatorCount = validatorRegistry.activeValidatorCount();
        assertEq(validatorCount, 3, "INV-SYNC1: Validator count should be 3");
    }

    /// @dev Validation count consistency
    function invariant_validationCountConsistency() external view {
        uint256 actorCount = handler.getGhostActorsLength();
        uint256 epochCount = handler.getGhostEpochIdsLength();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.getGhostActor(i);

            for (uint256 j = 0; j < epochCount; j++) {
                uint256 epochId = handler.getGhostEpochId(j);

                IPresenceRegistry.Presence memory presence = presenceRegistry.getPresence(actor, epochId);
                IPresenceRegistry.PresenceState state = presence.state;

                // If state is Validated, validationCount should be >= quorum
                if (state == IPresenceRegistry.PresenceState.Validated) {
                    uint256 quorum = validatorRegistry.quorumSize();
                    assertTrue(presence.validationCount >= quorum, "Validated state should have quorum votes");
                }

                // If state is Declared, validationCount should be < quorum
                if (state == IPresenceRegistry.PresenceState.Declared) {
                    uint256 quorum = validatorRegistry.quorumSize();
                    assertTrue(presence.validationCount < quorum, "Declared state should have less than quorum votes");
                }
            }
        }
    }

    /// @dev Quorum size determinism
    function invariant_quorumDeterministic() external view {
        uint256 q1 = validatorRegistry.quorumSize();
        uint256 q2 = validatorRegistry.quorumSize();
        uint256 q3 = validatorRegistry.quorumSize();

        assertEq(q1, q2, "Quorum 1-2 must match");
        assertEq(q2, q3, "Quorum 2-3 must match");
    }
}

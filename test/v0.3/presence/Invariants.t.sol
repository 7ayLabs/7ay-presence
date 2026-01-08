// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title PresenceRegistryHandler
 * @notice Handler contract for Foundry invariant testing
 * @dev Spec: specs/v0.3/presence.md
 */
contract PresenceRegistryHandler is Test {
    IPresenceRegistry public registry;
    IEpochRegistry public epochRegistry;
    address public constant AUTHORITY = address(0xA077);

    mapping(address => mapping(uint256 => bool)) public ghost_declared;
    mapping(address => mapping(uint256 => bool)) public ghost_finalized;
    address[] public ghost_actors;
    uint256[] public ghost_epochs;

    address[] internal boundedActors;
    uint256[] internal boundedEpochs;

    constructor(IPresenceRegistry _registry, IEpochRegistry _epochRegistry) {
        registry = _registry;
        epochRegistry = _epochRegistry;

        boundedActors.push(address(0xA11CE));
        boundedActors.push(address(0xB0B));
        boundedActors.push(address(0xCAFE));

        boundedEpochs.push(1);
        boundedEpochs.push(2);
        boundedEpochs.push(3);
    }

    function declarePresence(uint256 actorSeed, uint256 epochSeed) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        bool wasDeclared = ghost_declared[actor][epochId];
        bool wasFinalized = ghost_finalized[actor][epochId];

        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        if (!wasDeclared && !wasFinalized) {
            ghost_declared[actor][epochId] = true;
            ghost_actors.push(actor);
            ghost_epochs.push(epochId);
        }
    }

    function finalizePresence(uint256 actorSeed, uint256 epochSeed) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        bool wasDeclared = ghost_declared[actor][epochId];
        bool wasFinalized = ghost_finalized[actor][epochId];

        vm.prank(actor);
        registry.finalizePresence(actor, epochId);

        if (!wasFinalized) {
            ghost_finalized[actor][epochId] = true;
            if (!wasDeclared) {
                ghost_actors.push(actor);
                ghost_epochs.push(epochId);
            }
        }
    }

    function finalizePresenceUnauthorized(uint256 callerSeed, uint256 actorSeed, uint256 epochSeed) external {
        address caller = boundedActors[callerSeed % boundedActors.length];
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        if (caller == actor) return;

        vm.prank(caller);
        vm.expectRevert();
        registry.finalizePresence(actor, epochId);
    }

    function getGhostActorsLength() external view returns (uint256) {
        return ghost_actors.length;
    }

    function getGhostActor(uint256 index) external view returns (address) {
        return ghost_actors[index];
    }

    function getGhostEpoch(uint256 index) external view returns (uint256) {
        return ghost_epochs[index];
    }
}

/**
 * @title PresenceRegistryInvariants
 * @notice Protocol invariants for presence lifecycle
 * @dev Spec: specs/v0.3/presence.md
 */
contract PresenceRegistryInvariants is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    PresenceRegistryHandler internal handler;
    address internal constant AUTHORITY = address(0xA077);

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry)));

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1 days;
        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(1, start, end);
        epochRegistry.createEpoch(2, start, end);
        epochRegistry.createEpoch(3, start, end);
        vm.stopPrank();

        handler = new PresenceRegistryHandler(registry, epochRegistry);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PresenceRegistryHandler.declarePresence.selector;
        selectors[1] = PresenceRegistryHandler.finalizePresence.selector;
        selectors[2] = PresenceRegistryHandler.finalizePresenceUnauthorized.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV1: Valid state space {None, Declared, Finalized}
    function invariant_validStateSpace() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.PresenceState state = registry.presenceState(actor, epochId);

            assertTrue(
                state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Declared
                    || state == IPresenceRegistry.PresenceState.Finalized,
                "INV1: Invalid state"
            );
        }
    }

    /// @dev INV2: Declared = monotonic (cannot revert to None)
    function invariant_declarationMonotonicity() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            if (handler.ghost_declared(actor, epochId)) {
                IPresenceRegistry.PresenceState state = registry.presenceState(actor, epochId);
                assertTrue(
                    state == IPresenceRegistry.PresenceState.Declared
                        || state == IPresenceRegistry.PresenceState.Finalized,
                    "INV2: Declared reverted to None"
                );
            }
        }
    }

    /// @dev INV3: Finalized = immutable
    function invariant_finalizationMonotonicity() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            if (handler.ghost_finalized(actor, epochId)) {
                assertEq(
                    uint256(registry.presenceState(actor, epochId)),
                    uint256(IPresenceRegistry.PresenceState.Finalized),
                    "INV3: Finalized reverted"
                );
            }
        }
    }

    /// @dev INV4: Actor isolation
    function invariant_actorIsolation() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            bool ghostFinalized = handler.ghost_finalized(actor, epochId);
            IPresenceRegistry.PresenceState onChainState = registry.presenceState(actor, epochId);

            if (ghostFinalized) {
                assertEq(uint256(onChainState), uint256(IPresenceRegistry.PresenceState.Finalized), "INV4: Mismatch");
            }
        }
    }

    /// @dev INV5: Epoch isolation
    function invariant_epochIsolation() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            uint256 adjacentEpoch = epochId == type(uint256).max ? epochId - 1 : epochId + 1;

            if (!handler.ghost_finalized(actor, adjacentEpoch) && !handler.ghost_declared(actor, adjacentEpoch)) {
                assertEq(
                    uint256(registry.presenceState(actor, adjacentEpoch)),
                    uint256(IPresenceRegistry.PresenceState.None),
                    "INV5: Adjacent affected"
                );
            }
        }
    }

    /// @dev INV6: Ghost consistency (declared and finalized tracking)
    function invariant_ghostConsistency() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            bool ghostDeclared = handler.ghost_declared(actor, epochId);
            bool ghostFinalized = handler.ghost_finalized(actor, epochId);
            IPresenceRegistry.PresenceState onChainState = registry.presenceState(actor, epochId);

            if (ghostFinalized) {
                assertEq(
                    uint256(onChainState), uint256(IPresenceRegistry.PresenceState.Finalized), "INV6: Finalized desync"
                );
            } else if (ghostDeclared) {
                assertTrue(
                    onChainState == IPresenceRegistry.PresenceState.Declared
                        || onChainState == IPresenceRegistry.PresenceState.Finalized,
                    "INV6: Declared desync"
                );
            }
        }
    }
}

/**
 * @title PresenceRegistryPropertyTests
 * @notice Deterministic property tests
 */
contract PresenceRegistryPropertyTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    address internal constant AUTHORITY = address(0xA077);

    address internal constant ACTOR = address(0xA11CE);
    address internal constant ATTACKER = address(0xBEEF);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry)));

        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(1, block.timestamp, block.timestamp + 1 days);
        epochRegistry.createEpoch(2, block.timestamp, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function test_singleFinalizedPresencePerEpoch() external {
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));

        IPresenceRegistry.PresenceState state = registry.presenceState(ACTOR, EPOCH_ID);
        assertTrue(
            state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Declared
                || state == IPresenceRegistry.PresenceState.Finalized
        );
    }

    function test_finalizedPresenceIsImmutable() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateBefore = registry.presenceState(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateAfter = registry.presenceState(ACTOR, EPOCH_ID);

        assertEq(uint256(stateBefore), uint256(stateAfter));
        assertEq(uint256(stateAfter), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_deterministicFinalization() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state1 = registry.presenceState(ACTOR, EPOCH_ID);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state2 = registry.presenceState(ACTOR, EPOCH_ID);

        assertEq(uint256(state1), uint256(state2));
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_onlyActorCanFinalizePresence() external {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, ATTACKER, ACTOR));
        registry.finalizePresence(ACTOR, EPOCH_ID);
    }

    function test_actorIsolation() external {
        address actor2 = address(0xB0B);

        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(actor2, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));
    }

    function test_epochIsolation() external {
        vm.prank(ACTOR);
        registry.finalizePresence(ACTOR, 1);

        assertEq(uint256(registry.presenceState(ACTOR, 1)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(ACTOR, 2)), uint256(IPresenceRegistry.PresenceState.None));
    }
}

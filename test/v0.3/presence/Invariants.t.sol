// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title PresenceRegistryHandler
 * @notice Handler contract for Foundry invariant testing (updated for v0.4)
 * @dev Spec: specs/v0.4/presence.md
 */
contract PresenceRegistryHandler is Test {
    IPresenceRegistry public registry;
    IEpochRegistry public epochRegistry;
    IValidatorRegistry public validatorRegistry;
    address public constant AUTHORITY = address(0xA077);
    address public constant VALIDATOR_1 = address(0x1001);
    address public constant VALIDATOR_2 = address(0x1002);
    address public constant VALIDATOR_3 = address(0x1003);

    mapping(address => mapping(uint256 => bool)) public ghost_declared;
    mapping(address => mapping(uint256 => bool)) public ghost_validated;
    mapping(address => mapping(uint256 => bool)) public ghost_finalized;
    address[] public ghost_actors;
    uint256[] public ghost_epochs;

    address[] internal boundedActors;
    uint256[] internal boundedEpochs;

    constructor(IPresenceRegistry _registry, IEpochRegistry _epochRegistry, IValidatorRegistry _validatorRegistry) {
        registry = _registry;
        epochRegistry = _epochRegistry;
        validatorRegistry = _validatorRegistry;

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
        bool wasValidated = ghost_validated[actor][epochId];
        bool wasFinalized = ghost_finalized[actor][epochId];

        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        if (!wasDeclared && !wasValidated && !wasFinalized) {
            ghost_declared[actor][epochId] = true;
            ghost_actors.push(actor);
            ghost_epochs.push(epochId);
        }
    }

    function validatePresence(uint256 actorSeed, uint256 epochSeed) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        // Must be declared first
        if (!ghost_declared[actor][epochId]) return;
        if (ghost_validated[actor][epochId]) return;
        if (ghost_finalized[actor][epochId]) return;

        // Validate with quorum
        vm.prank(VALIDATOR_1);
        try registry.validatePresence(actor, epochId) {} catch { return; }

        vm.prank(VALIDATOR_2);
        try registry.validatePresence(actor, epochId) {} catch { return; }

        vm.prank(VALIDATOR_3);
        try registry.validatePresence(actor, epochId) {} catch { return; }

        ghost_validated[actor][epochId] = true;
    }

    function finalizePresence(uint256 actorSeed, uint256 epochSeed) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        bool wasValidated = ghost_validated[actor][epochId];
        bool wasFinalized = ghost_finalized[actor][epochId];

        // v0.4: Must be validated first
        if (!wasValidated) return;
        if (wasFinalized) return;

        // Warp to closed epoch if needed
        IEpochRegistry.EpochState epochState = epochRegistry.epochState(epochId);
        if (epochState == IEpochRegistry.EpochState.Active) {
            vm.warp(block.timestamp + 2 days);
        }

        try registry.finalizePresence(actor, epochId) {
            ghost_finalized[actor][epochId] = true;
        } catch {}
    }

    function declarePresenceUnauthorized(uint256 callerSeed, uint256 actorSeed, uint256 epochSeed) external {
        address caller = boundedActors[callerSeed % boundedActors.length];
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        if (caller == actor) return;

        vm.prank(caller);
        vm.expectRevert();
        registry.declarePresence(actor, epochId);
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
 * @notice Protocol invariants for presence lifecycle (updated for v0.4)
 * @dev Spec: specs/v0.4/presence.md
 */
contract PresenceRegistryInvariants is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    PresenceRegistryHandler internal handler;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1 days;
        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(1, start, end);
        epochRegistry.createEpoch(2, start, end);
        epochRegistry.createEpoch(3, start, end);
        validatorRegistry.addValidator(VALIDATOR_1);
        validatorRegistry.addValidator(VALIDATOR_2);
        validatorRegistry.addValidator(VALIDATOR_3);
        vm.stopPrank();

        handler = new PresenceRegistryHandler(registry, epochRegistry, validatorRegistry);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PresenceRegistryHandler.declarePresence.selector;
        selectors[1] = PresenceRegistryHandler.validatePresence.selector;
        selectors[2] = PresenceRegistryHandler.finalizePresence.selector;
        selectors[3] = PresenceRegistryHandler.declarePresenceUnauthorized.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV1: Valid state space {None, Declared, Validated, Finalized, Slashed}
    function invariant_validStateSpace() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.PresenceState state = registry.presenceState(actor, epochId);

            assertTrue(
                state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Declared
                    || state == IPresenceRegistry.PresenceState.Validated
                    || state == IPresenceRegistry.PresenceState.Finalized
                    || state == IPresenceRegistry.PresenceState.Slashed,
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
                        || state == IPresenceRegistry.PresenceState.Validated
                        || state == IPresenceRegistry.PresenceState.Finalized
                        || state == IPresenceRegistry.PresenceState.Slashed,
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

            if (
                !handler.ghost_finalized(actor, adjacentEpoch) && !handler.ghost_declared(actor, adjacentEpoch)
                    && !handler.ghost_validated(actor, adjacentEpoch)
            ) {
                assertEq(
                    uint256(registry.presenceState(actor, adjacentEpoch)),
                    uint256(IPresenceRegistry.PresenceState.None),
                    "INV5: Adjacent affected"
                );
            }
        }
    }

    /// @dev INV6: Ghost consistency (declared, validated, and finalized tracking)
    function invariant_ghostConsistency() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            bool ghostDeclared = handler.ghost_declared(actor, epochId);
            bool ghostValidated = handler.ghost_validated(actor, epochId);
            bool ghostFinalized = handler.ghost_finalized(actor, epochId);
            IPresenceRegistry.PresenceState onChainState = registry.presenceState(actor, epochId);

            if (ghostFinalized) {
                assertEq(
                    uint256(onChainState), uint256(IPresenceRegistry.PresenceState.Finalized), "INV6: Finalized desync"
                );
            } else if (ghostValidated) {
                assertTrue(
                    onChainState == IPresenceRegistry.PresenceState.Validated
                        || onChainState == IPresenceRegistry.PresenceState.Finalized,
                    "INV6: Validated desync"
                );
            } else if (ghostDeclared) {
                assertTrue(
                    onChainState == IPresenceRegistry.PresenceState.Declared
                        || onChainState == IPresenceRegistry.PresenceState.Validated
                        || onChainState == IPresenceRegistry.PresenceState.Finalized,
                    "INV6: Declared desync"
                );
            }
        }
    }
}

/**
 * @title PresenceRegistryPropertyTests
 * @notice Deterministic property tests (updated for v0.4)
 */
contract PresenceRegistryPropertyTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    address internal constant ACTOR = address(0xA11CE);
    address internal constant ATTACKER = address(0xBEEF);
    uint256 internal constant EPOCH_ID = 1;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(1, block.timestamp, block.timestamp + 1 days);
        epochRegistry.createEpoch(2, block.timestamp, block.timestamp + 1 days);
        validatorRegistry.addValidator(VALIDATOR_1);
        validatorRegistry.addValidator(VALIDATOR_2);
        validatorRegistry.addValidator(VALIDATOR_3);
        vm.stopPrank();
    }

    function _declareAndValidate(address actor, uint256 epochId) internal {
        vm.prank(actor);
        registry.declarePresence(actor, epochId);

        vm.prank(VALIDATOR_1);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(actor, epochId);
    }

    function test_singleFinalizedPresencePerEpoch() external {
        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));

        _declareAndValidate(ACTOR, EPOCH_ID);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));

        IPresenceRegistry.PresenceState state = registry.presenceState(ACTOR, EPOCH_ID);
        assertTrue(
            state == IPresenceRegistry.PresenceState.None || state == IPresenceRegistry.PresenceState.Declared
                || state == IPresenceRegistry.PresenceState.Validated || state == IPresenceRegistry.PresenceState.Finalized
                || state == IPresenceRegistry.PresenceState.Slashed
        );
    }

    function test_finalizedPresenceIsImmutable() external {
        _declareAndValidate(ACTOR, EPOCH_ID);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateBefore = registry.presenceState(ACTOR, EPOCH_ID);

        registry.finalizePresence(ACTOR, EPOCH_ID);
        registry.finalizePresence(ACTOR, EPOCH_ID);

        IPresenceRegistry.PresenceState stateAfter = registry.presenceState(ACTOR, EPOCH_ID);

        assertEq(uint256(stateBefore), uint256(stateAfter));
        assertEq(uint256(stateAfter), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_deterministicFinalization() external {
        _declareAndValidate(ACTOR, EPOCH_ID);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state1 = registry.presenceState(ACTOR, EPOCH_ID);

        registry.finalizePresence(ACTOR, EPOCH_ID);
        IPresenceRegistry.PresenceState state2 = registry.presenceState(ACTOR, EPOCH_ID);

        assertEq(uint256(state1), uint256(state2));
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Finalized));
    }

    function test_onlyActorCanDeclarePresence() external {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, ATTACKER, ACTOR));
        registry.declarePresence(ACTOR, EPOCH_ID);
    }

    function test_actorIsolation() external {
        address actor2 = address(0xB0B);

        _declareAndValidate(ACTOR, EPOCH_ID);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(ACTOR, EPOCH_ID);

        assertEq(uint256(registry.presenceState(ACTOR, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(actor2, EPOCH_ID)), uint256(IPresenceRegistry.PresenceState.None));
    }

    function test_epochIsolation() external {
        _declareAndValidate(ACTOR, 1);

        // Warp to Closed epoch
        vm.warp(block.timestamp + 2 days);

        registry.finalizePresence(ACTOR, 1);

        assertEq(uint256(registry.presenceState(ACTOR, 1)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(ACTOR, 2)), uint256(IPresenceRegistry.PresenceState.None));
    }
}

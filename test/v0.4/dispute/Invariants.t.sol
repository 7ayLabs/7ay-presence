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
 * @title DisputeHandler
 * @notice Handler contract for dispute invariant testing
 * @dev Spec: specs/v0.4/presence.md
 */
contract DisputeHandler is Test {
    IPresenceRegistry public registry;
    IEpochRegistry public epochRegistry;
    IValidatorRegistry public validatorRegistry;

    address public constant AUTHORITY = address(0xA077);
    address public constant VALIDATOR_1 = address(0x1001);
    address public constant VALIDATOR_2 = address(0x1002);
    address public constant VALIDATOR_3 = address(0x1003);
    address public constant CHALLENGER = address(0xC4A1);

    // Ghost state
    mapping(address => mapping(uint256 => bool)) public ghost_disputed;
    mapping(address => mapping(uint256 => bool)) public ghost_slashed;
    mapping(address => mapping(uint256 => IPresenceRegistry.DisputeStatus)) public ghost_disputeStatus;
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

        if (ghost_slashed[actor][epochId]) return;

        vm.prank(actor);
        try registry.declarePresence(actor, epochId) {
            _trackActor(actor, epochId);
        } catch {}
    }

    function initiateDispute(uint256 actorSeed, uint256 epochSeed, bytes32 evidenceHash) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        if (ghost_disputed[actor][epochId]) return;
        if (ghost_slashed[actor][epochId]) return;

        vm.prank(CHALLENGER);
        try registry.initiateDispute(actor, epochId, evidenceHash) {
            ghost_disputed[actor][epochId] = true;
            ghost_disputeStatus[actor][epochId] = IPresenceRegistry.DisputeStatus.Pending;
            _trackActor(actor, epochId);
        } catch {}
    }

    function voteAndResolve(uint256 actorSeed, uint256 epochSeed, bool upholdVote) external {
        address actor = boundedActors[actorSeed % boundedActors.length];
        uint256 epochId = boundedEpochs[epochSeed % boundedEpochs.length];

        if (!ghost_disputed[actor][epochId]) return;
        if (ghost_disputeStatus[actor][epochId] != IPresenceRegistry.DisputeStatus.Pending) return;

        // All validators vote the same way for simplicity
        vm.prank(VALIDATOR_1);
        try registry.voteOnDispute(actor, epochId, upholdVote) {} catch {}

        vm.prank(VALIDATOR_2);
        try registry.voteOnDispute(actor, epochId, upholdVote) {} catch {}

        vm.prank(VALIDATOR_3);
        try registry.voteOnDispute(actor, epochId, upholdVote) {} catch {}

        try registry.resolveDispute(actor, epochId) {
            if (upholdVote) {
                ghost_disputeStatus[actor][epochId] = IPresenceRegistry.DisputeStatus.Upheld;
                ghost_slashed[actor][epochId] = true;
            } else {
                ghost_disputeStatus[actor][epochId] = IPresenceRegistry.DisputeStatus.Rejected;
            }
        } catch {}
    }

    function _trackActor(address actor, uint256 epochId) internal {
        bool found = false;
        for (uint256 i = 0; i < ghost_actors.length; i++) {
            if (ghost_actors[i] == actor && ghost_epochs[i] == epochId) {
                found = true;
                break;
            }
        }
        if (!found) {
            ghost_actors.push(actor);
            ghost_epochs.push(epochId);
        }
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
 * @title DisputeInvariants
 * @notice Protocol invariants for dispute mechanism
 * @dev Spec: specs/v0.4/presence.md
 */
contract DisputeInvariants is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    DisputeHandler internal handler;

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

        handler = new DisputeHandler(registry, epochRegistry, validatorRegistry);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = DisputeHandler.declarePresence.selector;
        selectors[1] = DisputeHandler.initiateDispute.selector;
        selectors[2] = DisputeHandler.voteAndResolve.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev INV1: Slashed = terminal (cannot change)
    function invariant_slashedIsTerminal() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            if (handler.ghost_slashed(actor, epochId)) {
                assertEq(
                    uint256(registry.presenceState(actor, epochId)),
                    uint256(IPresenceRegistry.PresenceState.Slashed),
                    "INV1: Slashed state reverted"
                );
            }
        }
    }

    /// @dev INV2: Dispute status consistency
    function invariant_disputeStatusConsistency() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.DisputeStatus ghostStatus = handler.ghost_disputeStatus(actor, epochId);
            IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, epochId);

            if (ghostStatus == IPresenceRegistry.DisputeStatus.Upheld) {
                assertEq(
                    uint256(dispute.status),
                    uint256(IPresenceRegistry.DisputeStatus.Upheld),
                    "INV2: Upheld desync"
                );
            } else if (ghostStatus == IPresenceRegistry.DisputeStatus.Rejected) {
                assertEq(
                    uint256(dispute.status),
                    uint256(IPresenceRegistry.DisputeStatus.Rejected),
                    "INV2: Rejected desync"
                );
            }
        }
    }

    /// @dev INV3: Upheld dispute implies slashed presence
    function invariant_upheldImpliesSlashed() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, epochId);

            if (dispute.status == IPresenceRegistry.DisputeStatus.Upheld) {
                assertEq(
                    uint256(registry.presenceState(actor, epochId)),
                    uint256(IPresenceRegistry.PresenceState.Slashed),
                    "INV3: Upheld but not slashed"
                );
            }
        }
    }

    /// @dev INV4: Valid dispute status space
    function invariant_validDisputeStatusSpace() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, epochId);

            assertTrue(
                dispute.status == IPresenceRegistry.DisputeStatus.None
                    || dispute.status == IPresenceRegistry.DisputeStatus.Pending
                    || dispute.status == IPresenceRegistry.DisputeStatus.Upheld
                    || dispute.status == IPresenceRegistry.DisputeStatus.Rejected,
                "INV4: Invalid dispute status"
            );
        }
    }

    /// @dev INV5: Rejected dispute preserves presence state
    function invariant_rejectedPreservesPresence() external view {
        uint256 len = handler.getGhostActorsLength();
        for (uint256 i = 0; i < len; i++) {
            address actor = handler.getGhostActor(i);
            uint256 epochId = handler.getGhostEpoch(i);

            IPresenceRegistry.Dispute memory dispute = registry.getDispute(actor, epochId);

            if (dispute.status == IPresenceRegistry.DisputeStatus.Rejected) {
                IPresenceRegistry.PresenceState state = registry.presenceState(actor, epochId);
                assertTrue(
                    state == IPresenceRegistry.PresenceState.Declared
                        || state == IPresenceRegistry.PresenceState.Validated,
                    "INV5: Rejected changed presence to invalid state"
                );
            }
        }
    }
}

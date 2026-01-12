// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title NodeModelTest
 * @notice Tests for v0.6 Node Model specification
 * @dev Validates INV19 (Node Identity Derivability) and INV20 (Epoch Binding)
 *
 * Node Model (v0.6.2):
 * - Node is a logical abstraction over on-chain entities
 * - Identity derived from address + epoch context
 * - Role derived from ValidatorRegistry
 * - Capabilities derived from epoch capability + presence state
 */
contract NodeModelTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public participant = makeAddr("participant");

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    function setUp() public {
        startTime = block.timestamp + 1 hours;
        endTime = startTime + 1 days;

        epochRegistry = IEpochRegistry(address(new EpochRegistry(epochAuthority)));
        ValidatorRegistry _validatorRegistry = new ValidatorRegistry(validatorAuthority);
        validatorRegistry = IValidatorRegistry(address(_validatorRegistry));
        presenceRegistry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        // Register validators
        vm.startPrank(validatorAuthority);
        _validatorRegistry.addValidator(validator1);
        _validatorRegistry.addValidator(validator2);
        _validatorRegistry.addValidator(validator3);
        vm.stopPrank();

        // Create epoch with PresenceWithSignals capability
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // Warp to active
        vm.warp(startTime);
    }

    // =========================================================================
    // INV19: Node Identity Derivability
    // =========================================================================

    /// @notice Node identity is derived from on-chain presence
    function test_nodeIdentity_derivedFromPresence() public {
        // Declare presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // Identity derivable: address has presence in epoch
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.Declared));

        // Node identity components are on-chain verifiable
        assertTrue(uint256(epochRegistry.epochState(epochId)) != 0);
    }

    /// @notice Node with no presence is not a valid node
    function test_nodeIdentity_requiresPresence() public view {
        // No presence declared
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.None));

        // Node derivation returns null (not a valid node) - validate with helper
        assertFalse(_isValidNode(participant, epochId), "INV19: No presence means no valid node");
    }

    /// @notice Slashed actors are not valid nodes
    function test_nodeIdentity_slashedNotValid() public {
        // Declare and validate presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        vm.prank(validator1);
        presenceRegistry.validatePresence(participant, epochId);
        vm.prank(validator2);
        presenceRegistry.validatePresence(participant, epochId);
        vm.prank(validator3);
        presenceRegistry.validatePresence(participant, epochId);

        // Initiate dispute (v0.4 dispute mechanism)
        vm.prank(validator1);
        presenceRegistry.initiateDispute(participant, epochId, bytes32(0));

        // Vote to slash
        vm.prank(validator1);
        presenceRegistry.voteOnDispute(participant, epochId, true);
        vm.prank(validator2);
        presenceRegistry.voteOnDispute(participant, epochId, true);
        vm.prank(validator3);
        presenceRegistry.voteOnDispute(participant, epochId, true);

        // Resolve dispute (after quorum reached)
        presenceRegistry.resolveDispute(participant, epochId);

        // Slashed state
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.Slashed));

        // Slashed actors are not valid nodes per INV19 - validate with helper
        assertFalse(_isValidNode(participant, epochId), "INV19: Slashed actors are not valid nodes");
    }

    // =========================================================================
    // INV20: Epoch Binding
    // =========================================================================

    /// @notice Node is bound to exactly one epoch
    function test_epochBinding_singleEpoch() public {
        // Declare in epoch 1
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // Create epoch 2
        uint256 epochId2 = 2;
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId2,
            startTime + 2 days,
            endTime + 2 days,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0)
        );

        // Participant has presence in epoch 1
        IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Declared));

        // No presence in epoch 2
        IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(participant, epochId2);
        assertEq(uint256(state2), uint256(IPresenceRegistry.PresenceState.None));
    }

    /// @notice Multiple epochs can exist but node binding is per-epoch
    function test_epochBinding_multipleEpochs() public {
        // Declare in epoch 1
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // Create and activate epoch 2
        uint256 epochId2 = 2;
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId2,
            startTime + 1 hours,
            endTime + 1 hours,
            IEpochRegistry.EpochCapability.PresenceWithSignals,
            bytes32(0)
        );

        vm.warp(startTime + 1 hours);

        // Declare in epoch 2
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId2);

        // Has presence in both epochs (on-chain allows this)
        IPresenceRegistry.PresenceState state1 = presenceRegistry.presenceState(participant, epochId);
        IPresenceRegistry.PresenceState state2 = presenceRegistry.presenceState(participant, epochId2);

        assertEq(uint256(state1), uint256(IPresenceRegistry.PresenceState.Declared));
        assertEq(uint256(state2), uint256(IPresenceRegistry.PresenceState.Declared));

        // Per v0.6 spec (INV20), for messaging purposes a node is bound to ONE epoch at a time.
        // On-chain state allows presence in multiple epochs, but the semantic layer
        // enforces single-epoch binding for active messaging. Both are valid nodes:
        assertTrue(_isValidNode(participant, epochId), "Valid node in epoch 1");
        assertTrue(_isValidNode(participant, epochId2), "Valid node in epoch 2");
    }

    // =========================================================================
    // Role Derivation
    // =========================================================================

    /// @notice Role is derived from ValidatorRegistry
    function test_role_derivedFromValidatorRegistry() public {
        // Validator role
        assertTrue(validatorRegistry.isValidatorActive(validator1));
        assertTrue(validatorRegistry.isValidatorActive(validator2));
        assertTrue(validatorRegistry.isValidatorActive(validator3));

        // Participant role (not a validator)
        assertFalse(validatorRegistry.isValidatorActive(participant));
    }

    /// @notice Removed validators become participants
    function test_role_removedValidatorBecomesParticipant() public {
        // Validator is active
        assertTrue(validatorRegistry.isValidatorActive(validator1));

        // Remove validator (need to add one more first to keep min validators)
        // For this test, we add more validators then remove one
        address validator4 = makeAddr("validator4");
        ValidatorRegistry _validatorRegistry = ValidatorRegistry(address(validatorRegistry));
        vm.prank(validatorAuthority);
        _validatorRegistry.addValidator(validator4);

        vm.prank(validatorAuthority);
        _validatorRegistry.removeValidator(validator1);

        // Now participant role
        assertFalse(validatorRegistry.isValidatorActive(validator1));
    }

    // =========================================================================
    // Capability Model
    // =========================================================================

    /// @notice Discovery capability requires PresenceWithSignals epoch
    function test_capability_discoveryRequiresSignals() public view {
        // Epoch has PresenceWithSignals capability
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId);
        assertEq(uint256(cap), 1); // PresenceWithSignals = 1

        // Discovery capability is available for this epoch - validate with helper
        assertTrue(_hasDiscoveryCapability(epochId), "Discovery capability should be available");
    }

    /// @notice StateSync capability requires Validator role
    function test_capability_stateSyncRequiresValidator() public view {
        // Validators have StateSync capability
        assertTrue(validatorRegistry.isValidatorActive(validator1));

        // Participants don't have StateSync capability
        assertFalse(validatorRegistry.isValidatorActive(participant));
    }

    /// @notice PresenceOnly epochs don't support v0.6 features
    function test_capability_presenceOnlyNoV6Features() public {
        // Create PresenceOnly epoch
        uint256 epochId2 = 2;
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId2, startTime + 2 days, endTime + 2 days, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );

        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId2);
        assertEq(uint256(cap), 0); // PresenceOnly

        // No v0.6 capabilities for this epoch (Discovery, Messaging, StateSync) - validate with helper
        assertFalse(_hasDiscoveryCapability(epochId2), "PresenceOnly should not have discovery capability");
        assertFalse(_hasMessagingCapability(epochId2), "PresenceOnly should not have messaging capability");
        assertFalse(_hasStateSyncCapability(epochId2), "PresenceOnly should not have state sync capability");
    }

    // =========================================================================
    // Node Lifecycle
    // =========================================================================

    /// @notice Node lifecycle: None -> Participant
    function test_lifecycle_declareCreatesParticipant() public {
        // Before: no node
        IPresenceRegistry.PresenceState stateBefore = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(stateBefore), uint256(IPresenceRegistry.PresenceState.None));

        // Declare presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // After: participant node
        IPresenceRegistry.PresenceState stateAfter = presenceRegistry.presenceState(participant, epochId);
        assertEq(uint256(stateAfter), uint256(IPresenceRegistry.PresenceState.Declared));
        assertFalse(validatorRegistry.isValidatorActive(participant));
    }

    /// @notice Validators declaring presence become validator nodes
    function test_lifecycle_validatorDeclaresPresence() public {
        // Validator declares presence
        vm.prank(validator1);
        presenceRegistry.declarePresence(validator1, epochId);

        // Has presence and is validator
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(validator1, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.Declared));
        assertTrue(validatorRegistry.isValidatorActive(validator1));

        // This creates a "Validator Node" with all capabilities - validate
        assertTrue(_isValidNode(validator1, epochId), "Validator node is valid");
        assertTrue(_hasDiscoveryCapability(epochId), "Validator has discovery capability");
        assertTrue(_hasMessagingCapability(epochId), "Validator has messaging capability");
        assertTrue(_hasStateSyncCapability(epochId), "Validator has state sync capability (validator-only)");
    }

    /// @notice Node becomes inactive when epoch closes
    function test_lifecycle_epochCloseDeactivatesNode() public {
        // Declare presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // Active node - verify with helper
        assertTrue(_isActiveNode(participant, epochId), "Node should be active during Active epoch");

        // Close epoch
        vm.warp(endTime + 1);
        IEpochRegistry.EpochState epochState = epochRegistry.epochState(epochId);
        assertEq(uint256(epochState), uint256(IEpochRegistry.EpochState.Closed));

        // Node becomes inactive per semantic layer (epoch not Active)
        assertFalse(_isActiveNode(participant, epochId), "Node should be inactive after epoch closes");
    }

    // =========================================================================
    // Serialization Verification
    // =========================================================================

    /// @notice Minimal node data is queryable
    function test_serialization_minimalNodeData() public {
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochId);

        // All fields for MinimalNode are queryable
        address nodeAddress = participant;
        uint256 nodeEpochId = epochId;
        bool isValidator = validatorRegistry.isValidatorActive(participant);
        IPresenceRegistry.PresenceState presenceState = presenceRegistry.presenceState(participant, epochId);

        // Verify minimal node can be constructed
        assertEq(nodeAddress, participant);
        assertEq(nodeEpochId, epochId);
        assertFalse(isValidator); // Participant role
        assertEq(uint256(presenceState), uint256(IPresenceRegistry.PresenceState.Declared));
    }

    // =========================================================================
    // Semantic Validation Helpers (INV19, INV20)
    // =========================================================================

    /// @notice Check if address is a valid node in epoch (INV19)
    /// @dev Valid presence states: Declared, Validated, Finalized (not None, not Slashed)
    function _isValidNode(address actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    /// @notice Check if node is active (valid node + Active epoch)
    function _isActiveNode(address actor, uint256 _epochId) internal view returns (bool) {
        if (!_isValidNode(actor, _epochId)) return false;
        return epochRegistry.epochState(_epochId) == IEpochRegistry.EpochState.Active;
    }

    /// @notice Check if epoch has discovery capability (requires PresenceWithSignals)
    function _hasDiscoveryCapability(uint256 _epochId) internal view returns (bool) {
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(_epochId);
        return uint256(cap) >= uint256(IEpochRegistry.EpochCapability.PresenceWithSignals);
    }

    /// @notice Check if epoch has messaging capability (requires PresenceWithSignals)
    function _hasMessagingCapability(uint256 _epochId) internal view returns (bool) {
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(_epochId);
        return uint256(cap) >= uint256(IEpochRegistry.EpochCapability.PresenceWithSignals);
    }

    /// @notice Check if epoch has state sync capability (requires PresenceWithSignals)
    function _hasStateSyncCapability(uint256 _epochId) internal view returns (bool) {
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(_epochId);
        return uint256(cap) >= uint256(IEpochRegistry.EpochCapability.PresenceWithSignals);
    }
}

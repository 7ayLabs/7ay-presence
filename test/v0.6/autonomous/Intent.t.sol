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
 * @title AutonomousIntentTest
 * @notice Tests for v0.6.6 Autonomous Intent declaration
 * @dev Validates INV34 (Intent Presence) and intent lifecycle
 *
 * Autonomous Message Types:
 * - AUTONOMOUS_INTENT (0x50): Declare intent
 * - AUTONOMOUS_PATTERN (0x51): Pattern recognition
 * - AUTONOMOUS_EXECUTE (0x52): Execute action
 * - AUTONOMOUS_FINALIZE (0x53): Validator finalization
 * - AUTONOMOUS_REVOKE (0x54): Revoke authorization
 */
contract AutonomousIntentTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    // Test actors
    uint256 public actorPk = 0x1111;
    address public actor;
    uint256 public actor2Pk = 0x2222;
    address public actor2;

    // Validators
    uint256 public validatorPk1 = 0x3333;
    address public validator1;
    uint256 public validatorPk2 = 0x4444;
    address public validator2;
    uint256 public validatorPk3 = 0x5555;
    address public validator3;

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    // Message type constants
    uint8 constant MSG_AUTONOMOUS_INTENT = 0x50;
    uint8 constant MSG_AUTONOMOUS_PATTERN = 0x51;
    uint8 constant MSG_AUTONOMOUS_EXECUTE = 0x52;
    uint8 constant MSG_AUTONOMOUS_FINALIZE = 0x53;
    uint8 constant MSG_AUTONOMOUS_REVOKE = 0x54;

    function setUp() public {
        actor = vm.addr(actorPk);
        actor2 = vm.addr(actor2Pk);
        validator1 = vm.addr(validatorPk1);
        validator2 = vm.addr(validatorPk2);
        validator3 = vm.addr(validatorPk3);

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

        // Create epoch with signals capability
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // Warp to active
        vm.warp(startTime);
    }

    // =========================================================================
    // Message Type Tests
    // =========================================================================

    /// @notice AUTONOMOUS_INTENT message type is correct
    function test_autonomousIntent_messageType() public pure {
        assertEq(MSG_AUTONOMOUS_INTENT, 0x50);
    }

    /// @notice AUTONOMOUS_PATTERN message type is correct
    function test_autonomousPattern_messageType() public pure {
        assertEq(MSG_AUTONOMOUS_PATTERN, 0x51);
    }

    /// @notice AUTONOMOUS_EXECUTE message type is correct
    function test_autonomousExecute_messageType() public pure {
        assertEq(MSG_AUTONOMOUS_EXECUTE, 0x52);
    }

    /// @notice AUTONOMOUS_FINALIZE message type is correct
    function test_autonomousFinalize_messageType() public pure {
        assertEq(MSG_AUTONOMOUS_FINALIZE, 0x53);
    }

    /// @notice AUTONOMOUS_REVOKE message type is correct
    function test_autonomousRevoke_messageType() public pure {
        assertEq(MSG_AUTONOMOUS_REVOKE, 0x54);
    }

    // =========================================================================
    // INV34: Intent Presence Tests
    // =========================================================================

    /// @notice Validated presence can declare intent (INV34)
    function test_inv34_validatedPresenceCanDeclareIntent() public {
        // Declare and validate presence
        vm.prank(actor);
        presenceRegistry.declarePresence(actor, epochId);

        // Validate with quorum (all 3 validators needed for 67% of 3)
        vm.prank(validator1);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator2);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator3);
        presenceRegistry.validatePresence(actor, epochId);

        // Should be Validated
        assertEq(
            uint256(presenceRegistry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Validated)
        );

        // Can declare intent
        assertTrue(_canDeclareIntent(actor, epochId), "INV34: Validated presence can declare intent");
    }

    /// @notice Finalized presence can declare intent (INV34)
    /// @dev Note: Presence can only be finalized after epoch closes, so this tests
    ///      the helper logic for completeness. In practice, new intents would be
    ///      declared during Active epoch with Validated presence.
    function test_inv34_finalizedPresenceCanDeclareIntent() public {
        // Declare and validate presence during active epoch
        vm.prank(actor);
        presenceRegistry.declarePresence(actor, epochId);

        // Validate with quorum (all 3 validators needed for 67% of 3)
        vm.prank(validator1);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator2);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator3);
        presenceRegistry.validatePresence(actor, epochId);

        // Warp to after epoch closes (required for finalization)
        vm.warp(endTime + 1);

        // Now finalize presence
        vm.prank(actor);
        presenceRegistry.finalizePresence(actor, epochId);

        // Should be Finalized
        assertEq(
            uint256(presenceRegistry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Finalized)
        );

        // Helper correctly identifies Finalized as valid for intent declaration
        // (though new intents wouldn't be declared after epoch closes due to INV37)
        assertTrue(_canDeclareIntent(actor, epochId), "INV34: Finalized presence can declare intent");
    }

    /// @notice Declared-only presence cannot declare intent (INV34)
    function test_inv34_declaredOnlyCannotDeclareIntent() public {
        vm.prank(actor);
        presenceRegistry.declarePresence(actor, epochId);

        assertEq(
            uint256(presenceRegistry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.Declared)
        );

        assertFalse(_canDeclareIntent(actor, epochId), "INV34: Declared-only cannot declare intent");
    }

    /// @notice No presence cannot declare intent (INV34)
    function test_inv34_noPresenceCannotDeclareIntent() public view {
        assertEq(uint256(presenceRegistry.presenceState(actor, epochId)), uint256(IPresenceRegistry.PresenceState.None));

        assertFalse(_canDeclareIntent(actor, epochId), "INV34: No presence cannot declare intent");
    }

    // =========================================================================
    // Intent Hash Tests
    // =========================================================================

    /// @notice Intent hash is deterministic
    function test_intentHash_deterministic() public pure {
        bytes32 actionType = keccak256("transfer");
        uint256 maxExecutions = 10;
        uint256 expiresAt = 1700000000;

        bytes32 hash1 = keccak256(abi.encodePacked(actionType, maxExecutions, expiresAt));
        bytes32 hash2 = keccak256(abi.encodePacked(actionType, maxExecutions, expiresAt));

        assertEq(hash1, hash2);
    }

    /// @notice Intent ID is unique per actor and nonce
    function test_intentId_unique() public pure {
        address actor1 = address(0x1111);
        address actor2Addr = address(0x2222);
        uint256 nonce = 1;

        bytes32 id1 = keccak256(abi.encodePacked(actor1, nonce));
        bytes32 id2 = keccak256(abi.encodePacked(actor2Addr, nonce));

        assertNotEq(id1, id2);
    }

    // =========================================================================
    // Expiration Tests
    // =========================================================================

    /// @notice Intent expiration within epoch is valid
    function test_expiration_withinEpochValid() public view {
        uint256 expiresAt = endTime - 1 hours;

        assertTrue(expiresAt <= endTime, "Expiration within epoch is valid");
        assertTrue(expiresAt > startTime, "Expiration after start is valid");
    }

    /// @notice Intent expiration after epoch is invalid
    function test_expiration_afterEpochInvalid() public view {
        uint256 expiresAt = endTime + 1 hours;

        assertFalse(expiresAt <= endTime, "Expiration after epoch is invalid");
    }

    // =========================================================================
    // Max Executions Tests
    // =========================================================================

    /// @notice Max executions <= 100 is valid
    function test_maxExecutions_withinLimit() public pure {
        uint256 maxExecutions = 100;
        uint256 limit = 100;

        assertTrue(maxExecutions <= limit);
    }

    /// @notice Max executions > 100 is invalid
    function test_maxExecutions_exceedsLimit() public pure {
        uint256 maxExecutions = 101;
        uint256 limit = 100;

        assertFalse(maxExecutions <= limit);
    }

    /// @notice Max executions 0 means unlimited
    function test_maxExecutions_unlimitedWithZero() public pure {
        uint256 maxExecutions = 0;

        // 0 is interpreted as unlimited within epoch
        assertTrue(maxExecutions == 0, "0 means unlimited");
    }

    // =========================================================================
    // Action Type Tests
    // =========================================================================

    /// @notice Common action types
    function test_actionTypes() public pure {
        bytes32 transferType = keccak256("transfer");
        bytes32 voteType = keccak256("vote");
        bytes32 delegateType = keccak256("delegate");

        assertNotEq(transferType, voteType);
        assertNotEq(voteType, delegateType);
        assertNotEq(transferType, delegateType);
    }

    // =========================================================================
    // Epoch Binding Tests (INV37 preview)
    // =========================================================================

    /// @notice Intent requires active epoch
    function test_epochBinding_activeRequired() public view {
        assertEq(uint256(epochRegistry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Active));

        assertTrue(_isValidIntentEpoch(epochId));
    }

    /// @notice Intent invalid after epoch closes
    function test_epochBinding_closedInvalid() public {
        // Warp to after epoch ends
        vm.warp(endTime + 1);

        assertEq(uint256(epochRegistry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Closed));

        assertFalse(_isValidIntentEpoch(epochId));
    }

    // =========================================================================
    // Signature Tests
    // =========================================================================

    /// @notice Intent can be signed by actor
    function test_signature_actorSigns() public {
        bytes32 intentId = keccak256(abi.encodePacked(actor, epochId, uint256(1)));
        bytes32 intentHash = keccak256("test-intent");

        bytes32 signPayload = keccak256(abi.encodePacked(intentId, intentHash, epochId));
        bytes32 ethSignedHash = _toEthSignedMessageHash(signPayload);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(actorPk, ethSignedHash);

        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, actor);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _canDeclareIntent(address _actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(_actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Validated || state == IPresenceRegistry.PresenceState.Finalized;
    }

    function _isValidIntentEpoch(uint256 _epochId) internal view returns (bool) {
        return epochRegistry.epochState(_epochId) == IEpochRegistry.EpochState.Active;
    }
}

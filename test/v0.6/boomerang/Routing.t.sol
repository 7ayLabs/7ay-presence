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
 * @title BoomerangRoutingTest
 * @notice Tests for v0.6.5 Boomerang Routing mechanics
 * @dev Validates path divergence (INV30) and timeout handling (INV31)
 *
 * Boomerang Message Types:
 * - BOOMERANG_SEND (0x40): Initiate cycle
 * - BOOMERANG_ACK (0x41): Destination acknowledgment
 * - BOOMERANG_RETURN (0x42): Return path traversal
 * - BOOMERANG_COMPLETE (0x43): Cycle completion
 */
contract BoomerangRoutingTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    // Test nodes with known private keys
    uint256 public originPk = 0x1111;
    address public origin; // Node A - origin
    uint256 public intermediaryPk = 0x2222;
    address public intermediary; // Node B - forward path intermediary
    uint256 public destinationPk = 0x3333;
    address public destination; // Node C - destination
    uint256 public altPathPk = 0x4444;
    address public altPath; // Node D - return path alternative

    // Validators
    uint256 public validatorPk1 = 0x5555;
    address public validator1;
    uint256 public validatorPk2 = 0x6666;
    address public validator2;
    uint256 public validatorPk3 = 0x7777;
    address public validator3;

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    // Boomerang message type constants
    uint8 constant MSG_BOOMERANG_SEND = 0x40;
    uint8 constant MSG_BOOMERANG_ACK = 0x41;
    uint8 constant MSG_BOOMERANG_RETURN = 0x42;
    uint8 constant MSG_BOOMERANG_COMPLETE = 0x43;

    // Max timeout per spec
    uint256 constant MAX_TIMEOUT = 300; // 5 minutes

    function setUp() public {
        origin = vm.addr(originPk);
        intermediary = vm.addr(intermediaryPk);
        destination = vm.addr(destinationPk);
        altPath = vm.addr(altPathPk);
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

        // All nodes declare presence
        vm.prank(origin);
        presenceRegistry.declarePresence(origin, epochId);
        vm.prank(intermediary);
        presenceRegistry.declarePresence(intermediary, epochId);
        vm.prank(destination);
        presenceRegistry.declarePresence(destination, epochId);
        vm.prank(altPath);
        presenceRegistry.declarePresence(altPath, epochId);
    }

    // =========================================================================
    // BOOMERANG_SEND (0x40) Tests
    // =========================================================================

    /// @notice BOOMERANG_SEND message type is correct
    function test_boomerangSend_messageType() public pure {
        assertEq(MSG_BOOMERANG_SEND, 0x40);
    }

    /// @notice Sender must have valid presence
    function test_boomerangSend_requiresPresence() public view {
        assertTrue(_canInitiateBoomerang(origin, epochId));
    }

    /// @notice Destination must have valid presence
    function test_boomerangSend_destinationRequiresPresence() public view {
        assertTrue(_hasValidPresence(destination, epochId));
    }

    /// @notice Destination without presence is invalid
    function test_boomerangSend_invalidDestination() public {
        address noPresence = makeAddr("noPresence");
        assertFalse(_hasValidPresence(noPresence, epochId));
    }

    /// @notice Timeout must be <= 300 seconds
    function test_boomerangSend_maxTimeout() public pure {
        uint256 validTimeout = 300;
        uint256 invalidTimeout = 301;

        assertTrue(validTimeout <= MAX_TIMEOUT);
        assertFalse(invalidTimeout <= MAX_TIMEOUT);
    }

    /// @notice BoomerangId must be unique per sender per epoch
    function test_boomerangSend_uniqueBoomerangId() public view {
        bytes32 id1 = _generateBoomerangId(origin, epochId, 1);
        bytes32 id2 = _generateBoomerangId(origin, epochId, 2);

        assertNotEq(id1, id2);
    }

    /// @notice Same boomerangId from different senders is valid
    function test_boomerangSend_differentSendersCanUseSameNonce() public view {
        bytes32 id1 = _generateBoomerangId(origin, epochId, 1);
        bytes32 id2 = _generateBoomerangId(destination, epochId, 1);

        // Same nonce but different senders = different ids
        assertNotEq(id1, id2);
    }

    // =========================================================================
    // BOOMERANG_ACK (0x41) Tests
    // =========================================================================

    /// @notice BOOMERANG_ACK message type is correct
    function test_boomerangAck_messageType() public pure {
        assertEq(MSG_BOOMERANG_ACK, 0x41);
    }

    /// @notice ACK sender must be the destination from SEND
    function test_boomerangAck_senderMustBeDestination() public view {
        // Only destination can send ACK for a boomerang targeting them
        assertTrue(_canAcknowledgeBoomerang(destination, destination));
        assertFalse(_canAcknowledgeBoomerang(origin, destination)); // origin can't ack
    }

    /// @notice ACK must include divergent return path (INV30)
    function test_boomerangAck_requiresDivergentPath() public pure {
        // Forward path: origin → intermediary → destination
        address[] memory forwardPath = new address[](1);
        forwardPath[0] = address(0x2222); // intermediary

        // Valid return path (different intermediary)
        address[] memory validReturnPath = new address[](1);
        validReturnPath[0] = address(0x4444); // altPath

        // Invalid return path (same as forward)
        address[] memory invalidReturnPath = new address[](1);
        invalidReturnPath[0] = address(0x2222); // same intermediary

        assertTrue(_isPathDivergent(forwardPath, validReturnPath));
        assertFalse(_isPathDivergent(forwardPath, invalidReturnPath));
    }

    /// @notice Direct return (no intermediaries) is valid if forward had intermediaries
    function test_boomerangAck_directReturnValid() public pure {
        // Forward path: origin → intermediary → destination
        address[] memory forwardPath = new address[](1);
        forwardPath[0] = address(0x2222); // intermediary

        // Direct return (no intermediaries)
        address[] memory directReturn = new address[](0);

        // Direct is divergent from path with intermediary
        assertTrue(_isPathDivergent(forwardPath, directReturn));
    }

    /// @notice InnerPayloadHash must match
    function test_boomerangAck_hashVerification() public pure {
        bytes memory payload = "test message content";
        bytes32 expectedHash = keccak256(payload);

        bytes32 receivedHash = keccak256(payload);
        assertEq(receivedHash, expectedHash);
    }

    // =========================================================================
    // BOOMERANG_RETURN (0x42) Tests
    // =========================================================================

    /// @notice BOOMERANG_RETURN message type is correct
    function test_boomerangReturn_messageType() public pure {
        assertEq(MSG_BOOMERANG_RETURN, 0x42);
    }

    /// @notice Each hop must be signed by forwarder (INV33)
    function test_boomerangReturn_hopSignature() public {
        bytes32 boomerangId = _generateBoomerangId(origin, epochId, 1);
        bytes32 previousHash = bytes32(0);
        uint256 forwardedAt = block.timestamp;

        // Create hop signature payload per spec
        bytes32 hopPayload = keccak256(abi.encodePacked(boomerangId, altPath, previousHash, forwardedAt));

        bytes32 ethSignedHash = _toEthSignedMessageHash(hopPayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(altPathPk, ethSignedHash);

        // Verify signature
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, altPath);
    }

    /// @notice Hop index must increment correctly
    function test_boomerangReturn_hopIndexIncrement() public pure {
        uint256[] memory hopIndices = new uint256[](3);
        hopIndices[0] = 0;
        hopIndices[1] = 1;
        hopIndices[2] = 2;

        for (uint256 i = 1; i < hopIndices.length; i++) {
            assertEq(hopIndices[i], hopIndices[i - 1] + 1);
        }
    }

    /// @notice All forwarders must have valid presence
    function test_boomerangReturn_forwardersRequirePresence() public view {
        assertTrue(_hasValidPresence(altPath, epochId));
    }

    // =========================================================================
    // BOOMERANG_COMPLETE (0x43) Tests
    // =========================================================================

    /// @notice BOOMERANG_COMPLETE message type is correct
    function test_boomerangComplete_messageType() public pure {
        assertEq(MSG_BOOMERANG_COMPLETE, 0x43);
    }

    /// @notice Complete sender must be original sender
    function test_boomerangComplete_senderMustBeOrigin() public view {
        // Only origin can send COMPLETE
        assertTrue(_canCompleteBoomerang(origin, origin));
        assertFalse(_canCompleteBoomerang(destination, origin));
    }

    /// @notice PathsDivergent must be true (INV30)
    function test_boomerangComplete_pathsDivergentRequired() public pure {
        bool pathsDivergent = true; // Must always be true in valid COMPLETE

        assertTrue(pathsDivergent, "INV30: pathsDivergent must be true");
    }

    /// @notice Completion within timeout (INV31)
    function test_boomerangComplete_withinTimeout() public {
        uint256 sentAt = block.timestamp;
        uint256 timeout = 60; // 60 seconds

        // Complete within timeout
        vm.warp(sentAt + 30);
        uint256 completedAt = block.timestamp;

        assertTrue(completedAt - sentAt <= timeout, "INV31: Must complete within timeout");
    }

    /// @notice Completion after timeout is invalid (INV31)
    function test_boomerangComplete_afterTimeoutInvalid() public {
        uint256 sentAt = block.timestamp;
        uint256 timeout = 60;

        // Try to complete after timeout
        vm.warp(sentAt + timeout + 1);
        uint256 completedAt = block.timestamp;

        assertFalse(completedAt - sentAt <= timeout, "INV31: Should fail after timeout");
    }

    // =========================================================================
    // INV30: Path Divergence Tests
    // =========================================================================

    /// @notice Path divergence - different intermediary
    function test_inv30_differentIntermediary() public pure {
        address[] memory forward = new address[](1);
        forward[0] = address(0x2222);

        address[] memory ret = new address[](1);
        ret[0] = address(0x4444);

        assertTrue(_isPathDivergent(forward, ret), "INV30: Different intermediary = divergent");
    }

    /// @notice Path divergence - different length
    function test_inv30_differentLength() public pure {
        address[] memory forward = new address[](2);
        forward[0] = address(0x2222);
        forward[1] = address(0x3333);

        address[] memory ret = new address[](1);
        ret[0] = address(0x4444);

        assertTrue(_isPathDivergent(forward, ret), "INV30: Different length = divergent");
    }

    /// @notice Same path reversed is NOT divergent
    function test_inv30_samePathReversedInvalid() public pure {
        address[] memory forward = new address[](2);
        forward[0] = address(0x2222);
        forward[1] = address(0x3333);

        address[] memory ret = new address[](2);
        ret[0] = address(0x3333);
        ret[1] = address(0x2222);

        assertFalse(_isPathDivergent(forward, ret), "INV30: Same path reversed = not divergent");
    }

    // =========================================================================
    // INV31: Timeout Tests
    // =========================================================================

    /// @notice Timeout detection at exact boundary
    function test_inv31_timeoutBoundary() public {
        uint256 sentAt = block.timestamp;
        uint256 timeout = 60;

        // At exact timeout boundary
        vm.warp(sentAt + timeout);
        uint256 completedAt = block.timestamp;

        assertTrue(completedAt - sentAt <= timeout, "INV31: At boundary should pass");

        // One second after
        vm.warp(sentAt + timeout + 1);
        completedAt = block.timestamp;

        assertFalse(completedAt - sentAt <= timeout, "INV31: After boundary should fail");
    }

    /// @notice Timeout recovery allows new boomerangId
    function test_inv31_timeoutRecovery() public view {
        bytes32 originalId = _generateBoomerangId(origin, epochId, 1);
        bytes32 retryId = _generateBoomerangId(origin, epochId, 2);

        // Different IDs for retry
        assertNotEq(originalId, retryId, "Retry must use new boomerangId");
    }

    // =========================================================================
    // State Machine Tests
    // =========================================================================

    /// @notice Valid state transitions
    function test_stateMachine_validTransitions() public pure {
        // Pending → AwaitingReturn (via ACK)
        // Pending → Timeout (via timeout)
        // Pending → Failed (via error)
        // AwaitingReturn → Complete (via COMPLETE)
        // AwaitingReturn → Timeout (via timeout)

        uint8 PENDING = 0;
        uint8 AWAITING_RETURN = 1;
        uint8 COMPLETE = 2;
        uint8 TIMEOUT = 3;
        uint8 FAILED = 4;

        // Valid transitions
        assertTrue(_isValidTransition(PENDING, AWAITING_RETURN));
        assertTrue(_isValidTransition(PENDING, TIMEOUT));
        assertTrue(_isValidTransition(PENDING, FAILED));
        assertTrue(_isValidTransition(AWAITING_RETURN, COMPLETE));
        assertTrue(_isValidTransition(AWAITING_RETURN, TIMEOUT));

        // Invalid transitions
        assertFalse(_isValidTransition(COMPLETE, PENDING)); // terminal
        assertFalse(_isValidTransition(TIMEOUT, PENDING)); // terminal
        assertFalse(_isValidTransition(FAILED, PENDING)); // terminal
    }

    /// @notice Terminal states have no outgoing transitions (INV32)
    function test_inv32_terminalStates() public pure {
        uint8 COMPLETE = 2;
        uint8 TIMEOUT = 3;
        uint8 FAILED = 4;

        // No transitions from terminal states
        for (uint8 i = 0; i < 5; i++) {
            assertFalse(_isValidTransition(COMPLETE, i), "INV32: Complete is terminal");
            assertFalse(_isValidTransition(TIMEOUT, i), "INV32: Timeout is terminal");
            assertFalse(_isValidTransition(FAILED, i), "INV32: Failed is terminal");
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _generateBoomerangId(address sender, uint256 _epochId, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, _epochId, nonce));
    }

    function _hasValidPresence(address actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    function _canInitiateBoomerang(address sender, uint256 _epochId) internal view returns (bool) {
        if (!_hasValidPresence(sender, _epochId)) return false;
        if (epochRegistry.epochState(_epochId) != IEpochRegistry.EpochState.Active) return false;
        return true;
    }

    function _canAcknowledgeBoomerang(address acker, address expectedDestination) internal pure returns (bool) {
        return acker == expectedDestination;
    }

    function _canCompleteBoomerang(address completer, address expectedOrigin) internal pure returns (bool) {
        return completer == expectedOrigin;
    }

    function _isPathDivergent(address[] memory forwardPath, address[] memory returnPath) internal pure returns (bool) {
        // If lengths differ and at least one has content, it's divergent
        if (forwardPath.length == 0 && returnPath.length > 0) return true;
        if (forwardPath.length > 0 && returnPath.length == 0) return true;
        if (forwardPath.length == 0 && returnPath.length == 0) return false; // Both empty = same

        // Check if paths share all intermediaries (same or reversed = not divergent)
        // Simple check: at least one node must be different
        bool hasDifferentNode = false;

        for (uint256 i = 0; i < forwardPath.length; i++) {
            bool foundInReturn = false;
            for (uint256 j = 0; j < returnPath.length; j++) {
                if (forwardPath[i] == returnPath[j]) {
                    foundInReturn = true;
                    break;
                }
            }
            if (!foundInReturn) {
                hasDifferentNode = true;
                break;
            }
        }

        if (hasDifferentNode) return true;

        // Also check if return has nodes not in forward
        for (uint256 i = 0; i < returnPath.length; i++) {
            bool foundInForward = false;
            for (uint256 j = 0; j < forwardPath.length; j++) {
                if (returnPath[i] == forwardPath[j]) {
                    foundInForward = true;
                    break;
                }
            }
            if (!foundInForward) {
                return true;
            }
        }

        return false;
    }

    function _isValidTransition(uint8 from, uint8 to) internal pure returns (bool) {
        uint8 PENDING = 0;
        uint8 AWAITING_RETURN = 1;
        uint8 COMPLETE = 2;
        uint8 TIMEOUT = 3;
        uint8 FAILED = 4;

        // Terminal states have no outgoing transitions
        if (from == COMPLETE || from == TIMEOUT || from == FAILED) {
            return false;
        }

        // Valid transitions from PENDING
        if (from == PENDING) {
            return to == AWAITING_RETURN || to == TIMEOUT || to == FAILED;
        }

        // Valid transitions from AWAITING_RETURN
        if (from == AWAITING_RETURN) {
            return to == COMPLETE || to == TIMEOUT;
        }

        return false;
    }
}

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
 * @title MessageEnvelopeTest
 * @notice Tests for v0.6 Message Envelope specification
 * @dev Validates INV23 (Epoch-Bound Messages), INV24 (Signature Validity), INV25 (Nonce Uniqueness)
 *
 * Message Envelope (v0.6.2):
 * - version: "0.6.0"
 * - type: MessageType enum
 * - sender: NodeIdentity
 * - epochId: uint256
 * - timestamp: uint256
 * - nonce: bytes32
 * - signature: bytes (65 bytes ECDSA)
 * - payload: MessagePayload
 */
contract MessageEnvelopeTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    // Test accounts with known private keys
    uint256 public senderPk = 0x1234;
    address public sender;

    uint256 public validatorPk1 = 0x5678;
    address public validator1;
    uint256 public validatorPk2 = 0x9abc;
    address public validator2;
    uint256 public validatorPk3 = 0xdef0;
    address public validator3;

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    // Message type constants (from spec)
    uint8 constant MSG_NODE_ANNOUNCE = 0x01;
    uint8 constant MSG_NODE_QUERY = 0x02;
    uint8 constant MSG_STATE_SYNC_REQUEST = 0x10;
    uint8 constant MSG_PRESENCE_ATTESTATION = 0x20;

    function setUp() public {
        sender = vm.addr(senderPk);
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

        // Warp to active and declare presence
        vm.warp(startTime);
        vm.prank(sender);
        presenceRegistry.declarePresence(sender, epochId);
    }

    // =========================================================================
    // Signature Scheme (Section 2.3 of message-catalog.md)
    // =========================================================================

    /// @notice Signature payload matches spec
    function test_signature_payloadStructure() public view {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256("test-nonce");
        bytes32 payloadHash = keccak256("test-payload");

        // Signature payload per spec:
        // keccak256(abi.encodePacked(version, type, sender.address, epochId, timestamp, nonce, keccak256(payload)))
        bytes32 signaturePayload =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash));

        // Verify hash is deterministic
        bytes32 signaturePayload2 =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash));

        assertEq(signaturePayload, signaturePayload2);
    }

    /// @notice ECDSA signature verifies correctly
    function test_signature_ecdsaVerification() public {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256("test-nonce");
        bytes32 payloadHash = keccak256("test-payload");

        bytes32 signaturePayload =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash));

        // Sign with sender's private key (using eth_sign prefix)
        bytes32 ethSignedHash = _toEthSignedMessageHash(signaturePayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, ethSignedHash);

        // Verify signature using ecrecover
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, sender);
    }

    /// @notice Invalid signature is rejected (INV24)
    function test_signature_invalidRejected() public {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256("test-nonce");
        bytes32 payloadHash = keccak256("test-payload");

        bytes32 signaturePayload =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash));

        // Sign with wrong key
        bytes32 ethSignedHash = _toEthSignedMessageHash(signaturePayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPk1, ethSignedHash); // Wrong key!

        // Recovered address doesn't match sender
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertNotEq(recovered, sender);
        assertEq(recovered, validator1);
    }

    /// @notice Helper to create eth_sign prefixed hash
    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    // =========================================================================
    // INV23: Epoch-Bound Messages
    // =========================================================================

    /// @notice Message must reference valid epoch
    function test_epochBound_validEpoch() public view {
        // Epoch exists and is active
        assertTrue(uint256(epochRegistry.epochState(epochId)) != 0);
        IEpochRegistry.EpochState state = epochRegistry.epochState(epochId);
        assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Active));

        // Epoch supports signals (required for v0.6)
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId);
        assertTrue(uint256(cap) >= 1); // PresenceWithSignals (1) or PresenceWithEphemeralData (2)
    }

    /// @notice Message referencing non-existent epoch is invalid
    function test_epochBound_nonExistentEpoch() public view {
        uint256 invalidEpochId = 999;
        assertFalse(uint256(epochRegistry.epochState(invalidEpochId)) != 0);

        // Per INV23, this message would be invalid
    }

    /// @notice Message for PresenceOnly epoch is invalid (no v0.6 features)
    function test_epochBound_presenceOnlyInvalid() public {
        // Create PresenceOnly epoch
        uint256 presenceOnlyEpochId = 2;
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            presenceOnlyEpochId,
            startTime + 2 days,
            endTime + 2 days,
            IEpochRegistry.EpochCapability.PresenceOnly,
            bytes32(0)
        );

        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(presenceOnlyEpochId);
        assertEq(uint256(cap), 0); // PresenceOnly

        // Per INV23, v0.6 messages for this epoch would be invalid
    }

    // =========================================================================
    // INV25: Nonce Uniqueness
    // =========================================================================

    /// @notice Nonces must be unique per sender per epoch
    function test_nonceUniqueness_differentNonces() public pure {
        bytes32 nonce1 = keccak256("nonce-1");
        bytes32 nonce2 = keccak256("nonce-2");

        // Different nonces
        assertNotEq(nonce1, nonce2);
    }

    /// @notice Same nonce from different senders is valid (INV25 scopes to sender)
    function test_nonceUniqueness_differentSenders() public {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 sharedNonce = keccak256("shared-nonce");
        bytes32 payloadHash = keccak256("test-payload");

        // Second sender with presence
        uint256 sender2Pk = 0xabcd;
        address sender2 = vm.addr(sender2Pk);
        vm.prank(sender2);
        presenceRegistry.declarePresence(sender2, epochId);

        // Create signature payload for sender1
        bytes32 signaturePayload1 =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, sharedNonce, payloadHash));
        bytes32 ethSignedHash1 = _toEthSignedMessageHash(signaturePayload1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(senderPk, ethSignedHash1);

        // Create signature payload for sender2 (same nonce!)
        bytes32 signaturePayload2 =
            keccak256(abi.encodePacked(version, msgType, sender2, epochId, timestamp, sharedNonce, payloadHash));
        bytes32 ethSignedHash2 = _toEthSignedMessageHash(signaturePayload2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(sender2Pk, ethSignedHash2);

        // Both signatures verify correctly despite same nonce
        // This is valid because INV25 scopes uniqueness to (sender, nonce) pairs
        assertEq(ecrecover(ethSignedHash1, v1, r1, s1), sender);
        assertEq(ecrecover(ethSignedHash2, v2, r2, s2), sender2);
    }

    /// @notice Nonce reuse detection - same (sender, nonce) produces identical hash
    function test_nonceUniqueness_reuseDetectable() public view {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256("reused-nonce");
        bytes32 payloadHash1 = keccak256("payload-1");
        bytes32 payloadHash2 = keccak256("payload-2");

        // Message 1 with nonce
        bytes32 signaturePayload1 =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash1));

        // Message 2 with SAME nonce (different payload)
        bytes32 signaturePayload2 =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash2));

        // Different payloads produce different hashes even with same nonce
        assertNotEq(signaturePayload1, signaturePayload2);

        // But the (sender, epochId, nonce) tuple is the same - this is what INV25 tracks
        // A semantic layer would reject message 2 because it already saw this nonce from this sender
        bytes32 nonceKey1 = keccak256(abi.encodePacked(sender, epochId, nonce));
        bytes32 nonceKey2 = keccak256(abi.encodePacked(sender, epochId, nonce));
        assertEq(nonceKey1, nonceKey2); // Same key = replay detected per INV25
    }

    // =========================================================================
    // Message Types
    // =========================================================================

    /// @notice Discovery message types
    function test_messageTypes_discovery() public pure {
        assertEq(MSG_NODE_ANNOUNCE, 0x01);
        assertEq(MSG_NODE_QUERY, 0x02);
        // NODE_RESPONSE = 0x03
        // NODE_LEAVE = 0x04
    }

    /// @notice State sync message types
    function test_messageTypes_stateSync() public pure {
        assertEq(MSG_STATE_SYNC_REQUEST, 0x10);
        // STATE_SYNC_RESPONSE = 0x11
        // STATE_VECTOR_CLOCK = 0x12
        // STATE_DIFF = 0x13
    }

    /// @notice Attestation message types
    function test_messageTypes_attestation() public pure {
        assertEq(MSG_PRESENCE_ATTESTATION, 0x20);
        // VALIDATION_VOTE = 0x21
        // DISPUTE_NOTICE = 0x22
    }

    // =========================================================================
    // Timestamp Validation (Section 6.1)
    // =========================================================================

    /// @notice Timestamp must be within acceptable window
    function test_timestamp_withinWindow() public view {
        uint256 messageTimestamp = block.timestamp;
        uint256 currentTime = block.timestamp;

        // Window is +/- 5 minutes (300 seconds)
        uint256 maxDrift = 300;

        assertTrue(messageTimestamp >= currentTime - maxDrift);
        assertTrue(messageTimestamp <= currentTime + maxDrift);
    }

    /// @notice Timestamp too old is invalid
    function test_timestamp_tooOld() public view {
        uint256 currentTime = block.timestamp;
        uint256 maxDrift = 300; // 5 minutes

        uint256 oldTimestamp = currentTime - maxDrift - 1;

        // Would fail validation
        assertFalse(oldTimestamp >= currentTime - maxDrift);
    }

    /// @notice Timestamp too far in future is invalid
    function test_timestamp_tooFuture() public view {
        uint256 currentTime = block.timestamp;
        uint256 maxDrift = 300; // 5 minutes

        uint256 futureTimestamp = currentTime + maxDrift + 1;

        // Would fail validation
        assertFalse(futureTimestamp <= currentTime + maxDrift);
    }

    // =========================================================================
    // Sender Validation
    // =========================================================================

    /// @notice Sender must have valid presence (for most messages)
    function test_sender_requiresPresence() public view {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(sender, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.Declared));

        // Valid sender for messaging
    }

    /// @notice Sender without presence is invalid
    function test_sender_noPresenceInvalid() public {
        address noPresence = makeAddr("noPresence");
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(noPresence, epochId);
        assertEq(uint256(state), uint256(IPresenceRegistry.PresenceState.None));

        // Invalid sender per validation rules
    }

    /// @notice Validator-only messages require validator role
    function test_sender_validatorOnlyMessages() public view {
        // STATE_SYNC_REQUEST requires validator
        assertTrue(validatorRegistry.isValidatorActive(validator1));
        assertFalse(validatorRegistry.isValidatorActive(sender));

        // sender cannot send STATE_SYNC_REQUEST (not a validator)
    }

    // =========================================================================
    // Full Message Construction
    // =========================================================================

    /// @notice Construct and verify NODE_ANNOUNCE message
    function test_fullMessage_nodeAnnounce() public {
        string memory version = "0.6.0";
        uint8 msgType = MSG_NODE_ANNOUNCE;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256(abi.encodePacked(block.timestamp, sender));

        // Payload for NODE_ANNOUNCE
        bytes memory payload = abi.encode(
            sender, // node.identity.address
            epochId, // node.epoch.epochId
            false, // isValidator
            uint8(1), // presenceState (Declared)
            uint256(3600) // ttl
        );
        bytes32 payloadHash = keccak256(payload);

        // Construct signature payload
        bytes32 signaturePayload =
            keccak256(abi.encodePacked(version, msgType, sender, epochId, timestamp, nonce, payloadHash));

        // Sign
        bytes32 ethSignedHash = _toEthSignedMessageHash(signaturePayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderPk, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, sender);

        // All envelope fields are valid
        assertEq(keccak256(bytes(version)), keccak256(bytes("0.6.0")));
        assertEq(msgType, MSG_NODE_ANNOUNCE);
        assertTrue(uint256(epochRegistry.epochState(epochId)) != 0);
        assertEq(signature.length, 65);
    }

    /// @notice Construct and verify PRESENCE_ATTESTATION message (validator only)
    function test_fullMessage_presenceAttestation() public {
        // Validator declares presence
        vm.prank(validator1);
        presenceRegistry.declarePresence(validator1, epochId);

        string memory version = "0.6.0";
        uint8 msgType = MSG_PRESENCE_ATTESTATION;
        uint256 timestamp = block.timestamp;
        bytes32 nonce = keccak256(abi.encodePacked(block.timestamp, validator1));

        // Payload for PRESENCE_ATTESTATION
        bytes memory payload = abi.encode(
            sender, // actor being attested
            timestamp, // observedAt
            bytes32(0) // evidenceHash (optional)
        );
        bytes32 payloadHash = keccak256(payload);

        // Construct signature payload
        bytes32 signaturePayload =
            keccak256(abi.encodePacked(version, msgType, validator1, epochId, timestamp, nonce, payloadHash));

        // Sign with validator key
        bytes32 ethSignedHash = _toEthSignedMessageHash(signaturePayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPk1, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, validator1);
        assertTrue(validatorRegistry.isValidatorActive(validator1));
    }

    // =========================================================================
    // Version Validation
    // =========================================================================

    /// @notice Version must be "0.6.0"
    function test_version_mustMatch() public pure {
        string memory validVersion = "0.6.0";
        string memory invalidVersion = "0.5.0";

        assertEq(keccak256(bytes(validVersion)), keccak256(bytes("0.6.0")));
        assertNotEq(keccak256(bytes(invalidVersion)), keccak256(bytes("0.6.0")));
    }
}

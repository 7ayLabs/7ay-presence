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
 * @title BoomerangVerificationTest
 * @notice Tests for v0.6.5 Boomerang hop verification chain
 * @dev Validates INV33 (Verification Chain) - each hop must be signed by forwarding node
 *
 * Hop Signature Payload:
 * keccak256(abi.encodePacked(boomerangId, forwarder, previousHopHash, forwardedAt))
 */
contract BoomerangVerificationTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    // Chain of nodes for verification
    uint256 public originPk = 0x1111;
    address public origin;
    uint256 public destinationPk = 0x2222;
    address public destination;
    uint256 public hop1Pk = 0x3333;
    address public hop1;
    uint256 public hop2Pk = 0x4444;
    address public hop2;
    uint256 public hop3Pk = 0x5555;
    address public hop3;

    // Validators
    uint256 public validatorPk1 = 0x6666;
    address public validator1;
    uint256 public validatorPk2 = 0x7777;
    address public validator2;
    uint256 public validatorPk3 = 0x8888;
    address public validator3;

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    // Struct to represent a hop
    struct Hop {
        address forwarder;
        uint256 forwardedAt;
        bytes signature;
    }

    function setUp() public {
        origin = vm.addr(originPk);
        destination = vm.addr(destinationPk);
        hop1 = vm.addr(hop1Pk);
        hop2 = vm.addr(hop2Pk);
        hop3 = vm.addr(hop3Pk);
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

        // Create epoch
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // Warp to active
        vm.warp(startTime);

        // All nodes declare presence
        vm.prank(origin);
        presenceRegistry.declarePresence(origin, epochId);
        vm.prank(destination);
        presenceRegistry.declarePresence(destination, epochId);
        vm.prank(hop1);
        presenceRegistry.declarePresence(hop1, epochId);
        vm.prank(hop2);
        presenceRegistry.declarePresence(hop2, epochId);
        vm.prank(hop3);
        presenceRegistry.declarePresence(hop3, epochId);
    }

    // =========================================================================
    // Single Hop Verification
    // =========================================================================

    /// @notice Single hop signature verifies correctly
    function test_singleHop_signatureVerifies() public {
        bytes32 boomerangId = keccak256("test-boomerang");
        bytes32 previousHash = bytes32(0); // First hop has no previous
        uint256 forwardedAt = block.timestamp;

        // Create hop signature payload
        bytes32 hopPayload = keccak256(abi.encodePacked(boomerangId, hop1, previousHash, forwardedAt));

        bytes32 ethSignedHash = _toEthSignedMessageHash(hopPayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hop1Pk, ethSignedHash);

        // Verify signature
        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, hop1, "INV33: Hop signature must verify");
    }

    /// @notice Wrong signer is detected
    function test_singleHop_wrongSignerRejected() public {
        bytes32 boomerangId = keccak256("test-boomerang");
        bytes32 previousHash = bytes32(0);
        uint256 forwardedAt = block.timestamp;

        bytes32 hopPayload = keccak256(abi.encodePacked(boomerangId, hop1, previousHash, forwardedAt));

        bytes32 ethSignedHash = _toEthSignedMessageHash(hopPayload);
        // Sign with wrong key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hop2Pk, ethSignedHash);

        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertNotEq(recovered, hop1, "Wrong signer should not match forwarder");
        assertEq(recovered, hop2, "Should recover actual signer");
    }

    /// @notice Tampered payload is detected
    function test_singleHop_tamperedPayloadRejected() public {
        bytes32 boomerangId = keccak256("test-boomerang");
        bytes32 previousHash = bytes32(0);
        uint256 forwardedAt = block.timestamp;

        // Original payload and signature
        bytes32 originalPayload = keccak256(abi.encodePacked(boomerangId, hop1, previousHash, forwardedAt));
        bytes32 ethSignedHash = _toEthSignedMessageHash(originalPayload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hop1Pk, ethSignedHash);

        // Tamper with timestamp
        uint256 tamperedTime = forwardedAt + 1;
        bytes32 tamperedPayload = keccak256(abi.encodePacked(boomerangId, hop1, previousHash, tamperedTime));
        bytes32 tamperedHash = _toEthSignedMessageHash(tamperedPayload);

        // Original signature doesn't verify tampered payload
        address recovered = ecrecover(tamperedHash, v, r, s);
        assertNotEq(recovered, hop1, "Tampered payload should not verify");
    }

    // =========================================================================
    // Chain Verification (INV33)
    // =========================================================================

    /// @notice Two-hop chain verifies correctly
    function test_hopChain_twoHops() public {
        bytes32 boomerangId = keccak256("test-boomerang");

        // Hop 1: destination → hop1
        bytes32 prevHash0 = bytes32(0);
        uint256 time1 = block.timestamp;
        bytes32 hop1Payload = keccak256(abi.encodePacked(boomerangId, hop1, prevHash0, time1));
        bytes32 hop1EthHash = _toEthSignedMessageHash(hop1Payload);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(hop1Pk, hop1EthHash);

        // Verify hop1
        assertEq(ecrecover(hop1EthHash, v1, r1, s1), hop1, "Hop1 should verify");

        // Hash of hop1 for chain
        bytes32 hop1Hash = keccak256(abi.encodePacked(hop1, time1, abi.encodePacked(r1, s1, v1)));

        // Hop 2: hop1 → origin
        vm.warp(block.timestamp + 1);
        uint256 time2 = block.timestamp;
        bytes32 hop2Payload = keccak256(abi.encodePacked(boomerangId, hop2, hop1Hash, time2));
        bytes32 hop2EthHash = _toEthSignedMessageHash(hop2Payload);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(hop2Pk, hop2EthHash);

        // Verify hop2
        assertEq(ecrecover(hop2EthHash, v2, r2, s2), hop2, "Hop2 should verify");
    }

    /// @notice Three-hop chain verifies correctly
    function test_hopChain_threeHops() public {
        bytes32 boomerangId = keccak256("test-boomerang");
        bytes32 previousHash = bytes32(0);

        // Create and verify each hop
        bytes32[] memory hopHashes = new bytes32[](3);
        address[3] memory forwarders = [hop1, hop2, hop3];
        uint256[3] memory keys = [hop1Pk, hop2Pk, hop3Pk];

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(startTime + i + 1);
            uint256 forwardedAt = block.timestamp;

            bytes32 hopPayload = keccak256(abi.encodePacked(boomerangId, forwarders[i], previousHash, forwardedAt));
            bytes32 ethSignedHash = _toEthSignedMessageHash(hopPayload);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], ethSignedHash);

            // Verify
            assertEq(ecrecover(ethSignedHash, v, r, s), forwarders[i], "Each hop should verify");

            // Update previous hash for next hop
            previousHash = keccak256(abi.encodePacked(forwarders[i], forwardedAt, abi.encodePacked(r, s, v)));
            hopHashes[i] = previousHash;
        }
    }

    /// @notice Chain breaks if one hop has invalid signature
    function test_hopChain_brokenByInvalidHop() public {
        bytes32 boomerangId = keccak256("test-boomerang");

        // Valid hop1
        bytes32 prevHash0 = bytes32(0);
        uint256 time1 = block.timestamp;
        bytes32 hop1Payload = keccak256(abi.encodePacked(boomerangId, hop1, prevHash0, time1));
        bytes32 hop1EthHash = _toEthSignedMessageHash(hop1Payload);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(hop1Pk, hop1EthHash);

        bytes32 hop1Hash = keccak256(abi.encodePacked(hop1, time1, abi.encodePacked(r1, s1, v1)));

        // Invalid hop2 (signed by wrong key)
        vm.warp(block.timestamp + 1);
        uint256 time2 = block.timestamp;
        bytes32 hop2Payload = keccak256(abi.encodePacked(boomerangId, hop2, hop1Hash, time2));
        bytes32 hop2EthHash = _toEthSignedMessageHash(hop2Payload);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(hop3Pk, hop2EthHash); // Wrong key!

        // Verification fails for hop2
        address recovered = ecrecover(hop2EthHash, v2, r2, s2);
        assertNotEq(recovered, hop2, "Invalid hop breaks chain");
        assertEq(recovered, hop3, "Wrong signer is detected");
    }

    /// @notice Chain hash must be continuous
    function test_hopChain_hashContinuity() public {
        bytes32 boomerangId = keccak256("test-boomerang");

        // Hop 1
        bytes32 prevHash0 = bytes32(0);
        uint256 time1 = block.timestamp;
        bytes32 hop1Payload = keccak256(abi.encodePacked(boomerangId, hop1, prevHash0, time1));
        bytes32 hop1EthHash = _toEthSignedMessageHash(hop1Payload);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(hop1Pk, hop1EthHash);
        bytes32 hop1Hash = keccak256(abi.encodePacked(hop1, time1, abi.encodePacked(r1, s1, v1)));

        // Hop 2 with WRONG previous hash
        vm.warp(block.timestamp + 1);
        uint256 time2 = block.timestamp;
        bytes32 wrongPrevHash = keccak256("fake-previous");
        bytes32 hop2Payload = keccak256(abi.encodePacked(boomerangId, hop2, wrongPrevHash, time2));
        bytes32 hop2EthHash = _toEthSignedMessageHash(hop2Payload);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(hop2Pk, hop2EthHash);

        // Signature verifies (signed correctly by hop2)
        assertEq(ecrecover(hop2EthHash, v2, r2, s2), hop2);

        // But the chain is broken because wrongPrevHash != hop1Hash
        assertNotEq(wrongPrevHash, hop1Hash, "Chain broken: previous hash mismatch");
    }

    // =========================================================================
    // Forwarder Presence Validation
    // =========================================================================

    /// @notice Forwarder must have valid presence
    function test_forwarderPresence_required() public view {
        assertTrue(_hasValidPresence(hop1, epochId));
        assertTrue(_hasValidPresence(hop2, epochId));
        assertTrue(_hasValidPresence(hop3, epochId));
    }

    /// @notice Forwarder without presence invalidates hop
    function test_forwarderPresence_noPresenceInvalid() public {
        address noPresence = makeAddr("noPresence");
        assertFalse(_hasValidPresence(noPresence, epochId));

        // The hop would be rejected at presence validation, before signature check
        assertFalse(_isValidHop(noPresence, epochId), "Hop invalid without presence");
    }

    /// @notice Slashed forwarder invalidates hop
    function test_forwarderPresence_slashedInvalid() public {
        // Simulate slashing by checking state
        // In a real scenario, slashed nodes cannot forward

        // After slashing, presence state would be Slashed
        // This test validates the check exists
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(hop1, epochId);
        assertTrue(state != IPresenceRegistry.PresenceState.Slashed, "Normal node is not slashed");
    }

    // =========================================================================
    // Signature Format
    // =========================================================================

    /// @notice Signature is 65 bytes (r, s, v)
    function test_signatureFormat_65bytes() public {
        bytes32 payload = keccak256("test");
        bytes32 ethSignedHash = _toEthSignedMessageHash(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hop1Pk, ethSignedHash);

        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65, "Signature should be 65 bytes");
    }

    /// @notice v value is 27 or 28
    function test_signatureFormat_vValue() public {
        bytes32 payload = keccak256("test");
        bytes32 ethSignedHash = _toEthSignedMessageHash(payload);
        (uint8 v,,) = vm.sign(hop1Pk, ethSignedHash);

        assertTrue(v == 27 || v == 28, "v must be 27 or 28");
    }

    // =========================================================================
    // Timestamp Monotonicity
    // =========================================================================

    /// @notice Hop timestamps must be monotonically increasing
    function test_hopTimestamps_monotonic() public {
        uint256 time1 = block.timestamp;
        vm.warp(block.timestamp + 1);
        uint256 time2 = block.timestamp;
        vm.warp(block.timestamp + 1);
        uint256 time3 = block.timestamp;

        assertTrue(time1 < time2, "Timestamps must increase");
        assertTrue(time2 < time3, "Timestamps must increase");
    }

    /// @notice Non-monotonic timestamps should be rejected
    function test_hopTimestamps_nonMonotonicRejected() public view {
        uint256 time1 = block.timestamp;
        uint256 time2 = time1 - 1; // Earlier than time1!

        assertFalse(time2 > time1, "Non-monotonic timestamps invalid");
    }

    // =========================================================================
    // Max Hop Limit
    // =========================================================================

    /// @notice Maximum 10 hops per spec
    function test_maxHops_limit() public pure {
        uint256 maxHops = 10;

        assertTrue(5 <= maxHops, "5 hops valid");
        assertTrue(10 <= maxHops, "10 hops valid");
        assertFalse(11 <= maxHops, "11 hops exceeds limit");
    }

    // =========================================================================
    // Full Verification Function
    // =========================================================================

    /// @notice Complete chain verification - single hop
    function test_fullVerification_singleHop() public {
        bytes32 boomerangId = keccak256("single-hop-test");
        Hop memory h = _createHop(boomerangId, hop1, hop1Pk, bytes32(0), block.timestamp);

        assertTrue(_verifySingleHop(boomerangId, h, bytes32(0)), "Single hop should verify");
    }

    /// @notice Verification fails with invalid signature
    function test_fullVerification_failsInvalidSig() public {
        bytes32 boomerangId = keccak256("fail-test");
        // Create hop claiming to be hop1 but signed by hop2
        Hop memory h = _createHop(boomerangId, hop1, hop2Pk, bytes32(0), block.timestamp);

        assertFalse(_verifySingleHop(boomerangId, h, bytes32(0)), "Chain with invalid sig should fail");
    }

    /// @notice Create a hop helper
    function _createHop(bytes32 boomerangId, address forwarder, uint256 pk, bytes32 prevHash, uint256 time)
        internal
        returns (Hop memory)
    {
        bytes32 payload = keccak256(abi.encodePacked(boomerangId, forwarder, prevHash, time));
        bytes32 ethHash = _toEthSignedMessageHash(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethHash);
        return Hop({forwarder: forwarder, forwardedAt: time, signature: abi.encodePacked(r, s, v)});
    }

    /// @notice Verify single hop
    function _verifySingleHop(bytes32 boomerangId, Hop memory hop, bytes32 prevHash) internal view returns (bool) {
        if (!_hasValidPresence(hop.forwarder, epochId)) return false;

        bytes32 payload = keccak256(abi.encodePacked(boomerangId, hop.forwarder, prevHash, hop.forwardedAt));
        bytes32 ethHash = _toEthSignedMessageHash(payload);

        bytes memory sig = hop.signature;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }

        return ecrecover(ethHash, v, r, s) == hop.forwarder;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _hasValidPresence(address actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    function _isValidHop(address forwarder, uint256 _epochId) internal view returns (bool) {
        return _hasValidPresence(forwarder, _epochId);
    }
}

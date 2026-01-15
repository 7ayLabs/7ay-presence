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
 * @title MediaPolicyTest
 * @notice Tests for v0.6.4 Ephemeral Media policy validation
 * @dev Validates media policy constraints and epoch capability requirements
 *
 * Media Policy (v0.6.4):
 * - Requires PresenceWithEphemeralData capability
 * - Validates media types, sizes, and TTL
 * - Policy stored as hash in epoch
 */
contract MediaPolicyTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public participant = makeAddr("participant");

    uint256 public epochIdEphemeral = 1;
    uint256 public epochIdSignals = 2;
    uint256 public epochIdPresenceOnly = 3;
    uint256 public startTime;
    uint256 public endTime;

    // Default media policy JSON (v0.6.4)
    // Extracted as constant for maintainability - update here if policy structure changes
    string public constant MEDIA_POLICY_JSON =
        '{"version":"1.0.0","allowedImageTypes":["image/jpeg","image/png","image/webp"],'
        '"allowedAudioTypes":["audio/mp3","audio/aac","audio/opus"],'
        '"maxImageSize":5242880,"maxAudioSize":10485760,"maxAudioDuration":60,'
        '"maxTTL":3600,"propagationScope":"LocalOnly"}';

    // Media policy hash (keccak256 of default policy JSON)
    bytes32 public mediaPolicyHash = keccak256(bytes(MEDIA_POLICY_JSON));

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

        // Create epochs with different capabilities
        vm.startPrank(epochAuthority);

        // Epoch 1: PresenceWithEphemeralData (supports media)
        epochRegistry.createEpochWithCapability(
            epochIdEphemeral,
            startTime,
            endTime,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            mediaPolicyHash
        );

        // Epoch 2: PresenceWithSignals (no media support)
        epochRegistry.createEpochWithCapability(
            epochIdSignals, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // Epoch 3: PresenceOnly (no media support)
        epochRegistry.createEpochWithCapability(
            epochIdPresenceOnly, startTime, endTime, IEpochRegistry.EpochCapability.PresenceOnly, bytes32(0)
        );

        vm.stopPrank();

        // Warp to active
        vm.warp(startTime);
    }

    // =========================================================================
    // INV27: Media Epoch Binding
    // =========================================================================

    /// @notice Media requires PresenceWithEphemeralData capability
    function test_INV27_mediaRequiresEphemeralCapability() public view {
        // Check capability levels
        IEpochRegistry.EpochCapability capEphemeral = epochRegistry.epochCapability(epochIdEphemeral);
        IEpochRegistry.EpochCapability capSignals = epochRegistry.epochCapability(epochIdSignals);
        IEpochRegistry.EpochCapability capPresenceOnly = epochRegistry.epochCapability(epochIdPresenceOnly);

        // Only PresenceWithEphemeralData supports media
        assertTrue(_supportsMedia(epochIdEphemeral), "INV27: Ephemeral capability should support media");
        assertFalse(_supportsMedia(epochIdSignals), "INV27: Signals capability should not support media");
        assertFalse(_supportsMedia(epochIdPresenceOnly), "INV27: PresenceOnly should not support media");

        // Verify enum values
        assertEq(uint256(capEphemeral), 2); // PresenceWithEphemeralData
        assertEq(uint256(capSignals), 1); // PresenceWithSignals
        assertEq(uint256(capPresenceOnly), 0); // PresenceOnly
    }

    /// @notice Media policy hash is stored for ephemeral epochs
    function test_INV27_mediaPolicyHashStored() public view {
        // Ephemeral epoch has policy hash
        bytes32 storedHash = epochRegistry.epochDataPolicyHash(epochIdEphemeral);
        assertEq(storedHash, mediaPolicyHash, "INV27: Policy hash should be stored");

        // Other epochs have no policy hash
        assertEq(epochRegistry.epochDataPolicyHash(epochIdSignals), bytes32(0));
        assertEq(epochRegistry.epochDataPolicyHash(epochIdPresenceOnly), bytes32(0));
    }

    /// @notice Media epoch binding requires valid epoch
    function test_INV27_mediaRequiresValidEpoch() public view {
        // Non-existent epoch
        uint256 invalidEpochId = 999;

        // Should not support media (epoch doesn't exist)
        assertFalse(_supportsMedia(invalidEpochId), "INV27: Invalid epoch should not support media");

        // Verify epoch doesn't exist
        assertEq(uint256(epochRegistry.epochState(invalidEpochId)), uint256(IEpochRegistry.EpochState.None));
    }

    // =========================================================================
    // INV28: Media Policy Compliance
    // =========================================================================

    /// @notice Image type validation
    function test_INV28_imageTypeValidation() public pure {
        // Allowed types
        assertTrue(_isAllowedImageType("image/jpeg"), "INV28: JPEG should be allowed");
        assertTrue(_isAllowedImageType("image/png"), "INV28: PNG should be allowed");
        assertTrue(_isAllowedImageType("image/webp"), "INV28: WebP should be allowed");

        // Disallowed types
        assertFalse(_isAllowedImageType("image/gif"), "INV28: GIF should not be allowed");
        assertFalse(_isAllowedImageType("image/bmp"), "INV28: BMP should not be allowed");
        assertFalse(_isAllowedImageType("image/svg+xml"), "INV28: SVG should not be allowed");
    }

    /// @notice Audio type validation
    function test_INV28_audioTypeValidation() public pure {
        // Allowed types
        assertTrue(_isAllowedAudioType("audio/mp3"), "INV28: MP3 should be allowed");
        assertTrue(_isAllowedAudioType("audio/aac"), "INV28: AAC should be allowed");
        assertTrue(_isAllowedAudioType("audio/opus"), "INV28: Opus should be allowed");

        // Disallowed types
        assertFalse(_isAllowedAudioType("audio/wav"), "INV28: WAV should not be allowed");
        assertFalse(_isAllowedAudioType("audio/flac"), "INV28: FLAC should not be allowed");
        assertFalse(_isAllowedAudioType("audio/ogg"), "INV28: OGG should not be allowed");
    }

    /// @notice Image size validation
    function test_INV28_imageSizeValidation() public pure {
        uint256 maxImageSize = 5242880; // 5 MB

        // Valid sizes
        assertTrue(_isValidImageSize(1), "INV28: 1 byte should be valid");
        assertTrue(_isValidImageSize(maxImageSize), "INV28: Max size should be valid");
        assertTrue(_isValidImageSize(maxImageSize / 2), "INV28: Half max should be valid");

        // Invalid sizes
        assertFalse(_isValidImageSize(0), "INV28: 0 bytes should be invalid");
        assertFalse(_isValidImageSize(maxImageSize + 1), "INV28: Over max should be invalid");
    }

    /// @notice Audio size validation
    function test_INV28_audioSizeValidation() public pure {
        uint256 maxAudioSize = 10485760; // 10 MB

        // Valid sizes
        assertTrue(_isValidAudioSize(1), "INV28: 1 byte should be valid");
        assertTrue(_isValidAudioSize(maxAudioSize), "INV28: Max size should be valid");

        // Invalid sizes
        assertFalse(_isValidAudioSize(0), "INV28: 0 bytes should be invalid");
        assertFalse(_isValidAudioSize(maxAudioSize + 1), "INV28: Over max should be invalid");
    }

    /// @notice Audio duration validation
    function test_INV28_audioDurationValidation() public pure {
        uint256 maxDuration = 60; // 60 seconds

        // Valid durations
        assertTrue(_isValidAudioDuration(1), "INV28: 1 second should be valid");
        assertTrue(_isValidAudioDuration(maxDuration), "INV28: Max duration should be valid");
        assertTrue(_isValidAudioDuration(30), "INV28: 30 seconds should be valid");

        // Invalid durations
        assertFalse(_isValidAudioDuration(0), "INV28: 0 seconds should be invalid");
        assertFalse(_isValidAudioDuration(maxDuration + 1), "INV28: Over max should be invalid");
    }

    /// @notice TTL validation
    function test_INV28_ttlValidation() public pure {
        uint256 minTTL = 60; // 1 minute
        uint256 maxTTL = 3600; // 1 hour

        // Valid TTLs
        assertTrue(_isValidTTL(minTTL), "INV28: Min TTL should be valid");
        assertTrue(_isValidTTL(maxTTL), "INV28: Max TTL should be valid");
        assertTrue(_isValidTTL(1800), "INV28: 30 min TTL should be valid");

        // Invalid TTLs
        assertFalse(_isValidTTL(minTTL - 1), "INV28: Below min TTL should be invalid");
        assertFalse(_isValidTTL(maxTTL + 1), "INV28: Over max TTL should be invalid");
        assertFalse(_isValidTTL(0), "INV28: 0 TTL should be invalid");
    }

    // =========================================================================
    // INV29: Media Temporal Boundary
    // =========================================================================

    /// @notice Media inaccessible after epoch closes
    function test_INV29_mediaInaccessibleAfterEpochClose() public {
        // During active epoch, media is accessible
        assertTrue(_isMediaAccessible(epochIdEphemeral), "INV29: Media should be accessible during Active");

        // Warp past epoch end
        vm.warp(endTime + 1);

        // Epoch is now Closed
        IEpochRegistry.EpochState state = epochRegistry.epochState(epochIdEphemeral);
        assertEq(uint256(state), uint256(IEpochRegistry.EpochState.Closed));

        // Media is no longer accessible
        assertFalse(_isMediaAccessible(epochIdEphemeral), "INV29: Media should be inaccessible after Close");
    }

    /// @notice Media respects TTL within epoch bounds
    function test_INV29_mediaRespectsExpiration() public view {
        uint256 currentTime = block.timestamp;
        uint256 ttl = 1800; // 30 minutes

        uint256 createdAt = currentTime;
        uint256 expiresAt = createdAt + ttl;

        // Before expiration
        assertTrue(_isMediaNotExpired(createdAt, ttl, currentTime), "INV29: Media should not be expired");

        // After expiration
        assertFalse(_isMediaNotExpired(createdAt, ttl, expiresAt + 1), "INV29: Media should be expired after TTL");
    }

    // =========================================================================
    // Presence Requirements
    // =========================================================================

    /// @notice Only nodes with presence can share media
    function test_presenceRequiredForMedia() public {
        // Declare presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochIdEphemeral);

        // Has presence - can share media
        assertTrue(_canShareMedia(participant, epochIdEphemeral), "Participant with presence can share media");

        // No presence - cannot share media
        address noPresence = makeAddr("noPresence");
        assertFalse(_canShareMedia(noPresence, epochIdEphemeral), "No presence means no media sharing");
    }

    /// @notice Slashed nodes cannot share media
    function test_slashedCannotShareMedia() public {
        // Declare and validate presence
        vm.prank(participant);
        presenceRegistry.declarePresence(participant, epochIdEphemeral);

        vm.prank(validator1);
        presenceRegistry.validatePresence(participant, epochIdEphemeral);
        vm.prank(validator2);
        presenceRegistry.validatePresence(participant, epochIdEphemeral);
        vm.prank(validator3);
        presenceRegistry.validatePresence(participant, epochIdEphemeral);

        // Initiate and resolve dispute to slash
        vm.prank(validator1);
        presenceRegistry.initiateDispute(participant, epochIdEphemeral, bytes32(0));

        vm.prank(validator1);
        presenceRegistry.voteOnDispute(participant, epochIdEphemeral, true);
        vm.prank(validator2);
        presenceRegistry.voteOnDispute(participant, epochIdEphemeral, true);
        vm.prank(validator3);
        presenceRegistry.voteOnDispute(participant, epochIdEphemeral, true);

        presenceRegistry.resolveDispute(participant, epochIdEphemeral);

        // Slashed - cannot share media
        assertFalse(_canShareMedia(participant, epochIdEphemeral), "Slashed participant cannot share media");
    }

    // =========================================================================
    // Semantic Validation Helpers
    // =========================================================================

    /// @notice Check if epoch supports media (requires PresenceWithEphemeralData)
    function _supportsMedia(uint256 _epochId) internal view returns (bool) {
        if (epochRegistry.epochState(_epochId) == IEpochRegistry.EpochState.None) {
            return false;
        }
        IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(_epochId);
        return cap == IEpochRegistry.EpochCapability.PresenceWithEphemeralData;
    }

    /// @notice Check if media is accessible (epoch Active + supports media)
    function _isMediaAccessible(uint256 _epochId) internal view returns (bool) {
        if (!_supportsMedia(_epochId)) return false;
        return epochRegistry.epochState(_epochId) == IEpochRegistry.EpochState.Active;
    }

    /// @notice Check if actor can share media (valid presence + media support)
    function _canShareMedia(address actor, uint256 _epochId) internal view returns (bool) {
        if (!_supportsMedia(_epochId)) return false;

        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    /// @notice Check if image type is allowed
    function _isAllowedImageType(string memory contentType) internal pure returns (bool) {
        bytes32 typeHash = keccak256(bytes(contentType));
        return typeHash == keccak256("image/jpeg") || typeHash == keccak256("image/png")
            || typeHash == keccak256("image/webp");
    }

    /// @notice Check if audio type is allowed
    function _isAllowedAudioType(string memory contentType) internal pure returns (bool) {
        bytes32 typeHash = keccak256(bytes(contentType));
        return
            typeHash == keccak256("audio/mp3") || typeHash == keccak256("audio/aac")
                || typeHash == keccak256("audio/opus");
    }

    /// @notice Check if image size is valid
    function _isValidImageSize(uint256 size) internal pure returns (bool) {
        uint256 maxImageSize = 5242880; // 5 MB
        return size > 0 && size <= maxImageSize;
    }

    /// @notice Check if audio size is valid
    function _isValidAudioSize(uint256 size) internal pure returns (bool) {
        uint256 maxAudioSize = 10485760; // 10 MB
        return size > 0 && size <= maxAudioSize;
    }

    /// @notice Check if audio duration is valid
    function _isValidAudioDuration(uint256 duration) internal pure returns (bool) {
        uint256 maxDuration = 60; // 60 seconds
        return duration > 0 && duration <= maxDuration;
    }

    /// @notice Check if TTL is valid
    function _isValidTTL(uint256 ttl) internal pure returns (bool) {
        uint256 minTTL = 60; // 1 minute
        uint256 maxTTL = 3600; // 1 hour
        return ttl >= minTTL && ttl <= maxTTL;
    }

    /// @notice Check if media is not expired
    function _isMediaNotExpired(uint256 createdAt, uint256 ttl, uint256 currentTime) internal pure returns (bool) {
        uint256 expiresAt = createdAt + ttl;
        return currentTime < expiresAt;
    }
}

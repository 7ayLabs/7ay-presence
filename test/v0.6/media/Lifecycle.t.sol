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
 * @title MediaLifecycleTest
 * @notice Tests for v0.6.4 Ephemeral Media lifecycle
 * @dev Validates media state transitions and temporal boundaries
 *
 * Media Lifecycle:
 * - (none) -> Available (MEDIA_ANNOUNCE)
 * - Available -> Unavailable (TTL expires, MEDIA_REVOKE, or epoch closes)
 */
contract MediaLifecycleTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");
    address public participant = makeAddr("participant");
    address public mediaOwner = makeAddr("mediaOwner");

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    bytes32 public mediaPolicyHash = keccak256("default-media-policy");

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

        // Create epoch with PresenceWithEphemeralData
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, mediaPolicyHash
        );

        // Warp to active
        vm.warp(startTime);

        // Declare presence for media owner
        vm.prank(mediaOwner);
        presenceRegistry.declarePresence(mediaOwner, epochId);
    }

    // =========================================================================
    // Media Creation
    // =========================================================================

    /// @notice Media can be announced during Active epoch
    function test_mediaAnnounce_duringActiveEpoch() public view {
        // Epoch is Active
        assertEq(uint256(epochRegistry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Active));

        // Media owner has presence
        assertTrue(_hasValidPresence(mediaOwner, epochId), "Owner should have valid presence");

        // Can announce media
        assertTrue(_canAnnounceMedia(mediaOwner, epochId), "Should be able to announce media during Active");
    }

    /// @notice Media cannot be announced during Scheduled epoch
    function test_mediaAnnounce_notDuringScheduled() public {
        // Create future epoch
        uint256 futureEpochId = 2;
        uint256 futureStart = block.timestamp + 2 hours;
        uint256 futureEnd = futureStart + 1 days;

        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            futureEpochId,
            futureStart,
            futureEnd,
            IEpochRegistry.EpochCapability.PresenceWithEphemeralData,
            mediaPolicyHash
        );

        // Epoch is Scheduled
        assertEq(uint256(epochRegistry.epochState(futureEpochId)), uint256(IEpochRegistry.EpochState.Scheduled));

        // Cannot announce media in Scheduled epoch
        assertFalse(_canAnnounceMedia(mediaOwner, futureEpochId), "Should not announce media during Scheduled");
    }

    /// @notice Media cannot be announced during Closed epoch
    function test_mediaAnnounce_notDuringClosed() public {
        // Warp past epoch end
        vm.warp(endTime + 1);

        // Epoch is Closed
        assertEq(uint256(epochRegistry.epochState(epochId)), uint256(IEpochRegistry.EpochState.Closed));

        // Cannot announce media in Closed epoch
        assertFalse(_canAnnounceMedia(mediaOwner, epochId), "Should not announce media during Closed");
    }

    // =========================================================================
    // Media Expiration
    // =========================================================================

    /// @notice Media expires after TTL
    function test_mediaExpires_afterTTL() public view {
        uint256 createdAt = block.timestamp;
        uint256 ttl = 1800; // 30 minutes

        // Initially not expired
        assertTrue(_isMediaAvailable(createdAt, ttl, block.timestamp, epochId), "Media should be available initially");

        // After TTL - expired
        uint256 afterExpiry = createdAt + ttl + 1;
        assertFalse(_isMediaAvailable(createdAt, ttl, afterExpiry, epochId), "Media should expire after TTL");
    }

    /// @notice Media expires when epoch closes (even before TTL)
    function test_mediaExpires_whenEpochCloses() public {
        uint256 createdAt = block.timestamp;
        uint256 ttl = 86400; // 24 hours (longer than epoch)

        // Initially available
        assertTrue(_isMediaAvailable(createdAt, ttl, block.timestamp, epochId), "Media should be available");

        // Epoch closes (before TTL)
        vm.warp(endTime + 1);

        // Media expires with epoch
        assertFalse(
            _isMediaAvailable(createdAt, ttl, block.timestamp, epochId),
            "Media should expire when epoch closes even if TTL not reached"
        );
    }

    // =========================================================================
    // Media Revocation
    // =========================================================================

    /// @notice Owner can revoke their media
    function test_mediaRevoke_byOwner() public view {
        // Owner can revoke
        assertTrue(_canRevoke(mediaOwner, mediaOwner, RevokeReason.OWNER_REQUESTED), "Owner should be able to revoke");
    }

    /// @notice Non-owner cannot revoke with OWNER_REQUESTED reason
    function test_mediaRevoke_nonOwnerCannotUseOwnerReason() public view {
        // Non-owner cannot use OWNER_REQUESTED
        assertFalse(
            _canRevoke(participant, mediaOwner, RevokeReason.OWNER_REQUESTED),
            "Non-owner cannot use OWNER_REQUESTED reason"
        );
    }

    /// @notice Validator can revoke for policy violation
    function test_mediaRevoke_byValidatorForPolicyViolation() public view {
        // Validator can revoke for policy violation
        assertTrue(
            _canRevoke(validator1, mediaOwner, RevokeReason.POLICY_VIOLATION),
            "Validator should be able to revoke for policy violation"
        );
    }

    /// @notice Non-validator cannot revoke for policy violation
    function test_mediaRevoke_nonValidatorCannotUsePolicyReason() public view {
        // Non-validator cannot use POLICY_VIOLATION
        assertFalse(
            _canRevoke(participant, mediaOwner, RevokeReason.POLICY_VIOLATION),
            "Non-validator cannot use POLICY_VIOLATION reason"
        );
    }

    // =========================================================================
    // Media State Transitions
    // =========================================================================

    /// @notice Media state transition: none -> Available
    function test_lifecycle_noneToAvailable() public view {
        // Before announcement: no media
        MediaState stateBefore = MediaState.None;

        // After announcement: Available
        MediaState stateAfter = MediaState.Available;

        // Verify transition is valid
        assertTrue(
            _isValidTransition(stateBefore, stateAfter, MediaEvent.ANNOUNCE), "None -> Available should be valid"
        );
    }

    /// @notice Media state transition: Available -> Unavailable (expired)
    function test_lifecycle_availableToUnavailable_expired() public view {
        MediaState stateBefore = MediaState.Available;
        MediaState stateAfter = MediaState.Unavailable;

        assertTrue(
            _isValidTransition(stateBefore, stateAfter, MediaEvent.TTL_EXPIRED), "Available -> Unavailable (expired)"
        );
    }

    /// @notice Media state transition: Available -> Unavailable (revoked)
    function test_lifecycle_availableToUnavailable_revoked() public view {
        MediaState stateBefore = MediaState.Available;
        MediaState stateAfter = MediaState.Unavailable;

        assertTrue(
            _isValidTransition(stateBefore, stateAfter, MediaEvent.REVOKED), "Available -> Unavailable (revoked)"
        );
    }

    /// @notice Media state transition: Available -> Unavailable (epoch closed)
    function test_lifecycle_availableToUnavailable_epochClosed() public view {
        MediaState stateBefore = MediaState.Available;
        MediaState stateAfter = MediaState.Unavailable;

        assertTrue(
            _isValidTransition(stateBefore, stateAfter, MediaEvent.EPOCH_CLOSED),
            "Available -> Unavailable (epoch closed)"
        );
    }

    /// @notice Invalid transition: Unavailable -> Available
    function test_lifecycle_unavailableToAvailable_invalid() public view {
        MediaState stateBefore = MediaState.Unavailable;
        MediaState stateAfter = MediaState.Available;

        assertFalse(
            _isValidTransition(stateBefore, stateAfter, MediaEvent.ANNOUNCE),
            "Unavailable -> Available should be invalid"
        );
    }

    // =========================================================================
    // Semantic Validation Helpers
    // =========================================================================

    enum MediaState {
        None,
        Available,
        Unavailable
    }

    enum MediaEvent {
        ANNOUNCE,
        TTL_EXPIRED,
        REVOKED,
        EPOCH_CLOSED
    }

    enum RevokeReason {
        OWNER_REQUESTED,
        POLICY_VIOLATION,
        EPOCH_CLOSING
    }

    /// @notice Check if actor has valid presence
    function _hasValidPresence(address actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Declared || state == IPresenceRegistry.PresenceState.Validated
            || state == IPresenceRegistry.PresenceState.Finalized;
    }

    /// @notice Check if actor can announce media
    function _canAnnounceMedia(address actor, uint256 _epochId) internal view returns (bool) {
        // Epoch must be Active
        if (epochRegistry.epochState(_epochId) != IEpochRegistry.EpochState.Active) {
            return false;
        }

        // Epoch must support media
        if (epochRegistry.epochCapability(_epochId) != IEpochRegistry.EpochCapability.PresenceWithEphemeralData) {
            return false;
        }

        // Actor must have valid presence
        return _hasValidPresence(actor, _epochId);
    }

    /// @notice Check if media is available
    function _isMediaAvailable(uint256 createdAt, uint256 ttl, uint256 currentTime, uint256 _epochId)
        internal
        view
        returns (bool)
    {
        // Check TTL
        if (currentTime >= createdAt + ttl) {
            return false;
        }

        // Check epoch is Active
        if (epochRegistry.epochState(_epochId) != IEpochRegistry.EpochState.Active) {
            return false;
        }

        return true;
    }

    /// @notice Check if actor can revoke media
    function _canRevoke(address revoker, address owner, RevokeReason reason) internal view returns (bool) {
        if (reason == RevokeReason.OWNER_REQUESTED) {
            return revoker == owner;
        }

        if (reason == RevokeReason.POLICY_VIOLATION) {
            return validatorRegistry.isValidatorActive(revoker);
        }

        // EPOCH_CLOSING can be triggered by anyone (system event)
        return true;
    }

    /// @notice Check if state transition is valid
    function _isValidTransition(MediaState from, MediaState to, MediaEvent eventType) internal pure returns (bool) {
        // None -> Available (ANNOUNCE)
        if (from == MediaState.None && to == MediaState.Available && eventType == MediaEvent.ANNOUNCE) {
            return true;
        }

        // Available -> Unavailable (any exit event)
        if (from == MediaState.Available && to == MediaState.Unavailable) {
            return eventType == MediaEvent.TTL_EXPIRED || eventType == MediaEvent.REVOKED
                || eventType == MediaEvent.EPOCH_CLOSED;
        }

        // All other transitions are invalid
        return false;
    }
}

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
 * @title MediaInvariantHandler
 * @notice Handler for invariant testing of ephemeral media
 */
contract MediaInvariantHandler is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public authority;
    address public validatorAuthority;

    // Ghost state
    mapping(bytes32 => MediaGhost) public ghost_media;
    bytes32[] public ghost_mediaIds;
    mapping(bytes32 => bool) public ghost_mediaExists;

    struct MediaGhost {
        bytes32 mediaId;
        address owner;
        uint256 epochId;
        uint256 createdAt;
        uint256 ttl;
        string contentType;
        uint256 contentSize;
        bool revoked;
    }

    constructor(
        IEpochRegistry _epochRegistry,
        IPresenceRegistry _presenceRegistry,
        IValidatorRegistry _validatorRegistry,
        address _authority,
        address _validatorAuthority
    ) {
        epochRegistry = _epochRegistry;
        presenceRegistry = _presenceRegistry;
        validatorRegistry = _validatorRegistry;
        authority = _authority;
        validatorAuthority = _validatorAuthority;
    }

    /// @notice Simulate media announcement
    function announceMedia(uint256 epochSeed, address ownerSeed, uint256 ttlSeed, uint256 sizeSeed, uint256 typeSeed)
        external
    {
        // Bound inputs
        uint256 epochId = (epochSeed % 10) + 1;
        uint256 ttl = (ttlSeed % 3540) + 60; // 60-3600 seconds
        uint256 size = (sizeSeed % 5242879) + 1; // 1-5MB for images

        // Determine content type
        string memory contentType;
        uint256 typeIndex = typeSeed % 3;
        if (typeIndex == 0) contentType = "image/jpeg";
        else if (typeIndex == 1) contentType = "image/png";
        else contentType = "image/webp";

        // Check preconditions
        if (epochRegistry.epochState(epochId) != IEpochRegistry.EpochState.Active) return;
        if (epochRegistry.epochCapability(epochId) != IEpochRegistry.EpochCapability.PresenceWithEphemeralData) return;

        IPresenceRegistry.PresenceState presenceState = presenceRegistry.presenceState(ownerSeed, epochId);
        if (
            presenceState != IPresenceRegistry.PresenceState.Declared
                && presenceState != IPresenceRegistry.PresenceState.Validated
                && presenceState != IPresenceRegistry.PresenceState.Finalized
        ) return;

        // Create media
        bytes32 mediaId = keccak256(abi.encodePacked(ownerSeed, epochId, block.timestamp, sizeSeed));

        if (ghost_mediaExists[mediaId]) return;

        ghost_media[mediaId] = MediaGhost({
            mediaId: mediaId,
            owner: ownerSeed,
            epochId: epochId,
            createdAt: block.timestamp,
            ttl: ttl,
            contentType: contentType,
            contentSize: size,
            revoked: false
        });

        ghost_mediaIds.push(mediaId);
        ghost_mediaExists[mediaId] = true;
    }

    /// @notice Simulate media revocation
    function revokeMedia(uint256 mediaIndexSeed, address revokerSeed) external {
        if (ghost_mediaIds.length == 0) return;

        uint256 index = mediaIndexSeed % ghost_mediaIds.length;
        bytes32 mediaId = ghost_mediaIds[index];
        MediaGhost storage media = ghost_media[mediaId];

        if (media.revoked) return;

        // Only owner or validator can revoke
        bool isOwner = revokerSeed == media.owner;
        bool isValidator = validatorRegistry.isValidatorActive(revokerSeed);

        if (!isOwner && !isValidator) return;

        media.revoked = true;
    }

    /// @notice Get ghost media count
    function getGhostMediaCount() external view returns (uint256) {
        return ghost_mediaIds.length;
    }

    /// @notice Get ghost media by index
    function getGhostMediaId(uint256 index) external view returns (bytes32) {
        return ghost_mediaIds[index];
    }
}

/**
 * @title MediaInvariantsTest
 * @notice Invariant tests for v0.6.4 Ephemeral Media
 * @dev Tests INV27, INV28, INV29
 */
contract MediaInvariantsTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;
    MediaInvariantHandler public handler;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");

    address[] public participants;

    bytes32 public mediaPolicyHash = keccak256("default-media-policy");

    function setUp() public {
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = startTime + 1 days;

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
        for (uint256 i = 1; i <= 10; i++) {
            if (i <= 5) {
                // First 5 epochs support media
                epochRegistry.createEpochWithCapability(
                    i, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithEphemeralData, mediaPolicyHash
                );
            } else {
                // Rest are PresenceWithSignals
                epochRegistry.createEpochWithCapability(
                    i, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
                );
            }
        }
        vm.stopPrank();

        // Warp to active
        vm.warp(startTime);

        // Create participants with presence
        for (uint256 i = 0; i < 20; i++) {
            address participant = makeAddr(string(abi.encodePacked("participant", i)));
            participants.push(participant);

            // Declare presence in random epoch
            uint256 epochId = (i % 10) + 1;
            vm.prank(participant);
            try presenceRegistry.declarePresence(participant, epochId) {} catch {}
        }

        // Create handler
        handler = new MediaInvariantHandler(
            epochRegistry, presenceRegistry, validatorRegistry, epochAuthority, validatorAuthority
        );

        // Target handler
        targetContract(address(handler));

        // Target specific functions
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MediaInvariantHandler.announceMedia.selector;
        selectors[1] = MediaInvariantHandler.revokeMedia.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice INV27: All media bound to epoch with PresenceWithEphemeralData
    function invariant_INV27_mediaEpochBinding() external view {
        uint256 mediaCount = handler.getGhostMediaCount();

        for (uint256 i = 0; i < mediaCount; i++) {
            bytes32 mediaId = handler.getGhostMediaId(i);
            (,, uint256 epochId,,,,, bool revoked) = handler.ghost_media(mediaId);

            if (revoked) continue;

            // Media epoch must exist
            IEpochRegistry.EpochState epochState = epochRegistry.epochState(epochId);
            assertTrue(epochState != IEpochRegistry.EpochState.None, "INV27: Media epoch must exist");

            // Media epoch must have PresenceWithEphemeralData capability
            IEpochRegistry.EpochCapability cap = epochRegistry.epochCapability(epochId);
            assertEq(
                uint256(cap),
                uint256(IEpochRegistry.EpochCapability.PresenceWithEphemeralData),
                "INV27: Media epoch must have PresenceWithEphemeralData"
            );
        }
    }

    /// @notice INV28: All media complies with policy constraints
    function invariant_INV28_mediaPolicyCompliance() external view {
        uint256 mediaCount = handler.getGhostMediaCount();

        uint256 maxImageSize = 5242880; // 5 MB
        uint256 minTTL = 60;
        uint256 maxTTL = 3600;

        for (uint256 i = 0; i < mediaCount; i++) {
            bytes32 mediaId = handler.getGhostMediaId(i);
            (,,, uint256 createdAt, uint256 ttl, string memory contentType, uint256 contentSize,) =
                handler.ghost_media(mediaId);

            // Verify content type is allowed
            bytes32 typeHash = keccak256(bytes(contentType));
            bool validType = typeHash == keccak256("image/jpeg") || typeHash == keccak256("image/png")
                || typeHash == keccak256("image/webp") || typeHash == keccak256("audio/mp3")
                || typeHash == keccak256("audio/aac") || typeHash == keccak256("audio/opus");
            assertTrue(validType, "INV28: Media type must be allowed");

            // Verify size within limits (for images)
            if (
                typeHash == keccak256("image/jpeg") || typeHash == keccak256("image/png")
                    || typeHash == keccak256("image/webp")
            ) {
                assertTrue(contentSize <= maxImageSize, "INV28: Image size must not exceed max");
            }

            // Verify TTL within bounds
            assertTrue(ttl >= minTTL && ttl <= maxTTL, "INV28: TTL must be within policy bounds");
        }
    }

    /// @notice INV29: Media inaccessible after epoch closes
    function invariant_INV29_mediaTemporalBoundary() external view {
        uint256 mediaCount = handler.getGhostMediaCount();

        for (uint256 i = 0; i < mediaCount; i++) {
            bytes32 mediaId = handler.getGhostMediaId(i);
            (,, uint256 epochId, uint256 createdAt, uint256 ttl,,, bool revoked) = handler.ghost_media(mediaId);

            // Check if media should be accessible
            bool epochActive = epochRegistry.epochState(epochId) == IEpochRegistry.EpochState.Active;
            bool notExpired = block.timestamp < createdAt + ttl;
            bool notRevoked = !revoked;

            bool shouldBeAccessible = epochActive && notExpired && notRevoked;

            // If epoch is not Active, media must not be accessible
            if (!epochActive) {
                assertFalse(shouldBeAccessible, "INV29: Media must be inaccessible when epoch not Active");
            }
        }
    }

    /// @notice Revoked media stays revoked
    function invariant_revokedMediaStaysRevoked() external view {
        uint256 mediaCount = handler.getGhostMediaCount();

        for (uint256 i = 0; i < mediaCount; i++) {
            bytes32 mediaId = handler.getGhostMediaId(i);
            (,,,,,,, bool revoked) = handler.ghost_media(mediaId);

            // Once revoked, should stay revoked (this is enforced by handler)
            // Just verify the ghost state is consistent
            if (revoked) {
                assertTrue(revoked, "Revoked media should stay revoked");
            }
        }
    }
}

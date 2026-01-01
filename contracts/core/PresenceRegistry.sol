// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PresenceRegistry
 * @author 7ayLabs
 * @notice Canonical registry for Proof of Presence (PoP)
 *
 * @dev This contract defines the canonical lifecycle of Presence
 *      as specified in `specs/presence.md` and `specs/model.md`.
 *
 *      It does NOT:
 *      - manage epochs lifecycle
 *      - perform validation logic
 *      - handle slashing penalties
 *
 *      It ONLY enforces presence state transitions and invariants.
 */
contract PresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    enum PresenceState {
        None,
        Declared,
        Validated,
        Finalized,
        Expired,
        Slashed
    }

    struct Presence {
        PresenceState state;
        uint256 epochId;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice actor => epochId => Presence
    mapping(address => mapping(uint256 => Presence)) private _presences;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PresenceDeclared(address indexed actor, uint256 indexed epochId);
    event PresenceValidated(address indexed actor, uint256 indexed epochId);
    event PresenceFinalized(address indexed actor, uint256 indexed epochId);
    event PresenceExpired(address indexed actor, uint256 indexed epochId);
    event PresenceSlashed(address indexed actor, uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PresenceAlreadyExists();
    error InvalidPresenceState();
    error PresenceNotDeclared();
    error PresenceNotValidated();

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the presence state for an actor in a given epoch
     */
    function presenceState(address actor, uint256 epochId)
        external
        view
        returns (PresenceState)
    {
        return _presences[actor][epochId].state;
    }

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Declare presence for the sender in a given epoch
     *
     * Requirements:
     * - No existing presence for the actor in the epoch
     */
    function declarePresence(uint256 epochId) external {
        Presence storage presence = _presences[msg.sender][epochId];

        if (presence.state != PresenceState.None) {
            revert PresenceAlreadyExists();
        }

        presence.state = PresenceState.Declared;
        presence.epochId = epochId;

        emit PresenceDeclared(msg.sender, epochId);
    }

    /**
     * @notice Mark a declared presence as validated
     *
     * @dev Validation authority is enforced externally
     */
    function validatePresence(address actor, uint256 epochId) external {
        Presence storage presence = _presences[actor][epochId];

        if (presence.state != PresenceState.Declared) {
            revert PresenceNotDeclared();
        }

        presence.state = PresenceState.Validated;

        emit PresenceValidated(actor, epochId);
    }

    /**
     * @notice Finalize a validated presence
     */
    function finalizePresence(address actor, uint256 epochId) external {
        Presence storage presence = _presences[actor][epochId];

        if (presence.state != PresenceState.Validated) {
            revert PresenceNotValidated();
        }

        presence.state = PresenceState.Finalized;

        emit PresenceFinalized(actor, epochId);
    }

    /**
     * @notice Expire a declared presence
     */
    function expirePresence(address actor, uint256 epochId) external {
        Presence storage presence = _presences[actor][epochId];

        if (presence.state != PresenceState.Declared) {
            revert InvalidPresenceState();
        }

        presence.state = PresenceState.Expired;

        emit PresenceExpired(actor, epochId);
    }

    /**
     * @notice Slash a presence due to protocol violation
     *
     * @dev Slashing authority is enforced externally
     */
    function slashPresence(address actor, uint256 epochId) external {
        Presence storage presence = _presences[actor][epochId];

        if (
            presence.state != PresenceState.Declared &&
            presence.state != PresenceState.Validated
        ) {
            revert InvalidPresenceState();
        }

        presence.state = PresenceState.Slashed;

        emit PresenceSlashed(actor, epochId);
    }
}
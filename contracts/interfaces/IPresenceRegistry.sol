// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPresenceRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the Proof of Presence registry
 *
 * @dev This interface defines the external contract of the Presence Registry
 *      as specified in `specs/presence.md` and `specs/model.md`.
 *
 *      Any implementation claiming compliance with the 7ay PoP protocol
 *      MUST implement this interface without deviations.
 */
interface IPresenceRegistry {
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

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PresenceDeclared(address indexed actor, uint256 indexed epochId);
    event PresenceValidated(address indexed actor, uint256 indexed epochId);
    event PresenceFinalized(address indexed actor, uint256 indexed epochId);
    event PresenceExpired(address indexed actor, uint256 indexed epochId);
    event PresenceSlashed(address indexed actor, uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the presence state for a given actor and epoch
     *
     * @param actor   The actor address
     * @param epochId The epoch identifier
     *
     * @return state The current presence state
     */
    function presenceState(address actor, uint256 epochId)
        external
        view
        returns (PresenceState state);

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Declare presence for the caller in a given epoch
     *
     * @param epochId The epoch identifier
     */
    function declarePresence(uint256 epochId) external;

    /**
     * @notice Validate a declared presence
     *
     * @param actor   The actor whose presence is validated
     * @param epochId The epoch identifier
     */
    function validatePresence(address actor, uint256 epochId) external;

    /**
     * @notice Finalize a validated presence
     *
     * @param actor   The actor whose presence is finalized
     * @param epochId The epoch identifier
     */
    function finalizePresence(address actor, uint256 epochId) external;

    /**
     * @notice Expire a declared presence
     *
     * @param actor   The actor whose presence is expired
     * @param epochId The epoch identifier
     */
    function expirePresence(address actor, uint256 epochId) external;

    /**
     * @notice Slash a presence due to protocol violation
     *
     * @param actor   The actor whose presence is slashed
     * @param epochId The epoch identifier
     */
    function slashPresence(address actor, uint256 epochId) external;
}
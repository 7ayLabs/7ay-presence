// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPresenceRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the 7ay Proof of Presence (PoP) MVP
 *
 * @dev
 * This interface defines the on-chain contract boundary for the
 * Proof of Presence MVP.
 *
 * Scope (MVP):
 * - Acceptance-only presence finalization
 * - Deterministic and idempotent behavior
 * - On-chain persistence limited to {None, Finalized}
 *
 * Out of Scope (future versions):
 * - Presence lifecycle states (Declared, Validated, Expired, Slashed)
 * - Validators, quorum, disputes, or slashing
 *
 * Any implementation claiming compliance with the 7ay PoP MVP
 * MUST implement this interface without deviation.
 */
interface IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    enum PresenceState {
        None,
        Finalized
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when caller attempts to finalize presence for a different actor
    /// @param caller The address that called the function
    /// @param actor The actor address passed as parameter
    error UnauthorizedActor(address caller, address actor);

    /// @notice Raised when an invalid epoch identifier is provided
    /// @param epochId The invalid epoch identifier
    error InvalidEpoch(uint256 epochId);

    /// @notice Raised when actor address is zero
    error InvalidActor();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PresenceFinalized(address indexed actor, uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the protocol version
     *
     * @return The semantic version string (e.g., "0.1.0")
     */
    function protocolVersion() external pure returns (string memory);

    /**
     * @notice Returns the presence state for a given actor and epoch
     *
     * @dev
     * This is a pure view function that reads directly from storage.
     * No validation is performed on inputs:
     * - address(0) returns PresenceState.None (no revert)
     * - epochId == 0 returns PresenceState.None (no revert)
     *
     * Rationale: View functions should not consume gas on validation.
     * Invalid inputs simply return the default state (None).
     *
     * @param actor   The actor address (address(0) returns None)
     * @param epochId The epoch identifier (0 returns None)
     *
     * @return state The current presence state
     */
    function presenceState(address actor, uint256 epochId) external view returns (PresenceState state);

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalize presence for an actor within a given epoch
     *
     * @dev
     * Protocol rules (MVP):
     * - MUST be called by the actor itself
     * - MUST be deterministic and idempotent
     * - MUST NOT modify any other actor or epoch state
     * - MUST emit {PresenceFinalized} exactly once per (actor, epoch)
     *
     * @param actor   The actor whose presence is finalized
     * @param epochId The epoch identifier
     */
    function finalizePresence(address actor, uint256 epochId) external;
}

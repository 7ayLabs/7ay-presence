// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEpochRegistry} from "./IEpochRegistry.sol";

/**
 * @title IPresenceRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the 7ay Proof of Presence (PoP) v0.3
 *
 * @dev
 * This interface defines the on-chain contract boundary for the
 * Proof of Presence protocol with Declaration Layer.
 *
 * Scope (v0.3):
 * - Presence declaration and finalization
 * - On-chain epoch validation via IEpochRegistry
 * - Deterministic and idempotent behavior
 * - On-chain persistence: {None, Declared, Finalized}
 *
 * Out of Scope:
 * - Presence lifecycle states (Validated, Expired, Slashed)
 * - Validators, quorum, disputes, or slashing
 *
 * Specification: specs/v0.3/presence.md
 */
interface IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    enum PresenceState {
        None,
        Declared,
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

    /// @notice Raised when epoch is not in Active state
    /// @param epochId The epoch identifier that is not active
    error EpochNotActive(uint256 epochId);

    /// @notice Raised when epoch registry address is invalid
    error InvalidEpochRegistry();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when presence is declared
    event PresenceDeclared(address indexed actor, uint256 indexed epochId);

    /// @notice Emitted when presence is finalized
    event PresenceFinalized(address indexed actor, uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the protocol version
     * @return The semantic version string (e.g., "0.3.0")
     */
    function protocolVersion() external pure returns (string memory);

    /**
     * @notice Returns the epoch registry
     * @return The IEpochRegistry contract
     */
    function epochRegistry() external view returns (IEpochRegistry);

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
     * @notice Declare presence for an actor within a given epoch
     *
     * @dev
     * Protocol rules (v0.3):
     * - MUST be called by the actor itself
     * - MUST validate epoch is Active via IEpochRegistry
     * - MUST be deterministic and idempotent
     * - MUST emit {PresenceDeclared} exactly once per (actor, epoch)
     *
     * @param actor   The actor declaring presence
     * @param epochId The epoch identifier
     */
    function declarePresence(address actor, uint256 epochId) external;

    /**
     * @notice Finalize presence for an actor within a given epoch
     *
     * @dev
     * Protocol rules (v0.3):
     * - MUST be called by the actor itself
     * - MUST validate epoch is Active via IEpochRegistry
     * - MUST be deterministic and idempotent
     * - MUST emit {PresenceFinalized} exactly once per (actor, epoch)
     * - Supports both None->Finalized (legacy) and Declared->Finalized paths
     *
     * @param actor   The actor whose presence is finalized
     * @param epochId The epoch identifier
     */
    function finalizePresence(address actor, uint256 epochId) external;
}

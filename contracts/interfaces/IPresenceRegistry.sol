// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEpochRegistry} from "./IEpochRegistry.sol";
import {IValidatorRegistry} from "./IValidatorRegistry.sol";

/**
 * @title IPresenceRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the 7ay Proof of Presence (PoP) v0.4
 *
 * @dev
 * This interface defines the on-chain contract boundary for the
 * Proof of Presence protocol with Validators, Disputes, and Slashing.
 *
 * Scope (v0.4):
 * - Presence declaration, validation, and finalization
 * - Validator quorum-based validation
 * - Dispute mechanism with slashing
 * - On-chain persistence: {None, Declared, Validated, Finalized, Slashed}
 *
 * Specification: specs/v0.4/presence.md
 */
interface IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Presence state enumeration
     */
    enum PresenceState {
        None, // 0 - No presence exists
        Declared, // 1 - Actor declared presence
        Validated, // 2 - Quorum validated presence
        Finalized, // 3 - Permanently recorded (terminal)
        Slashed // 4 - Invalidated due to dispute (terminal)
    }

    /**
     * @notice Dispute status enumeration
     */
    enum DisputeStatus {
        None, // 0 - No dispute exists
        Pending, // 1 - Dispute initiated, awaiting votes
        Upheld, // 2 - Dispute successful, presence slashed
        Rejected // 3 - Dispute failed, presence valid
    }

    /**
     * @notice Presence data structure
     * @param state Current presence state
     * @param declaredAt Block timestamp of declaration
     * @param validatedAt Block timestamp of validation
     * @param validationCount Number of validator approvals
     */
    struct Presence {
        PresenceState state;
        uint256 declaredAt;
        uint256 validatedAt;
        uint256 validationCount;
    }

    /**
     * @notice Dispute data structure
     * @param status Current dispute status
     * @param challenger Address that initiated the dispute
     * @param initiatedAt Block timestamp of dispute initiation
     * @param evidenceHash Hash of off-chain evidence
     * @param votesFor Votes to uphold dispute
     * @param votesAgainst Votes to reject dispute
     */
    struct Dispute {
        DisputeStatus status;
        address challenger;
        uint256 initiatedAt;
        bytes32 evidenceHash;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS (v0.3)
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when actor address is zero
    error InvalidActor();

    /// @notice Raised when caller attempts to act for a different actor
    /// @param caller The address that called the function
    /// @param actor The actor address passed as parameter
    error UnauthorizedActor(address caller, address actor);

    /// @notice Raised when an invalid epoch identifier is provided
    /// @param epochId The invalid epoch identifier
    error InvalidEpoch(uint256 epochId);

    /// @notice Raised when epoch is not in Active state
    /// @param epochId The epoch identifier that is not active
    error EpochNotActive(uint256 epochId);

    /// @notice Raised when epoch registry address is invalid
    error InvalidEpochRegistry();

    /*//////////////////////////////////////////////////////////////
                            ERRORS (v0.4)
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when validator registry address is invalid
    error InvalidValidatorRegistry();

    /// @notice Raised when presence is not in expected state for operation
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param current The current state
    /// @param expected The expected state
    error InvalidPresenceState(address actor, uint256 epochId, PresenceState current, PresenceState expected);

    /// @notice Raised when caller is not an active validator
    /// @param caller The caller address
    error CallerNotValidator(address caller);

    /// @notice Raised when presence has been slashed
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error PresenceSlashed(address actor, uint256 epochId);

    /// @notice Raised when validator has already voted for presence
    /// @param validator The validator address
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error ValidatorAlreadyVoted(address validator, address actor, uint256 epochId);

    /// @notice Raised when presence cannot be finalized
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error PresenceNotFinalizable(address actor, uint256 epochId);

    /// @notice Raised when dispute already exists
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error DisputeAlreadyExists(address actor, uint256 epochId);

    /// @notice Raised when dispute does not exist
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error DisputeNotFound(address actor, uint256 epochId);

    /// @notice Raised when dispute window has closed
    /// @param epochId The epoch identifier
    error DisputeWindowClosed(uint256 epochId);

    /// @notice Raised when dispute is not in pending state
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error DisputeNotPending(address actor, uint256 epochId);

    /// @notice Raised when validator has already voted on dispute
    /// @param validator The validator address
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    error ValidatorAlreadyVotedOnDispute(address validator, address actor, uint256 epochId);

    /// @notice Raised when dispute window is zero
    error InvalidDisputeWindow();

    /*//////////////////////////////////////////////////////////////
                            EVENTS (v0.3)
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when presence is declared
    event PresenceDeclared(address indexed actor, uint256 indexed epochId);

    /// @notice Emitted when presence is finalized
    event PresenceFinalized(address indexed actor, uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                            EVENTS (v0.4)
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a validator votes on presence validation
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param validator The validator that voted
    /// @param currentVotes Current vote count
    /// @param requiredVotes Required votes for quorum
    event PresenceValidationVote(
        address indexed actor,
        uint256 indexed epochId,
        address indexed validator,
        uint256 currentVotes,
        uint256 requiredVotes
    );

    /// @notice Emitted when presence reaches validation quorum
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param validatorCount Number of validators that voted
    event PresenceValidated(address indexed actor, uint256 indexed epochId, uint256 validatorCount);

    /// @notice Emitted when presence is slashed
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param challenger Address that initiated the dispute
    event PresenceSlashedEvent(address indexed actor, uint256 indexed epochId, address indexed challenger);

    /// @notice Emitted when a dispute is initiated
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param challenger Address initiating the dispute
    /// @param evidenceHash Hash of evidence
    event DisputeInitiated(
        address indexed actor, uint256 indexed epochId, address indexed challenger, bytes32 evidenceHash
    );

    /// @notice Emitted when a validator votes on a dispute
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param validator The validator that voted
    /// @param voteToUphold True if vote to uphold dispute
    event DisputeVote(address indexed actor, uint256 indexed epochId, address indexed validator, bool voteToUphold);

    /// @notice Emitted when a dispute is resolved
    /// @param actor The actor address
    /// @param epochId The epoch identifier
    /// @param outcome The dispute resolution outcome
    event DisputeResolved(address indexed actor, uint256 indexed epochId, DisputeStatus outcome);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the protocol version
     * @return The semantic version string (e.g., "0.4.0")
     */
    function protocolVersion() external pure returns (string memory);

    /**
     * @notice Returns the epoch registry
     * @return The IEpochRegistry contract
     */
    function epochRegistry() external view returns (IEpochRegistry);

    /**
     * @notice Returns the validator registry
     * @return The IValidatorRegistry contract
     */
    function validatorRegistry() external view returns (IValidatorRegistry);

    /**
     * @notice Returns the dispute window in seconds
     * @return The dispute window duration
     */
    function disputeWindow() external view returns (uint256);

    /**
     * @notice Returns the presence state for a given actor and epoch
     *
     * @dev
     * This is a pure view function that reads directly from storage.
     * No validation is performed on inputs.
     *
     * @param actor The actor address
     * @param epochId The epoch identifier
     * @return The current presence state
     */
    function presenceState(address actor, uint256 epochId) external view returns (PresenceState);

    /**
     * @notice Returns the full presence data for a given actor and epoch
     *
     * @param actor The actor address
     * @param epochId The epoch identifier
     * @return The presence data structure
     */
    function getPresence(address actor, uint256 epochId) external view returns (Presence memory);

    /**
     * @notice Returns the dispute data for a given actor and epoch
     *
     * @param actor The actor address
     * @param epochId The epoch identifier
     * @return The dispute data structure
     */
    function getDispute(address actor, uint256 epochId) external view returns (Dispute memory);

    /**
     * @notice Checks if a validator has voted for presence validation
     *
     * @param validator The validator address
     * @param actor The actor address
     * @param epochId The epoch identifier
     * @return True if validator has voted
     */
    function hasValidatorVotedForPresence(address validator, address actor, uint256 epochId)
        external
        view
        returns (bool);

    /**
     * @notice Checks if a validator has voted on a dispute
     *
     * @param validator The validator address
     * @param actor The actor address
     * @param epochId The epoch identifier
     * @return True if validator has voted on the dispute
     */
    function hasValidatorVotedOnDispute(address validator, address actor, uint256 epochId) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Declare presence for an actor within a given epoch
     *
     * @dev
     * Protocol rules (v0.4):
     * - MUST be called by the actor itself
     * - MUST validate epoch is Active via IEpochRegistry
     * - MUST be deterministic and idempotent
     * - MUST emit {PresenceDeclared} exactly once per (actor, epoch)
     *
     * @param actor The actor declaring presence
     * @param epochId The epoch identifier
     */
    function declarePresence(address actor, uint256 epochId) external;

    /**
     * @notice Validate a declared presence (validators only)
     *
     * @dev
     * Protocol rules (v0.4):
     * - MUST be called by an active validator
     * - MUST validate epoch is Active via IEpochRegistry
     * - MUST validate presence is in Declared state
     * - MUST emit {PresenceValidationVote} for each vote
     * - MUST emit {PresenceValidated} when quorum is reached
     *
     * @param actor The actor whose presence to validate
     * @param epochId The epoch identifier
     */
    function validatePresence(address actor, uint256 epochId) external;

    /**
     * @notice Finalize a validated presence
     *
     * @dev
     * Protocol rules (v0.4):
     * - Anyone can finalize a validated presence
     * - Epoch MUST be Closed or Finalized
     * - Presence MUST be in Validated state
     * - No pending dispute allowed
     * - MUST emit {PresenceFinalized} exactly once
     *
     * @param actor The actor whose presence to finalize
     * @param epochId The epoch identifier
     */
    function finalizePresence(address actor, uint256 epochId) external;

    /*//////////////////////////////////////////////////////////////
                        DISPUTE MECHANISM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiate a dispute against a declared/validated presence
     *
     * @dev
     * Protocol rules (v0.4):
     * - Anyone can initiate a dispute
     * - MUST be within dispute window
     * - Presence MUST be in Declared or Validated state
     * - No existing pending dispute allowed
     * - MUST emit {DisputeInitiated}
     *
     * @param actor The actor whose presence to dispute
     * @param epochId The epoch identifier
     * @param evidenceHash Hash of off-chain evidence
     */
    function initiateDispute(address actor, uint256 epochId, bytes32 evidenceHash) external;

    /**
     * @notice Vote on a pending dispute (validators only)
     *
     * @dev
     * Protocol rules (v0.4):
     * - MUST be called by an active validator
     * - Dispute MUST be in Pending state
     * - Validator MUST NOT have already voted
     * - MUST emit {DisputeVote}
     *
     * @param actor The actor whose presence is disputed
     * @param epochId The epoch identifier
     * @param upholdDispute True to uphold (slash), false to reject
     */
    function voteOnDispute(address actor, uint256 epochId, bool upholdDispute) external;

    /**
     * @notice Resolve a dispute after voting threshold met
     *
     * @dev
     * Protocol rules (v0.4):
     * - Anyone can call once quorum is met
     * - Dispute MUST be in Pending state
     * - MUST emit {DisputeResolved}
     * - If upheld: MUST emit {PresenceSlashedEvent}
     *
     * @param actor The actor whose presence is disputed
     * @param epochId The epoch identifier
     */
    function resolveDispute(address actor, uint256 epochId) external;
}

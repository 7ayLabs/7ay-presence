// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IValidatorRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the 7ay Validator Registry v0.4
 *
 * @dev
 * This interface defines the on-chain contract boundary for
 * validator management in the Proof of Presence protocol.
 *
 * Validators are the trust anchors that validate presence claims.
 * Without validators, presence assertions cannot reach consensus.
 *
 * Validator States:
 * - None: Validator has never been registered
 * - Active: Validator can validate presences and vote on disputes
 * - Removed: Validator was active but is now removed (terminal)
 *
 * Any implementation claiming compliance with the 7ay Validator specification
 * MUST implement this interface without deviation.
 *
 * Specification reference: specs/v0.4/validator.md
 */
interface IValidatorRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validator status enumeration
     */
    enum ValidatorStatus {
        None, // 0 - Never registered
        Active, // 1 - Can validate presences
        Removed // 2 - Previously active, now removed
    }

    /**
     * @notice Validator data structure
     * @param status Current validator status
     * @param registeredAt Block timestamp when registered
     * @param removedAt Block timestamp when removed (0 if active)
     */
    struct Validator {
        ValidatorStatus status;
        uint256 registeredAt;
        uint256 removedAt;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when validator address is zero
    error InvalidValidator();

    /// @notice Raised when caller is not the validator authority
    /// @param caller The address that attempted the operation
    /// @param authority The authorized address
    error UnauthorizedValidatorAuthority(address caller, address authority);

    /// @notice Raised when attempting to add an already existing validator
    /// @param validator The validator address that already exists
    error ValidatorAlreadyExists(address validator);

    /// @notice Raised when referencing a validator that does not exist
    /// @param validator The validator address that was not found
    error ValidatorNotFound(address validator);

    /// @notice Raised when operating on an inactive validator
    /// @param validator The validator address that is not active
    error ValidatorNotActive(address validator);

    /// @notice Raised when removal would drop below minimum validators
    /// @param current The current number of active validators
    /// @param required The minimum required validators
    error InsufficientValidators(uint256 current, uint256 required);

    /// @notice Raised when validator authority address is invalid (zero address)
    error InvalidValidatorAuthority();

    /// @notice Raised when quorum threshold is out of range (must be 1-100)
    /// @param threshold The invalid threshold value
    error InvalidQuorumThreshold(uint256 threshold);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a validator is added
    /// @param validator The validator address
    /// @param timestamp The block timestamp when added
    event ValidatorAdded(address indexed validator, uint256 timestamp);

    /// @notice Emitted when a validator is removed
    /// @param validator The validator address
    /// @param timestamp The block timestamp when removed
    event ValidatorRemoved(address indexed validator, uint256 timestamp);

    /// @notice Emitted when quorum threshold is updated
    /// @param oldThreshold The previous threshold value
    /// @param newThreshold The new threshold value
    event QuorumThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the validator authority address
     * @return The address authorized to manage validators
     */
    function validatorAuthority() external view returns (address);

    /**
     * @notice Returns the current quorum threshold percentage
     * @return The threshold value (1-100)
     */
    function quorumThreshold() external view returns (uint256);

    /**
     * @notice Returns the minimum number of validators required
     * @return The minimum validator count
     */
    function minimumValidators() external view returns (uint256);

    /**
     * @notice Returns the validator data
     *
     * @param validator The validator address
     * @return The validator data structure
     */
    function getValidator(address validator) external view returns (Validator memory);

    /**
     * @notice Returns the validator status
     *
     * @dev
     * This is a pure view function that reads directly from storage.
     * No validation is performed on inputs:
     * - address(0) returns ValidatorStatus.None (no revert)
     *
     * @param validator The validator address
     * @return The current validator status
     */
    function validatorStatus(address validator) external view returns (ValidatorStatus);

    /**
     * @notice Checks if a validator is currently active
     *
     * @dev Convenience function equivalent to validatorStatus(validator) == ValidatorStatus.Active
     *
     * @param validator The validator address
     * @return True if validator is active
     */
    function isValidatorActive(address validator) external view returns (bool);

    /**
     * @notice Returns the count of active validators
     * @return The number of currently active validators
     */
    function activeValidatorCount() external view returns (uint256);

    /**
     * @notice Returns all active validators
     *
     * @dev
     * This function may be gas-intensive for large validator sets.
     * Use with caution in on-chain contexts.
     *
     * @return Array of active validator addresses
     */
    function getActiveValidators() external view returns (address[] memory);

    /**
     * @notice Calculates the quorum size based on current active validators
     *
     * @dev
     * Quorum is calculated as: ceil(activeValidatorCount * quorumThreshold / 100)
     * Always returns at least 1.
     *
     * @return The number of votes required for quorum
     */
    function quorumSize() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new validator
     *
     * @dev
     * Protocol rules:
     * - MUST be called by validator authority
     * - MUST reject if validator == address(0)
     * - MUST reject if validator already exists
     * - MUST emit {ValidatorAdded}
     *
     * @param validator The address to add as validator
     */
    function addValidator(address validator) external;

    /**
     * @notice Removes an existing validator
     *
     * @dev
     * Protocol rules:
     * - MUST be called by validator authority
     * - MUST reject if validator == address(0)
     * - MUST reject if validator is not active
     * - MUST reject if removal would drop below minimumValidators
     * - MUST emit {ValidatorRemoved}
     *
     * @param validator The address to remove
     */
    function removeValidator(address validator) external;

    /**
     * @notice Updates the quorum threshold
     *
     * @dev
     * Protocol rules:
     * - MUST be called by validator authority
     * - MUST reject if threshold is 0 or > 100
     * - MUST emit {QuorumThresholdUpdated}
     *
     * @param threshold The new threshold value (1-100)
     */
    function setQuorumThreshold(uint256 threshold) external;
}

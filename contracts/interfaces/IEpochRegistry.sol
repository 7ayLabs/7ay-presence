// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IEpochRegistry
 * @author 7ayLabs
 * @notice Canonical interface for the 7ay Epoch Registry
 *
 * @dev
 * This interface defines the on-chain contract boundary for
 * epoch lifecycle management in the Proof of Presence protocol.
 *
 * An epoch is the fundamental temporal unit that bounds presence assertions.
 * Without epochs, presence has no temporal context.
 *
 * Epoch States:
 * - None: Epoch does not exist
 * - Scheduled: Epoch created but not yet active (block.timestamp < startTime)
 * - Active: Epoch accepting presence finalization (startTime <= block.timestamp < endTime)
 * - Closed: Epoch ended but not finalized (block.timestamp >= endTime)
 * - Finalized: Epoch permanently sealed (terminal state)
 *
 * Any implementation claiming compliance with the 7ay Epoch specification
 * MUST implement this interface without deviation.
 *
 * Specification reference: specs/epoch.md v0.2
 */
interface IEpochRegistry {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Epoch state enumeration
     * @dev State is computed dynamically from storage and block.timestamp
     */
    enum EpochState {
        None, // 0 - Epoch does not exist
        Scheduled, // 1 - Created but not yet active
        Active, // 2 - Accepting presence finalization
        Closed, // 3 - Ended but not finalized
        Finalized // 4 - Permanently sealed
    }

    /**
     * @notice Epoch data structure
     * @param startTime Unix timestamp when epoch becomes active
     * @param endTime Unix timestamp when epoch closes
     * @param finalized Whether the epoch has been permanently sealed
     * @param exists Whether the epoch has been created
     */
    struct Epoch {
        uint256 startTime;
        uint256 endTime;
        bool finalized;
        bool exists;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when attempting to create an epoch that already exists
    /// @param epochId The epoch identifier that already exists
    error EpochAlreadyExists(uint256 epochId);

    /// @notice Raised when referencing an epoch that does not exist
    /// @param epochId The epoch identifier that was not found
    error EpochNotFound(uint256 epochId);

    /// @notice Raised when attempting presence finalization outside active window
    /// @param epochId The epoch identifier that is not active
    error EpochNotActive(uint256 epochId);

    /// @notice Raised when attempting to modify a finalized epoch
    /// @param epochId The epoch identifier that is already finalized
    error EpochAlreadyFinalized(uint256 epochId);

    /// @notice Raised when epoch bounds are invalid
    /// @param startTime The invalid start time
    /// @param endTime The invalid end time
    error InvalidEpochBounds(uint256 startTime, uint256 endTime);

    /// @notice Raised when caller is not the epoch authority
    /// @param caller The address that attempted the operation
    /// @param authority The authorized address
    error UnauthorizedEpochAuthority(address caller, address authority);

    /// @notice Raised when epoch identifier is zero (reserved)
    error InvalidEpochId();

    /// @notice Raised when epoch is not in Closed state for finalization
    /// @param epochId The epoch identifier
    /// @param currentState The current state of the epoch
    error EpochNotClosed(uint256 epochId, EpochState currentState);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new epoch is created
    /// @param epochId The unique epoch identifier
    /// @param startTime Unix timestamp when epoch becomes active
    /// @param endTime Unix timestamp when epoch closes
    event EpochCreated(uint256 indexed epochId, uint256 startTime, uint256 endTime);

    /// @notice Emitted when an epoch transitions to Active state
    /// @param epochId The epoch identifier
    /// @dev MAY be emitted lazily on first interaction after startTime
    event EpochActivated(uint256 indexed epochId);

    /// @notice Emitted when an epoch transitions to Closed state
    /// @param epochId The epoch identifier
    /// @dev MAY be emitted lazily on first interaction after endTime
    event EpochClosed(uint256 indexed epochId);

    /// @notice Emitted when an epoch is permanently sealed
    /// @param epochId The epoch identifier
    event EpochFinalized(uint256 indexed epochId);

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the epoch authority address
     * @return The address authorized to manage epochs
     */
    function epochAuthority() external view returns (address);

    /**
     * @notice Returns the raw epoch data
     *
     * @dev
     * This returns the stored data without computing current state.
     * Use epochState() for the computed current state.
     *
     * @param epochId The epoch identifier
     * @return epoch The epoch data structure
     */
    function getEpoch(uint256 epochId) external view returns (Epoch memory epoch);

    /**
     * @notice Returns the computed current state of an epoch
     *
     * @dev
     * State is computed from stored data and block.timestamp:
     * - None: epoch.exists == false
     * - Scheduled: exists && block.timestamp < startTime
     * - Active: exists && startTime <= block.timestamp < endTime && !finalized
     * - Closed: exists && block.timestamp >= endTime && !finalized
     * - Finalized: exists && finalized
     *
     * @param epochId The epoch identifier
     * @return state The current epoch state
     */
    function epochState(uint256 epochId) external view returns (EpochState state);

    /**
     * @notice Checks if an epoch is currently active
     *
     * @dev Convenience function equivalent to epochState(epochId) == EpochState.Active
     *
     * @param epochId The epoch identifier
     * @return active True if epoch is in Active state
     */
    function isEpochActive(uint256 epochId) external view returns (bool active);

    /**
     * @notice Returns the epoch bounds
     *
     * @param epochId The epoch identifier
     * @return startTime Unix timestamp when epoch becomes active
     * @return endTime Unix timestamp when epoch closes
     */
    function epochBounds(uint256 epochId) external view returns (uint256 startTime, uint256 endTime);

    /*//////////////////////////////////////////////////////////////
                            EPOCH LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new epoch with defined bounds
     *
     * @dev
     * Protocol rules:
     * - MUST be called by epoch authority
     * - MUST reject if epochId == 0
     * - MUST reject if epoch already exists
     * - MUST reject if startTime >= endTime
     * - MUST emit {EpochCreated}
     *
     * @param epochId The unique epoch identifier
     * @param startTime Unix timestamp when epoch becomes active
     * @param endTime Unix timestamp when epoch closes
     */
    function createEpoch(uint256 epochId, uint256 startTime, uint256 endTime) external;

    /**
     * @notice Permanently seals an epoch
     *
     * @dev
     * Protocol rules:
     * - MUST be called by epoch authority
     * - MUST reject if epoch does not exist
     * - MUST reject if epoch is not in Closed state
     * - MUST reject if epoch is already finalized
     * - MUST emit {EpochFinalized}
     * - After finalization, no presence state in this epoch MAY change
     *
     * @param epochId The epoch identifier to finalize
     */
    function finalizeEpoch(uint256 epochId) external;
}

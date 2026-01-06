// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEpochRegistry} from "../interfaces/IEpochRegistry.sol";

/**
 * @title EpochRegistry
 * @author 7ayLabs
 * @notice Canonical on-chain registry for Epoch lifecycle management
 *
 * @dev
 * This contract is the reference implementation of the
 * Epoch Registry specification.
 *
 * An epoch is the fundamental temporal unit that bounds presence assertions.
 * This contract manages epoch creation, state transitions, and finalization.
 *
 * Epoch States (computed from storage + block.timestamp):
 * - None: Epoch does not exist
 * - Scheduled: Created but block.timestamp < startTime
 * - Active: startTime <= block.timestamp < endTime
 * - Closed: block.timestamp >= endTime && !finalized
 * - Finalized: Permanently sealed (terminal)
 *
 * Specification reference: specs/epoch.md v0.2
 */
contract EpochRegistry is IEpochRegistry {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The address authorized to manage epochs
    address public immutable epochAuthority;

    /// @notice epochId => Epoch data
    mapping(uint256 => Epoch) private _epochs;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the registry with an epoch authority
     * @param _authority The address authorized to manage epochs
     */
    constructor(address _authority) {
        if (_authority == address(0)) {
            revert InvalidEpochAuthority();
        }
        epochAuthority = _authority;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to epoch authority only
    modifier onlyAuthority() {
        if (msg.sender != epochAuthority) {
            revert UnauthorizedEpochAuthority(msg.sender, epochAuthority);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEpochRegistry
     */
    function getEpoch(uint256 epochId) external view override returns (Epoch memory epoch) {
        return _epochs[epochId];
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function epochState(uint256 epochId) public view override returns (EpochState state) {
        Epoch storage epoch = _epochs[epochId];

        if (!epoch.exists) {
            return EpochState.None;
        }

        if (epoch.finalized) {
            return EpochState.Finalized;
        }

        if (block.timestamp < epoch.startTime) {
            return EpochState.Scheduled;
        }

        if (block.timestamp < epoch.endTime) {
            return EpochState.Active;
        }

        return EpochState.Closed;
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function isEpochActive(uint256 epochId) external view override returns (bool active) {
        return epochState(epochId) == EpochState.Active;
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function epochBounds(uint256 epochId) external view override returns (uint256 startTime, uint256 endTime) {
        Epoch storage epoch = _epochs[epochId];
        return (epoch.startTime, epoch.endTime);
    }

    /*//////////////////////////////////////////////////////////////
                            EPOCH LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEpochRegistry
     */
    function createEpoch(uint256 epochId, uint256 startTime, uint256 endTime) external override onlyAuthority {
        // Validate epochId
        if (epochId == 0) {
            revert InvalidEpochId();
        }

        // Check epoch doesn't already exist
        if (_epochs[epochId].exists) {
            revert EpochAlreadyExists(epochId);
        }

        // Validate bounds
        if (startTime >= endTime) {
            revert InvalidEpochBounds(startTime, endTime);
        }

        // Create epoch
        _epochs[epochId] = Epoch({startTime: startTime, endTime: endTime, finalized: false, exists: true});

        emit EpochCreated(epochId, startTime, endTime);
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function finalizeEpoch(uint256 epochId) external override onlyAuthority {
        Epoch storage epoch = _epochs[epochId];

        // Check epoch exists
        if (!epoch.exists) {
            revert EpochNotFound(epochId);
        }

        // Check not already finalized
        if (epoch.finalized) {
            revert EpochAlreadyFinalized(epochId);
        }

        // Check epoch is in Closed state
        EpochState currentState = epochState(epochId);
        if (currentState != EpochState.Closed) {
            revert EpochNotClosed(epochId, currentState);
        }

        // Finalize
        epoch.finalized = true;

        emit EpochFinalized(epochId);
    }
}

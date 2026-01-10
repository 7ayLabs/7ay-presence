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
 * Epoch Capabilities (v0.5):
 * - PresenceOnly: Basic presence tracking (default)
 * - PresenceWithSignals: Presence + signal emission
 * - PresenceWithEphemeralData: Full ephemeral data support
 *
 * Specification reference: specs/v0.2/epoch.md, specs/v0.5/ephemeral.md
 */
contract EpochRegistry is IEpochRegistry {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The address authorized to manage epochs
    address public immutable epochAuthority;

    /// @notice epochId => Epoch data
    mapping(uint256 => Epoch) private _epochs;

    /// @notice epochId => EpochCapability (v0.5)
    mapping(uint256 => EpochCapability) private _epochCapabilities;

    /// @notice epochId => dataPolicyHash (v0.5)
    mapping(uint256 => bytes32) private _epochDataPolicyHashes;

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

    /**
     * @inheritdoc IEpochRegistry
     */
    function epochCapability(uint256 epochId) external view override returns (EpochCapability capability) {
        return _epochCapabilities[epochId];
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function epochDataPolicyHash(uint256 epochId) external view override returns (bytes32 hash) {
        return _epochDataPolicyHashes[epochId];
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function supportsEphemeralData(uint256 epochId) external view override returns (bool supported) {
        return _epochs[epochId].exists && _epochCapabilities[epochId] == EpochCapability.PresenceWithEphemeralData;
    }

    /*//////////////////////////////////////////////////////////////
                            EPOCH LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IEpochRegistry
     * @dev v0.4 compatible - defaults to PresenceOnly capability
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

        // Set default capability (v0.5)
        _epochCapabilities[epochId] = EpochCapability.PresenceOnly;
        // _epochDataPolicyHashes[epochId] defaults to bytes32(0)

        // Emit both events for v0.5 compatibility
        emit EpochCreatedV2(epochId, startTime, endTime, EpochCapability.PresenceOnly, bytes32(0));
        emit EpochCreated(epochId, startTime, endTime);
    }

    /**
     * @inheritdoc IEpochRegistry
     */
    function createEpochWithCapability(
        uint256 epochId,
        uint256 startTime,
        uint256 endTime,
        EpochCapability capability,
        bytes32 dataPolicyHash
    ) external override {
        // Error priority: 1-6 (inline, no modifiers)

        // 1. InvalidEpochId
        if (epochId == 0) {
            revert InvalidEpochId();
        }

        // 2. EpochAlreadyExists
        if (_epochs[epochId].exists) {
            revert EpochAlreadyExists(epochId);
        }

        // 3. InvalidEpochBounds
        if (startTime >= endTime) {
            revert InvalidEpochBounds(startTime, endTime);
        }

        // 4. InvalidCapability
        if (uint256(capability) > uint256(EpochCapability.PresenceWithEphemeralData)) {
            revert InvalidCapability();
        }

        // 5. InvalidDataPolicyHash (only for PresenceWithEphemeralData)
        if (capability == EpochCapability.PresenceWithEphemeralData && dataPolicyHash == bytes32(0)) {
            revert InvalidDataPolicyHash();
        }

        // 6. UnauthorizedEpochAuthority
        if (msg.sender != epochAuthority) {
            revert UnauthorizedEpochAuthority(msg.sender, epochAuthority);
        }

        // Create epoch (struct unchanged)
        _epochs[epochId] = Epoch({startTime: startTime, endTime: endTime, finalized: false, exists: true});

        // Store capability and policy in separate mappings
        _epochCapabilities[epochId] = capability;
        _epochDataPolicyHashes[epochId] = dataPolicyHash;

        // Emit both events
        emit EpochCreatedV2(epochId, startTime, endTime, capability, dataPolicyHash);
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

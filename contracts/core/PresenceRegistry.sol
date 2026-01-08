// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPresenceRegistry} from "../interfaces/IPresenceRegistry.sol";
import {IEpochRegistry} from "../interfaces/IEpochRegistry.sol";

/**
 * @title PresenceRegistry
 * @author 7ayLabs
 * @notice Canonical on-chain registry for Proof of Presence (PoP) v0.3
 *
 * @dev
 * Reference implementation with Declaration Layer.
 *
 * Scope (v0.3):
 * - Presence declaration and finalization
 * - On-chain epoch validation via IEpochRegistry
 * - On-chain persistence: {None, Declared, Finalized}
 *
 * Out of Scope:
 * - Presence lifecycle states (Validated, Expired, Slashed)
 * - Validation logic, disputes, slashing, or penalties
 *
 * Specification: specs/v0.3/presence.md
 */
contract PresenceRegistry is IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol version following semantic versioning
    string public constant PROTOCOL_VERSION = "0.3.0";

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPresenceRegistry
    IEpochRegistry public immutable epochRegistry;

    /// @notice actor => epochId => presence state
    mapping(address => mapping(uint256 => PresenceState)) private _presence;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the registry with an epoch registry
     * @param _epochRegistry The epoch registry contract address
     */
    constructor(IEpochRegistry _epochRegistry) {
        if (address(_epochRegistry) == address(0)) {
            revert InvalidEpochRegistry();
        }
        epochRegistry = _epochRegistry;
    }

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPresenceRegistry
     */
    function protocolVersion() external pure override returns (string memory) {
        return PROTOCOL_VERSION;
    }

    /**
     * @inheritdoc IPresenceRegistry
     * @dev No input validation - see IPresenceRegistry for rationale
     */
    function presenceState(address actor, uint256 epochId) external view override returns (PresenceState state) {
        return _presence[actor][epochId];
    }

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPresenceRegistry
     */
    function declarePresence(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > UnauthorizedActor > InvalidEpoch > EpochNotActive
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (actor != msg.sender) {
            revert UnauthorizedActor(msg.sender, actor);
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        if (!epochRegistry.isEpochActive(epochId)) {
            revert EpochNotActive(epochId);
        }

        // Idempotent: already Declared or Finalized = silent return
        PresenceState currentState = _presence[actor][epochId];
        if (currentState == PresenceState.Declared || currentState == PresenceState.Finalized) {
            return;
        }

        _presence[actor][epochId] = PresenceState.Declared;

        emit PresenceDeclared(actor, epochId);
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function finalizePresence(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > UnauthorizedActor > InvalidEpoch > EpochNotActive
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (actor != msg.sender) {
            revert UnauthorizedActor(msg.sender, actor);
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        if (!epochRegistry.isEpochActive(epochId)) {
            revert EpochNotActive(epochId);
        }

        // Idempotent finalization
        if (_presence[actor][epochId] == PresenceState.Finalized) {
            return;
        }

        // Supports both None->Finalized (legacy) and Declared->Finalized
        _presence[actor][epochId] = PresenceState.Finalized;

        emit PresenceFinalized(actor, epochId);
    }
}

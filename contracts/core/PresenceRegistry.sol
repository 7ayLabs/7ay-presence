// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPresenceRegistry } from "../interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistry
 * @author 7ayLabs
 * @notice Canonical on-chain registry for Proof of Presence (PoP) — MVP
 *
 * @dev
 * This contract is the canonical MVP implementation of the
 * Proof of Presence protocol.
 *
 * Scope (MVP):
 * - Acceptance-only presence finalization
 * - Deterministic and idempotent behavior
 * - On-chain persistence limited to {None, Finalized}
 *
 * Out of Scope:
 * - Presence lifecycle states (Declared, Validated, Expired, Slashed)
 * - Validation logic, disputes, slashing, or penalties
 * - Epoch lifecycle management
 *
 * All lifecycle and validation logic MUST live off-chain
 * or in future protocol versions.
 */
contract PresenceRegistry is IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol version following semantic versioning
    string public constant PROTOCOL_VERSION = "0.1.0";

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice actor => epochId => presence state
    mapping(address => mapping(uint256 => PresenceState)) private _presence;

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
     */
    function presenceState(
        address actor,
        uint256 epochId
    ) external view override returns (PresenceState state) {
        return _presence[actor][epochId];
    }

    /*//////////////////////////////////////////////////////////////
                        PRESENCE FINALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPresenceRegistry
     */
    function finalizePresence(address actor, uint256 epochId) external override {
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (actor != msg.sender) {
            revert UnauthorizedActor(msg.sender, actor);
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        // Idempotent finalization
        if (_presence[actor][epochId] == PresenceState.Finalized) {
            return;
        }

        _presence[actor][epochId] = PresenceState.Finalized;

        emit PresenceFinalized(actor, epochId);
    }
}
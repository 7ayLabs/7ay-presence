// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPresenceRegistry} from "../interfaces/IPresenceRegistry.sol";
import {IEpochRegistry} from "../interfaces/IEpochRegistry.sol";
import {IValidatorRegistry} from "../interfaces/IValidatorRegistry.sol";

/**
 * @title PresenceRegistry
 * @author 7ayLabs
 * @notice Canonical on-chain registry for Proof of Presence (PoP) v0.4
 *
 * @dev
 * Reference implementation with Validators, Disputes, and Slashing.
 *
 * Scope (v0.4):
 * - Presence declaration, validation, and finalization
 * - Validator quorum-based validation
 * - Dispute mechanism with slashing
 * - On-chain persistence: {None, Declared, Validated, Finalized, Slashed}
 *
 * Specification: specs/v0.4/presence.md
 */
contract PresenceRegistry is IPresenceRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol version following semantic versioning
    string public constant PROTOCOL_VERSION = "0.4.0";

    /// @notice Default dispute window (1 day)
    uint256 public constant DEFAULT_DISPUTE_WINDOW = 1 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPresenceRegistry
    IEpochRegistry public immutable override epochRegistry;

    /// @inheritdoc IPresenceRegistry
    IValidatorRegistry public immutable override validatorRegistry;

    /// @inheritdoc IPresenceRegistry
    uint256 public override disputeWindow;

    /// @notice actor => epochId => presence data
    mapping(address => mapping(uint256 => Presence)) private _presences;

    /// @notice actor => epochId => dispute data
    mapping(address => mapping(uint256 => Dispute)) private _disputes;

    /// @notice actor => epochId => validator => has voted for presence
    mapping(address => mapping(uint256 => mapping(address => bool))) private _presenceVotes;

    /// @notice actor => epochId => validator => has voted on dispute
    mapping(address => mapping(uint256 => mapping(address => bool))) private _disputeVotes;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the registry with dependencies
     * @param _epochRegistry The epoch registry contract address
     * @param _validatorRegistry The validator registry contract address
     * @param _disputeWindow The dispute window in seconds (0 for default)
     */
    constructor(IEpochRegistry _epochRegistry, IValidatorRegistry _validatorRegistry, uint256 _disputeWindow) {
        if (address(_epochRegistry) == address(0)) {
            revert InvalidEpochRegistry();
        }
        if (address(_validatorRegistry) == address(0)) {
            revert InvalidValidatorRegistry();
        }

        epochRegistry = _epochRegistry;
        validatorRegistry = _validatorRegistry;
        disputeWindow = _disputeWindow == 0 ? DEFAULT_DISPUTE_WINDOW : _disputeWindow;
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
    function presenceState(address actor, uint256 epochId) external view override returns (PresenceState) {
        return _presences[actor][epochId].state;
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function getPresence(address actor, uint256 epochId) external view override returns (Presence memory) {
        return _presences[actor][epochId];
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function getDispute(address actor, uint256 epochId) external view override returns (Dispute memory) {
        return _disputes[actor][epochId];
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function hasValidatorVotedForPresence(address validator, address actor, uint256 epochId)
        external
        view
        override
        returns (bool)
    {
        return _presenceVotes[actor][epochId][validator];
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function hasValidatorVotedOnDispute(address validator, address actor, uint256 epochId)
        external
        view
        override
        returns (bool)
    {
        return _disputeVotes[actor][epochId][validator];
    }

    /*//////////////////////////////////////////////////////////////
                        PRESENCE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPresenceRegistry
     */
    function declarePresence(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > UnauthorizedActor > InvalidEpoch > PresenceSlashed > EpochNotActive
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (actor != msg.sender) {
            revert UnauthorizedActor(msg.sender, actor);
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Presence storage presence = _presences[actor][epochId];

        if (presence.state == PresenceState.Slashed) {
            revert PresenceSlashed(actor, epochId);
        }

        if (!epochRegistry.isEpochActive(epochId)) {
            revert EpochNotActive(epochId);
        }

        // Idempotent: already declared or beyond = silent return
        if (presence.state != PresenceState.None) {
            return;
        }

        presence.state = PresenceState.Declared;
        presence.declaredAt = block.timestamp;

        emit PresenceDeclared(actor, epochId);
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function validatePresence(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > InvalidEpoch > PresenceSlashed > EpochNotActive > CallerNotValidator > InvalidPresenceState > ValidatorAlreadyVoted
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Presence storage presence = _presences[actor][epochId];

        if (presence.state == PresenceState.Slashed) {
            revert PresenceSlashed(actor, epochId);
        }

        if (!epochRegistry.isEpochActive(epochId)) {
            revert EpochNotActive(epochId);
        }

        if (!validatorRegistry.isValidatorActive(msg.sender)) {
            revert CallerNotValidator(msg.sender);
        }

        if (presence.state != PresenceState.Declared) {
            revert InvalidPresenceState(actor, epochId, presence.state, PresenceState.Declared);
        }

        if (_presenceVotes[actor][epochId][msg.sender]) {
            revert ValidatorAlreadyVoted(msg.sender, actor, epochId);
        }

        // Record vote
        _presenceVotes[actor][epochId][msg.sender] = true;
        presence.validationCount++;

        uint256 required = validatorRegistry.quorumSize();

        emit PresenceValidationVote(actor, epochId, msg.sender, presence.validationCount, required);

        // Check if quorum reached
        if (presence.validationCount >= required) {
            presence.state = PresenceState.Validated;
            presence.validatedAt = block.timestamp;

            emit PresenceValidated(actor, epochId, presence.validationCount);
        }
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function finalizePresence(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > InvalidEpoch > PresenceSlashed > PresenceNotFinalizable
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Presence storage presence = _presences[actor][epochId];

        if (presence.state == PresenceState.Slashed) {
            revert PresenceSlashed(actor, epochId);
        }

        // Idempotent: already finalized = silent return
        if (presence.state == PresenceState.Finalized) {
            return;
        }

        // Must be validated
        if (presence.state != PresenceState.Validated) {
            revert PresenceNotFinalizable(actor, epochId);
        }

        // Epoch must be Closed or Finalized
        IEpochRegistry.EpochState epochState = epochRegistry.epochState(epochId);
        if (epochState != IEpochRegistry.EpochState.Closed && epochState != IEpochRegistry.EpochState.Finalized) {
            revert PresenceNotFinalizable(actor, epochId);
        }

        // No pending dispute
        if (_disputes[actor][epochId].status == DisputeStatus.Pending) {
            revert PresenceNotFinalizable(actor, epochId);
        }

        presence.state = PresenceState.Finalized;

        emit PresenceFinalized(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE MECHANISM
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPresenceRegistry
     */
    function initiateDispute(address actor, uint256 epochId, bytes32 evidenceHash) external override {
        // Error priority: InvalidActor > InvalidEpoch > PresenceSlashed > DisputeAlreadyExists > DisputeWindowClosed > InvalidPresenceState
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Presence storage presence = _presences[actor][epochId];

        if (presence.state == PresenceState.Slashed) {
            revert PresenceSlashed(actor, epochId);
        }

        Dispute storage dispute = _disputes[actor][epochId];

        if (dispute.status == DisputeStatus.Pending) {
            revert DisputeAlreadyExists(actor, epochId);
        }

        // Check dispute window
        if (!_isWithinDisputeWindow(epochId)) {
            revert DisputeWindowClosed(epochId);
        }

        // Must be Declared or Validated
        if (presence.state != PresenceState.Declared && presence.state != PresenceState.Validated) {
            revert InvalidPresenceState(actor, epochId, presence.state, PresenceState.Declared);
        }

        dispute.status = DisputeStatus.Pending;
        dispute.challenger = msg.sender;
        dispute.initiatedAt = block.timestamp;
        dispute.evidenceHash = evidenceHash;
        dispute.votesFor = 0;
        dispute.votesAgainst = 0;

        emit DisputeInitiated(actor, epochId, msg.sender, evidenceHash);
    }

    /**
     * @inheritdoc IPresenceRegistry
     */
    function voteOnDispute(address actor, uint256 epochId, bool upholdDispute) external override {
        // Error priority: InvalidActor > InvalidEpoch > DisputeNotFound > CallerNotValidator > ValidatorAlreadyVotedOnDispute > DisputeNotPending
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Dispute storage dispute = _disputes[actor][epochId];

        if (dispute.status == DisputeStatus.None) {
            revert DisputeNotFound(actor, epochId);
        }

        if (!validatorRegistry.isValidatorActive(msg.sender)) {
            revert CallerNotValidator(msg.sender);
        }

        if (_disputeVotes[actor][epochId][msg.sender]) {
            revert ValidatorAlreadyVotedOnDispute(msg.sender, actor, epochId);
        }

        if (dispute.status != DisputeStatus.Pending) {
            revert DisputeNotPending(actor, epochId);
        }

        // Record vote
        _disputeVotes[actor][epochId][msg.sender] = true;

        if (upholdDispute) {
            dispute.votesFor++;
        } else {
            dispute.votesAgainst++;
        }

        emit DisputeVote(actor, epochId, msg.sender, upholdDispute);
    }

    /**
     * @inheritdoc IPresenceRegistry
     * @dev Resolution requires quorum votes. If quorum not met, returns silently without
     *      state change (idempotent). Ties (votesFor == votesAgainst) result in rejection,
     *      preserving the actor's presence - the challenger must prove their case.
     */
    function resolveDispute(address actor, uint256 epochId) external override {
        // Error priority: InvalidActor > InvalidEpoch > DisputeNotFound > DisputeNotPending
        if (actor == address(0)) {
            revert InvalidActor();
        }

        if (epochId == 0) {
            revert InvalidEpoch(epochId);
        }

        Dispute storage dispute = _disputes[actor][epochId];

        if (dispute.status == DisputeStatus.None) {
            revert DisputeNotFound(actor, epochId);
        }

        if (dispute.status != DisputeStatus.Pending) {
            revert DisputeNotPending(actor, epochId);
        }

        uint256 totalVotes = dispute.votesFor + dispute.votesAgainst;
        uint256 required = validatorRegistry.quorumSize();

        // Need quorum to resolve
        if (totalVotes < required) {
            return; // Silent return, not enough votes yet
        }

        // Majority vote determines outcome
        if (dispute.votesFor > dispute.votesAgainst) {
            // Uphold dispute - slash presence
            dispute.status = DisputeStatus.Upheld;
            _presences[actor][epochId].state = PresenceState.Slashed;

            emit DisputeResolved(actor, epochId, DisputeStatus.Upheld);
            emit PresenceSlashedEvent(actor, epochId, dispute.challenger);
        } else {
            // Reject dispute - presence remains valid
            dispute.status = DisputeStatus.Rejected;

            emit DisputeResolved(actor, epochId, DisputeStatus.Rejected);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if current time is within dispute window for an epoch
     * @param epochId The epoch identifier
     * @return True if within dispute window
     * @dev Design note: Active epochs allow disputes indefinitely. This is intentional as
     *      epochs should transition to Closed state via normal lifecycle. If an epoch is
     *      stuck in Active state, off-chain orchestration should handle the transition.
     */
    function _isWithinDisputeWindow(uint256 epochId) internal view returns (bool) {
        IEpochRegistry.EpochState state = epochRegistry.epochState(epochId);

        // Active epoch - disputes allowed
        if (state == IEpochRegistry.EpochState.Active) {
            return true;
        }

        // Closed epoch - check dispute window
        if (state == IEpochRegistry.EpochState.Closed) {
            (, uint256 endTime) = epochRegistry.epochBounds(epochId);
            return block.timestamp <= endTime + disputeWindow;
        }

        return false;
    }
}

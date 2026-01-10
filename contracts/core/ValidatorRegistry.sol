// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IValidatorRegistry} from "../interfaces/IValidatorRegistry.sol";

/**
 * @title ValidatorRegistry
 * @author 7ayLabs
 * @notice Canonical on-chain registry for Validator management v0.4
 *
 * @dev
 * This contract is the reference implementation of the
 * Validator Registry specification.
 *
 * Validators are the trust anchors that validate presence claims.
 * This contract manages validator registration, removal, and quorum.
 *
 * Validator States:
 * - None: Never registered
 * - Active: Can validate presences and vote on disputes
 * - Removed: Previously active, now removed (terminal)
 *
 * Specification reference: specs/v0.4/validator.md
 */
contract ValidatorRegistry is IValidatorRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum number of validators required
    uint256 public constant MINIMUM_VALIDATORS = 3;

    /// @notice Default quorum threshold (67%)
    uint256 public constant DEFAULT_QUORUM_THRESHOLD = 67;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The address authorized to manage validators
    address public immutable validatorAuthority;

    /// @notice Current quorum threshold percentage (1-100)
    uint256 public quorumThreshold;

    /// @notice validator => Validator data
    mapping(address => Validator) private _validators;

    /// @notice List of all validator addresses (for enumeration)
    address[] private _validatorList;

    /// @notice Count of currently active validators
    uint256 private _activeValidatorCount;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the registry with a validator authority
     * @param _authority The address authorized to manage validators
     */
    constructor(address _authority) {
        if (_authority == address(0)) {
            revert InvalidValidatorAuthority();
        }
        validatorAuthority = _authority;
        quorumThreshold = DEFAULT_QUORUM_THRESHOLD;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to validator authority only
    modifier onlyAuthority() {
        if (msg.sender != validatorAuthority) {
            revert UnauthorizedValidatorAuthority(msg.sender, validatorAuthority);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            READ OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IValidatorRegistry
     */
    function minimumValidators() external pure override returns (uint256) {
        return MINIMUM_VALIDATORS;
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function getValidator(address validator) external view override returns (Validator memory) {
        return _validators[validator];
    }

    /**
     * @inheritdoc IValidatorRegistry
     * @dev No input validation - returns None for invalid addresses
     */
    function validatorStatus(address validator) external view override returns (ValidatorStatus) {
        return _validators[validator].status;
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function isValidatorActive(address validator) external view override returns (bool) {
        return _validators[validator].status == ValidatorStatus.Active;
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function activeValidatorCount() external view override returns (uint256) {
        return _activeValidatorCount;
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function getActiveValidators() external view override returns (address[] memory) {
        address[] memory active = new address[](_activeValidatorCount);
        uint256 index = 0;

        for (uint256 i = 0; i < _validatorList.length; i++) {
            if (_validators[_validatorList[i]].status == ValidatorStatus.Active) {
                active[index] = _validatorList[i];
                index++;
            }
        }

        return active;
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function quorumSize() external view override returns (uint256) {
        return _calculateQuorumSize();
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATOR LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IValidatorRegistry
     */
    function addValidator(address validator) external override {
        // Error priority: InvalidValidator > UnauthorizedValidatorAuthority > ValidatorAlreadyExists
        if (validator == address(0)) {
            revert InvalidValidator();
        }

        if (msg.sender != validatorAuthority) {
            revert UnauthorizedValidatorAuthority(msg.sender, validatorAuthority);
        }

        // Check not already registered
        if (_validators[validator].status != ValidatorStatus.None) {
            revert ValidatorAlreadyExists(validator);
        }

        // Register validator
        _validators[validator] =
            Validator({status: ValidatorStatus.Active, registeredAt: block.timestamp, removedAt: 0});

        _validatorList.push(validator);
        _activeValidatorCount++;

        emit ValidatorAdded(validator, block.timestamp);
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function removeValidator(address validator) external override {
        // Error priority: InvalidValidator > UnauthorizedValidatorAuthority > ValidatorNotFound > ValidatorNotActive > InsufficientValidators
        if (validator == address(0)) {
            revert InvalidValidator();
        }

        if (msg.sender != validatorAuthority) {
            revert UnauthorizedValidatorAuthority(msg.sender, validatorAuthority);
        }

        // Check validator exists and is active
        if (_validators[validator].status != ValidatorStatus.Active) {
            if (_validators[validator].status == ValidatorStatus.None) {
                revert ValidatorNotFound(validator);
            }
            revert ValidatorNotActive(validator);
        }

        // Check minimum validators
        if (_activeValidatorCount - 1 < MINIMUM_VALIDATORS) {
            revert InsufficientValidators(_activeValidatorCount - 1, MINIMUM_VALIDATORS);
        }

        // Remove validator
        _validators[validator].status = ValidatorStatus.Removed;
        _validators[validator].removedAt = block.timestamp;
        _activeValidatorCount--;

        emit ValidatorRemoved(validator, block.timestamp);
    }

    /**
     * @inheritdoc IValidatorRegistry
     */
    function setQuorumThreshold(uint256 threshold) external override onlyAuthority {
        if (threshold == 0 || threshold > 100) {
            revert InvalidQuorumThreshold(threshold);
        }

        uint256 oldThreshold = quorumThreshold;
        quorumThreshold = threshold;

        emit QuorumThresholdUpdated(oldThreshold, threshold);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates quorum size based on current active validators
     * @dev Uses ceiling division: ceil(count * threshold / 100)
     * @return The number of votes required for quorum
     */
    function _calculateQuorumSize() internal view returns (uint256) {
        uint256 count = _activeValidatorCount;
        if (count == 0) {
            return 1;
        }
        // Ceiling division: (count * threshold + 99) / 100
        return (count * quorumThreshold + 99) / 100;
    }
}

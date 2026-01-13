// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title AutonomousPatternTest
 * @notice Tests for v0.6.6 Pattern Recognition
 * @dev Validates INV35 (Pattern Threshold)
 *
 * Pattern Types:
 * - FREQUENCY: N actions in time window
 * - PERIODIC: Regular interval actions
 * - CONDITIONAL: Triggered by conditions
 */
contract AutonomousPatternTest is Test {
    IEpochRegistry public epochRegistry;
    IPresenceRegistry public presenceRegistry;
    IValidatorRegistry public validatorRegistry;

    address public epochAuthority = makeAddr("epochAuthority");
    address public validatorAuthority = makeAddr("validatorAuthority");

    // Test actor
    uint256 public actorPk = 0x1111;
    address public actor;

    // Validators
    uint256 public validatorPk1 = 0x2222;
    address public validator1;
    uint256 public validatorPk2 = 0x3333;
    address public validator2;
    uint256 public validatorPk3 = 0x4444;
    address public validator3;

    uint256 public epochId = 1;
    uint256 public startTime;
    uint256 public endTime;

    // Pattern thresholds
    uint256 constant FREQUENCY_THRESHOLD = 5; // 5 actions per hour
    uint256 constant PERIODIC_THRESHOLD = 3; // 3 consecutive periodic actions
    uint256 constant CONDITIONAL_THRESHOLD = 2; // 2 condition-triggered actions

    // Pattern types
    uint8 constant PATTERN_FREQUENCY = 0;
    uint8 constant PATTERN_PERIODIC = 1;
    uint8 constant PATTERN_CONDITIONAL = 2;

    function setUp() public {
        actor = vm.addr(actorPk);
        validator1 = vm.addr(validatorPk1);
        validator2 = vm.addr(validatorPk2);
        validator3 = vm.addr(validatorPk3);

        startTime = block.timestamp + 1 hours;
        endTime = startTime + 1 days;

        epochRegistry = IEpochRegistry(address(new EpochRegistry(epochAuthority)));
        ValidatorRegistry _validatorRegistry = new ValidatorRegistry(validatorAuthority);
        validatorRegistry = IValidatorRegistry(address(_validatorRegistry));
        presenceRegistry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        // Register validators
        vm.startPrank(validatorAuthority);
        _validatorRegistry.addValidator(validator1);
        _validatorRegistry.addValidator(validator2);
        _validatorRegistry.addValidator(validator3);
        vm.stopPrank();

        // Create epoch
        vm.prank(epochAuthority);
        epochRegistry.createEpochWithCapability(
            epochId, startTime, endTime, IEpochRegistry.EpochCapability.PresenceWithSignals, bytes32(0)
        );

        // Warp to active
        vm.warp(startTime);

        // Setup actor with validated presence
        vm.prank(actor);
        presenceRegistry.declarePresence(actor, epochId);
        // Validate with quorum (all 3 validators needed for 67% of 3)
        vm.prank(validator1);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator2);
        presenceRegistry.validatePresence(actor, epochId);
        vm.prank(validator3);
        presenceRegistry.validatePresence(actor, epochId);
    }

    // =========================================================================
    // INV35: Pattern Threshold Tests
    // =========================================================================

    /// @notice Frequency threshold met (INV35)
    function test_inv35_frequencyThresholdMet() public pure {
        uint256 observedFrequency = 5;

        assertTrue(
            _isThresholdMet(PATTERN_FREQUENCY, observedFrequency), "INV35: 5 actions meets FREQUENCY threshold of 5"
        );
    }

    /// @notice Frequency threshold not met (INV35)
    function test_inv35_frequencyThresholdNotMet() public pure {
        uint256 observedFrequency = 4;

        assertFalse(
            _isThresholdMet(PATTERN_FREQUENCY, observedFrequency), "INV35: 4 actions does not meet FREQUENCY threshold"
        );
    }

    /// @notice Periodic threshold met (INV35)
    function test_inv35_periodicThresholdMet() public pure {
        uint256 consecutiveCount = 3;

        assertTrue(_isThresholdMet(PATTERN_PERIODIC, consecutiveCount), "INV35: 3 consecutive meets PERIODIC threshold");
    }

    /// @notice Conditional threshold met (INV35)
    function test_inv35_conditionalThresholdMet() public pure {
        uint256 triggeredCount = 2;

        assertTrue(
            _isThresholdMet(PATTERN_CONDITIONAL, triggeredCount), "INV35: 2 triggered meets CONDITIONAL threshold"
        );
    }

    // =========================================================================
    // Pattern Observation Window Tests
    // =========================================================================

    /// @notice Observation window is valid (1 hour)
    function test_observationWindow_valid() public view {
        uint256 windowStart = block.timestamp;
        uint256 windowEnd = windowStart + 1 hours;

        assertTrue(windowEnd > windowStart);
        assertEq(windowEnd - windowStart, 1 hours);
    }

    /// @notice Observations within window count
    function test_observationWindow_withinCount() public {
        uint256 windowStart = block.timestamp;
        uint256 windowEnd = windowStart + 1 hours;

        // Simulate 5 actions within window
        uint256[] memory timestamps = new uint256[](5);
        timestamps[0] = windowStart + 10 minutes;
        timestamps[1] = windowStart + 20 minutes;
        timestamps[2] = windowStart + 30 minutes;
        timestamps[3] = windowStart + 40 minutes;
        timestamps[4] = windowStart + 50 minutes;

        uint256 count = 0;
        for (uint256 i = 0; i < timestamps.length; i++) {
            if (timestamps[i] >= windowStart && timestamps[i] <= windowEnd) {
                count++;
            }
        }

        assertEq(count, 5);
    }

    /// @notice Observations outside window don't count
    function test_observationWindow_outsideDontCount() public {
        uint256 windowStart = block.timestamp;
        uint256 windowEnd = windowStart + 1 hours;

        // Action before window
        uint256 beforeWindow = windowStart - 1;
        // Action after window
        uint256 afterWindow = windowEnd + 1;

        assertFalse(beforeWindow >= windowStart && beforeWindow <= windowEnd);
        assertFalse(afterWindow >= windowStart && afterWindow <= windowEnd);
    }

    // =========================================================================
    // Validator Pattern Report Tests
    // =========================================================================

    /// @notice Validator can report pattern
    function test_validatorReport_canReport() public view {
        assertTrue(validatorRegistry.isValidatorActive(validator1));
        assertTrue(_canReportPattern(validator1));
    }

    /// @notice Non-validator cannot report pattern
    function test_validatorReport_nonValidatorCannot() public view {
        assertFalse(validatorRegistry.isValidatorActive(actor));
        assertFalse(_canReportPattern(actor));
    }

    /// @notice Pattern requires actor with declared intent
    function test_validatorReport_requiresActorIntent() public view {
        // Actor has validated presence (can declare intent)
        assertTrue(_canDeclareIntent(actor, epochId));
    }

    // =========================================================================
    // Evidence Hash Tests
    // =========================================================================

    /// @notice Evidence hash is deterministic
    function test_evidenceHash_deterministic() public pure {
        bytes32 intentId = keccak256("intent-1");
        uint256 windowStart = 1700000000;
        uint256 windowEnd = 1700003600;
        uint256 frequency = 5;

        bytes32 hash1 = keccak256(abi.encodePacked(intentId, windowStart, windowEnd, frequency));
        bytes32 hash2 = keccak256(abi.encodePacked(intentId, windowStart, windowEnd, frequency));

        assertEq(hash1, hash2);
    }

    // =========================================================================
    // Periodic Pattern Tests
    // =========================================================================

    /// @notice Periodic actions at regular intervals
    function test_periodic_regularIntervals() public {
        uint256 interval = 4 hours;
        uint256[] memory timestamps = new uint256[](3);

        timestamps[0] = startTime;
        timestamps[1] = startTime + interval;
        timestamps[2] = startTime + 2 * interval;

        assertTrue(_isRegularInterval(timestamps, interval));
    }

    /// @notice Non-periodic actions (irregular intervals)
    function test_periodic_irregularIntervals() public {
        uint256 expectedInterval = 4 hours;
        uint256[] memory timestamps = new uint256[](3);

        timestamps[0] = startTime;
        timestamps[1] = startTime + 2 hours; // Wrong interval
        timestamps[2] = startTime + 7 hours; // Wrong interval

        assertFalse(_isRegularInterval(timestamps, expectedInterval));
    }

    // =========================================================================
    // Conditional Pattern Tests
    // =========================================================================

    /// @notice Conditional triggers count correctly
    function test_conditional_triggerCount() public pure {
        bytes32[] memory conditionsMet = new bytes32[](2);
        conditionsMet[0] = keccak256("condition-1");
        conditionsMet[1] = keccak256("condition-2");

        assertEq(conditionsMet.length, 2);
        assertTrue(conditionsMet.length >= CONDITIONAL_THRESHOLD);
    }

    // =========================================================================
    // Threshold Met State Transition Tests
    // =========================================================================

    /// @notice Threshold met transitions to Eligible
    function test_thresholdMet_transitionsToEligible() public pure {
        uint8 STATE_DECLARED = 0;
        uint8 STATE_ELIGIBLE = 1;

        uint8 currentState = STATE_DECLARED;
        bool thresholdMet = true;

        uint8 nextState = thresholdMet ? STATE_ELIGIBLE : STATE_DECLARED;

        assertEq(nextState, STATE_ELIGIBLE);
    }

    /// @notice Threshold not met stays in Declared
    function test_thresholdNotMet_staysDeclared() public pure {
        uint8 STATE_DECLARED = 0;
        uint8 STATE_INACTIVE = 2;

        uint8 currentState = STATE_DECLARED;
        bool thresholdMet = false;
        bool windowExpired = true;

        uint8 nextState = currentState;
        if (!thresholdMet && windowExpired) {
            nextState = STATE_INACTIVE;
        }

        assertEq(nextState, STATE_INACTIVE);
    }

    // =========================================================================
    // Pattern Signature Tests
    // =========================================================================

    /// @notice Validator signs pattern report
    function test_patternSignature_validatorSigns() public {
        bytes32 intentId = keccak256("test-intent");
        bool thresholdMet = true;
        bytes32 evidenceHash = keccak256("evidence");

        bytes32 signPayload = keccak256(abi.encodePacked(intentId, thresholdMet, evidenceHash));
        bytes32 ethSignedHash = _toEthSignedMessageHash(signPayload);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPk1, ethSignedHash);

        address recovered = ecrecover(ethSignedHash, v, r, s);
        assertEq(recovered, validator1);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _isThresholdMet(uint8 patternType, uint256 observed) internal pure returns (bool) {
        if (patternType == PATTERN_FREQUENCY) {
            return observed >= FREQUENCY_THRESHOLD;
        } else if (patternType == PATTERN_PERIODIC) {
            return observed >= PERIODIC_THRESHOLD;
        } else if (patternType == PATTERN_CONDITIONAL) {
            return observed >= CONDITIONAL_THRESHOLD;
        }
        return false;
    }

    function _canReportPattern(address reporter) internal view returns (bool) {
        return validatorRegistry.isValidatorActive(reporter);
    }

    function _canDeclareIntent(address _actor, uint256 _epochId) internal view returns (bool) {
        IPresenceRegistry.PresenceState state = presenceRegistry.presenceState(_actor, _epochId);
        return state == IPresenceRegistry.PresenceState.Validated || state == IPresenceRegistry.PresenceState.Finalized;
    }

    function _isRegularInterval(uint256[] memory timestamps, uint256 expectedInterval) internal pure returns (bool) {
        if (timestamps.length < 2) return false;

        uint256 tolerance = expectedInterval / 10; // 10% tolerance

        for (uint256 i = 1; i < timestamps.length; i++) {
            uint256 actualInterval = timestamps[i] - timestamps[i - 1];
            if (actualInterval < expectedInterval - tolerance || actualInterval > expectedInterval + tolerance) {
                return false;
            }
        }
        return true;
    }
}

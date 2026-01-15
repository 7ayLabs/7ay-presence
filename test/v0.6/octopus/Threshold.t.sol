// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";

/**
 * @title OctopusThresholdTest
 * @notice Tests for v0.6.7 Octopus threshold mechanics
 * @dev Validates INV38 (Activation Threshold) and INV42 (Deactivation Hysteresis)
 *
 * Thresholds:
 * - ACTIVATION: > 45% throughput
 * - DEACTIVATION: < 20% throughput (sustained)
 */
contract OctopusThresholdTest is Test {
    // Configuration
    uint256 constant MAX_THROUGHPUT = 1000; // msgs/second
    uint256 constant ACTIVATION_THRESHOLD = 45; // 45%
    uint256 constant DEACTIVATION_THRESHOLD = 20; // 20%
    uint256 constant HYSTERESIS_WINDOW = 300; // 5 minutes

    // Threshold types
    uint8 constant THRESHOLD_ACTIVATION = 0;
    uint8 constant THRESHOLD_DEACTIVATION = 1;

    // =========================================================================
    // INV38: Activation Threshold Tests
    // =========================================================================

    /// @notice Division allowed above 45% (INV38)
    function test_inv38_divisionAboveThreshold() public pure {
        uint256 currentThroughput = 460; // 46%

        assertTrue(_isAboveActivationThreshold(currentThroughput), "INV38: 46% throughput exceeds activation threshold");
    }

    /// @notice Division not allowed at exactly 45% (INV38)
    function test_inv38_divisionAtThreshold() public pure {
        uint256 currentThroughput = 450; // Exactly 45%

        assertFalse(_isAboveActivationThreshold(currentThroughput), "INV38: Exactly 45% does not exceed threshold");
    }

    /// @notice Division not allowed below 45% (INV38)
    function test_inv38_divisionBelowThreshold() public pure {
        uint256 currentThroughput = 440; // 44%

        assertFalse(_isAboveActivationThreshold(currentThroughput), "INV38: 44% throughput below activation threshold");
    }

    /// @notice Activation threshold calculation
    function test_activationThreshold_calculation() public pure {
        uint256 threshold = (MAX_THROUGHPUT * ACTIVATION_THRESHOLD) / 100;
        assertEq(threshold, 450, "Activation threshold is 450");
    }

    /// @notice Fuzz: Only above 45% activates
    function testFuzz_activation_onlyAboveThreshold(uint256 throughput) public pure {
        throughput = bound(throughput, 0, MAX_THROUGHPUT);

        bool shouldActivate = _isAboveActivationThreshold(throughput);
        uint256 threshold = (MAX_THROUGHPUT * ACTIVATION_THRESHOLD) / 100;

        if (throughput > threshold) {
            assertTrue(shouldActivate);
        } else {
            assertFalse(shouldActivate);
        }
    }

    // =========================================================================
    // INV42: Deactivation Hysteresis Tests
    // =========================================================================

    /// @notice Merge allowed below 20% with sustained period (INV42)
    function test_inv42_mergeWithHysteresis() public pure {
        uint256 currentThroughput = 190; // 19%
        uint256 belowThresholdDuration = 300; // Exactly 5 min

        assertTrue(
            _shouldDeactivate(currentThroughput, belowThresholdDuration),
            "INV42: Merge allowed after sustained low throughput"
        );
    }

    /// @notice Merge not allowed without sustained period (INV42)
    function test_inv42_mergeWithoutHysteresis() public pure {
        uint256 currentThroughput = 190; // 19%
        uint256 belowThresholdDuration = 299; // Just under 5 min

        assertFalse(
            _shouldDeactivate(currentThroughput, belowThresholdDuration),
            "INV42: Merge not allowed before hysteresis window"
        );
    }

    /// @notice Merge not allowed if throughput not low enough (INV42)
    function test_inv42_mergeNotLowEnough() public pure {
        uint256 currentThroughput = 210; // 21%
        uint256 belowThresholdDuration = 600; // 10 min

        assertFalse(
            _shouldDeactivate(currentThroughput, belowThresholdDuration), "INV42: Merge not allowed if above 20%"
        );
    }

    /// @notice Deactivation threshold calculation
    function test_deactivationThreshold_calculation() public pure {
        uint256 threshold = (MAX_THROUGHPUT * DEACTIVATION_THRESHOLD) / 100;
        assertEq(threshold, 200, "Deactivation threshold is 200");
    }

    /// @notice Hysteresis prevents rapid toggling
    function test_hysteresis_preventsRapidToggle() public pure {
        // Drop to 19% for 1 minute
        assertFalse(_shouldDeactivate(190, 60), "Should not merge after 1 min");

        // Drop to 19% for 3 minutes
        assertFalse(_shouldDeactivate(190, 180), "Should not merge after 3 min");

        // Drop to 19% for 5 minutes
        assertTrue(_shouldDeactivate(190, 300), "Should merge after 5 min");
    }

    // =========================================================================
    // Throughput Calculation Tests
    // =========================================================================

    /// @notice Throughput percentage calculation
    function test_throughputPercentage() public pure {
        assertEq(_throughputPercentage(500), 50, "500/1000 = 50%");
        assertEq(_throughputPercentage(450), 45, "450/1000 = 45%");
        assertEq(_throughputPercentage(200), 20, "200/1000 = 20%");
        assertEq(_throughputPercentage(1000), 100, "1000/1000 = 100%");
    }

    /// @notice Zero throughput handling
    function test_throughput_zero() public pure {
        assertEq(_throughputPercentage(0), 0);
        assertFalse(_isAboveActivationThreshold(0));
        assertTrue(_shouldDeactivate(0, HYSTERESIS_WINDOW));
    }

    /// @notice Max throughput handling
    function test_throughput_max() public pure {
        assertEq(_throughputPercentage(MAX_THROUGHPUT), 100);
        assertTrue(_isAboveActivationThreshold(MAX_THROUGHPUT));
        assertFalse(_shouldDeactivate(MAX_THROUGHPUT, HYSTERESIS_WINDOW));
    }

    // =========================================================================
    // Threshold Message Tests
    // =========================================================================

    /// @notice Threshold type is ACTIVATION when above 45%
    function test_thresholdType_activation() public pure {
        uint256 throughput = 500;
        uint8 thresholdType = _getThresholdType(throughput, 0);

        assertEq(thresholdType, THRESHOLD_ACTIVATION);
    }

    /// @notice Threshold type is DEACTIVATION when below 20% sustained
    function test_thresholdType_deactivation() public pure {
        uint256 throughput = 150;
        uint256 duration = 300;
        uint8 thresholdType = _getThresholdType(throughput, duration);

        assertEq(thresholdType, THRESHOLD_DEACTIVATION);
    }

    // =========================================================================
    // Edge Cases
    // =========================================================================

    /// @notice Boundary at activation threshold
    function test_boundary_activation() public pure {
        assertFalse(_isAboveActivationThreshold(450), "450 = 45%, not above");
        assertTrue(_isAboveActivationThreshold(451), "451 > 45%, above");
    }

    /// @notice Boundary at deactivation threshold
    function test_boundary_deactivation() public pure {
        assertFalse(_shouldDeactivate(200, 300), "200 = 20%, not below");
        assertTrue(_shouldDeactivate(199, 300), "199 < 20%, below");
    }

    /// @notice Gap between thresholds prevents oscillation
    function test_thresholdGap_preventsOscillation() public pure {
        uint256 activationThreshold = (MAX_THROUGHPUT * ACTIVATION_THRESHOLD) / 100;
        uint256 deactivationThreshold = (MAX_THROUGHPUT * DEACTIVATION_THRESHOLD) / 100;

        // 25% gap between thresholds
        uint256 gap = activationThreshold - deactivationThreshold;
        assertEq(gap, 250, "Gap is 250 (25% of max)");

        // Any value in the gap doesn't trigger either
        uint256 midPoint = 350; // 35%
        assertFalse(_isAboveActivationThreshold(midPoint));
        assertFalse(_shouldDeactivate(midPoint, 300));
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _isAboveActivationThreshold(uint256 currentThroughput) internal pure returns (bool) {
        uint256 threshold = (MAX_THROUGHPUT * ACTIVATION_THRESHOLD) / 100;
        return currentThroughput > threshold;
    }

    function _shouldDeactivate(uint256 currentThroughput, uint256 belowThresholdDuration) internal pure returns (bool) {
        uint256 threshold = (MAX_THROUGHPUT * DEACTIVATION_THRESHOLD) / 100;
        return currentThroughput < threshold && belowThresholdDuration >= HYSTERESIS_WINDOW;
    }

    function _throughputPercentage(uint256 currentThroughput) internal pure returns (uint256) {
        return (currentThroughput * 100) / MAX_THROUGHPUT;
    }

    function _getThresholdType(uint256 throughput, uint256 belowDuration) internal pure returns (uint8) {
        if (_isAboveActivationThreshold(throughput)) {
            return THRESHOLD_ACTIVATION;
        }
        if (_shouldDeactivate(throughput, belowDuration)) {
            return THRESHOLD_DEACTIVATION;
        }
        revert("No threshold crossed");
    }
}

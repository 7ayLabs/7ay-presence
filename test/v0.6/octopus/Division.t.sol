// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";

/**
 * @title OctopusDivisionTest
 * @notice Tests for v0.6.7 Octopus division mechanics
 * @dev Validates INV39 (Sub-Node Identity) and INV40 (Sub-Node Limit)
 *
 * Division levels:
 * - Level 1: 1 => 2 sub-nodes
 * - Level 2: 2 => 4 sub-nodes (max)
 */
contract OctopusDivisionTest is Test {
    // Constants
    uint256 constant MAX_SUBNODES = 4;

    // Test addresses
    address public parent = makeAddr("parent");

    // =========================================================================
    // INV39: Sub-Node Identity Tests
    // =========================================================================

    /// @notice Sub-node ID is deterministic (INV39)
    function test_inv39_subNodeIdDeterministic() public view {
        bytes32 id1 = _deriveSubNodeId(parent, 0);
        bytes32 id2 = _deriveSubNodeId(parent, 0);

        assertEq(id1, id2, "INV39: Sub-node ID is deterministic");
    }

    /// @notice Different indices produce different IDs (INV39)
    function test_inv39_differentIndicesDifferentIds() public view {
        bytes32 id0 = _deriveSubNodeId(parent, 0);
        bytes32 id1 = _deriveSubNodeId(parent, 1);
        bytes32 id2 = _deriveSubNodeId(parent, 2);
        bytes32 id3 = _deriveSubNodeId(parent, 3);

        assertNotEq(id0, id1);
        assertNotEq(id0, id2);
        assertNotEq(id0, id3);
        assertNotEq(id1, id2);
        assertNotEq(id1, id3);
        assertNotEq(id2, id3);
    }

    /// @notice Different parents produce different IDs (INV39)
    function test_inv39_differentParentsDifferentIds() public {
        address parent2 = makeAddr("parent2");

        bytes32 id1 = _deriveSubNodeId(parent, 0);
        bytes32 id2 = _deriveSubNodeId(parent2, 0);

        assertNotEq(id1, id2, "INV39: Different parents produce different IDs");
    }

    /// @notice Fuzz: Sub-node ID derivation
    function testFuzz_subNodeId_derivation(address _parent, uint256 _index) public pure {
        _index = bound(_index, 0, 3);

        bytes32 id = keccak256(abi.encodePacked(_parent, _index));
        bytes32 derived = _deriveSubNodeId(_parent, _index);

        assertEq(id, derived);
    }

    // =========================================================================
    // INV40: Sub-Node Limit Tests
    // =========================================================================

    /// @notice Max 4 sub-nodes (INV40)
    function test_inv40_maxSubNodes() public pure {
        assertTrue(_canDivide(0), "Can divide from 0");
        assertTrue(_canDivide(1), "Can divide from 1");
        assertTrue(_canDivide(2), "Can divide from 2");
        assertFalse(_canDivide(3), "Cannot divide from 3");
        assertFalse(_canDivide(4), "Cannot divide from 4");
    }

    /// @notice First division: 1 => 2 (INV40)
    function test_inv40_firstDivision() public pure {
        uint256 currentCount = 1;
        uint256 newCount = _getNewSubNodeCount(currentCount);

        assertEq(newCount, 2, "INV40: First division creates 2 sub-nodes");
    }

    /// @notice Second division: 2 => 4 (INV40)
    function test_inv40_secondDivision() public pure {
        uint256 currentCount = 2;
        uint256 newCount = _getNewSubNodeCount(currentCount);

        assertEq(newCount, 4, "INV40: Second division creates 4 sub-nodes");
    }

    /// @notice Division levels
    function test_divisionLevel() public pure {
        assertEq(_getDivisionLevel(1), 0, "No sub-nodes = level 0");
        assertEq(_getDivisionLevel(2), 1, "2 sub-nodes = level 1");
        assertEq(_getDivisionLevel(4), 2, "4 sub-nodes = level 2");
    }

    // =========================================================================
    // Hash Range Distribution Tests
    // =========================================================================

    /// @notice Two sub-nodes split 0-255 evenly
    function test_hashRange_twoSubNodes() public pure {
        (uint256 start0, uint256 end0) = _getHashRange(0, 2);
        (uint256 start1, uint256 end1) = _getHashRange(1, 2);

        assertEq(start0, 0, "S0 starts at 0");
        assertEq(end0, 127, "S0 ends at 127");
        assertEq(start1, 128, "S1 starts at 128");
        assertEq(end1, 255, "S1 ends at 255");
    }

    /// @notice Four sub-nodes split 0-255 into quarters
    function test_hashRange_fourSubNodes() public pure {
        (uint256 start0, uint256 end0) = _getHashRange(0, 4);
        (uint256 start1, uint256 end1) = _getHashRange(1, 4);
        (uint256 start2, uint256 end2) = _getHashRange(2, 4);
        (uint256 start3, uint256 end3) = _getHashRange(3, 4);

        assertEq(start0, 0, "S0 starts at 0");
        assertEq(end0, 63, "S0 ends at 63");
        assertEq(start1, 64, "S1 starts at 64");
        assertEq(end1, 127, "S1 ends at 127");
        assertEq(start2, 128, "S2 starts at 128");
        assertEq(end2, 191, "S2 ends at 191");
        assertEq(start3, 192, "S3 starts at 192");
        assertEq(end3, 255, "S3 ends at 255");
    }

    /// @notice Ranges are contiguous and cover full space
    function test_hashRange_coverage() public pure {
        // Two sub-nodes
        assertTrue(_rangesContiguous(2));

        // Four sub-nodes
        assertTrue(_rangesContiguous(4));
    }

    // =========================================================================
    // Division Message Tests
    // =========================================================================

    /// @notice Division message has correct sub-node count
    function test_divideMessage_subNodeCount() public view {
        bytes32[] memory subNodeIds = _generateSubNodeIds(parent, 2);

        assertEq(subNodeIds.length, 2);
        assertEq(subNodeIds[0], _deriveSubNodeId(parent, 0));
        assertEq(subNodeIds[1], _deriveSubNodeId(parent, 1));
    }

    /// @notice Division message has correct sub-node IDs for 4 nodes
    function test_divideMessage_fourSubNodes() public view {
        bytes32[] memory subNodeIds = _generateSubNodeIds(parent, 4);

        assertEq(subNodeIds.length, 4);
        assertEq(subNodeIds[0], _deriveSubNodeId(parent, 0));
        assertEq(subNodeIds[1], _deriveSubNodeId(parent, 1));
        assertEq(subNodeIds[2], _deriveSubNodeId(parent, 2));
        assertEq(subNodeIds[3], _deriveSubNodeId(parent, 3));
    }

    // =========================================================================
    // Sub-Node Registration Tests
    // =========================================================================

    /// @notice Sub-node can verify its own ID
    function test_subNodeRegistration_verifyId() public view {
        bytes32 subNodeId = _deriveSubNodeId(parent, 0);
        uint256 index = 0;

        assertTrue(_verifySubNodeId(subNodeId, parent, index), "Sub-node can verify its own ID");
    }

    /// @notice Sub-node rejects incorrect ID
    function test_subNodeRegistration_rejectWrongId() public view {
        bytes32 wrongId = keccak256("wrong");
        uint256 index = 0;

        assertFalse(_verifySubNodeId(wrongId, parent, index), "Rejects incorrect ID");
    }

    // =========================================================================
    // Edge Cases
    // =========================================================================

    /// @notice Zero address parent
    function test_zeroAddressParent() public pure {
        bytes32 id = _deriveSubNodeId(address(0), 0);

        // Should still produce a valid hash
        assertNotEq(id, bytes32(0));
    }

    /// @notice Index bounds
    function test_indexBounds() public pure {
        // Valid indices
        _deriveSubNodeId(address(1), 0);
        _deriveSubNodeId(address(1), 1);
        _deriveSubNodeId(address(1), 2);
        _deriveSubNodeId(address(1), 3);

        // Note: Index 4+ would be invalid per INV40 but the derivation
        // function itself doesn't enforce this
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _deriveSubNodeId(address _parent, uint256 _index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_parent, _index));
    }

    function _canDivide(uint256 currentCount) internal pure returns (bool) {
        // currentCount = number of existing sub-nodes for a parent
        // 0 = parent exists with no sub-nodes (can divide to 2)
        // 1 = parent has 1 sub-node (treated as 0, can divide to 2)
        // 2 = parent has 2 sub-nodes (can divide to 4)
        // 3+ = cannot divide further (max 4 sub-nodes per INV40)
        return currentCount <= 2;
    }

    function _getNewSubNodeCount(uint256 currentCount) internal pure returns (uint256) {
        if (currentCount <= 1) return 2;
        if (currentCount == 2) return 4;
        revert("Cannot divide further");
    }

    function _getDivisionLevel(uint256 subNodeCount) internal pure returns (uint256) {
        if (subNodeCount <= 1) return 0;
        if (subNodeCount == 2) return 1;
        if (subNodeCount == 4) return 2;
        revert("Invalid sub-node count");
    }

    function _getHashRange(uint256 index, uint256 totalSubNodes) internal pure returns (uint256 start, uint256 end) {
        uint256 rangeSize = 256 / totalSubNodes;
        start = index * rangeSize;
        end = start + rangeSize - 1;
    }

    function _rangesContiguous(uint256 totalSubNodes) internal pure returns (bool) {
        uint256 expectedStart = 0;
        for (uint256 i = 0; i < totalSubNodes; i++) {
            (uint256 start, uint256 end) = _getHashRange(i, totalSubNodes);
            if (start != expectedStart) return false;
            expectedStart = end + 1;
        }
        return expectedStart == 256;
    }

    function _generateSubNodeIds(address _parent, uint256 count) internal pure returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            ids[i] = _deriveSubNodeId(_parent, i);
        }
        return ids;
    }

    function _verifySubNodeId(bytes32 subNodeId, address _parent, uint256 index) internal pure returns (bool) {
        return subNodeId == _deriveSubNodeId(_parent, index);
    }
}

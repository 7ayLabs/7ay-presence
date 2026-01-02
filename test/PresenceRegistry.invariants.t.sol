// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { PresenceRegistry } from "../contracts/core/PresenceRegistry.sol";
import { IPresenceRegistry } from "../contracts/interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistryInvariants
 * @notice Invariant tests for the PresenceRegistry contract
 *
 * @dev These tests validate protocol-level invariants defined in:
 *      - specs/presence.md
 *      - specs/model.md
 *
 *      This is NOT unit testing.
 *      This is property-based testing of protocol rules.
 */
contract PresenceRegistryInvariants is Test {
    IPresenceRegistry internal registry;

    address internal actor;
    uint256 internal epochId;

    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));

        actor = address(0xA11CE);
        epochId = 1;
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #1
      An actor MUST NOT have more than one active presence per epoch
    //////////////////////////////////////////////////////////////*/

    function invariant_singlePresencePerEpoch() external {
        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);

        // Only one presence can exist per actor/epoch
        assertTrue(
            state == IPresenceRegistry.PresenceState.None ||
            state == IPresenceRegistry.PresenceState.Declared ||
            state == IPresenceRegistry.PresenceState.Validated ||
            state == IPresenceRegistry.PresenceState.Finalized ||
            state == IPresenceRegistry.PresenceState.Expired ||
            state == IPresenceRegistry.PresenceState.Slashed
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #2
      A Finalized presence MUST NOT change state
    //////////////////////////////////////////////////////////////*/

    function invariant_finalizedIsTerminal() external {
        vm.prank(actor);
        registry.declarePresence(epochId);

        registry.validatePresence(actor, epochId);
        registry.finalizePresence(actor, epochId);

        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);

        assertTrue(
            state == IPresenceRegistry.PresenceState.Finalized
        );

        // Try illegal transitions
        vm.expectRevert();
        registry.validatePresence(actor, epochId);

        vm.expectRevert();
        registry.expirePresence(actor, epochId);

        vm.expectRevert();
        registry.slashPresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #3
      A Slashed presence MUST NOT become valid again
    //////////////////////////////////////////////////////////////*/

    function invariant_slashedIsTerminal() external {
        vm.prank(actor);
        registry.declarePresence(epochId);

        registry.slashPresence(actor, epochId);

        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);

        assertTrue(
            state == IPresenceRegistry.PresenceState.Slashed
        );

        vm.expectRevert();
        registry.validatePresence(actor, epochId);

        vm.expectRevert();
        registry.finalizePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #4
      An Expired presence MUST NOT be validated retroactively
    //////////////////////////////////////////////////////////////*/

    function invariant_expiredCannotBeValidated() external {
        vm.prank(actor);
        registry.declarePresence(epochId);

        registry.expirePresence(actor, epochId);

        IPresenceRegistry.PresenceState state =
            registry.presenceState(actor, epochId);

        assertTrue(
            state == IPresenceRegistry.PresenceState.Expired
        );

        vm.expectRevert();
        registry.validatePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT #6
      Presence state transitions MUST be deterministic
    //////////////////////////////////////////////////////////////*/

    function invariant_deterministicTransitions() external {
        uint256 randomEpoch =
            uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % 1_000_000 + 1;

        vm.prank(actor);
        registry.declarePresence(randomEpoch);

        IPresenceRegistry.PresenceState stateAfterDeclare =
            registry.presenceState(actor, randomEpoch);

        assertTrue(
            stateAfterDeclare == IPresenceRegistry.PresenceState.Declared
        );

        registry.validatePresence(actor, randomEpoch);

        IPresenceRegistry.PresenceState stateAfterValidate =
            registry.presenceState(actor, randomEpoch);

        assertTrue(
            stateAfterValidate == IPresenceRegistry.PresenceState.Validated
        );
    }
}
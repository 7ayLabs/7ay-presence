// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { PresenceRegistry } from "../contracts/core/PresenceRegistry.sol";
import { IPresenceRegistry } from "../contracts/interfaces/IPresenceRegistry.sol";

/**
 * @title PresenceRegistryFuzzTests
 * @notice Property-based fuzz tests for the 7ay PoP
 *
 * @dev
 * Fuzz tests verify protocol properties with randomized inputs.
 * These tests complement invariant tests by exploring edge cases
 * that fixed values might miss.
 *
 * Specification references:
 * - specs/presence.md (MVP profile)
 * - specs/errors.md (error handling)
 */
contract PresenceRegistryFuzzTests is Test {
    IPresenceRegistry internal registry;

    function setUp() external {
        registry = IPresenceRegistry(address(new PresenceRegistry()));
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Finalization
      Any valid (actor, epochId) pair MUST result in Finalized state.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_finalizePresence(
        address fuzzActor,
        uint256 fuzzEpochId
    ) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)),
            uint256(IPresenceRegistry.PresenceState.Finalized)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Actor Isolation
      Finalizing for actorA MUST NOT affect actorB for any epoch.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_actorIsolation(
        address actorA,
        address actorB,
        uint256 fuzzEpochId
    ) external {
        vm.assume(actorA != address(0));
        vm.assume(actorB != address(0));
        vm.assume(actorA != actorB);
        vm.assume(fuzzEpochId != 0);

        vm.prank(actorA);
        registry.finalizePresence(actorA, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(actorA, fuzzEpochId)),
            uint256(IPresenceRegistry.PresenceState.Finalized)
        );
        assertEq(
            uint256(registry.presenceState(actorB, fuzzEpochId)),
            uint256(IPresenceRegistry.PresenceState.None)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Epoch Isolation
      Finalizing in epochA MUST NOT affect epochB for same actor.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_epochIsolation(
        address fuzzActor,
        uint256 epochA,
        uint256 epochB
    ) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(epochA != 0);
        vm.assume(epochB != 0);
        vm.assume(epochA != epochB);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, epochA);

        assertEq(
            uint256(registry.presenceState(fuzzActor, epochA)),
            uint256(IPresenceRegistry.PresenceState.Finalized)
        );
        assertEq(
            uint256(registry.presenceState(fuzzActor, epochB)),
            uint256(IPresenceRegistry.PresenceState.None)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Idempotency
      Multiple calls with same (actor, epochId) MUST be idempotent.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_idempotency(
        address fuzzActor,
        uint256 fuzzEpochId
    ) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)),
            uint256(IPresenceRegistry.PresenceState.Finalized)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Authorization
      Non-actor callers MUST be rejected for any (actor, epochId).
    //////////////////////////////////////////////////////////////*/

    function testFuzz_unauthorizedActor(
        address caller,
        address targetActor,
        uint256 fuzzEpochId
    ) external {
        vm.assume(caller != address(0));
        vm.assume(targetActor != address(0));
        vm.assume(caller != targetActor);
        vm.assume(fuzzEpochId != 0);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.UnauthorizedActor.selector,
                caller,
                targetActor
            )
        );
        registry.finalizePresence(targetActor, fuzzEpochId);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Invalid Epoch
      Epoch 0 MUST be rejected for any actor.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_invalidEpoch(address fuzzActor) external {
        vm.assume(fuzzActor != address(0));

        vm.prank(fuzzActor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresenceRegistry.InvalidEpoch.selector,
                0
            )
        );
        registry.finalizePresence(fuzzActor, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: Invalid Actor
      address(0) MUST be rejected as actor.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_invalidActor(uint256 fuzzEpochId) external {
        vm.assume(fuzzEpochId != 0);

        vm.prank(address(0));
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.finalizePresence(address(0), fuzzEpochId);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST: Protocol Version
      Protocol version MUST be readable.
    //////////////////////////////////////////////////////////////*/

    function test_protocolVersion() external view {
        string memory version = registry.protocolVersion();
        assertEq(version, "0.1.0");
    }
}

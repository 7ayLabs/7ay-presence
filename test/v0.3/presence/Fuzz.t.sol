// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";

/**
 * @title PresenceRegistryFuzzTests
 * @notice Property-based fuzz tests for presence lifecycle
 * @dev Spec: specs/v0.3/presence.md
 */
contract PresenceRegistryFuzzTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    address internal constant AUTHORITY = address(0xA077);

    uint256 internal constant ACTIVE_EPOCH = 1;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry)));

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1 days;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(ACTIVE_EPOCH, start, end);
    }

    function _ensureActiveEpoch(uint256 epochId) internal {
        if (epochId == 0 || epochId == ACTIVE_EPOCH) return;
        if (epochRegistry.epochState(epochId) != IEpochRegistry.EpochState.None) return;

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1 days;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, start, end);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_finalizePresence(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Finalized)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ISOLATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_actorIsolation(address actorA, address actorB, uint256 fuzzEpochId) external {
        vm.assume(actorA != address(0));
        vm.assume(actorB != address(0));
        vm.assume(actorA != actorB);
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(actorA);
        registry.finalizePresence(actorA, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(actorA, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Finalized)
        );
        assertEq(uint256(registry.presenceState(actorB, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.None));
    }

    function testFuzz_epochIsolation(address fuzzActor, uint256 epochA, uint256 epochB) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(epochA != 0);
        vm.assume(epochB != 0);
        vm.assume(epochA != epochB);

        _ensureActiveEpoch(epochA);
        _ensureActiveEpoch(epochB);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, epochA);

        assertEq(uint256(registry.presenceState(fuzzActor, epochA)), uint256(IPresenceRegistry.PresenceState.Finalized));
        assertEq(uint256(registry.presenceState(fuzzActor, epochB)), uint256(IPresenceRegistry.PresenceState.None));
    }

    /*//////////////////////////////////////////////////////////////
                            IDEMPOTENCY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_idempotency(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.finalizePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Finalized)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_unauthorizedActor(address caller, address targetActor, uint256 fuzzEpochId) external {
        vm.assume(caller != address(0));
        vm.assume(targetActor != address(0));
        vm.assume(caller != targetActor);
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, caller, targetActor));
        registry.finalizePresence(targetActor, fuzzEpochId);
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_invalidEpoch(address fuzzActor) external {
        vm.assume(fuzzActor != address(0));

        vm.prank(fuzzActor);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.finalizePresence(fuzzActor, 0);
    }

    function testFuzz_invalidActor(uint256 fuzzEpochId) external {
        vm.assume(fuzzEpochId != 0);

        vm.prank(address(0));
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.finalizePresence(address(0), fuzzEpochId);
    }

    /*//////////////////////////////////////////////////////////////
                            ERROR PRIORITY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_errorPriority_unauthorizedBeforeInvalidEpoch(address caller, address targetActor) external {
        vm.assume(caller != address(0));
        vm.assume(targetActor != address(0));
        vm.assume(caller != targetActor);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.UnauthorizedActor.selector, caller, targetActor));
        registry.finalizePresence(targetActor, 0);
    }

    function testFuzz_errorPriority_invalidActorBeforeUnauthorized(address caller) external {
        vm.assume(caller != address(0));

        vm.prank(caller);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.finalizePresence(address(0), 1);
    }

    function test_errorPriority_invalidActorBeforeInvalidEpoch() external {
        address caller = address(0xCAFE);

        vm.prank(caller);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.finalizePresence(address(0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            VERSION
    //////////////////////////////////////////////////////////////*/

    function test_protocolVersion() external view {
        string memory version = registry.protocolVersion();
        assertEq(version, "0.3.0");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PresenceRegistry} from "../../../contracts/core/PresenceRegistry.sol";
import {IPresenceRegistry} from "../../../contracts/interfaces/IPresenceRegistry.sol";
import {EpochRegistry} from "../../../contracts/core/EpochRegistry.sol";
import {IEpochRegistry} from "../../../contracts/interfaces/IEpochRegistry.sol";
import {ValidatorRegistry} from "../../../contracts/core/ValidatorRegistry.sol";
import {IValidatorRegistry} from "../../../contracts/interfaces/IValidatorRegistry.sol";

/**
 * @title PresenceRegistryFuzzTests
 * @notice Property-based fuzz tests for presence lifecycle (updated for v0.4)
 * @dev Spec: specs/v0.4/presence.md
 */
contract PresenceRegistryFuzzTests is Test {
    IPresenceRegistry internal registry;
    IEpochRegistry internal epochRegistry;
    IValidatorRegistry internal validatorRegistry;
    address internal constant AUTHORITY = address(0xA077);
    address internal constant VALIDATOR_1 = address(0x1001);
    address internal constant VALIDATOR_2 = address(0x1002);
    address internal constant VALIDATOR_3 = address(0x1003);

    uint256 internal constant ACTIVE_EPOCH = 1;

    function setUp() external {
        epochRegistry = IEpochRegistry(address(new EpochRegistry(AUTHORITY)));
        validatorRegistry = IValidatorRegistry(address(new ValidatorRegistry(AUTHORITY)));
        registry = IPresenceRegistry(address(new PresenceRegistry(epochRegistry, validatorRegistry, 0)));

        vm.startPrank(AUTHORITY);
        epochRegistry.createEpoch(ACTIVE_EPOCH, block.timestamp, block.timestamp + 1 days);
        validatorRegistry.addValidator(VALIDATOR_1);
        validatorRegistry.addValidator(VALIDATOR_2);
        validatorRegistry.addValidator(VALIDATOR_3);
        vm.stopPrank();
    }

    function _ensureActiveEpoch(uint256 epochId) internal {
        if (epochId == 0 || epochId == ACTIVE_EPOCH) return;
        if (epochRegistry.epochState(epochId) != IEpochRegistry.EpochState.None) return;

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1 days;
        vm.prank(AUTHORITY);
        epochRegistry.createEpoch(epochId, start, end);
    }

    function _validatePresence(address actor, uint256 epochId) internal {
        vm.prank(VALIDATOR_1);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_2);
        registry.validatePresence(actor, epochId);
        vm.prank(VALIDATOR_3);
        registry.validatePresence(actor, epochId);
    }

    /*//////////////////////////////////////////////////////////////
                            DECLARATION
    //////////////////////////////////////////////////////////////*/

    function testFuzz_declarePresence(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(fuzzActor);
        registry.declarePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Declared)
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
        registry.declarePresence(actorA, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(actorA, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Declared)
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
        registry.declarePresence(fuzzActor, epochA);

        assertEq(uint256(registry.presenceState(fuzzActor, epochA)), uint256(IPresenceRegistry.PresenceState.Declared));
        assertEq(uint256(registry.presenceState(fuzzActor, epochB)), uint256(IPresenceRegistry.PresenceState.None));
    }

    /*//////////////////////////////////////////////////////////////
                            IDEMPOTENCY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_declareIdempotency(address fuzzActor, uint256 fuzzEpochId) external {
        vm.assume(fuzzActor != address(0));
        vm.assume(fuzzEpochId != 0);

        _ensureActiveEpoch(fuzzEpochId);

        vm.prank(fuzzActor);
        registry.declarePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.declarePresence(fuzzActor, fuzzEpochId);

        vm.prank(fuzzActor);
        registry.declarePresence(fuzzActor, fuzzEpochId);

        assertEq(
            uint256(registry.presenceState(fuzzActor, fuzzEpochId)), uint256(IPresenceRegistry.PresenceState.Declared)
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
        registry.declarePresence(targetActor, fuzzEpochId);
    }

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_invalidEpoch(address fuzzActor) external {
        vm.assume(fuzzActor != address(0));

        vm.prank(fuzzActor);
        vm.expectRevert(abi.encodeWithSelector(IPresenceRegistry.InvalidEpoch.selector, 0));
        registry.declarePresence(fuzzActor, 0);
    }

    function testFuzz_invalidActor(uint256 fuzzEpochId) external {
        vm.assume(fuzzEpochId != 0);

        vm.prank(address(0));
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), fuzzEpochId);
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
        registry.declarePresence(targetActor, 0);
    }

    function testFuzz_errorPriority_invalidActorBeforeUnauthorized(address caller) external {
        vm.assume(caller != address(0));

        vm.prank(caller);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), 1);
    }

    function test_errorPriority_invalidActorBeforeInvalidEpoch() external {
        address caller = address(0xCAFE);

        vm.prank(caller);
        vm.expectRevert(IPresenceRegistry.InvalidActor.selector);
        registry.declarePresence(address(0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            VERSION
    //////////////////////////////////////////////////////////////*/

    function test_protocolVersion() external view {
        string memory version = registry.protocolVersion();
        assertEq(version, "0.6.0");
    }
}

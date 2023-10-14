pragma solidity ^0.8.15;

import {MockStateBridge} from "src/mock/MockStateBridge.sol";
import {WorldIDIdentityManagerMock} from "src/mock/WorldIDIdentityManagerMock.sol";
import {MockBridgedWorldID} from "src/mock/MockBridgedWorldID.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

/// @title Mock State Bridge Test
/// @author Worldcoin
contract MockStateBridgeTest is PRBTest, StdCheats {
    MockStateBridge mockStateBridge;
    WorldIDIdentityManagerMock mockWorldID;
    MockBridgedWorldID mockBridgedWorldID;

    address owner;

    uint8 treeDepth;

    uint256 initialRoot;

    /// @notice The time in the `rootHistory` mapping associated with a root that has never been
    ///         seen before.
    uint128 internal constant NULL_ROOT_TIME = 0;

    /// @notice Emitted when root history expiry is set
    event RootHistoryExpirySet(uint256 rootHistoryExpiry);

    /// @notice Emitted when a new root is received by the contract.
    ///
    /// @param root The value of the root that was added.
    /// @param timestamp The timestamp of insertion for the given root.
    event RootAdded(uint256 root, uint128 timestamp);

    function setUp() public {
        owner = address(0x1234);

        vm.label(owner, "owner");

        vm.prank(owner);

        treeDepth = uint8(30);

        initialRoot = uint256(0x111);

        mockBridgedWorldID = new MockBridgedWorldID(treeDepth);
        mockWorldID = new WorldIDIdentityManagerMock(initialRoot);
        mockStateBridge = new MockStateBridge(address(mockWorldID), address(mockBridgedWorldID));
    }

    function testPropagateRootSucceeds() public {
        vm.expectEmit(true, true, true, true);
        emit RootAdded(mockBridgedWorldID.latestRoot(), uint128(block.timestamp));
        mockStateBridge.propagateRoot();

        assert(mockWorldID.latestRoot() == mockBridgedWorldID.latestRoot());
    }

}

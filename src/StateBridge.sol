// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Optimism interface for cross domain messaging
import {ICrossDomainMessenger} from
    "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";
import {IOpWorldID} from "./interfaces/IOpWorldID.sol";
import {IPolygonWorldID} from "./interfaces/IPolygonWorldID.sol";
import {IRootHistory} from "./interfaces/IRootHistory.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {ICrossDomainOwnable3} from "./interfaces/ICrossDomainOwnable3.sol";
import {FxBaseRootTunnel} from "fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";

/// @title World ID State Bridge
/// @author Worldcoin
/// @notice Distributes new World ID Identity Manager roots to World ID supported networks
/// @dev This contract lives on Ethereum mainnet and is called by the World ID Identity Manager contract
/// in the registerIdentities method
contract StateBridge is FxBaseRootTunnel, Ownable2Step {
    ///////////////////////////////////////////////////////////////////
    ///                           STORAGE                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice The address of the OPWorldID contract on Optimism
    address public immutable opWorldIDAddress;

    /// @notice address for Optimism's Ethereum mainnet L1CrossDomainMessenger contract
    address internal immutable opCrossDomainMessengerAddress;

    /// @notice The address of the BaseWorldID contract on Base
    address public immutable baseWorldIDAddress;

    /// @notice address for Base's Ethereum mainnet L1CrossDomainMessenger contract
    address internal immutable baseCrossDomainMessengerAddress;

    /// @notice worldID Address
    address public immutable worldIDAddress;

    /// @notice Amount of gas purchased on Optimism for _sendRootToOptimism
    uint32 internal gasLimitSendRootOptimism;

    /// @notice Amount of gas purchased on Optimism for setRootHistoryExpiryOptimism
    uint32 internal gasLimitSetRootHistoryExpiryOptimism;

    /// @notice Amount of gas purchased on Optimism for transferOwnershipOptimism
    uint32 internal gasLimitTransferOwnershipOptimism;

    /// @notice Amount of gas purchased on Base for _sendRootToBase
    uint32 internal gasLimitSendRootBase;

    /// @notice Amount of gas purchased on Base for setRootHistoryExpiryBase
    uint32 internal gasLimitSetRootHistoryExpiryBase;

    /// @notice Amount of gas purchased on Base for transferOwnershipBase
    uint32 internal gasLimitTransferOwnershipBase;

    ///////////////////////////////////////////////////////////////////
    ///                            EVENTS                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Emmitted when the the StateBridge gives ownership of the OPWorldID contract
    /// to the WorldID Identity Manager contract away
    /// @param previousOwner The previous owner of the OPWorldID contract
    /// @param newOwner The new owner of the OPWorldID contract
    /// @param isLocal Whether the ownership transfer is local (Optimism EOA/contract) or an Ethereum EOA or contract
    event OwnershipTransferredOptimism(
        address indexed previousOwner, address indexed newOwner, bool isLocal
    );

    /// @notice Emmitted when the the StateBridge gives ownership of the OPWorldID contract
    /// to the WorldID Identity Manager contract away
    /// @param previousOwner The previous owner of the OPWorldID contract
    /// @param newOwner The new owner of the OPWorldID contract
    /// @param isLocal Whether the ownership transfer is local (Base EOA/contract) or an Ethereum EOA or contract
    event OwnershipTransferredBase(
        address indexed previousOwner, address indexed newOwner, bool isLocal
    );

    /// @notice Emmitted when the the StateBridge sets the root history expiry for OpWorldID and PolygonWorldID
    /// @param rootHistoryExpiry The new root history expiry
    event SetRootHistoryExpiry(uint256 rootHistoryExpiry);

    /// @notice Emmitted when a root is sent to OpWorldID and PolygonWorldID
    /// @param root The latest WorldID Identity Manager root.
    /// @param timestamp The Ethereum block timestamp of the latest WorldID Identity Manager root.
    event RootSentMultichain(uint256 root, uint128 timestamp);

    /// @notice Emmitted when the the StateBridge sets the gas limit for sendRootOptimism
    /// @param _opGasLimit The new opGasLimit for sendRootOptimism
    event SetGasLimitSendRootOptimism(uint32 _opGasLimit);

    /// @notice Emmitted when the the StateBridge sets the gas limit for setRootHistoryExpiryOptimism
    /// @param _opGasLimit The new opGasLimit for setRootHistoryExpiryOptimism
    event SetGasLimitSetRootHistoryExpiryOptimism(uint32 _opGasLimit);

    /// @notice Emmitted when the the StateBridge sets the gas limit for transferOwnershipOptimism
    /// @param _opGasLimit The new opGasLimit for transferOwnershipOptimism
    event SetGasLimitTransferOwnershipOptimism(uint32 _opGasLimit);

    /// @notice Emmitted when the the StateBridge sets the gas limit for sendRootBase
    /// @param _baseGasLimit The new baseGasLimit for sendRootBase
    event SetGasLimitSendRootBase(uint32 _baseGasLimit);

    /// @notice Emmitted when the the StateBridge sets the gas limit for setRootHistoryExpiryBase
    /// @param _baseGasLimit The new baseGasLimit for setRootHistoryExpiryBase
    event SetGasLimitSetRootHistoryExpiryBase(uint32 _baseGasLimit);

    /// @notice Emmitted when the the StateBridge sets the gas limit for transferOwnershipBase
    /// @param _baseGasLimit The new baseGasLimit for transferOwnershipBase
    event SetGasLimitTransferOwnershipBase(uint32 _baseGasLimit);

    ///////////////////////////////////////////////////////////////////
    ///                            ERRORS                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Thrown when the caller of `sendRootMultichain` is not the WorldID Identity Manager contract.
    error NotWorldIDIdentityManager();

    /// @notice Thrown when an attempt is made to renounce ownership.
    error CannotRenounceOwnership();

    ///////////////////////////////////////////////////////////////////
    ///                          MODIFIERS                          ///
    ///////////////////////////////////////////////////////////////////
    modifier onlyWorldIDIdentityManager() {
        if (msg.sender != worldIDAddress) {
            revert NotWorldIDIdentityManager();
        }
        _;
    }

    ///////////////////////////////////////////////////////////////////
    ///                         CONSTRUCTOR                         ///
    ///////////////////////////////////////////////////////////////////

    /// @notice constructor
    /// @param _checkpointManager address of the checkpoint manager contract
    /// @param _fxRoot address of Polygon's fxRoot contract, part of the FxPortal bridge (Goerli or Mainnet)
    /// @param _worldIDIdentityManager Deployment address of the WorldID Identity Manager contract
    /// @param _opWorldIDAddress Address of the Optimism contract that will receive the new root and timestamp
    /// @param _opCrossDomainMessenger L1CrossDomainMessenger contract used to communicate with the Optimism network
    /// @param _baseWorldIDAddress Address of the Base contract that will receive the new root and timestamp
    /// @param _baseCrossDomainMessenger L1CrossDomainMessenger contract used to communicate with the Base OP-Stack network
    constructor(
        address _checkpointManager,
        address _fxRoot,
        address _worldIDIdentityManager,
        address _opWorldIDAddress,
        address _opCrossDomainMessenger,
        address _baseWorldIDAddress,
        address _baseCrossDomainMessenger
    ) FxBaseRootTunnel(_checkpointManager, _fxRoot) {
        opWorldIDAddress = _opWorldIDAddress;
        worldIDAddress = _worldIDIdentityManager;
        baseWorldIDAddress = _baseWorldIDAddress;
        opCrossDomainMessengerAddress = _opCrossDomainMessenger;
        baseCrossDomainMessengerAddress = _baseCrossDomainMessenger;
        gasLimitSendRootOptimism = 100000;
        gasLimitSetRootHistoryExpiryOptimism = 100000;
        gasLimitTransferOwnershipOptimism = 100000;
        gasLimitSendRootBase = 100000;
        gasLimitSetRootHistoryExpiryBase = 100000;
        gasLimitTransferOwnershipBase = 100000;
    }

    ///////////////////////////////////////////////////////////////////
    ///                          PUBLIC API                         ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sends the latest WorldID Identity Manager root to all chains.
    /// @dev Calls this method on the L1 Proxy contract to relay roots and timestamps to WorldID supported chains.
    /// @param root The latest WorldID Identity Manager root.
    function sendRootMultichain(uint256 root) external onlyWorldIDIdentityManager {
        uint128 timestamp = uint128(block.timestamp);
        _sendRootToOptimism(root, timestamp);
        _sendRootToPolygon(root, timestamp);
        _sendRootToBase(root, timestamp);
        // add other chains here

        emit RootSentMultichain(root, timestamp);
    }

    /// @notice Sets the root history expiry for OpWorldID (on Optimism) and PolygonWorldID (on Polygon)
    /// @param expiryTime The new root history expiry for OpWorldID and PolygonWorldID
    function setRootHistoryExpiry(uint256 expiryTime) public onlyWorldIDIdentityManager {
        setRootHistoryExpiryOptimism(expiryTime);
        setRootHistoryExpiryPolygon(expiryTime);
        setRootHistoryExpiryBase(expiryTime);

        emit SetRootHistoryExpiry(expiryTime);
    }

    ///////////////////////////////////////////////////////////////////
    ///                           OPTIMISM                          ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sends the latest WorldID Identity Manager root to all chains.
    /// @dev Calls this method on the L1 Proxy contract to relay roots and timestamps to WorldID supported chains.
    /// @param root The latest WorldID Identity Manager root.
    /// @param timestamp The Ethereum block timestamp of the latest WorldID Identity Manager root.
    function _sendRootToOptimism(uint256 root, uint128 timestamp) internal {
        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        bytes memory message = abi.encodeCall(IOpWorldID.receiveRoot, (root, timestamp));

        ICrossDomainMessenger(opCrossDomainMessengerAddress).sendMessage(
            // Contract address on Optimism
            opWorldIDAddress,
            message,
            gasLimitSendRootOptimism
        );
    }

    /// @notice Adds functionality to the StateBridge to transfer ownership
    /// of OpWorldID to another contract on L1 or to a local Optimism EOA
    /// @param _owner new owner (EOA or contract)
    /// @param _isLocal true if new owner is on Optimism, false if it is a cross-domain owner
    function transferOwnershipOptimism(address _owner, bool _isLocal) public onlyOwner {
        bytes memory message;

        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        message = abi.encodeCall(ICrossDomainOwnable3.transferOwnership, (_owner, _isLocal));

        ICrossDomainMessenger(opCrossDomainMessengerAddress).sendMessage(
            // Contract address on Optimism
            opWorldIDAddress,
            message,
            gasLimitTransferOwnershipOptimism
        );

        emit OwnershipTransferredOptimism(owner(), _owner, _isLocal);
    }

    /// @notice Adds functionality to the StateBridge to set the root history expiry on OpWorldID
    /// @param _rootHistoryExpiry new root history expiry
    function setRootHistoryExpiryOptimism(uint256 _rootHistoryExpiry) internal {
        bytes memory message;

        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        message = abi.encodeCall(IRootHistory.setRootHistoryExpiry, (_rootHistoryExpiry));

        ICrossDomainMessenger(opCrossDomainMessengerAddress).sendMessage(
            // Contract address on Optimism
            opWorldIDAddress,
            message,
            gasLimitSetRootHistoryExpiryOptimism
        );
    }

    ///////////////////////////////////////////////////////////////////
    ///                         OP GAS LIMIT                        ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sets the gas limit for the Optimism sendRootMultichain method
    /// @param _opGasLimit The new gas limit for the sendRootMultichain method
    function setGasLimitSendRootOptimism(uint32 _opGasLimit) external onlyOwner {
        gasLimitSendRootOptimism = _opGasLimit;

        emit SetGasLimitSendRootOptimism(_opGasLimit);
    }

    /// @notice Sets the gas limit for the Optimism setRootHistoryExpiry method
    /// @param _opGasLimit The new gas limit for the setRootHistoryExpiry method
    function setGasLimitSetRootHistoryExpiryOptimism(uint32 _opGasLimit) external onlyOwner {
        gasLimitSetRootHistoryExpiryOptimism = _opGasLimit;

        emit SetGasLimitSetRootHistoryExpiryOptimism(_opGasLimit);
    }

    /// @notice Sets the gas limit for the transferOwnershipOptimism method
    /// @param _opGasLimit The new gas limit for the transferOwnershipOptimism method
    function setGasLimitTransferOwnershipOptimism(uint32 _opGasLimit) external onlyOwner {
        gasLimitTransferOwnershipOptimism = _opGasLimit;

        emit SetGasLimitTransferOwnershipOptimism(_opGasLimit);
    }

    ///////////////////////////////////////////////////////////////////
    ///                             BASE                            ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sends the latest WorldID Identity Manager root to all chains.
    /// @dev Calls this method on the L1 Proxy contract to relay roots and timestamps to WorldID supported chains.
    /// @param root The latest WorldID Identity Manager root.
    /// @param timestamp The Ethereum block timestamp of the latest WorldID Identity Manager root.
    function _sendRootToBase(uint256 root, uint128 timestamp) internal {
        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        bytes memory message = abi.encodeCall(IOpWorldID.receiveRoot, (root, timestamp));

        ICrossDomainMessenger(baseCrossDomainMessengerAddress).sendMessage(
            // Contract address on Base
            baseWorldIDAddress,
            message,
            gasLimitSendRootBase
        );
    }

    /// @notice Adds functionality to the StateBridge to transfer ownership
    /// of OpWorldID to another contract on L1 or to a local Base EOA
    /// @param _owner new owner (EOA or contract)
    /// @param _isLocal true if new owner is on Base, false if it is a cross-domain owner
    function transferOwnershipBase(address _owner, bool _isLocal) public onlyOwner {
        bytes memory message;

        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        message = abi.encodeCall(ICrossDomainOwnable3.transferOwnership, (_owner, _isLocal));

        ICrossDomainMessenger(baseCrossDomainMessengerAddress).sendMessage(
            // Contract address on Base
            baseWorldIDAddress,
            message,
            gasLimitTransferOwnershipBase
        );

        emit OwnershipTransferredBase(owner(), _owner, _isLocal);
    }

    /// @notice Adds functionality to the StateBridge to set the root history expiry on OpWorldID
    /// @param _rootHistoryExpiry new root history expiry
    function setRootHistoryExpiryBase(uint256 _rootHistoryExpiry) internal {
        bytes memory message;

        // The `encodeCall` function is strongly typed, so this checks that we are passing the
        // correct data to the optimism bridge.
        message = abi.encodeCall(IRootHistory.setRootHistoryExpiry, (_rootHistoryExpiry));

        ICrossDomainMessenger(baseCrossDomainMessengerAddress).sendMessage(
            // Contract address on Base
            baseWorldIDAddress,
            message,
            gasLimitSetRootHistoryExpiryBase
        );
    }

    ///////////////////////////////////////////////////////////////////
    ///                        BASE GAS LIMIT                       ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sets the gas limit for the Base sendRootMultichain method
    /// @param _baseGasLimit The new gas limit for the sendRootMultichain method
    function setGasLimitSendRootBase(uint32 _baseGasLimit) external onlyOwner {
        gasLimitSendRootBase = _baseGasLimit;

        emit SetGasLimitSendRootBase(_baseGasLimit);
    }

    /// @notice Sets the gas limit for the Base setRootHistoryExpiry method
    /// @param _baseGasLimit The new gas limit for the setRootHistoryExpiry method
    function setGasLimitSetRootHistoryExpiryBase(uint32 _baseGasLimit) external onlyOwner {
        gasLimitSetRootHistoryExpiryBase = _baseGasLimit;

        emit SetGasLimitSetRootHistoryExpiryBase(_baseGasLimit);
    }

    /// @notice Sets the gas limit for the transferOwnershipBase method
    /// @param _baseGasLimit The new gas limit for the transferOwnershipBase method
    function setGasLimitTransferOwnershipBase(uint32 _baseGasLimit) external onlyOwner {
        gasLimitTransferOwnershipBase = _baseGasLimit;

        emit SetGasLimitTransferOwnershipBase(_baseGasLimit);
    }

    ///////////////////////////////////////////////////////////////////
    ///                           POLYGON                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Sends root and timestamp to Polygon's StateChild contract (PolygonWorldID)
    /// @param root The latest WorldID Identity Manager root to be sent to Polygon
    /// @param timestamp The Ethereum block timestamp of the latest WorldID Identity Manager root
    function _sendRootToPolygon(uint256 root, uint128 timestamp) internal {
        bytes memory message;

        message = abi.encodeCall(IPolygonWorldID.receiveRoot, (root, timestamp));

        /// @notice FxBaseRootTunnel method to send bytes payload to FxBaseChildTunnel contract
        _sendMessageToChild(message);
    }

    /// @notice Sets the root history expiry for PolygonWorldID
    /// @param _rootHistoryExpiry The new root history expiry
    function setRootHistoryExpiryPolygon(uint256 _rootHistoryExpiry) internal {
        bytes memory message;

        message = abi.encodeCall(IRootHistory.setRootHistoryExpiry, (_rootHistoryExpiry));

        /// @notice FxBaseRootTunnel method to send bytes payload to FxBaseChildTunnel contract
        _sendMessageToChild(message);
    }

    /// @notice boilerplate function to satisfy FxBaseRootTunnel inheritance (not going to be used)
    function _processMessageFromChild(bytes memory) internal override {
        /// WorldID 🌎🆔 State Bridge
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                            ADDRESS MANAGEMENT                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Sets the `fxChildTunnel` address if not already set.
    /// @dev This implementation replicates the logic from `FxBaseRootTunnel` due to the inability
    ///      to call `external` superclass methods when overriding them.
    ///
    /// @param _fxChildTunnel The address of the child (non-L1) tunnel contract.
    ///
    /// @custom:reverts string If the root tunnel has already been set.
    function setFxChildTunnel(address _fxChildTunnel) public virtual override onlyOwner {
        require(fxChildTunnel == address(0x0), "FxBaseRootTunnel: CHILD_TUNNEL_ALREADY_SET");
        fxChildTunnel = _fxChildTunnel;
    }

    ///////////////////////////////////////////////////////////////////
    ///                          OWNERSHIP                          ///
    ///////////////////////////////////////////////////////////////////
    /// @notice Ensures that ownership of WorldID implementations cannot be renounced.
    /// @dev This function is intentionally not `virtual` as we do not want it to be possible to
    ///      renounce ownership for any WorldID implementation.
    /// @dev This function is marked as `onlyOwner` to maintain the access restriction from the base
    ///      contract.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggGatewayCore } from "../interfaces/IAggGatewayCore.sol";

import { IPolygonZkEVMBridgeV2 } from "../interfaces/IPolygonZkEVMBridgeV2.sol";
import { AggOFTBase } from "./AggOFTBase.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { MessagingFee, OFTReceipt, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";

/**
 * @title AggOFTNativeV1
 * @dev Native implementation of AggOFT (Agglayer Omnichain Fungible Token)
 * This contract is the default token implementation with built-in cross-chain capabilities.
 * Uses LayerZero for messaging and Unified Bridge for asset custody.
 */
contract AggOFTNativeV1 is OFT, AggOFTBase {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;
    using SafeERC20 for IERC20;

    address public immutable MINTER_BURNER;
    address public immutable MIGRATOR;

    error OnlyMinterBurner();
    error MintFailedInvalidAmount();
    error BurnFailedInvalidAmount();

    modifier onlyMinterBurner() {
        if (msg.sender != owner() && msg.sender != MINTER_BURNER && msg.sender != MIGRATOR) revert OnlyMinterBurner();
        _;
    }

    /**
     * @dev Constructor initializes the AggOFTNativeV1 token
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param lzEndpoint The LayerZero endpoint address
     * @param delegate The delegate capable of making OApp configurations inside of the endpoint
     * @param gatewayCore The AggGatewayCore contract that tracks global supply
     * @param _unifiedBridge The Unified Bridge address for token locking
     * @param _migrator The AggOFTMigrator contract address
     * @param initialChains Initial array of authorized chain IDs
     */
    constructor(
        string memory name,
        string memory symbol,
        address lzEndpoint,
        address delegate,
        address gatewayCore,
        address _unifiedBridge,
        address _migrator,
        uint32[] memory initialChains
    )
        OFT(name, symbol, lzEndpoint, delegate)
        AggOFTBase(IAggGatewayCore(gatewayCore), _unifiedBridge, initialChains, delegate)
    {
        if (lzEndpoint == address(0) || gatewayCore == address(0) || delegate == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        MINTER_BURNER = _unifiedBridge;
        MIGRATOR = _migrator;
    }

    /**
     * @notice Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyMinterBurner {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert MintFailedInvalidAmount();

        super._mint(to, amount);
        GATEWAY.mintSupply(address(this), amount);
    }

    /**
     * @notice Burns tokens from the specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyMinterBurner {
        if (from == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert BurnFailedInvalidAmount();

        super._burn(from, amount);
        GATEWAY.burnSupply(address(this), amount);
    }

    /**
     * @notice Sends tokens with a composed message to the destination chain
     * @param spCalldata The parameters for the send operation.
     * @param fee The calculated fee for the send() operation.
     * @param refundAddr The address to receive any excess funds.
     */
    function sendWithCompose(SendParam calldata spCalldata, MessagingFee calldata fee, address refundAddr)
        external
        payable
        override
    {
        if (!authorizedChains[spCalldata.dstEid]) revert UnauthorizedChain();
        if (spCalldata.amountLD == 0) revert InvalidAmount();
        if (refundAddr == address(0)) revert ZeroAddressNotAllowed();

        // Generate compose message
        bytes memory composeMsg = abi.encodePacked(bytes32(uint256(uint160(msg.sender))), spCalldata.composeMsg);

        // Convert to LZ message format with sender info
        bytes memory lzMessage = abi.encode(
            uint32(0), // Local chain ID
            address(this), // This contract address
            spCalldata.amountLD,
            msg.sender,
            composeMsg
        );

        // Send via _lzSend
        MessagingReceipt memory receipt =
            _lzSend(spCalldata.dstEid, lzMessage, spCalldata.extraOptions, fee, refundAddr);

        // Check receipt
        if (receipt.guid == bytes32(0)) revert LzEndpointSendFailed();

        // Handle bridge asset with transfer
        if (UNIFIED_BRIDGE != address(0)) {
            _bridgeAssetWithTransferInternal(spCalldata.dstEid, spCalldata.to, spCalldata.amountLD, address(this));
        }
    }

    /**
     * @notice Simplified function to send tokens to another chain
     * @param dstEid The destination chain ID
     * @param to The recipient address on the destination chain
     * @param amount The amount of tokens to send
     */
    function sendTokens(uint32 dstEid, address to, uint256 amount) external payable {
        if (!authorizedChains[dstEid]) revert UnauthorizedChain();
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert InvalidAmount();

        SendParam memory sp = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: bytes(""),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });
        MessagingFee memory messagingFee = this.quoteSend(sp, false);
        // Use msg.sender as refund address
        this.sendWithCompose(sp, messagingFee, msg.sender);
    }

    /**
     * @dev Internal version of bridgeAssetWithTransfer that does not use nonReentrant
     * to avoid reentrancy conflicts when called from sendWithCompose.
     */
    function _bridgeAssetWithTransferInternal(uint32 dstEid, bytes32 to, uint256 amount, address _token) internal {
        if (!authorizedChains[dstEid]) revert UnauthorizedChain();
        if (amount == 0) revert InvalidAmount();
        if (_token == address(0)) revert ZeroAddressNotAllowed();

        // Transfer tokens from sender to this contract using SafeERC20
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Use forceApprove to safely approve the bridge
        SafeERC20.forceApprove(token, UNIFIED_BRIDGE, amount);

        // Call bridgeAsset on the Unified Bridge
        try IPolygonZkEVMBridgeV2(payable(UNIFIED_BRIDGE)).bridgeAsset(
            dstEid, // destination network ID
            address(uint160(uint256(to))), // destination address (convert bytes32 to address)
            amount, // amount to bridge
            _token, // token address
            false, // forceUpdateGlobalExitRoot (false for simplicity)
            "" // permitData (empty for simplicity)
        ) {
            // Bridging successful
            emit TokensBridgedWithPolygon(_token, address(uint160(uint256(to))), amount, dstEid);
        } catch Error(string memory reason) {
            // Bubble up the revert reason in a custom error
            revert BridgeAssetFailedWithReason(reason);
        } catch Panic(uint256 errorCode) {
            // Handle panic error codes explicitly
            revert BridgeAssetFailedWithPanic(errorCode);
        } catch (bytes memory lowLevelData) {
            if (lowLevelData.length == 0) revert ZeroLengthBridgeRevert();
            // Bubble up the original revert data so the caller sees the bridge's custom error
            assembly {
                revert(add(lowLevelData, 32), mload(lowLevelData))
            }
        }
    }

    /**
     * @dev Override the OFT _debit function to not burn tokens from the sender's specified balance,
     *  since they will be locked in the Unified Bridge.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(address, /*_from*/ uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Ensure minimum amount criteria is met
        if (amountReceivedLD < _minAmountLD) revert SlippageExceeded(amountReceivedLD, _minAmountLD);

        return (amountSentLD, amountReceivedLD);
    }

    /**
     * @dev Override the OFT _credit function to not mint tokens to the specified address since they will be unlocked in
     * the Unified Bridge.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(address _to, uint256 _amountLD, uint32 /*_srcEid*/ )
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0x0)) _to = address(0xdead); // _mint(...) does not support address(0x0)
        // @dev We don't need to mint tokens here, since they will be minted when the tokens are bridged.
        return _amountLD;
    }

    function _sendMemory(SendParam memory sp, MessagingFee calldata fee, address refundAddr)
        internal
        returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt)
    {
        // Encode the memory struct into bytes
        bytes memory blob = abi.encode(sp);

        // Create a calldata reference to the encoded data
        SendParam calldata spCD;
        assembly {
            spCD := add(blob, 0x20)
        }

        (receipt, oftReceipt) = super._send(spCD, fee, refundAddr);
    }

    function _extractOriginFromPayload(bytes calldata payload)
        internal
        pure
        override
        returns (uint32 originNet, address originAddr, bytes memory actualPayload)
    {
        (uint32 net, address addr, uint256 amountLD, address sender, bytes memory userCompose) =
            abi.decode(payload, (uint32, address, uint256, address, bytes));
        originNet = net;
        originAddr = addr;
        actualPayload = abi.encode(amountLD, sender, userCompose);
    }
}

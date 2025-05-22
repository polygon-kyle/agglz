// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggGatewayCore } from "../interfaces/IAggGatewayCore.sol";
import { AggOFTBase } from "./AggOFTBase.sol";

import { MessagingFee, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";

/**
 * @title AggOFTAdapterV1
 * @dev Adapter implementation of AggOFT (Agglayer Omnichain Fungible Token)
 * Wraps existing ERC20 tokens and provides cross-chain capabilities.
 * Uses LayerZero for messaging and Unified Bridge for asset custody.
 */
contract AggOFTAdapterV1 is OFTAdapter, AggOFTBase {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    // Custom errors
    error InitFailed();
    error TransferFromFailed();
    error ApprovalFailed();

    /**
     * @dev Constructor initializes the AggOFTAdapterV1 token
     * @param _innerToken The address of the token being wrapped
     * @param lzEndpoint The LayerZero endpoint address
     * @param delegate The delegate capable of making OApp configurations inside of the endpoint
     * @param gatewayCore The AggGatewayCore contract that tracks global supply
     * @param _unifiedBridge The Unified Bridge address for token locking
     * @param initialChains Initial array of authorized chain IDs
     */
    constructor(
        address _innerToken,
        address lzEndpoint,
        address delegate,
        address gatewayCore,
        address _unifiedBridge,
        uint32[] memory initialChains
    )
        OFTAdapter(_innerToken, lzEndpoint, delegate)
        AggOFTBase(IAggGatewayCore(gatewayCore), _unifiedBridge, initialChains, delegate)
    {
        // Validate critical addresses
        if (_innerToken == address(0) || lzEndpoint == address(0) || gatewayCore == address(0)) {
            revert ZeroAddressNotAllowed();
        }
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
        nonReentrant
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
            _bridgeAssetWithTransfer(spCalldata.dstEid, spCalldata.to, spCalldata.amountLD, address(innerToken));
        }

        GATEWAY.burnSupply(address(innerToken), spCalldata.amountLD);
    }

    /**
     * @notice Simplified function to send tokens to another chain
     * @param dstEid The destination chain ID
     * @param to The recipient address on the destination chain
     * @param amount The amount of tokens to send
     */
    function sendTokens(uint32 dstEid, address to, uint256 amount) external payable nonReentrant {
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
        MessagingFee memory fee = this.quoteSend(sp, false);
        // Use msg.sender as refund address
        this.sendWithCompose(sp, fee, msg.sender);
    }

    /**
     * @notice Sets or removes a trusted peer for a given endpoint
     * @param _eid The endpoint ID
     * @param _peer The peer address
     * @param _trusted True to set as trusted, false to remove
     */
    function setTrustedPeer(uint32 _eid, bytes32 _peer, bool _trusted) external onlyOwner {
        if (_trusted) setPeer(_eid, _peer);
        else setPeer(_eid, bytes32(0));
    }

    /**
     * @notice Returns the local decimals of the wrapped token
     */
    function localDecimals() public view returns (uint8 decimals) {
        // OFTCore stores local decimals as immutable
        decimals = IERC20Metadata(token()).decimals();
    }

    /**
     * @notice Returns the balance of the wrapped token for an account
     */
    function balanceOf(address account) public view returns (uint256 balance) {
        balance = IERC20(token()).balanceOf(account);
    }

    /**
     * @notice Returns the address of the wrapped token (alias for token())
     */
    function getToken() public view returns (address tokenAddress) {
        tokenAddress = token();
    }

    /**
     * @dev Override the OFT _debit function to not burn tokens from the sender's balance,
     * since they will be locked in the Unified Bridge.
     */
    function _debit(address, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        // Call the view function to calculate send/receive amounts
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Ensure minimum amount criteria is met
        if (amountReceivedLD < _minAmountLD) revert SlippageExceeded(amountReceivedLD, _minAmountLD);

        return (amountSentLD, amountReceivedLD);
    }

    /**
     * @dev Override the OFT _credit function to not mint tokens to the specified address
     * since they will be unlocked from the Unified Bridge.
     */
    function _credit(address _to, uint256 _amountLD, uint32 /*_srcEid*/ )
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0x0)) _to = address(0xdead);
        // No need to mint tokens here, they will be claimed from the bridge
        return _amountLD;
    }

    /**
     * @dev Internal function to execute the send operation with calldata parameters.
     * @param _sendParam The parameters for the send operation in calldata.
     * @param _fee The calculated fee for the send() operation in calldata.
     * @param _refundAddress The address to receive any excess funds.
     * @return msgReceipt The receipt for the send operation.
     * @return oftReceipt The OFT receipt information.
     */
    function _executeSend(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        internal
        virtual
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // Call parent class's _send function with calldata parameters
        return super._send(_sendParam, _fee, _refundAddress);
    }

    function _sendMemory(SendParam memory sp, MessagingFee calldata fee, address refundAddr)
        internal
        returns (MessagingReceipt memory messageReceipt, OFTReceipt memory oftReceipt)
    {
        // encode–decode trick to obtain a *calldata* struct without copying fields one-by-one
        bytes memory blob = abi.encode(sp);
        SendParam calldata spCD;
        assembly {
            spCD := add(blob, 0x20)
        }
        (messageReceipt, oftReceipt) = super._send(spCD, fee, refundAddr);
    }
}

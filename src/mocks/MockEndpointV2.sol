// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroReceiver } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";

/**
 * @title MockEndpointV2
 * @dev A simplified mock of the LayerZero EndpointV2 contract for testing
 */
contract MockEndpointV2 {
    // Tracking variables
    mapping(address => mapping(uint32 => mapping(bytes32 => uint64))) public outboundNonce;
    mapping(address => address) public delegates;

    event SendRequested(
        address sender, uint32 dstEid, bytes32 receiver, bytes message, bytes options, bool payInLzToken
    );
    event PacketSent(bytes encodedPacket, bytes options, address sendLibrary);
    event PacketDelivered(Origin origin, address receiver);

    /**
     * @dev Sets a delegate for the caller
     * @param _delegate The address to set as delegate
     */
    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    /**
     * @dev Mock implementation of send function
     * @param _params The messaging parameters
     */
    function send(MessagingParams calldata _params, address /* _refundAddress */ )
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        // Increment outbound nonce
        uint64 nonce = ++outboundNonce[msg.sender][_params.dstEid][_params.receiver];

        // Generate a mock GUID
        bytes32 guid = keccak256(abi.encodePacked(nonce, uint32(1), msg.sender, _params.dstEid, _params.receiver));

        // Create a simple fee structure - in real implementation this would be calculated
        MessagingFee memory fee = MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 });

        // Mock the packet being sent
        bytes memory encodedPacket = abi.encodePacked(guid, _params.message);
        emit PacketSent(encodedPacket, _params.options, address(this));
        emit SendRequested(
            msg.sender, _params.dstEid, _params.receiver, _params.message, _params.options, _params.payInLzToken
        );

        // Return a receipt
        return MessagingReceipt({ guid: guid, nonce: nonce, fee: fee });
    }

    /**
     * @dev Mock implementation for the OFT _send function
     */
    function _send(
        address _msgSender,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256, /* _minAmountLD */
        bytes memory _extraOptions,
        bool _payInLzToken,
        bytes memory, /* _composeMsg */
        bytes memory /* _oftCmd */
    ) external payable returns (bytes32 guid) {
        // Generate a mock GUID
        guid = keccak256(abi.encodePacked(_msgSender, _dstEid, _to, _amountLD, block.timestamp));

        // Log the send request
        emit SendRequested(_msgSender, _dstEid, _to, abi.encodePacked(_amountLD), _extraOptions, _payInLzToken);

        return guid;
    }

    /// @dev MESSAGING STEP 3 - the last step
    /// @dev execute a verified message to the designated receiver
    /// @dev the execution provides the execution context (caller, extraData) to the receiver. the receiver can
    /// optionally assert the caller and validate the untrusted extraData
    /// @dev cant reentrant because the payload is cleared before execution
    /// @param _origin the origin of the message
    /// @param _receiver the receiver of the message
    /// @param _guid the guid of the message
    /// @param _message the message
    /// @param _extraData the extra data provided by the executor. this data is untrusted and should be validated.
    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable {
        // clear the payload first to prevent reentrancy, and then execute the message
        ILayerZeroReceiver(_receiver).lzReceive{ value: msg.value }(_origin, _guid, _message, msg.sender, _extraData);
        emit PacketDelivered(_origin, _receiver);
    }

    /**
     * @dev Mock implementation of hasPeer function
     */
    function hasPeer(uint32 /* _eid */ ) external pure returns (bool) {
        // In a real implementation, this would check if the endpoint has a peer for the given eid
        return true;
    }
}

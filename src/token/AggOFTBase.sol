// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggGatewayCore } from "../interfaces/IAggGatewayCore.sol";

import { IPolygonZkEVMBridgeV2 } from "../interfaces/IPolygonZkEVMBridgeV2.sol";

import { MessagingFee, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
/**
 * @title AggOFTBase
 * @dev Abstract base contract for AggOFT implementations with common functionality
 * for both Adapter and Native implementations
 */

abstract contract AggOFTBase is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Constant for the exit network ID
    uint32 private constant _EXIT_NETWORK_ID = 9999;

    /// @dev Reference to the AggGatewayCore contract
    IAggGatewayCore public immutable GATEWAY;

    /// @dev Address of the Unified Bridge contract
    address public immutable UNIFIED_BRIDGE;

    /// @dev Chain IDs that are authorized for bridging
    mapping(uint32 chainId => bool authorized) public authorizedChains;

    /// @dev Mapping of addresses authorized to call restricted functions
    mapping(address caller => bool isAuthorized) public isAuthorizedCaller;

    /// @dev Emitted when tokens are bridged
    event TokensBridgedWithPolygon(
        address indexed token, address indexed recipient, uint256 amount, uint32 sourceChainId
    );

    /// @dev Emitted when tokens are claimed
    event TokenClaimedFromPolygon(address indexed token, address indexed to, uint256 amount, uint32 srcEid);

    /// @dev Emitted when a chain is authorized or unauthorized
    event ChainAuthorized(uint32 chainId, bool status);

    /// @dev Emitted when a caller is authorized or unauthorized
    event CallerAuthorized(address caller, bool status);

    /// @dev Event emitted when tokens exit the Agglayer ecosystem
    event TokenExited(address indexed token, address indexed sender, uint256 amount);

    /// @dev Custom errors for reverts
    error UnauthorizedChain();
    error UnauthorizedCaller();
    error InvalidCommand();
    error LzEndpointSendFailed();
    error BridgeAssetFailedWithReason(string reason);
    error BridgeAssetFailedWithPanic(uint256 errorCode);
    error ClaimAssetFailed();
    error TransferFailed(uint256);
    error ApproveBridgeFailed();
    error ZeroLengthBridgeRevert();
    error ZeroAddressNotAllowed();
    error InvalidAmount();
    error FailedTokenTransfer();

    /**
     * @dev Constructor initializes the AggOFTBase contract
     * @param gatewayCore The AggGatewayCore contract that tracks global supply
     * @param _unifiedBridge The Unified Bridge address for token locking
     * @param initialChains Initial array of authorized chain IDs
     */
    constructor(IAggGatewayCore gatewayCore, address _unifiedBridge, uint32[] memory initialChains, address owner)
        Ownable(owner)
    {
        if (address(gatewayCore) == address(0)) revert ZeroAddressNotAllowed();

        GATEWAY = gatewayCore;
        UNIFIED_BRIDGE = _unifiedBridge;

        // Set initial authorized chains
        for (uint256 i = 0; i < initialChains.length; ++i) {
            authorizedChains[initialChains[i]] = true;
            emit ChainAuthorized(initialChains[i], true);
        }
    }

    /**
     * @dev Authorizes or revokes a chain ID
     * @param chainId The chain ID
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedChain(uint32 chainId, bool authorized) external onlyOwner {
        authorizedChains[chainId] = authorized;
        emit ChainAuthorized(chainId, authorized);
    }

    /**
     * @dev Authorizes or revokes a caller
     * @param caller The caller address
     * @param status True to authorize, false to revoke
     */
    function setCallerStatus(address caller, bool status) external onlyOwner {
        if (caller == address(0)) revert ZeroAddressNotAllowed();
        isAuthorizedCaller[caller] = status;
        emit CallerAuthorized(caller, status);
    }

    /**
     * @notice Sends tokens with a composed message to the destination chain
     * @param _sendParam The parameters for the send operation.
     * @param _fee The calculated fee for the send() operation.
     * @param _refundAddress The address to receive any excess funds.
     */
    function sendWithCompose(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        virtual;

    function isAuthorizedChain(uint32 _chainId) public view returns (bool authorized) {
        return authorizedChains[_chainId];
    }

    /**
     * @dev Helper function to claim tokens from the bridge
     * @param srcEid Source chain ID
     * @param to Recipient address
     * @param amountLD Amount in local decimals
     * @param tokenAddress The token address to claim
     */
    function _claimFromBridge(uint32 srcEid, address to, uint256 amountLD, address tokenAddress)
        internal
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amountLD == 0) revert InvalidAmount();
        if (tokenAddress == address(0)) revert ZeroAddressNotAllowed();

        // Create empty arrays for the merkle proofs (not needed in mock)
        bytes32[32] memory emptyProof;

        // Use a simplified global index for testing (can be any unique value)
        uint256 globalIndex = uint256(keccak256(abi.encodePacked(srcEid, to, amountLD, block.timestamp)));

        // For simplicity, we use empty values for the root parameters
        bytes32 emptyRoot;

        // Call the claimAsset function on the mock bridge
        try IPolygonZkEVMBridgeV2(payable(UNIFIED_BRIDGE)).claimMessage(
            emptyProof, // smtProofLocalExitRoot (ignored in mock)
            emptyProof, // smtProofRollupExitRoot (ignored in mock)
            globalIndex, // A unique identifier for this claim
            emptyRoot, // mainnetExitRoot (ignored in mock)
            emptyRoot, // rollupExitRoot (ignored in mock)
            srcEid, // Origin network/chain ID
            tokenAddress, // Origin token address
            uint32(block.chainid), // Destination network (current chain)
            to, // Destination address
            amountLD, // Amount of tokens
            "" // metadata (empty for simplicity)
        ) {
            emit TokenClaimedFromPolygon(tokenAddress, to, amountLD, srcEid);
        } catch {
            revert ClaimAssetFailed();
        }
    }

    /**
     * @dev Helper function to bridge assets
     * @param dstEid Destination chain ID
     * @param to Recipient address as bytes32
     * @param amount Amount to bridge
     * @param tokenAddress The token address to bridge
     */
    function _bridgeAsset(uint32 dstEid, bytes32 to, uint256 amount, address tokenAddress) internal nonReentrant {
        if (!authorizedChains[dstEid]) revert UnauthorizedChain();
        if (amount == 0) revert InvalidAmount();
        if (tokenAddress == address(0)) revert ZeroAddressNotAllowed();

        // Call bridgeAsset on the Unified Bridge
        try IPolygonZkEVMBridgeV2(payable(UNIFIED_BRIDGE)).bridgeAsset(
            dstEid, // destination network ID
            address(uint160(uint256(to))), // destination address (convert bytes32 to address)
            amount, // amount to bridge
            tokenAddress, // token address
            false, // forceUpdateGlobalExitRoot (false for simplicity)
            "" // permitData (empty for simplicity)
        ) {
            // Bridging successful
            emit TokensBridgedWithPolygon(tokenAddress, address(uint160(uint256(to))), amount, dstEid);
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
     * @dev Helper function to bridge assets with approval for ERC20 tokens
     * @param dstEid Destination chain ID
     * @param to Recipient address as bytes32
     * @param amount Amount to bridge
     * @param _token Token address
     */
    function _bridgeAssetWithTransfer(uint32 dstEid, bytes32 to, uint256 amount, address _token)
        internal
        nonReentrant
    {
        if (!authorizedChains[dstEid]) revert UnauthorizedChain();
        if (amount == 0) revert InvalidAmount();
        if (_token == address(0)) revert ZeroAddressNotAllowed();

        // Transfer tokens from sender to this contract using SafeERC20
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Use forceApprove to safely approve the bridge
        SafeERC20.forceApprove(token, UNIFIED_BRIDGE, amount);

        // Use the common implementation from the base class
        _bridgeAsset(dstEid, to, amount, _token);
    }

    /**
     * @dev Extracts token origin information from a message payload
     * @param payload The payload containing origin information
     * @return originNet The origin chain ID
     * @return originAddr The origin token address
     * @return actualPayload The original payload without origin information
     */
    function _extractOriginFromPayload(bytes calldata payload)
        internal
        pure
        virtual
        returns (uint32 originNet, address originAddr, bytes memory actualPayload)
    {
        originNet = uint32(bytes4(payload[0:4]));
        originAddr = address(bytes20(payload[4:24]));
        actualPayload = payload[24:];
    }

    function _unwrapCompose(bytes calldata payload)
        internal
        pure
        returns (uint32 originNet, address originAddr, uint256 amt, address sender, bytes memory userCompose)
    {
        return abi.decode(payload, (uint32, address, uint256, address, bytes));
    }
}

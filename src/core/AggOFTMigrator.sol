// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggGatewayCore } from "../interfaces/IAggGatewayCore.sol";

import { IAggOFTFactory } from "../interfaces/IAggOFTFactory.sol";
import { AggOFTNativeV1 } from "../token/AggOFTNativeV1.sol";

import { SimpleERC20 } from "../token/SimpleERC20.sol";
import { SimpleOFT } from "../token/SimpleOFT.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AggOFTMigrator
 * @dev Manages migration between different token implementations
 * This contract handles the creation of SimpleOFT instances and migration of tokens
 */
contract AggOFTMigrator is Ownable {
    /// @notice LayerZero endpoint address
    address public immutable LZ_ENDPOINT;

    /// @notice Gateway Core contract that tracks global supply
    IAggGatewayCore public immutable GATEWAY;

    /// @notice Unified Bridge contract address
    address public immutable UNIFIED_BRIDGE;

    /// @notice AggOFTFactory contract address
    IAggOFTFactory public immutable FACTORY;

    /// @dev Token type enum for downgrade options
    enum TokenType {
        ERC20,
        OFT
    }

    // Mapping to track deployed SimpleOFT contracts for each source token
    mapping(address => address) public deployedOFTs;

    // Mapping to track deployed SimpleERC20 contracts for each source token
    mapping(address => address) public deployedERC20;

    // Mapping to track deployed AggOFT adapters for each source token
    mapping(address => address) public deployedAggOFTs;

    // Event emitted when a token is downgraded
    event TokenDowngraded(address indexed aggOFT, address indexed simpleToken, address user, uint256 amount);

    // Event emitted when a token is upgraded
    event TokenUpgraded(address indexed sourceToken, address indexed aggOFT, address user);

    // Event emitted when a SimpleOFT is deployed
    event SimpleOFTDeployed(address indexed aggOFT, address indexed simpleOFT);

    // Event emitted when a SimpleERC20 is deployed
    event ERC20Deployed(address indexed aggOFT, address indexed simpleERC20);

    // Event emitted when an AggOFT adapter is deployed
    event AggOFTDeployed(address indexed sourceToken, address indexed aggOFT);

    // Event emitted when deployment fails
    event DeploymentFailed(address indexed sourceToken);

    error NoTokens();
    error TransferFailed();
    error DeploymentError();
    error AddressMismatch();
    error AlreadyAggOFT();
    error NotAggOFT();
    error InsufficientAllowance();
    error UnsupportedType();

    constructor(address lzEndpoint, address gatewayCore, address initialOwner, address unifiedBridge, address factory)
        Ownable(initialOwner)
    {
        LZ_ENDPOINT = lzEndpoint;
        GATEWAY = IAggGatewayCore(gatewayCore);
        UNIFIED_BRIDGE = unifiedBridge;
        FACTORY = IAggOFTFactory(factory);
    }

    /**
     * @notice Upgrade legacy ERC20 tokens to AggOFT adapter
     * @param sourceToken The ERC20 token to upgrade
     * @param initialChains Initial authorized chains
     * @param amount Amount of tokens (0 for full balance)
     * @return aggOFTAddress The adapter address
     */
    function upgradeToAggOFT(address sourceToken, uint32[] calldata initialChains, uint256 amount)
        external
        returns (address aggOFTAddress)
    {
        // Check if already an AggOFT
        if (GATEWAY.isAggOFT(sourceToken)) revert AlreadyAggOFT();

        // Check for existing deployment
        aggOFTAddress = deployedAggOFTs[sourceToken];

        if (aggOFTAddress == address(0)) {
            // Deploy new adapter
            aggOFTAddress = FACTORY.deployAdapter(sourceToken, initialChains);
            deployedAggOFTs[sourceToken] = aggOFTAddress;
            emit AggOFTDeployed(sourceToken, aggOFTAddress);
        }

        // Calculate amount
        uint256 transferAmount = amount == 0 ? IERC20(sourceToken).balanceOf(msg.sender) : amount;
        if (transferAmount == 0) revert NoTokens();

        // Check allowance
        if (IERC20(sourceToken).allowance(msg.sender, address(this)) < transferAmount) revert InsufficientAllowance();

        // Transfer tokens
        if (!IERC20(sourceToken).transferFrom(msg.sender, aggOFTAddress, transferAmount)) revert TransferFailed();

        emit TokenUpgraded(sourceToken, aggOFTAddress, msg.sender);
        return aggOFTAddress;
    }

    /**
     * @notice Generic function to downgrade tokens
     * @param sourceToken The AggOFT token to downgrade
     * @param tokenType The target token type
     * @param amount Amount to downgrade (0 for full balance)
     * @return targetAddress The downgraded token address
     */
    function downgradeToken(address sourceToken, TokenType tokenType, uint256 amount)
        external
        returns (address targetAddress)
    {
        // Validate source token
        if (!GATEWAY.isAggOFT(sourceToken)) revert NotAggOFT();

        // Get token reference
        AggOFTNativeV1 aggOFT = AggOFTNativeV1(sourceToken);

        // Check for existing deployment
        if (tokenType == TokenType.OFT) targetAddress = deployedOFTs[sourceToken];
        else if (tokenType == TokenType.ERC20) targetAddress = deployedERC20[sourceToken];
        else revert UnsupportedType();

        // Deploy if needed
        if (targetAddress == address(0)) {
            // Get token details
            string memory name = aggOFT.name();
            string memory symbol = aggOFT.symbol();

            // Prepare data for deployment
            uint256 salt = uint256(keccak256(abi.encodePacked(sourceToken, block.chainid, uint8(tokenType))));
            bytes memory bytecode;

            if (tokenType == TokenType.OFT) {
                bytecode =
                    abi.encodePacked(type(SimpleOFT).creationCode, abi.encode(name, symbol, LZ_ENDPOINT, owner()));
            } else {
                bytecode = abi.encodePacked(
                    type(SimpleERC20).creationCode, abi.encode(name, symbol, aggOFT.decimals(), UNIFIED_BRIDGE)
                );
            }

            // Calculate address and check for existing code
            bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
            address predictedAddress = address(uint160(uint256(hash)));

            uint256 size;
            assembly {
                size := extcodesize(predictedAddress)
            }

            // Deploy if needed
            if (size == 0) {
                address deployed;
                assembly {
                    deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
                }

                if (deployed == address(0)) {
                    emit DeploymentFailed(sourceToken);
                    revert DeploymentError();
                }

                if (deployed != predictedAddress) revert AddressMismatch();

                targetAddress = deployed;
            } else {
                targetAddress = predictedAddress;
            }

            // Record deployment
            if (tokenType == TokenType.OFT) {
                deployedOFTs[sourceToken] = targetAddress;
                emit SimpleOFTDeployed(sourceToken, targetAddress);
            } else {
                deployedERC20[sourceToken] = targetAddress;
                emit ERC20Deployed(sourceToken, targetAddress);
            }
        }

        // Process the token migration
        uint256 transferAmount = amount == 0 ? aggOFT.balanceOf(msg.sender) : amount;
        if (transferAmount == 0) revert NoTokens();

        if (IERC20(sourceToken).allowance(msg.sender, address(this)) < transferAmount) revert InsufficientAllowance();

        if (!IERC20(sourceToken).transferFrom(msg.sender, address(this), transferAmount)) revert TransferFailed();

        // Burn and mint
        aggOFT.burn(address(this), transferAmount);

        if (tokenType == TokenType.OFT) SimpleOFT(targetAddress).mint(msg.sender, transferAmount);
        else SimpleERC20(targetAddress).mint(msg.sender, transferAmount);

        emit TokenDowngraded(sourceToken, targetAddress, msg.sender, transferAmount);
        return targetAddress;
    }
}

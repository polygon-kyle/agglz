// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { PolygonZkEVMBridge } from "../mocks/PolygonZkEVMBridge.sol";
import { TokenWrapped } from "../token/TokenWrapped.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BridgeL2SovereignChain is PolygonZkEVMBridge {
    // Bridge manager address; can set custom mapping for any token
    address public bridgeManager;

    // Map to store wrappedAddresses that are not mintable
    mapping(address sovereignTokenAddress => bool isNotMintable) public wrappedAddressIsNotMintable;

    /**
     * @dev Emitted when a bridge manager is updated
     */
    event SetBridgeManager(address bridgeManager);

    /**
     * @dev Emitted when a token address is remapped by a sovereign token address
     */
    event SetSovereignTokenAddress(
        uint32 originNetwork, address originTokenAddress, address sovereignTokenAddress, bool isNotMintable
    );

    /**
     * @dev Emitted when a remapped token is removed from mapping
     */
    event RemoveLegacySovereignTokenAddress(address sovereignTokenAddress);

    /**
     * @dev Emitted when a WETH address is remapped by a sovereign WETH address
     */
    event SetSovereignWETHAddress(address sovereignWETHTokenAddress, bool isNotMintable);

    /**
     * @dev Emitted when a legacy token is migrated to a new token
     */
    event MigrateLegacyToken(address sender, address legacyTokenAddress, address updatedTokenAddress, uint256 amount);

    // Error definitions
    error InvalidZeroAddress();
    error OriginNetworkInvalid();
    error TokenAlreadyMapped();
    error InputArraysLengthMismatch();
    error OnlyBridgeManager();
    error TokenNotMapped();
    error TokenAlreadyUpdated();
    error WETHRemappingNotSupportedOnGasTokenNetworks();
    error TokenNotRemapped();

    modifier onlyBridgeManager() {
        if (bridgeManager != msg.sender) revert OnlyBridgeManager();
        _;
    }

    constructor(address _bridgeManager) PolygonZkEVMBridge() {
        bridgeManager = _bridgeManager;
    }

    /**
     * @notice Remap multiple wrapped tokens to a new sovereign token address
     * @dev This function is a "multi/batch call" to `setSovereignTokenAddress`
     * @param originNetworks Array of Origin networks
     * @param originTokenAddresses Array od Origin token addresses, 0 address is reserved for ether
     * @param sovereignTokenAddresses Array of Addresses of the sovereign wrapped token
     * @param isNotMintable Array of Flags to indicate if the wrapped token is not mintable
     */
    function setMultipleSovereignTokenAddress(
        uint32[] calldata originNetworks,
        address[] calldata originTokenAddresses,
        address[] calldata sovereignTokenAddresses,
        bool[] calldata isNotMintable
    ) external onlyBridgeManager {
        if (
            originNetworks.length != originTokenAddresses.length
                || originNetworks.length != sovereignTokenAddresses.length || originNetworks.length != isNotMintable.length
        ) revert InputArraysLengthMismatch();

        // Make multiple calls to setSovereignTokenAddress
        for (uint256 i = 0; i < sovereignTokenAddresses.length; i++) {
            _setSovereignTokenAddress(
                originNetworks[i], originTokenAddresses[i], sovereignTokenAddresses[i], isNotMintable[i]
            );
        }
    }

    /**
     * @notice Updated bridge manager address, recommended to set a timelock at this address after bootstrapping phase
     * @param _bridgeManager Bridge manager address
     */
    function setBridgeManager(address _bridgeManager) external onlyBridgeManager {
        bridgeManager = _bridgeManager;
        emit SetBridgeManager(bridgeManager);
    }

    /**
     * @notice Remove the address of a remapped token from the mapping. Used to stop supporting legacy sovereign tokens
     * @notice It also removes the token from the isNotMintable mapping
     * @notice Although the token is removed from the mapping, the user will still be able to withdraw their tokens
     * using tokenInfoToWrappedToken mapping
     * @param legacySovereignTokenAddress Address of the sovereign wrapped token
     */
    function removeLegacySovereignTokenAddress(address legacySovereignTokenAddress) external onlyBridgeManager {
        // Only allow to remove already remapped tokens
        TokenInformation memory tokenInfo = wrappedTokenToTokenInfo[legacySovereignTokenAddress];
        bytes32 tokenInfoHash = keccak256(abi.encodePacked(tokenInfo.originNetwork, tokenInfo.originTokenAddress));

        if (
            tokenInfoToWrappedToken[tokenInfoHash] == address(0)
                || tokenInfoToWrappedToken[tokenInfoHash] == legacySovereignTokenAddress
        ) revert TokenNotRemapped();
        delete wrappedTokenToTokenInfo[legacySovereignTokenAddress];
        delete wrappedAddressIsNotMintable[legacySovereignTokenAddress];
        emit RemoveLegacySovereignTokenAddress(legacySovereignTokenAddress);
    }

    /**
     * @notice Moves old native or remapped token (legacy) to the new mapped token. If the token is mintable, it will be
     * burnt and minted, otherwise it will be transferred
     * @param legacyTokenAddress Address of legacy token to migrate
     * @param amount Legacy token balance to migrate
     */
    function migrateLegacyToken(address legacyTokenAddress, uint256 amount) external {
        // Get current wrapped token address
        TokenInformation memory legacyTokenInfo = wrappedTokenToTokenInfo[legacyTokenAddress];
        if (legacyTokenInfo.originTokenAddress == address(0)) revert TokenNotMapped();

        // Check current token mapped is proposed updatedTokenAddress
        address currentTokenAddress = tokenInfoToWrappedToken[keccak256(
            abi.encodePacked(legacyTokenInfo.originNetwork, legacyTokenInfo.originTokenAddress)
        )];

        if (currentTokenAddress == legacyTokenAddress) revert TokenAlreadyUpdated();

        // Proceed to migrate the token
        if (wrappedAddressIsNotMintable[legacyTokenAddress]) {
            // Transfer to this contract if not mintable
            IERC20(legacyTokenAddress).transferFrom(msg.sender, address(this), amount);
        } else {
            // Burn tokens
            TokenWrapped(legacyTokenAddress).burn(msg.sender, amount);
        }

        if (wrappedAddressIsNotMintable[currentTokenAddress]) {
            // Transfer tokens
            IERC20(currentTokenAddress).transfer(msg.sender, amount);
        } else {
            // Claim tokens
            TokenWrapped(currentTokenAddress).mint(msg.sender, amount);
        }

        // Trigger event
        emit MigrateLegacyToken(msg.sender, legacyTokenAddress, currentTokenAddress, amount);
    }

    /**
     * @notice Set the custom wrapper for weth
     * @notice If this function is called multiple times this will override the previous calls and only keep the last
     * WETHToken.
     * @notice WETH will not maintain legacy versions.Users easily should be able to unwrapp the legacy WETH and unwrapp
     * it with the new one.
     * @param sovereignWETHTokenAddress Address of the sovereign weth token
     * @param isNotMintable Flag to indicate if the wrapped token is not mintable
     */
    function setSovereignWETHAddress(address sovereignWETHTokenAddress, bool isNotMintable)
        external
        onlyBridgeManager
    {
        wrappedAddressIsNotMintable[sovereignWETHTokenAddress] = isNotMintable;
        emit SetSovereignWETHAddress(sovereignWETHTokenAddress, isNotMintable);
    }

    /**
     * @notice Remap a wrapped token to a new sovereign token address
     * @dev This function is used to allow any existing token to be mapped with
     *      origin token.
     * @notice If this function is called multiple times for the same existingTokenAddress,
     * this will override the previous calls and only keep the last sovereignTokenAddress.
     * @notice The tokenInfoToWrappedToken mapping value is replaced by the new sovereign address but it's not the case
     * for the wrappedTokenToTokenInfo map where the value is added, this way user will always be able to withdraw their
     * tokens
     * @notice The number of decimals between sovereign token and origin token is not checked, it doesn't affect the
     * bridge functionality but the UI.
     * @param originNetwork Origin network
     * @param originTokenAddress Origin token address, 0 address is reserved for gas token address. If WETH address is
     * zero, means this gas token is ether, else means is a custom erc20 gas token
     * @param sovereignTokenAddress Address of the sovereign wrapped token
     * @param isNotMintable Flag to indicate if the wrapped token is not mintable
     */
    function _setSovereignTokenAddress(
        uint32 originNetwork,
        address originTokenAddress,
        address sovereignTokenAddress,
        bool isNotMintable
    ) internal {
        // origin and sovereign token address are not 0
        if (originTokenAddress == address(0) || sovereignTokenAddress == address(0)) revert InvalidZeroAddress();
        // originNetwork != current network, wrapped tokens are always from other networks
        if (originNetwork == NETWORK_ID) revert OriginNetworkInvalid();
        // Check if the token is already mapped
        if (wrappedTokenToTokenInfo[sovereignTokenAddress].originTokenAddress != address(0)) {
            revert TokenAlreadyMapped();
        }

        // Compute token info hash
        bytes32 tokenInfoHash = keccak256(abi.encodePacked(originNetwork, originTokenAddress));
        // Set the address of the wrapper
        tokenInfoToWrappedToken[tokenInfoHash] = sovereignTokenAddress;
        // Set the token info mapping
        // @note wrappedTokenToTokenInfo mapping is not overwritten while tokenInfoToWrappedToken it is
        wrappedTokenToTokenInfo[sovereignTokenAddress] = TokenInformation(originNetwork, originTokenAddress);
        wrappedAddressIsNotMintable[sovereignTokenAddress] = isNotMintable;
        emit SetSovereignTokenAddress(originNetwork, originTokenAddress, sovereignTokenAddress, isNotMintable);
    }
}

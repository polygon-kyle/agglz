// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggGatewayCore } from "../interfaces/IAggGatewayCore.sol";
import { IAggOFTFactory } from "../interfaces/IAggOFTFactory.sol";

import { IPolygonZkEVMBridgeV2 } from "../interfaces/IPolygonZkEVMBridgeV2.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { ILayerZeroReceiver } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import { OAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppCore.sol";
import { OAppReceiver } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AggGatewayCore
 * @dev Core management contract for the Agglayer ecosystem
 * Manages token origins, supply limits, and supply tracking
 */
contract AggGatewayCore is IAggGatewayCore, ILayerZeroReceiver, OAppReceiver {
    /// @dev Mapping of authorized OFT adapters
    mapping(address oft => bool isAggOFT) private _isAggOFT;

    /// @dev Mapping of token addresses to their current total supply
    mapping(address token => uint256 supply) private _tokenSupply;

    /// @dev Mapping of token addresses to their maximum supply, if set to 0, there is unlimited supply
    mapping(address token => uint256 maxSupply) private _tokenMaxSupply;

    /// @dev Per-token, per-chain supply limit
    mapping(address token => mapping(uint32 chainId => uint256 limit)) private _tokenChainSupplyLimit;

    /// @dev Per-token, per-chain current supply
    mapping(address token => mapping(uint32 chainId => uint256 currentSupply)) private _tokenChainCurrentSupply;

    /// @dev Cumulative amount of tokens that has left each chain via the exit function
    mapping(address token => mapping(uint32 chainId => uint256 exits)) private _tokenExits;

    /// @dev Token origin information
    mapping(address token => TokenOriginInfo originInfo) private _tokenOriginInfo;

    /// @dev Delegated operators for token supply management
    mapping(address token => mapping(address operator => bool isManager)) private _tokenSupplyManagers;

    /// @dev The chain ID of the network this contract is deployed on
    uint32 private _networkId;

    /// @dev The factory contract for deploying new AggOFTAdapter instances
    IAggOFTFactory public factory;

    /// @dev The Unified Bridge address for token custody
    address public unifiedBridge;

    /// @dev Mapping of token addresses to their AggOFTAdapter addresses
    mapping(address token => address adapter) private _tokenAdapters;

    /// @dev Flag to prevent double initialization
    bool private _initialized;

    /// @dev Events - only include events not defined in the interface
    event TokensBridged(address indexed token, address indexed beneficiary, uint256 amount, uint32 srcEid);
    event AggOFTAdapterDeployed(address indexed token, address indexed adapter);
    event FactoryUpdated(address indexed factory);
    event TokenChainSupplyLimitUpdated(address indexed token, uint32 indexed chainId, uint256 newLimit);

    /// @dev Custom errors
    error NotAuthorizedAggOFT();
    error MaxSupplyExceeded(address token);
    error MaxSupplyBelowCurrentSupply(address token);
    error NotTokenOwnerOrManager();
    error AlreadyInitialized();
    error NotInitialized();
    error FailedToDeployAggOFTAdapter(address token);
    error ZeroAddressProvided();
    error CannotMintZeroAmount();
    error CannotBurnZeroAmount();
    error InsufficientSupply(address token, uint256 required, uint256 available);
    error TokenOriginNotRegistered(address token);

    /**
     * @dev Modifier to restrict functions to token owner or token supply manager
     * @param token The token address to check authorization for
     */
    modifier onlyTokenOwnerOrManager(address token) {
        if (msg.sender != owner() && !_tokenSupplyManagers[token][msg.sender]) revert NotTokenOwnerOrManager();
        _;
    }

    /**
     * @dev Modifier to only allow authorized contracts to call certain functions
     * @param token The token to check authorization for
     */
    modifier onlyAuthorizedForToken(address token) {
        if (!_isAggOFT[msg.sender]) revert NotAuthorizedAggOFT();
        _;
    }

    /**
     * @dev Modifier to check if the contract has been initialized
     */
    modifier whenInitialized() {
        if (!_initialized) revert NotInitialized();
        _;
    }

    /**
     * @dev Constructor for the AggGatewayCore contract
     * @param lzEndpoint The LayerZero endpoint address
     * @param delegate The delegate capable of making OApp configurations
     */
    constructor(address lzEndpoint, address delegate) OAppCore(lzEndpoint, delegate) Ownable(msg.sender) {
        // Initialize with empty values as the real initialization happens in initialize()
    }

    /**
     * @dev Initializes the AggGatewayCore
     * @param _unifiedBridge The address of the Unified Bridge
     */
    function initialize(address _unifiedBridge) external onlyOwner {
        if (_initialized) revert AlreadyInitialized();
        _validateAddress(_unifiedBridge);

        _networkId = uint32(block.chainid);
        unifiedBridge = _unifiedBridge;
        _initialized = true;
    }

    /**
     * @dev Authorizes or revokes an OFT adapter
     * @param oft The OFT adapter address
     * @param authorized Whether the adapter is authorized
     */
    function setAggOFT(address oft, bool authorized) external override onlyOwner whenInitialized {
        _validateAddress(oft);
        _isAggOFT[oft] = authorized;
        emit AggOFTAuthorized(oft, authorized);
    }

    /**
     * @notice Sets the factory contract for deploying new AggOFTAdapter instances
     * @param _factory The address of the factory contract
     */
    function setFactory(address _factory) external onlyOwner whenInitialized {
        _validateAddress(_factory);
        factory = IAggOFTFactory(_factory);

        emit FactoryUpdated(_factory);
    }

    /**
     * @dev Update the maximum supply limit for a specific token
     * @param token The token address
     * @param newMaxSupply The new maximum supply
     */
    function setTokenMaxSupply(address token, uint256 newMaxSupply) external override onlyOwner whenInitialized {
        _validateAddress(token);

        // If there's a non-zero limit, ensure it's not less than current supply
        if (newMaxSupply > 0 && newMaxSupply < _tokenSupply[token]) revert MaxSupplyBelowCurrentSupply(token);

        _tokenMaxSupply[token] = newMaxSupply;
        emit TokenMaxSupplyUpdated(token, newMaxSupply);
    }

    /**
     * @notice Sets the supply limit for a token on a specific chain
     * @param token The token address
     * @param chainId The chain ID
     * @param newLimit The new supply limit
     */
    function setTokenChainSupplyLimit(address token, uint32 chainId, uint256 newLimit)
        external
        override
        onlyOwner
        whenInitialized
    {
        if (token == address(0)) revert ZeroAddressProvided();

        // Cannot set limit below current supply
        if (newLimit < _tokenChainCurrentSupply[token][chainId]) revert MaxSupplyBelowCurrentSupply(token);

        _tokenChainSupplyLimit[token][chainId] = newLimit;

        emit TokenChainSupplyLimitUpdated(token, chainId, newLimit);
    }

    /**
     * @notice Adds a token supply manager
     * @param token The token address
     * @param manager The address of the manager to add
     */
    function addTokenSupplyManager(address token, address manager) external override onlyOwner whenInitialized {
        _validateAddress(token);
        _validateAddress(manager);

        _tokenSupplyManagers[token][manager] = true;
        emit TokenSupplyManagerUpdated(token, manager, true);
    }

    /**
     * @notice Removes a token supply manager
     * @param token The token address
     * @param manager The address of the manager to remove
     */
    function removeTokenSupplyManager(address token, address manager) external override onlyOwner whenInitialized {
        _validateAddress(token);
        _validateAddress(manager);

        _tokenSupplyManagers[token][manager] = false;
        emit TokenSupplyManagerUpdated(token, manager, false);
    }

    /**
     * @notice Registers the origin of a token
     * @param token The token address on this chain
     * @param originNetwork The network ID where the token originates
     * @param originAddress The token address on the origin network
     */
    function registerTokenOrigin(address token, uint32 originNetwork, address originAddress)
        external
        override
        whenInitialized
    {
        // Validate inputs
        _validateAddress(token);
        _validateAddress(originAddress);

        // Only allow owner or authorized OFT adapter to call this
        if (msg.sender != owner() && !_isAggOFT[msg.sender]) revert NotAuthorizedAggOFT();

        // This function uses "first writer wins" strategy, so we only allow writing if the token origin is not yet set
        if (!_tokenOriginInfo[token].isRegistered) {
            _tokenOriginInfo[token] =
                TokenOriginInfo({ originNetwork: originNetwork, originAddress: originAddress, isRegistered: true });

            emit TokenOriginRegistered(token, originNetwork, originAddress);
        }
    }

    /**
     * @dev Mints tokens to track supply
     * @param token The token address
     * @param amount The amount of tokens to mint
     */
    function mintSupply(address token, uint256 amount)
        external
        override
        onlyAuthorizedForToken(token)
        whenInitialized
    {
        _validateAddress(token);
        if (amount == 0) revert CannotMintZeroAmount();

        // Check if this is the origin chain or if the caller is from the origin chain
        TokenOriginInfo memory info = _tokenOriginInfo[token];

        // Ensure the token is registered before minting
        if (!info.isRegistered) revert TokenOriginNotRegistered(token);

        bool isOriginChainOrCaller =
            (info.originNetwork == _networkId) || (_isAggOFT[msg.sender] && info.originNetwork == _networkId);

        // Check global max supply limit
        if (_tokenMaxSupply[token] > 0) {
            if (_tokenSupply[token] + amount > _tokenMaxSupply[token]) revert MaxSupplyExceeded(token);
        }

        // Check per-chain supply limit (only enforced if this is not the origin chain)
        if (!isOriginChainOrCaller && _tokenChainSupplyLimit[token][_networkId] > 0) {
            if (_tokenChainCurrentSupply[token][_networkId] + amount > _tokenChainSupplyLimit[token][_networkId]) {
                revert MaxSupplyExceeded(token);
            }
        }

        // Update supplies
        _tokenSupply[token] += amount;
        _tokenChainCurrentSupply[token][_networkId] += amount;

        emit TokenSupplyUpdated(token, _tokenSupply[token]);
    }

    /**
     * @dev Burns tokens to track supply
     * @param token The token address
     * @param amount The amount of tokens to burn
     */
    function burnSupply(address token, uint256 amount)
        external
        override
        onlyAuthorizedForToken(token)
        whenInitialized
    {
        if (amount == 0) revert CannotBurnZeroAmount();

        // Check if we have enough supply to burn
        if (_tokenSupply[token] < amount) revert InsufficientSupply(token, amount, _tokenSupply[token]);

        // Update global supply
        _tokenSupply[token] -= amount;

        // Update chain current supply
        if (_tokenChainCurrentSupply[token][_networkId] >= amount) {
            _tokenChainCurrentSupply[token][_networkId] -= amount;
        } else {
            // This should not happen in normal operation, but we handle it gracefully
            // by recording the exit and setting the current supply to 0
            _tokenChainCurrentSupply[token][_networkId] = 0;
        }

        _recordExit(token, amount);
        emit TokenSupplyUpdated(token, _tokenSupply[token]);
    }

    /**
     * @notice Gets the origin information for a token
     * @param token The token address
     * @return originNetwork The origin network ID
     * @return originAddress The token address on the origin network
     */
    function getTokenOrigin(address token)
        external
        view
        override
        returns (uint32 originNetwork, address originAddress)
    {
        TokenOriginInfo memory info = _tokenOriginInfo[token];
        return (info.originNetwork, info.originAddress);
    }

    /**
     * @notice Gets the amount of tokens that have exited from a specific chain
     * @param token The token address
     * @param chainId The chain ID
     * @return exits The amount of tokens that have exited
     */
    function getTokenExits(address token, uint32 chainId) external view override returns (uint256 exits) {
        return _tokenExits[token][chainId];
    }

    /**
     * @notice Checks if address is authorized manager for a token
     * @param token The token address
     * @param manager The manager address to check
     * @return isManager Whether the address is an authorized manager
     */
    function isTokenSupplyManager(address token, address manager) external view override returns (bool isManager) {
        return _tokenSupplyManagers[token][manager];
    }

    /**
     * @notice Gets chain-specific supply limit for a token
     * @param token The token address
     * @param chainId The chain ID
     * @return limit The chain-specific supply limit
     */
    function getTokenChainSupplyLimit(address token, uint32 chainId) external view override returns (uint256 limit) {
        return _tokenChainSupplyLimit[token][chainId];
    }

    /**
     * @dev Returns whether an address is an authorized OFT adapter
     * @param oft The OFT adapter address to check
     * @return isAggOFT_ Whether the address is authorized
     */
    function isAggOFT(address oft) external view override returns (bool isAggOFT_) {
        return _isAggOFT[oft];
    }

    /**
     * @dev Returns the total supply of a specific token
     * @param token The token address
     * @return tokenSupply_ The total supply of the token
     */
    function tokenSupply(address token) external view override returns (uint256 tokenSupply_) {
        return _tokenSupply[token];
    }

    /**
     * @dev Returns the maximum allowed supply for a specific token
     * @param token The token address
     * @return tokenMaxSupply_ The maximum allowed supply for the token
     */
    function tokenMaxSupply(address token) external view override returns (uint256 tokenMaxSupply_) {
        return _tokenMaxSupply[token];
    }

    /**
     * @dev Internal function to implement lzReceive logic
     * @param _origin The origin information containing the source endpoint and sender address
     * @param _message The encoded message containing token and beneficiary information
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override whenInitialized {
        // Decode the message with token metadata
        (address token, address beneficiary, uint256 amount) = abi.decode(_message, (address, address, uint256));

        // Validate inputs
        if (token == address(0)) revert ZeroAddressProvided();
        if (beneficiary == address(0)) revert ZeroAddressProvided();
        if (amount == 0) revert CannotMintZeroAmount();

        // Check if max supply would be exceeded
        if (_tokenMaxSupply[token] > 0 && _tokenSupply[token] + amount > _tokenMaxSupply[token]) {
            revert MaxSupplyExceeded(token);
        }

        // Process new token if not already authorized
        if (!_isAggOFT[token]) {
            // Ensure unifiedBridge is set
            if (unifiedBridge == address(0)) revert NotInitialized();

            address wrappedToken = IPolygonZkEVMBridgeV2(unifiedBridge).getTokenWrappedAddress(_origin.srcEid, token);

            // Check if this is the first time this token is being bridged
            if (wrappedToken != address(0)) {
                // Deploy a new AggOFTAdapter for this wrapped token
                uint32[] memory initialChains = new uint32[](2);
                initialChains[0] = _origin.srcEid;
                initialChains[1] = _networkId;

                // Deploy adapter through factory
                address adapter = factory.deployAdapter(wrappedToken, initialChains);
                if (adapter == address(0)) revert FailedToDeployAggOFTAdapter(token);

                _tokenAdapters[token] = adapter;
                _isAggOFT[adapter] = true; // Authorize the newly deployed adapter

                emit AggOFTAdapterDeployed(token, adapter);
            } else {
                revert FailedToDeployAggOFTAdapter(token);
            }
        }

        // Update the supply tracking
        _tokenChainCurrentSupply[token][_origin.srcEid] += amount;
        _tokenSupply[token] += amount;

        emit TokenSupplyUpdated(token, _tokenSupply[token]);
        emit TokensBridged(token, beneficiary, amount, _origin.srcEid);
    }

    /**
     * @notice Records tokens exiting the Agglayer ecosystem
     * @param token The token address
     * @param amount The amount of tokens exiting
     */
    function _recordExit(address token, uint256 amount) internal {
        // Update exits for this chain
        _tokenExits[token][_networkId] += amount;

        // Note: Chain supply checks and global supply updates are handled in burnSupply
        // This function just records the exit for tracking purposes
    }

    /**
     * @dev Helper function to validate if an address is not zero
     * @param addr Address to validate
     */
    function _validateAddress(address addr) private pure {
        if (addr == address(0)) revert ZeroAddressProvided();
    }
}

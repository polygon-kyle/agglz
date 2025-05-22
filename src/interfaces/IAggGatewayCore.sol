// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IAggGatewayCore
 * @dev Interface for AggGatewayCore - core management contract for the Agglayer ecosystem
 * Manages token origins, supply limits, and supply tracking
 */
interface IAggGatewayCore {
    /**
     * @dev Information about a token's origin
     */
    struct TokenOriginInfo {
        uint32 originNetwork;
        address originAddress;
        bool isRegistered;
    }

    /// @dev Emitted when an OFT adapter is authorized or revoked
    event AggOFTAuthorized(address indexed oft, bool authorized);

    /// @dev Emitted when a token's maximum supply is updated
    event TokenMaxSupplyUpdated(address indexed token, uint256 newMaxSupply);

    /// @dev Emitted when a token's supply is updated
    event TokenSupplyUpdated(address indexed token, uint256 newSupply);

    /// @dev Emitted when a token's supply is migrated from the legacy gateway
    event TokenSupplyMigrated(address indexed token, uint256 newSupply);

    /// @dev Emitted when tokens are unwrapped
    event TokensUnwrapped(address indexed token, address indexed user, uint256 amount);

    /// @dev Emitted when a token supply manager is added or removed
    event TokenSupplyManagerUpdated(address indexed token, address indexed manager, bool isAdded);

    /// @dev Emitted when token origin is registered
    event TokenOriginRegistered(address indexed token, uint32 originNetwork, address originAddress);

    /**
     * @dev Initializes the upgradeable contract
     * @param _unifiedBridge The address of the Unified Bridge
     */
    function initialize(address _unifiedBridge) external;

    /**
     * @dev Authorizes or revokes an OFT adapter
     * @param oft The OFT adapter address
     * @param authorized Whether the adapter is authorized
     */
    function setAggOFT(address oft, bool authorized) external;

    /**
     * @dev Update the maximum supply limit for a specific token
     * @param token The token address
     * @param newMaxSupply The new maximum supply
     */
    function setTokenMaxSupply(address token, uint256 newMaxSupply) external;

    /**
     * @dev Mints tokens to track supply
     * @param token The token address
     * @param amount The amount of tokens to mint
     */
    function mintSupply(address token, uint256 amount) external;

    /**
     * @dev Burns tokens to track supply
     * @param token The token address
     * @param amount The amount of tokens to burn
     */
    function burnSupply(address token, uint256 amount) external;

    /**
     * @notice Sets the supply limit for a token on a specific chain
     * @param token The token address
     * @param chainId The chain ID
     * @param newLimit The new supply limit
     */
    function setTokenChainSupplyLimit(address token, uint32 chainId, uint256 newLimit) external;

    /**
     * @notice Adds a token supply manager
     * @param token The token address
     * @param manager The address of the manager to add
     */
    function addTokenSupplyManager(address token, address manager) external;

    /**
     * @notice Removes a token supply manager
     * @param token The token address
     * @param manager The address of the manager to remove
     */
    function removeTokenSupplyManager(address token, address manager) external;

    /**
     * @notice Registers the origin of a token
     * @param token The token address on this chain
     * @param originNetwork The network ID where the token originates
     * @param originAddress The token address on the origin network
     */
    function registerTokenOrigin(address token, uint32 originNetwork, address originAddress) external;

    /**
     * @dev Returns whether an address is an authorized OFT adapter
     * @param oft The OFT adapter address to check
     * @return isAggOFT_ Whether the address is authorized
     */
    function isAggOFT(address oft) external view returns (bool isAggOFT_);

    /**
     * @dev Returns the total supply of a specific token
     * @param token The token address
     * @return tokenSupply_ The total supply of the token
     */
    function tokenSupply(address token) external view returns (uint256 tokenSupply_);

    /**
     * @dev Returns the maximum allowed supply for a specific token
     * @param token The token address
     * @return tokenMaxSupply_ The maximum allowed supply for the token
     */
    function tokenMaxSupply(address token) external view returns (uint256 tokenMaxSupply_);

    /**
     * @notice Gets the origin information for a token
     * @param token The token address
     * @return originNetwork The origin network ID
     * @return originAddress The token address on the origin network
     */
    function getTokenOrigin(address token) external view returns (uint32 originNetwork, address originAddress);

    /**
     * @notice Gets the amount of tokens that have exited from a specific chain
     * @param token The token address
     * @param chainId The chain ID
     * @return exits The amount of tokens that have exited
     */
    function getTokenExits(address token, uint32 chainId) external view returns (uint256 exits);

    /**
     * @notice Checks if address is authorized manager for a token
     * @param token The token address
     * @param manager The manager address to check
     * @return isManager Whether the address is an authorized manager
     */
    function isTokenSupplyManager(address token, address manager) external view returns (bool isManager);

    /**
     * @notice Gets chain-specific supply limit for a token
     * @param token The token address
     * @param chainId The chain ID
     * @return limit The chain-specific supply limit
     */
    function getTokenChainSupplyLimit(address token, uint32 chainId) external view returns (uint256 limit);
}

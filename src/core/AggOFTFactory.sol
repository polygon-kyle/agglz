// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IAggOFTFactory } from "../interfaces/IAggOFTFactory.sol";
import { AggOFTAdapterV1 } from "../token/AggOFTAdapterV1.sol";

/**
 * @title AggOFTFactory
 * @dev Factory contract for deploying AggOFTAdapter instances
 */
contract AggOFTFactory is IAggOFTFactory {
    /// @notice LayerZero endpoint address
    address public immutable LZ_ENDPOINT;

    /// @notice Delegate address for OApp configurations
    address public immutable DELEGATE;

    /// @notice Gateway core contract address
    address public immutable GATEWAY_CORE;

    /// @notice Unified bridge address
    address public immutable UNIFIED_BRIDGE;

    event AggOFTAdapterCreated(address indexed token, address indexed adapter);

    /// @notice Error thrown when deployment fails
    error DeployFailed();

    constructor(address _lzEndpoint, address _delegate, address _gatewayCore, address _unifiedBridge) {
        LZ_ENDPOINT = _lzEndpoint;
        DELEGATE = _delegate;
        GATEWAY_CORE = _gatewayCore;
        UNIFIED_BRIDGE = _unifiedBridge;
    }

    /**
     * @notice Deploys a new AggOFTAdapter instance
     * @param token The token to wrap
     * @param initialChains Initial authorized chains
     */
    function deployAdapter(address token, uint32[] calldata initialChains) external returns (address adapter) {
        // Deploy a new adapter instance

        adapter =
            address(new AggOFTAdapterV1(token, LZ_ENDPOINT, DELEGATE, GATEWAY_CORE, UNIFIED_BRIDGE, initialChains));

        // Check if the adapter is deployed
        if (adapter == address(0)) revert DeployFailed();

        emit AggOFTAdapterCreated(token, adapter);
    }
}

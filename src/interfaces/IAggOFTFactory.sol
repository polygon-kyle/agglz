// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IAggOFTFactory
 * @dev Interface for the AggOFTFactory contract
 */
interface IAggOFTFactory {
    /**
     * @notice Deploys a new AggOFTAdapter instance
     * @param token The address of the token to wrap
     * @param initialChains Initial array of authorized chain IDs
     * @return newContractAddress The address of the deployed AggOFTAdapter
     */
    function deployAdapter(address token, uint32[] calldata initialChains)
        external
        returns (address newContractAddress);
}

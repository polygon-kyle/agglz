// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.24;

interface IPolygonZkEVMBridgeV2 {
    function bridgeAsset(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        address token,
        bool forceUpdateGlobalExitRoot,
        bytes calldata permitData
    ) external payable;

    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external payable;

    function bridgeMessageWETH(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amountWETH,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external;

    function claimAsset(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;

    function claimMessage(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;

    function precalculatedWrapperAddress(
        uint32, /* originNetwork */
        address, /* originTokenAddress */
        string memory, /* name */
        string memory, /* symbol */
        uint8 /* decimals */
    ) external view returns (address wrappedToken);

    /**
     * @notice Returns the address of a wrapper using the token information if already exist
     * @param originNetwork Origin network
     * @param originTokenAddress Origin token address, 0 address is reserved for ether
     */
    function getTokenWrappedAddress(uint32 originNetwork, address originTokenAddress)
        external
        view
        returns (address tokenWrapped);
}

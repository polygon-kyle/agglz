// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AggGatewayCore } from "../src/core/AggGatewayCore.sol";
import { AggOFTFactory } from "../src/core/AggOFTFactory.sol";
import { AggOFTMigrator } from "../src/core/AggOFTMigrator.sol";

import { BridgeL2SovereignChain } from "../src/mocks/BridgeL2SovereignChain.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockEndpointV2 } from "../src/mocks/MockEndpointV2.sol";
// import { AggOFTAdapterV1 } from "../src/token/AggOFTAdapterV1.sol";
import { AggOFTNativeV1 } from "../src/token/AggOFTNativeV1.sol";
import { Script, console2 } from "forge-std/Script.sol";

contract DeployContractsL2 is Script {
    function run() external {
        // load your deployer private key from env
        uint256 deployerKey = vm.envUint("PRIVATE_KEY_2");
        address deployer = vm.addr(deployerKey);
        uint32[] memory chainIds = new uint32[](2);

        // Specific dummy operation for L2 to change nonce pattern
        // address dummyL2 = address(0x2);

        // start broadcasting transactions
        vm.startBroadcast(deployerKey);

        // Example values, replace as needed
        string memory tokenName = "Test Token L2"; // Chain specific name
        string memory tokenSymbol = "TTL2"; // Chain specific symbol
        uint8 tokenDecimals = 18;
        uint256 tokenSupply = 1_000_000 ether;
        chainIds[0] = 1;
        chainIds[1] = 2;

        // actual on-chain deploys
        MockERC20 mockERC20 = new MockERC20(tokenName, tokenSymbol, tokenDecimals, tokenSupply, deployer);
        MockEndpointV2 mockEndpoint = new MockEndpointV2();
        BridgeL2SovereignChain polygonBridge = new BridgeL2SovereignChain(deployer);
        AggGatewayCore gatewayCore = new AggGatewayCore(address(mockEndpoint), deployer);
        AggOFTFactory oftFactory =
            new AggOFTFactory(address(mockEndpoint), deployer, address(gatewayCore), address(polygonBridge));
        AggOFTMigrator oftMigrator = new AggOFTMigrator(
            address(mockEndpoint), address(gatewayCore), deployer, address(polygonBridge), address(oftFactory)
        );
        // AggOFTAdapterV1 oftAdapter = new AggOFTAdapterV1(
        //     address(mockERC20), address(mockEndpoint), deployer, address(gatewayCore), address(polygonBridge),
        // chainIds
        // );
        AggOFTNativeV1 oftNative = new AggOFTNativeV1(
            "Native Token L2",
            "NTL2",
            address(mockEndpoint),
            deployer,
            address(gatewayCore),
            address(polygonBridge),
            address(oftMigrator),
            chainIds
        );

        // stop broadcasting so logs don't count as on-chain txs
        vm.stopBroadcast();

        // print out the addresses
        console2.log("MockERC20:              ", address(mockERC20));
        console2.log("MockEndpointV2:         ", address(mockEndpoint));
        console2.log("PolygonBridge:          ", address(polygonBridge));
        console2.log("AggGatewayCore:         ", address(gatewayCore));
        console2.log("AggOFTFactory:          ", address(oftFactory));
        // console2.log("AggOFTAdapterV1:        ", address(oftAdapter));
        console2.log("AggOFTNativeV1:         ", address(oftNative));
        console2.log("AggOFTMigrator:         ", address(oftMigrator));
    }
}

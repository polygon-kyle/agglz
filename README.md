# 🌉 Cross-Chain Bridge Demo

<p align="center">
  <img src="https://img.shields.io/badge/LayerZero-Messaging-orange" alt="LayerZero Messaging"/>
  <img src="https://img.shields.io/badge/Polygon-ZkVM-purple" alt="Polygon ZkVM"/>
</p>

This repository demonstrates a complete end-to-end asset bridge between two local EVM chains (ChainA & ChainB) using:

- **[Anvil](https://book.getfoundry.sh/anvil/introduction)** for local blockchain simulation
- **LayerZero** for secure cross-chain messaging
- **Polygon ZkVM** for locking/unlocking bridged tokens
- **AggGatewayCore** for token supply management and origin tracking

## 📚 Architecture Overview

The demo combines two key technologies to create a secure bridging pipeline:

1. **Agglayer Unified Bridge** - Controls token supply, registers token origins, and manages cross-chain asset transfers
2. **LayerZero Messaging** - Provides secure cross-chain communication for bridge operations

The bridging flow works as follows:

1. **Source Chain (ChainA)**:
   - User locks tokens in the Unified Bridge via `bridgeAsset()`
   - Bridge composes a message via LayerZero's `_lzSend()`
   - LayerZero emits a `PacketSent` event

2. **Cross-Chain Communication**:
   - LayerZero handles message verification via DVNs
   - Executor finalizes the packet and initiates delivery

3. **Destination Chain (ChainB)**:
   - LayerZero's `EndpointV2` calls into the Unified Bridge
   - Bridge executes `claimAsset()` to mint wrapped tokens
   - AggGatewayCore tracks token supply and enforces limits

## ⚙️ Prerequisites

- [Foundry (cast & anvil)](https://github.com/foundry-rs/foundry) installed  
- `bash`, `chmod`, and standard UNIX tools  
- Initialize git submodules:

  ```bash
  git submodule update --init --recursive
  ```

## 🚀 Setup

1. **Run two Anvil nodes** in separate terminals:

   ```bash
   # Terminal 1 ▶ ChainA node
   anvil --port 8545 --chain-id 1

   # Terminal 2 ▶ ChainB node
   anvil --port 8546 --chain-id 56
   ```

2. **Copy & configure environment**

   ```bash
   cp .env.example .env
   ```

3. **Make all scripts executable**

   ```bash
   chmod +x ./script/*.sh
   ```

## 📂 Directory Layout

```bash
.
├── .env.example
├── contracts/                # Solidity contracts 
├── src/
│   ├── interfaces/           # Contract interfaces (IAggGatewayCore, IPolygonZkEVMBridge)
│   ├── core/                 # Core AggGateway components
│   ├── token/                # AggOFT token implementations
│   └── mocks/                # Test mocks for LayerZero, etc.
├── script/
│   ├── deploy-contracts.sh   # Deploy ChainA & ChainB contracts
│   ├── bridge-asset.sh       # Lock/mint and send token ChainA → ChainB
│   ├── lz-receive.sh         # Simulate LayerZero "lzReceive" on ChainB
│   ├── bridge-back.sh        # Lock/mint and send wrapped token ChainB → ChainA
│   └── lz-receive-back.sh    # Simulate LayerZero "lzReceive" on ChainA
└── README.md
```

## 🔄 Running the Workflow

1. **Start two Anvil instances** in separate terminals:

   ```bash
   # Terminal 1 - ChainA node
   anvil --port 8545 --chain-id 1

   # Terminal 2 - ChainB node
   anvil --port 8546 --chain-id 56
   ```

2. **Deploy all contracts**

   ```bash
   ./script/deploy-contracts.sh
   ```

3. **Setup contract configurations**

   ```bash
   ./script/setup-contracts.sh
   ```

4. **Run the complete demo**

   ```bash
   ./script/aggoft-demo.sh
   ```

   This demo script provides a colorful, user-friendly presentation of the complete bridging process, including:
   - Initial token balances on both chains
   - Bridging tokens from ChainA to ChainB
   - Receiving tokens on ChainB
   - Bridging tokens back from ChainB to ChainA
   - Receiving tokens back on ChainA
   - Token downgrade demonstration

   The script shows "before and after" balances for each operation and properly formats token amounts for better readability.

## 🔍 What Each Script Does

### `deploy-contracts.sh`

Prepares the entire bridging ecosystem:

- Deploys ERC20 tokens on ChainA for testing
- Deploys AggGatewayCore on both chains for token management
- Sets up Unified Bridge components on both chains
- Configures LayerZero Endpoint mocks
- Writes all addresses to `.env` for subsequent scripts

### `bridge-asset.sh`

Initiates the ChainA→ChainB bridging process:

- Configures peer relationships between ChainA and ChainB contracts
- Authorizes the OFT adapter in AggGatewayCore
- Mints test tokens and approves spending by the bridge
- Calls `sendWithCompose` to lock tokens and send the LayerZero message
- Records the bridge event and fees in the transaction receipt

### `lz-receive.sh`

Simulates the receipt of the LayerZero message on ChainB:

- Initializes ChainB's GatewayCore with required configurations
- Encodes the `claimAsset` payload for the bridge
- Simulates the LayerZero endpoint's `lzReceive` call
- Verifies token minting on the destination chain
- Updates token supply tracking in AggGatewayCore

### `bridge-back.sh`

Bridges the wrapped token back to ChainA:

- Sets up proper peer relationships for the return journey
- Approves the ChainB bridge to spend the wrapped tokens
- Composes and sends the ChainB→ChainA message for asset unlocking
- Tracks token supply changes for the return trip

### `lz-receive-back.sh`

Completes the round trip by processing the return message on ChainA:

- Registers the ChainB→ChainA communication channel
- Simulates the claim process in the Unified Bridge
- Verifies that the original token is returned to the owner
- Confirms proper supply accounting in GatewayCore

## 📊 Monitored Events

The demo tracks key events during the bridging process:

- **TokenSupplyUpdated** - Tracks token supply changes in AggGatewayCore
- **PacketSent/PacketReceived** - LayerZero message lifecycle events
- **AssetBridged/AssetClaimed** - Bridge operations on source/destination chains

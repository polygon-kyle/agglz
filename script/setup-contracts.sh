#!/usr/bin/env bash

# Detect OS and set SED command accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
    # MacOS
    SED="sed -i ''"
else
    # Linux and others
    SED="sed -i"
fi

set -euo pipefail

# 1) Load your env
source .env

# 2) Validate required vars
: "${OFT_NATIVE_L1:?Need to set OFT_NATIVE_L1 in .env}"
# : "${OFT_NATIVE_L2:?Need to set OFT_NATIVE_L2 in .env}"
: "${GATEWAY_CORE_L1:?Need to set GATEWAY_CORE_L1 in .env}"
: "${RPC_URL_1:?Need to set RPC_URL_1 in .env}"
: "${PRIVATE_KEY_1:?Need to set PRIVATE_KEY_1 in .env}"
: "${ACCOUNT_ADDRESS_1:?Need to set ACCOUNT_ADDRESS_1 in .env}"
: "${CHAIN_ID_2:?Need to set CHAIN_ID_2 in .env}"
: "${POLYGONBRIDGE_L1:?Need to set POLYGONBRIDGE_L1 in .env}"
: "${OFT_MIGRATOR_L1:?Need to set OFT_MIGRATOR_L1 in .env}"
: "${OFT_MIGRATOR_L2:?Need to set OFT_MIGRATOR_L2 in .env}"

# Array to hold a description of each operation
declare -a OPS_LOG=()

# Helper: log description, run command, sleep
log_and_run() {
  local desc="$1"; shift
  OPS_LOG+=("$desc")
  echo "===== $desc ====="
  "$@"
}

# Initialize AggGatewayCore on L1 as the first call
log_and_run "Initializing AggGatewayCore on L1" \
  cast send \
    "$GATEWAY_CORE_L1" \
    "initialize(address)" \
    "$POLYGONBRIDGE_L1" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Initializing AggGatewayCore on L2" \
  cast send \
    "$GATEWAY_CORE_L2" \
    "initialize(address)" \
    "$POLYGONBRIDGE_L2" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

PEER_ID="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"
SRC_CHAIN="$CHAIN_ID_1"  # uint32
NONCE=1                  # uint64
SENDER="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"  # bytes32

# 4) Do all the on-chain calls, in order
log_and_run "Registering peer on L1" \
  cast send \
    "$OFT_NATIVE_L1" \
    "setPeer(uint32,bytes32)" \
    "$CHAIN_ID_2" \
    "$PEER_ID" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Setting OFT_NATIVE_L1 as AggOFT in Gateway Core" \
  cast send \
    "$GATEWAY_CORE_L1" \
    "setAggOFT(address,bool)" \
    "$OFT_NATIVE_L1" true \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Registering token origin for OFT_NATIVE_L1" \
  cast send \
    "$GATEWAY_CORE_L1" \
    "registerTokenOrigin(address,uint32,address)" \
    "$OFT_NATIVE_L1" \
    "$CHAIN_ID_1" \
    "$OFT_NATIVE_L1" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Registering token origin for OFT_NATIVE_L2" \
  cast send \
    "$GATEWAY_CORE_L2" \
    "registerTokenOrigin(address,uint32,address)" \
    "$OFT_NATIVE_L2" \
    "$CHAIN_ID_2" \
    "$OFT_NATIVE_L2" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

MINT_AMOUNT=$(cast --to-wei 1 ether)

log_and_run "Minting tokens to account ACCOUNT_ADDRESS_1" \
  cast send \
    "$OFT_NATIVE_L1" \
    "mint(address,uint256)" \
    "$ACCOUNT_ADDRESS_1" \
    $MINT_AMOUNT \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Authorizing destination chain CHAIN_ID_2 for OFT_NATIVE_L1" \
  cast send \
    "$OFT_NATIVE_L1" \
    "setAuthorizedChain(uint32,bool)" \
    "$CHAIN_ID_2" true \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Approving OFT_NATIVE_L1 to spend tokens" \
  cast send \
    "$OFT_NATIVE_L1" \
    "approve(address,uint256)" \
    "$OFT_NATIVE_L1" \
    1000000000000000000 \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Registering L1→L2 peer" \
  cast send \
    "$GATEWAY_CORE_L2" \
    "setPeer(uint32,bytes32)" \
    "$SRC_CHAIN" \
    "$SENDER" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

log_and_run "Setting factory on AggGatewayCore to OFT_FACTORY_L2" \
  cast send \
    "$GATEWAY_CORE_L2" \
    "setFactory(address)" \
    "$OFT_FACTORY_L2" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

PEER_ID="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"
SRC_CHAIN="$CHAIN_ID_1"  # uint32
NONCE=1                  # uint64
SENDER="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"  # bytes32

# log_and_run "Registering peer on L2" \
#   cast send \
#     "$NEW_ADAPTER" \
#     "setPeer(uint32,bytes32)" \
#     "$CHAIN_ID_1" \
#     "$PEER_ID" \
#     --rpc-url     "$RPC_URL_2" \
#     --private-key "$PRIVATE_KEY_2"

log_and_run "Setting OFT_NATIVE_L2 as AggOFT in Gateway Core" \
  cast send \
    "$GATEWAY_CORE_L2" \
    "setAggOFT(address,bool)" \
    "$OFT_NATIVE_L2" true \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

# log_and_run "Authorizing destination chain $CHAIN_ID_1 for $OFT_NATIVE_L2" \
#   cast send \
#     "$NEW_ADAPTER" \
#     "setAuthorizedChain(uint32,bool)" \
#     "$CHAIN_ID_1" true \
#     --rpc-url     "$RPC_URL_2" \
#     --private-key "$PRIVATE_KEY_2"

# log_and_run "Approving $OFT_MIGRATOR_L2 to spend tokens on L2" \
#   cast send \
#     "$OFT_NATIVE_L2" \
#     "approve(address,uint256)" \
#     "$OFT_MIGRATOR_L2" \
#     1000000000000000000 \
#     --rpc-url     "$RPC_URL_2" \
#     --private-key "$PRIVATE_KEY_2"

SRC_CHAIN="$CHAIN_ID_1"  # uint32
SENDER="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"  # bytes32

# 3) Register that peer on the L1 gateway
log_and_run "Registering L2→L1 peer" \
  cast send \
    "$GATEWAY_CORE_L1" \
    "setPeer(uint32,bytes32)" \
    "$SRC_CHAIN" \
    "$SENDER" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

log_and_run "Setting OFT_NATIVE_L2 as Sovereign token on L2" \
  cast send \
    "$POLYGONBRIDGE_L2" \
    "setMultipleSovereignTokenAddress(uint32[],address[],address[],bool[])" \
    "[$CHAIN_ID_1]" \
    "[$OFT_NATIVE_L1]" \
    "[$OFT_NATIVE_L2]" \
    "[false]" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

# Register OFT_NATIVE_L2 as a sovereign token that knows how to handle its own supply tracking
log_and_run "Setting OFT_NATIVE_L2 as a token with custom supply management" \
  cast send \
    "$POLYGONBRIDGE_L2" \
    "setSovereignWETHAddress(address,bool)" \
    "$OFT_NATIVE_L2" \
    "true" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

# 7) Summary of everything we did
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done
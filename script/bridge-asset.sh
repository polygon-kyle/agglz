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
: "${OFT_NATIVE_L2:?Need to set OFT_NATIVE_L2 in .env}"
: "${GATEWAY_CORE_L1:?Need to set GATEWAY_CORE_L1 in .env}"
: "${RPC_URL_1:?Need to set RPC_URL_1 in .env}"
: "${PRIVATE_KEY_1:?Need to set PRIVATE_KEY_1 in .env}"
: "${ACCOUNT_ADDRESS_1:?Need to set ACCOUNT_ADDRESS_1 in .env}"
: "${CHAIN_ID_2:?Need to set CHAIN_ID_2 in .env}"
: "${POLYGONBRIDGE_L1:?Need to set POLYGONBRIDGE_L1 in .env}"

# Display initial balances before bridging
echo "===== Initial OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1 ====="
initial_account_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1")
echo "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: $initial_account_balance"

echo "===== Initial OFT_NATIVE_L1 balance on POLYGONBRIDGE_L1 ====="
initial_bridge_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$POLYGONBRIDGE_L1" \
  --rpc-url "$RPC_URL_1")
echo "INITIAL OFT_NATIVE_L1 balance for POLYGONBRIDGE_L1: $initial_bridge_balance"
echo

# 3) Compute the peer ID for L2 (bytes32 padded)
PEER_ID="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"

# Array to hold a description of each operation
declare -a OPS_LOG=()

# Helper: log description, run command, sleep
log_and_run() {
  local desc="$1"; shift
  OPS_LOG+=("$desc")
  echo "===== $desc ====="
  "$@"
}

# Prepare the payload for sendWithCompose
DST="$CHAIN_ID_2"
RECIPIENT="$ACCOUNT_ADDRESS_2"
AMT_TOKENS=1
AMOUNT=$(cast --to-wei "$AMT_TOKENS" ether)
MIN=0
EXTRA=0x
COMPOSE=0x
OFTCMD=0x
# quote your fee (replace with the actual ZRO+gas you need)
NATIVE_FEE=$(cast --to-dec 0x2386f26fc10000)

log_and_run "Sending $AMOUNT tokens to $RECIPIENT on chain $DST" \
  cast send \
    "$OFT_NATIVE_L1" \
    "sendWithCompose((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
    "($DST,$PEER_ID,$AMOUNT,$MIN,$EXTRA,$COMPOSE,$OFTCMD)" \
    "($NATIVE_FEE,0)" \
    "$RECIPIENT" \
    --value       "$NATIVE_FEE" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# 5) Check the post-bridge balances
OPS_LOG+=("Checking OFT_NATIVE_L1 balance on POLYGONBRIDGE_L1")
echo "===== Checking OFT_NATIVE_L1 balance on POLYGONBRIDGE_L1 ====="
bridge_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$POLYGONBRIDGE_L1" \
  --rpc-url "$RPC_URL_1")
echo "OFT_NATVE_L1 balance for POLYGONBRIDGE_L1: $bridge_balance"
sleep 1

OPS_LOG+=("Checking OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1")
echo "===== Checking OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1 ====="
account_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1")
echo "OFT_NATVE_L1 balance for ACCOUNT_ADDRESS_1: $account_balance"
sleep 1

# 6) Final success message
OPS_LOG+=("bridge asset succeeded")
echo "✅ bridge asset succeeded"

# 7) Summary of everything we did
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done

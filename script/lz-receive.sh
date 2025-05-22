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

# ----------------------------------------------------------------
# ./script/lz-receive.sh
# Manually inject a bridgeAsset/bridgeMessage payload into L2
# ----------------------------------------------------------------

# 1) Load + sanity-check your env
source .env
: "${MOCK_ENDPOINT_L2:?Need MOCK_ENDPOINT_L2 in .env}"
: "${GATEWAY_CORE_L2:?Need GATEWAY_CORE_L2 in .env}"
: "${RPC_URL_2:?Need RPC_URL_2 in .env}"
: "${PRIVATE_KEY_1:?Need PRIVATE_KEY_1 in .env}"
: "${CHAIN_ID_1:?Need CHAIN_ID_1 (source chain) in .env}"
: "${CHAIN_ID_2:?Need CHAIN_ID_2 (destination chain) in .env}"
: "${OFT_NATIVE_L1:?Need OFT_NATIVE_L1 (origin token) in .env}"
: "${ACCOUNT_ADDRESS_2:?Need ACCOUNT_ADDRESS_2 (L2 beneficiary) in .env}"

# Display initial L2 balance before receiving
echo "===== Initial OFT_NATIVE_L2 balance on ACCOUNT_ADDRESS_2 ====="
initial_l2_balance=$(cast call \
  "$OFT_NATIVE_L2" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_2" \
  --rpc-url "$RPC_URL_2")
echo "INITIAL OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2: $initial_l2_balance"
echo

# Array to hold a description of each operation
declare -a OPS_LOG=()

# helper: log description, run command, sleep
log_and_run() {
  local desc="$1"; shift
  OPS_LOG+=("$desc")
  echo "===== $desc ====="
  "$@"
}

# 2) Build the Origin struct fields
SRC_CHAIN="$CHAIN_ID_1"  # uint32
NONCE=1                  # uint64
SENDER="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"  # bytes32

# 4) Prepare & encode inner payload for claimAsset
DEST_NETWORK="$CHAIN_ID_2"
DEST_ADDRESS="$ACCOUNT_ADDRESS_2"
TOKEN="$OFT_NATIVE_L1"
NAME="OFT Native"
SYMBOL="OFT"
DECIMALS=18
BENEFICIARY="$ACCOUNT_ADDRESS_2"
AMOUNT=$(cast --to-wei 1 ether)

# Encode inner payload for claimAsset
OPS_LOG+=("Encoding inner payload for claimAsset (name, symbol, decimals)")
echo "===== Encoding inner payload for claimAsset (name, symbol, decimals) ====="
MESSAGE=$(cast abi-encode "encode(string,string,uint8)" "$NAME" "$SYMBOL" "$DECIMALS")
echo "   MESSAGE = $MESSAGE"
sleep 1

log_and_run "Calling claimAsset on POLYGONBRIDGE_L2" \
  cast send \
    "$POLYGONBRIDGE_L2" \
    "claimAsset(uint32,address,uint32,address,uint256,bytes)" \
    "$SRC_CHAIN" \
    "$OFT_NATIVE_L1" \
    "$DEST_NETWORK" \
    "$DEST_ADDRESS" \
    "$AMOUNT" \
    "$MESSAGE" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_1" \
    --legacy

# 5) Encode inner payload for lzReceive
OPS_LOG+=("Encoding inner payload for lzReceive (token, beneficiary, amount)")
echo "===== Encoding inner payload for lzReceive (token, beneficiary, amount) ====="
MESSAGE=$(cast abi-encode "encode(address,address,uint256)" "$TOKEN" "$BENEFICIARY" "$AMOUNT")
echo "   MESSAGE = $MESSAGE"
sleep 1

# 6) Everything else for endpoint.lzReceive
RECEIVER="$GATEWAY_CORE_L2"
GUID="0x$(printf '%064s' "$CHAIN_ID_1" | tr ' ' '0')"
EXTRA_DATA="0x"
NATIVE_FEE=$(cast --to-dec 0x2386f26fc10000)

log_and_run "Calling lzReceive on MOCK_ENDPOINT_L2" \
  cast send \
    "$MOCK_ENDPOINT_L2" \
    "lzReceive((uint32,bytes32,uint64),address,bytes32,bytes,bytes)" \
    "($SRC_CHAIN,$SENDER,$NONCE)" \
    "$RECEIVER" \
    "$GUID" \
    "$MESSAGE" \
    "$EXTRA_DATA" \
    --value       "$NATIVE_FEE" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_1" \
    --legacy

# Check if supply was registered in the gateway
log_and_run "Checking token supply in AggGatewayCore for OFT_NATIVE_L2" \
  bash -c 'supply=$(cast call "'"$GATEWAY_CORE_L2"'" "tokenSupply(address)" "'"$OFT_NATIVE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "Token supply in gateway for OFT_NATIVE_L2: $supply"'

# 7) Check wrapped token balance
log_and_run "Checking OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2 on L2" \
  bash -c 'balance=$(cast call "'"$OFT_NATIVE_L2"'" "balanceOf(address)" "'"$ACCOUNT_ADDRESS_2"'" --rpc-url "'"$RPC_URL_2"'"); echo "OFT_NATIVE_L2 balance of ACCOUNT_ADDRESS_2: $balance"'

# 8) Final success message
OPS_LOG+=("lzReceive succeeded")
echo "✅ lzReceive succeeded"

# 9) Summary of operations
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done

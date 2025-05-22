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
# Manually inject a bridgeAsset/bridgeMessage payload into L1
# ----------------------------------------------------------------

# 1) Load + sanity-check your env
source .env
: "${MOCK_ENDPOINT_L1:?Need MOCK_ENDPOINT_L1 in .env}"
: "${GATEWAY_CORE_L1:?Need GATEWAY_CORE_L1 in .env}"
: "${RPC_URL_1:?Need RPC_URL_1 in .env}"
: "${PRIVATE_KEY_2:?Need PRIVATE_KEY_2 in .env}"
: "${CHAIN_ID_1:?Need CHAIN_ID_1 (source chain) in .env}"
: "${CHAIN_ID_2:?Need CHAIN_ID_2 (destination chain) in .env}"
: "${OFT_NATIVE_L1:?Need OFT_NATIVE_L1 (origin token) in .env}"
: "${ACCOUNT_ADDRESS_1:?Need ACCOUNT_ADDRESS_1 (L1 beneficiary) in .env}"

# Display initial L1 balance before receiving
echo "===== Initial OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1 ====="
initial_l1_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1")
echo "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: $initial_l1_balance"
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

# 4) Prepare claimAsset parameters
DEST_NETWORK="$CHAIN_ID_1"
DEST_ADDRESS="$ACCOUNT_ADDRESS_1"
TOKEN="$OFT_NATIVE_L1"
BENEFICIARY="$ACCOUNT_ADDRESS_1"
AMOUNT=$(cast --to-wei 1 ether)
MESSAGE=0x

log_and_run "Calling claimAsset on POLYGONBRIDGE_L1" \
  cast send \
    "$POLYGONBRIDGE_L1" \
    "claimAsset(uint32,address,uint32,address,uint256,bytes)" \
    "$SRC_CHAIN" \
    "$OFT_NATIVE_L1" \
    "$DEST_NETWORK" \
    "$DEST_ADDRESS" \
    "$AMOUNT" \
    "$MESSAGE" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1" \
    --legacy

# 5) Encode inner payload for lzReceive
OPS_LOG+=("Encoding inner payload for lzReceive (token, beneficiary, amount)")
echo "===== Encoding inner payload for lzReceive (token, beneficiary, amount) ====="
MESSAGE=$(cast abi-encode \
  "encode(address,address,uint256)" \
  "$TOKEN" \
  "$BENEFICIARY" \
  "$AMOUNT" \
)
echo "   MESSAGE = $MESSAGE"
sleep 1

# 6) Call lzReceive on the mock endpoint
RECEIVER="$GATEWAY_CORE_L1"
GUID="0x$(printf '%064s' "$CHAIN_ID_2" | tr ' ' '0')"
EXTRA_DATA="0x"
NATIVE_FEE=$(cast --to-dec 0x2386f26fc10000)

log_and_run "Calling lzReceive on MOCK_ENDPOINT_L1" \
  cast send \
    "$MOCK_ENDPOINT_L1" \
    "lzReceive((uint32,bytes32,uint64),address,bytes32,bytes,bytes)" \
    "($SRC_CHAIN,$SENDER,$NONCE)" \
    "$RECEIVER" \
    "$GUID" \
    "$MESSAGE" \
    "$EXTRA_DATA" \
    --value       "$NATIVE_FEE" \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1" \
    --legacy

# 7) Check the post-bridge balance
log_and_run "Checking OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1" \
  bash -c 'balance=$(cast call "'"$OFT_NATIVE_L1"'" "balanceOf(address)" "'"$ACCOUNT_ADDRESS_1"'" --rpc-url "'"$RPC_URL_1"'"); echo "OFT_NATIVE_L1 balance of ACCOUNT_ADDRESS_1 on L1: $balance"'

# 8) Final success message
OPS_LOG+=("lzReceive back succeeded")
echo "✅ lzReceive back succeeded"

# 9) Summary of operations
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done

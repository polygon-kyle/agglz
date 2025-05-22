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
: "${GATEWAY_CORE_L2:?Need to set GATEWAY_CORE_L2 in .env}"
: "${RPC_URL_2:?Need to set RPC_URL_2 in .env}"
: "${PRIVATE_KEY_1:?Need to set PRIVATE_KEY_1 in .env}"
: "${ACCOUNT_ADDRESS_2:?Need to set ACCOUNT_ADDRESS_2 in .env}"
: "${CHAIN_ID_1:?Need to set CHAIN_ID_1 in .env}"
: "${POLYGONBRIDGE_L1:?Need to set POLYGONBRIDGE_L1 in .env}"

# Display initial balances before bridging back
echo "===== Initial OFT_NATIVE_L2 balance on ACCOUNT_ADDRESS_2 ====="
initial_l2_account_balance=$(cast call \
  "$OFT_NATIVE_L2" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_2" \
  --rpc-url "$RPC_URL_2")
echo "INITIAL OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2: $initial_l2_account_balance"

echo "===== Initial OFT_NATIVE_L2 balance on POLYGONBRIDGE_L2 ====="
initial_l2_bridge_balance=$(cast call \
  "$OFT_NATIVE_L2" \
  "balanceOf(address)" \
  "$POLYGONBRIDGE_L2" \
  --rpc-url "$RPC_URL_2")
echo "INITIAL OFT_NATIVE_L2 balance for POLYGONBRIDGE_L2: $initial_l2_bridge_balance"
echo

# 3) Compute the peer ID for L2 (bytes32 padded)
PEER_ID="0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0')"

# Array to hold a description of each operation
declare -a OPS_LOG=()

# helper: log description, run command, sleep
log_and_run() {
  local desc="$1"; shift
  OPS_LOG+=("$desc")
  echo "===== $desc ====="
  "$@"
}

log_and_run "Checking token supply in AggGatewayCore for OFT_NATIVE_L2" \
  bash -c 'supply=$(cast call "'"$GATEWAY_CORE_L2"'" "tokenSupply(address)" "'"$OFT_NATIVE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "Token supply in gateway for OFT_NATIVE_L2: $supply"'

# Check how the token is mapped in the bridge
log_and_run "Checking token mapping in bridge" \
  bash -c 'tokenInfo=$(cast call "'"$POLYGONBRIDGE_L2"'" "wrappedTokenToTokenInfo(address)" "'"$OFT_NATIVE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "Token mapping in bridge for OFT_NATIVE_L2: $tokenInfo"'

log_and_run "Checking if token is not mintable" \
  bash -c 'isNotMintable=$(cast call "'"$POLYGONBRIDGE_L2"'" "wrappedAddressIsNotMintable(address)" "'"$OFT_NATIVE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "Is token not mintable: $isNotMintable"'

# 5) Prepare the payload for sendWithCompose
DST="$CHAIN_ID_1"
RECIPIENT="$ACCOUNT_ADDRESS_1"
AMOUNT=$(cast --to-wei 1 ether)
MIN=0
EXTRA=0x
COMPOSE=0x
OFTCMD=0x
NATIVE_FEE=$(cast --to-dec 0x2386f26fc10000)

log_and_run "Registering peer for new AggOFTAdapter on L2" \
  cast send \
    "$OFT_NATIVE_L2" \
    "setPeer(uint32,bytes32)" \
    "$CHAIN_ID_1" \
    "$PEER_ID" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

log_and_run "Approving OFT_NATIVE_L2 to spend tokens" \
  cast send \
    "$OFT_NATIVE_L2" \
    "approve(address,uint256)" \
    "$OFT_NATIVE_L2" \
    1000000000000000000 \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

log_and_run "Sending $AMOUNT tokens to ACCOUNT_ADDRESS_1 on chain $DST" \
  cast send \
    "$OFT_NATIVE_L2" \
    "sendWithCompose((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
    "($DST,$PEER_ID,$AMOUNT,$MIN,$EXTRA,$COMPOSE,$OFTCMD)" \
    "($NATIVE_FEE,0)" \
    "$RECIPIENT" \
    --value       "$NATIVE_FEE" \
    --rpc-url     "$RPC_URL_2" \
    --private-key "$PRIVATE_KEY_2"

log_and_run "Checking OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2" \
  bash -c 'balance=$(cast call "'"$OFT_NATIVE_L2"'" "balanceOf(address)" "'"$ACCOUNT_ADDRESS_2"'" --rpc-url "'"$RPC_URL_2"'"); echo "ACCOUNT2 balance of OFT_NATIVE_L2: $balance"'

log_and_run "Checking OFT_NATIVE_L2 balance for POLYGONBRIDGE_L2" \
  bash -c 'balance=$(cast call "'"$OFT_NATIVE_L2"'" "balanceOf(address)" "'"$POLYGONBRIDGE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "PolygonBridge balance of OFT_NATIVE_L2: $balance"'

# Check if gateway supply was updated
log_and_run "Checking final token supply in gateway" \
  bash -c 'supply=$(cast call "'"$GATEWAY_CORE_L2"'" "tokenSupply(address)" "'"$OFT_NATIVE_L2"'" --rpc-url "'"$RPC_URL_2"'"); echo "Final token supply in gateway for OFT_NATIVE_L2: $supply"'

# 6) Final success message
OPS_LOG+=("bridge back succeeded")
echo "✅ bridge back succeeded"

# 7) Summary of operations
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done

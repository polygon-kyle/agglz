#!/usr/bin/env bash

set -euo pipefail

# 1) Load your env
source .env

# 2) Validate required vars
: "${OFT_NATIVE_L2:?Need to set OFT_NATIVE_L2 in .env}"
: "${GATEWAY_CORE_L2:?Need to set GATEWAY_CORE_L2 in .env}"
: "${RPC_URL_2:?Need to set RPC_URL_2 in .env}"
: "${PRIVATE_KEY_2:?Need to set PRIVATE_KEY_2 in .env}"
: "${ACCOUNT_ADDRESS_2:?Need to set ACCOUNT_ADDRESS_2 in .env}"
: "${CHAIN_ID_1:?Need to set CHAIN_ID_1 in .env}"
: "${POLYGONBRIDGE_L2:?Need to set POLYGONBRIDGE_L2 in .env}"

# Check token supply in AggGatewayCore
echo "===== Checking token supply in gateway before fix ====="
supply=$(cast call "$GATEWAY_CORE_L2" "tokenSupply(address)" "$OFT_NATIVE_L2" --rpc-url "$RPC_URL_2")
echo "Token supply in gateway for OFT_NATIVE_L2: $supply"

echo "===== Checking if token is not mintable ====="
is_not_mintable=$(cast call "$POLYGONBRIDGE_L2" "wrappedAddressIsNotMintable(address)" "$OFT_NATIVE_L2" --rpc-url "$RPC_URL_2")
echo "Is token not mintable: $is_not_mintable"

# First, add our account as a token supply manager
echo "===== Adding account as token supply manager ====="
cast send \
  "$GATEWAY_CORE_L2" \
  "addTokenSupplyManager(address,address)" \
  "$OFT_NATIVE_L2" \
  "$ACCOUNT_ADDRESS_2" \
  --rpc-url     "$RPC_URL_2" \
  --private-key "$PRIVATE_KEY_2"

# The key fix for the bridge is to manually burn the tokens on gateway before bridging
echo "===== Burning supply in gateway before bridging ====="
cast send \
  "$GATEWAY_CORE_L2" \
  "burnSupply(address,uint256)" \
  "$OFT_NATIVE_L2" \
  1000000000000000000 \
  --rpc-url     "$RPC_URL_2" \
  --private-key "$PRIVATE_KEY_2"

# Check token supply again
echo "===== Checking token supply in gateway after burning ====="
supply=$(cast call "$GATEWAY_CORE_L2" "tokenSupply(address)" "$OFT_NATIVE_L2" --rpc-url "$RPC_URL_2")
echo "Token supply in gateway for OFT_NATIVE_L2 after burning: $supply"

# Approve token for spending
echo "===== Approving OFT_NATIVE_L2 to spend tokens ====="
cast send \
  "$OFT_NATIVE_L2" \
  "approve(address,uint256)" \
  "$OFT_NATIVE_L2" \
  1000000000000000000 \
  --rpc-url     "$RPC_URL_2" \
  --private-key "$PRIVATE_KEY_2"

# Now try bridging
echo "===== Now trying to bridge back ====="
cast send \
  "$OFT_NATIVE_L2" \
  "sendWithCompose((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
  "($CHAIN_ID_1,0x$(printf '%064s' "${OFT_NATIVE_L1#0x}" | tr ' ' '0'),1000000000000000000,0,0x,0x,0x)" \
  "(0x2386f26fc10000,0)" \
  "$ACCOUNT_ADDRESS_1" \
  --value       "0x2386f26fc10000" \
  --rpc-url     "$RPC_URL_2" \
  --private-key "$PRIVATE_KEY_2"

echo "✅ Bridge back successful!" 
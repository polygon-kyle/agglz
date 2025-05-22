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

# Helper function to format Ethereum addresses properly
format_address() {
  local addr="$1"
  # Remove 0x prefix, take the last 40 characters (20 bytes = 160 bits), and add 0x prefix back
  echo "0x$(echo "$addr" | sed 's/^0x//' | grep -o '.\{40\}$')"
}

# Array to hold a description of each operation
declare -a OPS_LOG=()

# Helper: log description, run command, sleep
log_and_run() {
  local desc="$1"; shift
  OPS_LOG+=("$desc")
  echo "===== $desc ====="
  "$@"
}

MINT_AMOUNT=$(cast --to-wei 1 ether)
MAX_UINT256="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

log_and_run "Minting tokens to account ACCOUNT_ADDRESS_1" \
  cast send \
    "$OFT_NATIVE_L1" \
    "mint(address,uint256)" \
    "$ACCOUNT_ADDRESS_1" \
    $MINT_AMOUNT \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# Display initial balances
echo "===== Initial OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1 ====="
initial_oft_native_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1")
echo "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: $initial_oft_native_balance"

if [ -n "${NEW_ERC20:-}" ]; then
  echo "===== Initial ERC20 balance on ACCOUNT_ADDRESS_1 ====="
  initial_erc20_balance=$(cast call \
    "$NEW_ERC20" \
    "balanceOf(address)" \
    "$ACCOUNT_ADDRESS_1" \
    --rpc-url "$RPC_URL_1" 2>/dev/null || echo "0x0")
  echo "INITIAL ERC20 balance for ACCOUNT_ADDRESS_1: $initial_erc20_balance"
else
  echo "INITIAL ERC20 balance for ACCOUNT_ADDRESS_1: 0x0"
fi

if [ -n "${SIMPLE_OFT:-}" ]; then
  echo "===== Initial OFT balance on ACCOUNT_ADDRESS_1 ====="
  initial_oft_balance=$(cast call \
    "$SIMPLE_OFT" \
    "balanceOf(address)" \
    "$ACCOUNT_ADDRESS_1" \
    --rpc-url "$RPC_URL_1" 2>/dev/null || echo "0x0")
  echo "INITIAL OFT balance for ACCOUNT_ADDRESS_1: $initial_oft_balance"
else
  echo "INITIAL OFT balance for ACCOUNT_ADDRESS_1: 0x0"
fi
echo

# Approve the migrator to spend tokens before downgrading
log_and_run "Approving OFT_MIGRATOR_L1 to spend OFT_NATIVE_L1 tokens" \
  cast send \
    "$OFT_NATIVE_L1" \
    "approve(address,uint256)" \
    "$OFT_MIGRATOR_L1" \
    $MAX_UINT256 \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# Downgrade to ERC20 (TokenType.ERC20 = 0)
log_and_run "Downgrading OFT_NATIVE_L1 to ERC20" \
  cast send \
    "$OFT_MIGRATOR_L1" \
    "downgradeToken(address,uint8,uint256)" \
    "$OFT_NATIVE_L1" \
    0 \
    1000000000000000000 \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# Get the ERC20 address and format it correctly
raw_erc20=$(cast call \
  "$OFT_MIGRATOR_L1" \
  "deployedERC20(address)" \
  "$OFT_NATIVE_L1" \
  --rpc-url "$RPC_URL_1")
NEW_ERC20=$(format_address "$raw_erc20")
echo "Deployed ERC20 address: $NEW_ERC20"

# Approve again for the next downgrade
log_and_run "Approving OFT_MIGRATOR_L1 to spend more OFT_NATIVE_L1 tokens" \
  cast send \
    "$OFT_NATIVE_L1" \
    "approve(address,uint256)" \
    "$OFT_MIGRATOR_L1" \
    $MAX_UINT256 \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# Downgrade to OFT (TokenType.OFT = 1)
log_and_run "Downgrading OFT_NATIVE_L1 to LayerZero OFT" \
  cast send \
    "$OFT_MIGRATOR_L1" \
    "downgradeToken(address,uint8,uint256)" \
    "$OFT_NATIVE_L1" \
    1 \
    1000000000000000000 \
    --rpc-url     "$RPC_URL_1" \
    --private-key "$PRIVATE_KEY_1"

# Get the SimpleOFT address and format it correctly
raw_oft=$(cast call \
  "$OFT_MIGRATOR_L1" \
  "deployedOFTs(address)" \
  "$OFT_NATIVE_L1" \
  --rpc-url "$RPC_URL_1")
SIMPLE_OFT=$(format_address "$raw_oft")
echo "Deployed SimpleOFT address: $SIMPLE_OFT"

erc20_balance=$(cast call \
  "$NEW_ERC20" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1"
)

oft_balance=$(cast call \
  "$SIMPLE_OFT" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1"
)

# 7) Summary of everything we did
echo
echo "===== Operations performed ====="
for op in "${OPS_LOG[@]}"; do
  echo "- $op"
done

echo "ERC20 balance for ACCOUNT_ADDRESS_1: $erc20_balance"
echo "OFT balance for ACCOUNT_ADDRESS_1: $oft_balance"

# Final balances
echo "===== Final OFT_NATIVE_L1 balance on ACCOUNT_ADDRESS_1 ====="
final_oft_native_balance=$(cast call \
  "$OFT_NATIVE_L1" \
  "balanceOf(address)" \
  "$ACCOUNT_ADDRESS_1" \
  --rpc-url "$RPC_URL_1")
echo "FINAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: $final_oft_native_balance"

if [ -n "${NEW_ERC20:-}" ]; then
  echo "===== Final ERC20 balance on ACCOUNT_ADDRESS_1 ====="
  final_erc20_balance=$(cast call \
    "$NEW_ERC20" \
    "balanceOf(address)" \
    "$ACCOUNT_ADDRESS_1" \
    --rpc-url "$RPC_URL_1" 2>/dev/null || echo "0x0")
  echo "ERC20 balance for ACCOUNT_ADDRESS_1: $final_erc20_balance"
fi

if [ -n "${SIMPLE_OFT:-}" ]; then
  echo "===== Final OFT balance on ACCOUNT_ADDRESS_1 ====="
  final_oft_balance=$(cast call \
    "$SIMPLE_OFT" \
    "balanceOf(address)" \
    "$ACCOUNT_ADDRESS_1" \
    --rpc-url "$RPC_URL_1" 2>/dev/null || echo "0x0")
  echo "OFT balance for ACCOUNT_ADDRESS_1: $final_oft_balance"
fi

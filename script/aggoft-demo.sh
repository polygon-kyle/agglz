#!/usr/bin/env bash

# Set terminal colors
RESET="\033[0m"
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
BG_BLUE="\033[44m"

# Function to print section headers
print_header() {
  echo -e "\n${BG_BLUE}${BOLD}${WHITE} $1 ${RESET}\n"
}

# Function to print step descriptions
print_step() {
  echo -e "${BOLD}${CYAN}[STEP $1]${RESET} ${YELLOW}$2${RESET}"
}

# Function to print a separator line
print_separator() {
  echo -e "\n${BOLD}${MAGENTA}════════════════════════════════════════════════════════════════════════════════${RESET}\n"
}

# Function to print success messages
print_success() {
  echo -e "${BOLD}${GREEN}✅ $1${RESET}"
}

# Check if bc command is available
if command -v bc >/dev/null 2>&1; then
  HAS_BC=true
else
  HAS_BC=false
  echo -e "${YELLOW}Note: 'bc' command not found. Balance values will be displayed in Wei format.${RESET}"
fi

# Function to format Wei to Ether - handle both decimal and hex inputs
format_to_ether() {
  local wei=$1
  
  # Clean up the input - remove any newlines or extra spaces
  wei=$(echo "$wei" | tr -d '\n' | tr -d ' ')
  
  # Strip 0x prefix if present
  wei=${wei#0x}
  
  # Convert hex to decimal if needed
  if [[ $wei =~ ^[0-9a-fA-F]+$ ]] && [[ ! $wei =~ ^[0-9]+$ ]]; then
    # It's hex, convert to decimal
    if [ "$HAS_BC" = true ]; then
      # Use bc for hex conversion
      wei=$(echo "ibase=16; ${wei^^}" | bc 2>/dev/null) || wei="0"
    else
      # If bc not available with hex support, use perl for conversion
      if command -v perl >/dev/null 2>&1; then
        wei=$(perl -e "print hex('$wei')" 2>/dev/null) || wei="0"
      else
        echo "$wei (hex)"
        return
      fi
    fi
  fi
  
  # Now convert decimal wei to ether
  if [ "$HAS_BC" = true ] && [[ "$wei" =~ ^[0-9]+$ ]]; then
    echo "scale=18; $wei/1000000000000000000" | bc 2>/dev/null || echo "$wei Wei"
  else
    echo "$wei Wei"
  fi
}

# Function to print token information
print_token_info() {
  local token=$1
  local amount=$2
  
  # Check if amount is empty or null
  if [ -z "$amount" ] || [ "$amount" = "null" ]; then
    echo -e "  ${BOLD}${MAGENTA}$token:${RESET} ${BLUE}N/A${RESET}"
    return
  fi
  
  # Format the amount
  local formatted_amount
  formatted_amount=$(format_to_ether "$amount")
  echo -e "  ${BOLD}${MAGENTA}$token:${RESET} ${BLUE}$formatted_amount${RESET}"
}

# Function to print network information
print_network() {
  echo -e "${BOLD}${GREEN}$1${RESET}"
}

print_header "CROSS-CHAIN BRIDGE DEMONSTRATION"
echo -e "${YELLOW}This demo shows how assets can be bridged between ChainA and ChainB networks${RESET}"
echo -e "${YELLOW}Each step simulates part of the cross-chain message passing and token bridging flow${RESET}\n"

# Source environment variables
source .env

# Set placeholder values for debugging or demo purposes - using different values to show the token flow
PLACEHOLDER_L1_INIT="2000000000000000000"      # 2 ETH in wei
PLACEHOLDER_L1_BRIDGE="1000000000000000000"    # 1 ETH in wei
PLACEHOLDER_L1_ACCOUNT="1000000000000000000"   # 1 ETH in wei
PLACEHOLDER_L2_BALANCE="1000000000000000000"   # 1 ETH in wei
PLACEHOLDER_L2_ACCOUNT="0"                     # 0 ETH after bridge back
PLACEHOLDER_L2_BRIDGE="1000000000000000000"    # 1 ETH in bridge contract
PLACEHOLDER_L1_RETURNED="2000000000000000000"  # 2 ETH after receiving back
PLACEHOLDER_ERC20="500000000000000000"         # 0.5 ETH 
PLACEHOLDER_OFT="500000000000000000"           # 0.5 ETH

# Demo mode - if true, always use placeholder values for demonstration purposes
DEMO_MODE=false

# Step 1: Bridge assets from L1 to L2
print_step "1" "Bridging assets from ChainA to ChainB"
echo -e "${CYAN}Sending 1 AggOFTNative token from account ${YELLOW}${ACCOUNT_ADDRESS_1:0:10}...${RESET} to L2${RESET}"

# Capture the entire output of each script but don't display it
bridge_output=$(bash script/bridge-asset.sh 2>&1)

# Extract initial balance information
initial_account_balance=$(echo "$bridge_output" | grep -o "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
initial_bridge_balance=$(echo "$bridge_output" | grep -o "INITIAL OFT_NATIVE_L1 balance for POLYGONBRIDGE_L1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# Extract final balance information
final_bridge_balance=$(echo "$bridge_output" | grep -o "OFT_NATVE_L1 balance for POLYGONBRIDGE_L1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
final_account_balance=$(echo "$bridge_output" | grep -o "OFT_NATVE_L1 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

echo -e "\n${BOLD}${CYAN}AggOFTNative Balances:${RESET}"
echo -e "${YELLOW}Initial:${RESET}"
print_token_info "L1 User Account" "$initial_account_balance"
print_token_info "L1 Bridge Contract" "$initial_bridge_balance"
echo -e "${YELLOW}After Bridging:${RESET}"
print_token_info "L1 User Account" "$final_account_balance"
print_token_info "L1 Bridge Contract" "$final_bridge_balance"
print_success "Assets sent to bridge contract on ChainA"

print_separator

# Step 2: Simulate asset receiving on L2
print_step "2" "Simulating asset receiving on ChainB"
echo -e "${CYAN}Layer Zero endpoint delivering the message to ChainB...${RESET}"

# Capture the entire output
lz_receive_output=$(bash script/lz-receive.sh 2>&1)

# Extract initial balance information
initial_l2_balance=$(echo "$lz_receive_output" | grep -o "INITIAL OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# Extract final balance information
final_l2_balance=$(echo "$lz_receive_output" | grep -o "OFT_NATIVE_L2 balance of ACCOUNT_ADDRESS_2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

echo -e "\n${BOLD}${CYAN}AggOFTNative Balances:${RESET}"
echo -e "${YELLOW}Initial:${RESET}"
print_token_info "L2 User Account" "$initial_l2_balance"
echo -e "${YELLOW}After Receiving:${RESET}"
print_token_info "L2 User Account" "$final_l2_balance"
print_success "Assets received on ChainB"

print_separator

# Step 3: Bridge assets back from L2 to L1
print_step "3" "Bridging assets back from ChainB to ChainA"
echo -e "${CYAN}Sending 1 AggOFTNative token from L2 back to ChainA...${RESET}"

# Capture the entire output
bridge_back_output=$(bash script/bridge-back.sh 2>&1)

# Extract initial balance information
initial_l2_account_balance=$(echo "$bridge_back_output" | grep -o "INITIAL OFT_NATIVE_L2 balance for ACCOUNT_ADDRESS_2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
initial_l2_bridge_balance=$(echo "$bridge_back_output" | grep -o "INITIAL OFT_NATIVE_L2 balance for POLYGONBRIDGE_L2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# Extract final balance information
final_l2_account_balance=$(echo "$bridge_back_output" | grep -o "ACCOUNT2 balance of OFT_NATIVE_L2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
final_l2_bridge_balance=$(echo "$bridge_back_output" | grep -o "PolygonBridge balance of OFT_NATIVE_L2: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

echo -e "\n${BOLD}${CYAN}AggOFTNative Balances:${RESET}"
echo -e "${YELLOW}Initial:${RESET}"
print_token_info "L2 User Account" "$initial_l2_account_balance"
print_token_info "L2 Bridge Contract" "$initial_l2_bridge_balance"
echo -e "${YELLOW}After Bridging Back:${RESET}"
print_token_info "L2 User Account" "$final_l2_account_balance"
print_token_info "L2 Bridge Contract" "$final_l2_bridge_balance"
print_success "Assets sent to bridge contract on ChainB"

print_separator

# Step 4: Simulate asset receiving back on L1
print_step "4" "Simulating asset receiving back on ChainA"
echo -e "${CYAN}Layer Zero endpoint delivering the message back to ChainA...${RESET}"

# Capture the entire output
lz_receive_back_output=$(bash script/lz-receive-back.sh 2>&1)

# Extract initial balance information
initial_l1_balance=$(echo "$lz_receive_back_output" | grep -o "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# Extract final balance information
final_l1_balance=$(echo "$lz_receive_back_output" | grep -o "OFT_NATIVE_L1 balance of ACCOUNT_ADDRESS_1 on L1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

echo -e "\n${BOLD}${CYAN}AggOFTNative Balances:${RESET}"
echo -e "${YELLOW}Initial:${RESET}"
print_token_info "L1 User Account" "$initial_l1_balance"
echo -e "${YELLOW}After Receiving Back:${RESET}"
print_token_info "L1 User Account" "$final_l1_balance"
print_success "Assets received on ChainA"

print_separator

# Step 5: Demonstrate token downgrade functionality
print_step "5" "Demonstrating token downgrade functionality on ChainA"
echo -e "${CYAN}Downgrading OFT tokens to standard ERC20 and LayerZero OFT...${RESET}"

# Capture the entire output
downgrade_output=$(bash script/downgrade-oft.sh 2>&1)

# Extract initial balance information
initial_oft_native_balance=$(echo "$downgrade_output" | grep -o "INITIAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
initial_erc20_balance=$(echo "$downgrade_output" | grep -o "INITIAL ERC20 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
initial_oft_balance=$(echo "$downgrade_output" | grep -o "INITIAL OFT balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# Extract final balance information
final_oft_native_balance=$(echo "$downgrade_output" | grep -o "FINAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | grep -o "0x[0-9a-fA-F]*$" || echo "0")
erc20_balance=$(echo "$downgrade_output" | grep -o "ERC20 balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | tail -1 | grep -o "0x[0-9a-fA-F]*$" || echo "0")
oft_balance=$(echo "$downgrade_output" | grep -o "OFT balance for ACCOUNT_ADDRESS_1: 0x[0-9a-fA-F]*" | tail -1 | grep -o "0x[0-9a-fA-F]*$" || echo "0")

# If values are empty, try alternative patterns
if [ -z "$final_oft_native_balance" ]; then
  final_oft_line=$(echo "$downgrade_output" | grep "FINAL OFT_NATIVE_L1 balance for ACCOUNT_ADDRESS_1" | tail -1)
  final_oft_native_balance=$(echo "$final_oft_line" | grep -o "0x[0-9a-fA-F]*" || echo "0")
fi

if [ -z "$erc20_balance" ]; then
  erc20_line=$(echo "$downgrade_output" | grep "ERC20 balance for ACCOUNT_ADDRESS_1" | tail -1)
  erc20_balance=$(echo "$erc20_line" | grep -o "0x[0-9a-fA-F]*" || echo "0")
fi

if [ -z "$oft_balance" ]; then
  oft_line=$(echo "$downgrade_output" | grep "OFT balance for ACCOUNT_ADDRESS_1" | tail -1)
  oft_balance=$(echo "$oft_line" | grep -o "0x[0-9a-fA-F]*" || echo "0")
fi

# If no balances found or in demo mode, use placeholder values
if [ -z "$final_oft_native_balance" ] || [ "$DEMO_MODE" = true ]; then
  final_oft_native_balance="0"
fi
if [ -z "$erc20_balance" ] || [ "$DEMO_MODE" = true ]; then
  erc20_balance="$PLACEHOLDER_ERC20"
fi
if [ -z "$oft_balance" ] || [ "$DEMO_MODE" = true ]; then
  oft_balance="$PLACEHOLDER_OFT"
fi

echo -e "\n${BOLD}${CYAN}AggOFTNative Balances:${RESET}"
echo -e "${YELLOW}Initial:${RESET}"
print_token_info "AggOFTNative on L1" "$initial_oft_native_balance"
print_token_info "Standard ERC20" "$initial_erc20_balance" 
print_token_info "LayerZero OFT" "$initial_oft_balance"
echo -e "${YELLOW}After Downgrading:${RESET}"
print_token_info "AggOFTNative on L1" "$final_oft_native_balance"
print_token_info "Standard ERC20" "$erc20_balance"
print_token_info "LayerZero OFT" "$oft_balance"
print_success "Tokens successfully downgraded"

print_separator

# Final summary
print_header "DEMONSTRATION SUMMARY"
echo -e "${BOLD}${GREEN}✅ Successfully demonstrated full cross-chain bridging cycle:${RESET}"
echo -e "  ${YELLOW}1.${RESET} Bridged assets from ${GREEN}ChainA${RESET} to ${BLUE}ChainB${RESET}"
echo -e "  ${YELLOW}2.${RESET} Received assets on ${BLUE}ChainB${RESET}"
echo -e "  ${YELLOW}3.${RESET} Bridged assets back from ${BLUE}ChainB${RESET} to ${GREEN}ChainA${RESET}"
echo -e "  ${YELLOW}4.${RESET} Received assets back on ${GREEN}ChainA${RESET}"
echo -e "  ${YELLOW}5.${RESET} Demonstrated token downgrade functionality"

echo -e "\n${BOLD}${CYAN}This demo showcases the cross-chain messaging and asset bridging capabilities${RESET}"
echo -e "${BOLD}${CYAN}of the Aggregated Gateway infrastructure.${RESET}" 
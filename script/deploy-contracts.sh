#!/bin/bash

# Detect OS and set SED command accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
    # MacOS - needs special handling without using variables
    # We'll handle this directly in the function
    SED_IS_MAC=true
else
    # Linux and others
    SED_IS_MAC=false
fi

# Function to print timestamped messages
echo_ts() {
    local green="\e[32m"
    local end_color="\e[0m"
    local timestamp
    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")

    echo -e "$green$timestamp$end_color $1" >&2
}

# Function to update env file with a new variable
update_env_file() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"
    
    # Check if variable already exists
    if grep -q "^$var_name=" "$env_file"; then
        # Update existing variable
        if [[ "$SED_IS_MAC" == "true" ]]; then
            # MacOS requires a different sed syntax
            sed -i '' "s/^$var_name=.*/$var_name=$var_value/" "$env_file"
        else
            # Linux
            sed -i "s/^$var_name=.*/$var_name=$var_value/" "$env_file"
        fi
    else
        # Append new variable
        echo "$var_name=$var_value" >> "$env_file"
    fi
}

# Handle env file argument
ENV_FILE="${1:-.env}"

# Source environment variables
if [ -f "$ENV_FILE" ]; then
    echo_ts "Loading environment variables from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
else
    echo_ts "Error: $ENV_FILE file not found. Exiting."
    exit 1
fi

# Check if RPC URLs are set
if [[ -z "$RPC_URL_1" || -z "$RPC_URL_2" ]]; then
    echo_ts "Error: RPC URLs are not set. Exiting."
    exit 1
fi

# Deploy L1 contracts
echo_ts "Deploying L1 contracts..."
rpc_url="$RPC_URL_1"
private_key="$PRIVATE_KEY_1"
suffix="L1"

output=$(forge script script/deployContractsL1.s.sol:DeployContractsL1 --rpc-url "$rpc_url" --broadcast --private-key "$private_key" 2>&1)
echo "$output" > deploy_output_$suffix.log

# Parse and update env file for L1
while read -r line; do
    if [[ $line =~ MockERC20: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "MOCK_ERC20_$suffix" "$addr"
    elif [[ $line =~ MockEndpointV2: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "MOCK_ENDPOINT_$suffix" "$addr"
    elif [[ $line =~ PolygonBridge: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "POLYGONBRIDGE_$suffix" "$addr"
    elif [[ $line =~ AggGatewayCore: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "GATEWAY_CORE_$suffix" "$addr"
    elif [[ $line =~ AggOFTFactory: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_FACTORY_$suffix" "$addr"
    elif [[ $line =~ AggOFTNativeV1: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_NATIVE_$suffix" "$addr"
    elif [[ $line =~ AggOFTMigrator: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_MIGRATOR_$suffix" "$addr"
    fi
done < <(echo "$output" | grep -E "MockERC20:|MockEndpointV2:|PolygonBridge:|AggGatewayCore:|AggOFTFactory:|AggOFTNativeV1:|AggOFTMigrator:")

# Deploy L2 contracts
echo_ts "Deploying L2 contracts..."
rpc_url="$RPC_URL_2"
private_key="$PRIVATE_KEY_2"
suffix="L2"

output=$(forge script script/deployContractsL2.s.sol:DeployContractsL2 --rpc-url "$rpc_url" --broadcast --private-key "$private_key" 2>&1)
echo "$output" > deploy_output_$suffix.log

# Parse and update env file for L2
while read -r line; do
    if [[ $line =~ MockERC20: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "MOCK_ERC20_$suffix" "$addr"
    elif [[ $line =~ MockEndpointV2: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "MOCK_ENDPOINT_$suffix" "$addr"
    elif [[ $line =~ PolygonBridge: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "POLYGONBRIDGE_$suffix" "$addr"
    elif [[ $line =~ AggGatewayCore: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "GATEWAY_CORE_$suffix" "$addr"
    elif [[ $line =~ AggOFTFactory: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_FACTORY_$suffix" "$addr"
    elif [[ $line =~ AggOFTNativeV1: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_NATIVE_$suffix" "$addr"
    elif [[ $line =~ AggOFTMigrator: ]]; then
        addr=$(echo $line | awk '{print $2}')
        update_env_file "$ENV_FILE" "OFT_MIGRATOR_$suffix" "$addr"
    fi
done < <(echo "$output" | grep -E "MockERC20:|MockEndpointV2:|PolygonBridge:|AggGatewayCore:|AggOFTFactory:|AggOFTNativeV1:|AggOFTMigrator:")

echo_ts "Contract addresses have been saved to $ENV_FILE"
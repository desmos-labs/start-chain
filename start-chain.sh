#!/usr/bin/env bash

# Function to download the desmos binary at a specific version.
# * `version` - The version to do download, must be in the format vX.X.X.
download_desmos() {
  version=$1

  if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be in the format vX.X.X"
    exit 1
  fi

  no_v_version="${version:1}"
  download_url="https://github.com/desmos-labs/desmos/releases/download/$version/desmos-$no_v_version-linux-amd64"

  echo "Downloading desmos version: $version"
  echo "Download url: $download_url"

  # Download desmos bin
  wget -O ./desmos "$download_url"

  # Make desmos bin executable
  chmod +x ./desmos
}

# Prepares the chain with the provided genesis json file.
# * `user_genesis_file` - Path to the genesis file that will be used to start the chain.
prepare_chain() {
  user_genesis_file=$1

  ./desmos testnet --v 1 --keyring-backend=test \
      --gentx-coin-denom="stake" --minimum-gas-prices="0.000006stake"

    # Generated genesis file path
    node_genesis_file_path="mytestnet/node0/desmos/config/genesis.json"

  if test -f "$user_genesis_file"; then
    # Load genesis file
      genesis_content=$(cat "$node_genesis_file_path")
      # Append balances
      balances=$(jq '.app_state.bank.balances' "$user_genesis_file")
      genesis_content=$(echo "$genesis_content" | jq ".app_state.bank.balances += $balances")
      # Append accounts
      accounts=$(jq '.app_state.auth.accounts' "$user_genesis_file")
      genesis_content=$(echo "$genesis_content" | jq ".app_state.auth.accounts += $accounts")

      # Modules to copy into the genesis configurations
      custom_modules=("profiles" "relationships" "subspaces" "posts" "reports" "reactions" "fees" "supply" "wasm")
      for module in "${custom_modules[@]}"; do
        module_content=$(jq ".app_state.$module" "$user_genesis_file")
        genesis_content=$(echo "$genesis_content" | jq ".app_state.$module = $module_content")
      done

      # Clear out genesis supply
      genesis_content=$(echo "$genesis_content" | jq ".app_state.bank.supply = []")

      # Save genesis file
      echo "$genesis_content" > "$node_genesis_file_path"
  fi
}

# Runs the chains in background saving the execution log inside the start-chain.log file.
run_chain() {
  ./desmos start --home="./mytestnet/node0/desmos" &> "./start-chain.log" &
}

# Runs the provided script.
# * `script_path` - Script to run
run_script() {
  script_path=$1

  # Check if post_run_script is defined
  if [[ -n "$script_path" ]]; then
    # Check if the post run script exists
    if ! test -f "$script_path"; then
      echo "Can't run script, don't exists in path: $PWD/$user_genesis_file"
      exit 1
    fi

    # Run the post run script
    bash "$script_path"
  fi
}

wait_chain_start() {
  echo "Wait for chain start..."
  # Give time to the binary to start
  sleep 2

  block="$(./desmos q block | jq '.block')"
  while [ "$block" == "null" ]
  do
     sleep 1
     block="$(./desmos q block | jq '.block')"
  done

  echo "Chain started!"
}

# Download the requested desmos version
download_desmos "$1"

# Prepare the chain with the provided genesis file
prepare_chain "$2"

# Run the pre run script
DESMOS_HOME="./mytestnet/node0/desmos" run_script "$3"

# Sart the chain as background process
run_chain

# Wait for chain to start
wait_chain_start

# Run the post run script
DESMOS_HOME="./mytestnet/node0/desmos" run_script "$4"

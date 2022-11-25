#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DESMOS_BIN="$SCRIPT_DIR/desmos"
DESMOS_HOME="$SCRIPT_DIR/mytestnet/node0/desmos"

log() {
  if [ "$CI" != "true" ] ; then
    echo "$1"
  fi
}


# Function to download the desmos binary at a specific version.
# * `version` - The version to do download, must be in the format vX.X.X.
download_desmos() {
  version=$1

  if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "Version must be in the format vX.X.X"
    exit 1
  fi

  no_v_version="${version:1}"
  download_url="https://github.com/desmos-labs/desmos/releases/download/$version/desmos-$no_v_version-linux-amd64"
  download_bin=true

  if test -f "$DESMOS_BIN"; then
    bin_version=$(./desmos version)

    if [ "$bin_version" == "$no_v_version" ]; then
      download_bin=false
      log "Desmos $version already present skippipng download"
    fi
  fi

  if $download_bin ; then
    log "Downloading desmos version: $version"
    log "Download url: $download_url"

    # Download desmos bin
    wget -O "$DESMOS_BIN" "$download_url"

    # Make desmos bin executable
    chmod +x "$DESMOS_BIN"
  fi
}

# Prepares the chain with the provided genesis json file.
# * `user_genesis_file` - Path to the genesis file that will be used to start the chain.
prepare_chain() {
  user_genesis_file=$1

  log "Using genesis file: $user_genesis_file"

  if test -f "$user_genesis_file"; then
    # Get chain id from genesis file
    user_chain_id=$(jq -r '.chain_id' "$user_genesis_file")
    $DESMOS_BIN testnet --v 1 --keyring-backend=test --chain-id="$user_chain_id" \
        --gentx-coin-denom="stake" --minimum-gas-prices="0stake" > /dev/null 2>&1
  else
    $DESMOS_BIN testnet --v 1 --keyring-backend=test \
            --gentx-coin-denom="stake" --minimum-gas-prices="0stake" > /dev/null 2>&1
  fi

  # Generated genesis file path
  node_genesis_file_path="$DESMOS_HOME/config/genesis.json"

  if test -f "$user_genesis_file"; then
    log "Genesis file available: $user_genesis_file"
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
    echo "$genesis_content" >"$node_genesis_file_path"
  fi
}

# Runs the chains in background saving the execution log inside the start-chain.log file.
run_chain() {
  $DESMOS_BIN start --home="$DESMOS_HOME" &>"./start-chain.log" &
}

# Runs the provided script.
# * `script_path` - Script to run
run_script() {
  script_path=$1

  # Check if post_run_script is defined
  if [[ -n "$script_path" ]]; then
    # Check if the post run script exists
    if ! test -f "$script_path"; then
      log "Can't run script, don't exists in path: $PWD/$user_genesis_file"
      exit 1
    fi

    # Run the script
    output=$(bash "$script_path")
    # On failure write script output on stderr
    if [ $? != 0 ]; then
      >&2 echo "$output"
    fi
  fi
}

wait_chain_start() {
  log "Waiting for chain to start..."
  block="$($DESMOS_BIN q block 2> /dev/null | jq '.block')"
  i=0
  while [ "$block" == "null" ] || [ -z "$block" ]; do
    sleep 1
    block="$($DESMOS_BIN q block 2> /dev/null | jq '.block')"
    ((i=i+1))
    if [ $i == 15 ] ; then
      >&2 echo "Chain start failed"
      >&2 cat ./start-chain.log
      >&2 ls "$DESMOS_HOME"
      exit 1
    fi
  done

  log "Chain started!"

  if [ "$CI" == "true" ] ; then
    echo "desmos-bin=$DESMOS_BIN"
    echo "desmos-home=$DESMOS_HOME"
  fi
}

VALID_ARGS=$(getopt -o v:g:p:P:i:h --long version:,genesis:,pre-run:,post-run:,chain-id:,help -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi


desmos_version=""
genesis_file=""
pre_run_script=""
post_run_script=""

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -v | --version)
        desmos_version=$2
        shift 2
        ;;
    -g | --genesis)
        genesis_file=$2
        shift 2
        ;;
    -p | --pre-run)
        pre_run_script=$2
        shift 2
        ;;
    -P | --post-run)
        post_run_script=$2
        shift 2
        ;;
    -h | --help)
        echo "Script to start a Desmos chain for testing purpose"
        echo "Usage: $(basename "$0") [OPTION]..."
        echo ""
        echo -e "-v, --version\t Desmos chain version ex: v4.6.3"
        echo -e "-g, --genesis\t chain genesis file"
        echo -e "-p, --pre-run\t script to run before the chain starts"
        echo -e "-P, --post-tun\t script to run after the chains is started"
        exit 0
        ;;
    --) shift;
        break
        ;;
  esac
done

# Download the requested desmos version
download_desmos "$desmos_version"

# Prepare the chain with the provided genesis file
prepare_chain "$genesis_file"

# Run the pre run script
DESMOS_HOME="$DESMOS_HOME" DESMOS_BIN="$DESMOS_BIN" run_script "$pre_run_script"

# Sart the chain as background process
run_chain

# Wait for chain to start
wait_chain_start

# Run the post run script
DESMOS_HOME="$DESMOS_HOME" DESMOS_BIN="$DESMOS_BIN" run_script "$post_run_script"

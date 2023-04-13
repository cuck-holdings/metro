#!/bin/sh

# set -x

set -o errexit -o nounset

SLEEP_TIMEOUT=5

# number of nodes
QTD=2
CHAINID="private"
DATA_DIR="$HOME/.metro"
GENTXDIR="$HOME/.metrogentx"
KEY="validator"

# starting ports; these increment by (node index * 10) for each node
IP_ADDR="127.0.0.1"
NODE_P2P_PORT=26656
NODE_LISTEN_PORT=26658
API_PORT=1317
GRPC_PORT=9090
NODE_RPC_PORT=26657

coins="1000000000000000utick"

if [ "$#" -eq 1 ]; then
    QTD=$1
fi

if [ $QTD -lt 1 ] || [ $QTD -gt 10 ]; then
    echo "invalid number of nodes"
    exit 1
fi

echo "removing old data"
pkill -f metro
rm -rf $HOME/.metro*
mkdir -p "$GENTXDIR"
echo "starting $QTD nodes"

# validator metro addresses for genesis file
declare -a genesis_addresses=()

# evm addresses (from anvil) 
# these are arbitrary
declare -a evm_addresses=("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" "0x90F79bf6EB2c4f870365E785982E1f101E93b906" "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65" "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc" "0x976EA74026E726554dB657fA54763abd0C3a0aa9" "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955" "0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f" "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720")

# metro p2p addresses for persistent peers
bootnodes=""

init_func() {
    echo "init"
    metro init $CHAINID --chain-id $CHAINID --home "$DATA_DIR$i"
    sed -i 's/addr_book_strict = true/addr_book_strict = false/' "$DATA_DIR$i/config/config.toml"
    # sed -i 's/seed_mode = false/seed_mode = true/' "$DATA_DIR$i/config/config.toml"

    echo "adding key"
    metro keys add $KEY"$i" --home "$DATA_DIR$i" --keyring-backend test

    genesis_addresses+=("$(metro keys show "$KEY$i" -a --home "$DATA_DIR$i" --keyring-backend test)")

    if [ "$i" -eq 1 ]; then
        echo "bootnode"
        bootnodes="$(metro tendermint show-node-id --home "$DATA_DIR$i")@$IP_ADDR:$NODE_P2P_PORT"
    fi
    # if [ "$i" -gt 1 ]; then
    #     bootnodes="$bootnodes,$(metro tendermint show-node-id --home "$DATA_DIR$i")@$IP_ADDR:$(($NODE_P2P_PORT+($i-1)*10))"
    # fi

    # sed -i'.bak' 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' "$DATA_DIR/config/config.toml"
    # sed -i 's/timeout_commit = "1s"/timeout_commit = "1s"/g' "$DATA_DIR$i/config/config.toml"
    # sed -i 's/timeout_propose = "1s"/timeout_propose = "1s"/g' "$DATA_DIR$i/config/config.toml"
    # sed -i 's/index_all_keys = false/index_all_keys = true/g' "$DATA_DIR$i/config/config.toml"
    # sed -i 's/mode = "full"/mode = "validator"/g' "$DATA_DIR$i/config/config.toml"
}

add_genesis_accounts() {
    for addr in "${genesis_addresses[@]}"
    do
        echo "adding genesis account $addr"
        metro add-genesis-account --home "$DATA_DIR$i" "$addr" $coins 
    done

    echo "gentx"
    metro gentx "$KEY$i" 5000000000utick \
    --output-document "$GENTXDIR/gentx-$KEY$i.json" \
    --home "$DATA_DIR$i" \
    --keyring-backend="test" \
    --chain-id $CHAINID \
    --orchestrator-address $(metro keys show "$KEY$i" -a --home "$DATA_DIR$i" --keyring-backend=test) \
    --evm-address ${evm_addresses[$i-1]}
}

collect_gentxs() {
    echo "collect-gentxs $i"
    metro collect-gentxs --home "$DATA_DIR$i" --gentx-dir "$GENTXDIR"
    metro validate-genesis --home "$DATA_DIR$i"
}

start_func() {
    PORT_MOD=$(( (i-1) * 10 ))
    echo "starting metro node $i in background..."
    echo "node p2p port: $(( $NODE_P2P_PORT+$PORT_MOD ))"
    echo "node p2p listen port:  $(( $NODE_LISTEN_PORT+$PORT_MOD ))"
    echo "node rpc port:  $(( $NODE_RPC_PORT+$PORT_MOD ))"
    echo "node api port:  $(( $API_PORT+$PORT_MOD ))"

    echo $bootnodes

    if [ "$i" -eq 1 ]; then
        metro start --home "$DATA_DIR$i" \
        --api.address tcp://$IP_ADDR:$(($API_PORT+$PORT_MOD )) \
        --p2p.external-address tcp://$IP_ADDR:$(($NODE_P2P_PORT+$PORT_MOD )) \
        --p2p.laddr tcp://$IP_ADDR:$(($NODE_P2P_PORT+$PORT_MOD )) \
        --address tcp://$IP_ADDR:$(($NODE_LISTEN_PORT+$PORT_MOD )) \
        --rpc.laddr tcp://$IP_ADDR:$(($NODE_RPC_PORT+$PORT_MOD )) \
        --grpc.address $IP_ADDR:$(($GRPC_PORT+$PORT_MOD )) \
        --grpc-web.enable=false \
        --cpu-profile=false \
        &> "$DATA_DIR$i/node.log" &
    else 
        metro start --home "$DATA_DIR$i" \
        --api.address tcp://$IP_ADDR:$(($API_PORT+$PORT_MOD )) \
        --p2p.external-address tcp://$IP_ADDR:$(($NODE_P2P_PORT+$PORT_MOD )) \
        --p2p.laddr tcp://$IP_ADDR:$(($NODE_P2P_PORT+$PORT_MOD )) \
        --address tcp://$IP_ADDR:$(($NODE_LISTEN_PORT+$PORT_MOD )) \
        --rpc.laddr tcp://$IP_ADDR:$(($NODE_RPC_PORT+$PORT_MOD )) \
        --grpc.address $IP_ADDR:$(($GRPC_PORT+$PORT_MOD )) \
        --grpc-web.enable=false \
        --cpu-profile=false \
        --p2p.persistent_peers "$bootnodes" \
        &> "$DATA_DIR$i/node.log" &
    fi
    
    PID=$!
    echo "started metro node, pid=$PID"
    echo "node logs are available at $DATA_DIR$i/node.log"
    # add PID to array
    arr+=("$PID")
}

for i in $(seq 1 "$QTD"); do
    init_func "$i"
done

for i in $(seq 1 "$QTD"); do
    add_genesis_accounts "$i"
done

# create genesis in first node
# copy genesis file to all other nodes
i=1
collect_gentxs
for i in $(seq 1 "$QTD"); do
    if [ "$i" -eq 1 ]; then
        continue
    fi
    cp ""$DATA_DIR"1/config/genesis.json" "$DATA_DIR$i/config/genesis.json"
done

for i in $(seq 1 "$QTD"); do
    start_func $i
    sleep 1
    echo "sleeping $SLEEP_TIMEOUT seconds for startup"
    sleep "$SLEEP_TIMEOUT"
    echo "done sleeping"
done

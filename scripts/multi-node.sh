#!/bin/sh

set -o errexit -o nounset

SLEEP_TIMEOUT=5

# number of nodes
NUM_NODES=2
CHAINID="private"
DATA_DIR="$HOME/.metro"
GENTXDIR="$HOME/.metrogentx"
KEY="validator"

# starting ports; these increment by (node index * 10) for each node
IP_ADDR="127.0.0.1"
NODE_P2P_PORT=26656
NODE_LISTEN_PORT=26656
API_PORT=1317
GRPC_PORT=9090
NODE_RPC_PORT=26657

coins="1000000000000000utick"

if [ "$#" -eq 1 ]; then
    NUM_NODES=$1
fi

if [ $NUM_NODES -lt 1 ] || [ $NUM_NODES -gt 10 ]; then
    echo "invalid number of nodes"
    exit 1
fi

echo "removing old data"
rm -rf $HOME/.metro*
mkdir -p "$GENTXDIR"
echo "starting $NUM_NODES nodes"

# validator metro addresses for genesis file
declare -a genesis_addresses=()

# evm addresses (from anvil) 
# these are arbitrary
declare -a evm_addresses=("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" "0x90F79bf6EB2c4f870365E785982E1f101E93b906" "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65" "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc" "0x976EA74026E726554dB657fA54763abd0C3a0aa9" "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955" "0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f" "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720")

# metro p2p addresses for persistent peers
bootnodes=""

# pids of all nodes
declare -a pids=()

init_func() {
    echo "initializing node $i"
    metro init $CHAINID --chain-id $CHAINID --home "$DATA_DIR$i"
    sed -i 's/addr_book_strict = true/addr_book_strict = false/' "$DATA_DIR$i/config/config.toml"
    sed -i 's/allow_duplicate_ip = false/allow_duplicate_ip = true/' "$DATA_DIR$i/config/config.toml"

    echo "adding key for node $i"
    metro keys add $KEY"$i" --home "$DATA_DIR$i" --keyring-backend test

    genesis_addresses+=("$(metro keys show "$KEY$i" -a --home "$DATA_DIR$i" --keyring-backend test)")

    # just add first node as bootnode right now
    if [ "$i" -eq 1 ]; then
        bootnodes="$(metro tendermint show-node-id --home "$DATA_DIR$i")@$IP_ADDR:$NODE_P2P_PORT"
        echo "added bootnode $bootnodes" 
    fi

    # uncomment these to set block time to 1s
    # sed -i 's/timeout_commit = "1s"/timeout_commit = "1s"/g' "$DATA_DIR$i/config/config.toml"
    # sed -i 's/timeout_propose = "1s"/timeout_propose = "1s"/g' "$DATA_DIR$i/config/config.toml"
}

add_genesis_accounts() {
    for addr in "${genesis_addresses[@]}"
    do
        echo "adding genesis account $addr for node $i"
        metro add-genesis-account --home "$DATA_DIR$i" "$addr" $coins 
    done

    echo "gentx for node $i"
    metro gentx "$KEY$i" 5000000000utick \
    --output-document "$GENTXDIR/gentx-$KEY$i.json" \
    --home "$DATA_DIR$i" \
    --keyring-backend="test" \
    --chain-id $CHAINID \
    --orchestrator-address $(metro keys show "$KEY$i" -a --home "$DATA_DIR$i" --keyring-backend=test) \
    --evm-address ${evm_addresses[$i-1]}
}

collect_gentxs() {
    echo "collect-gentxs for node $i"
    metro collect-gentxs --home "$DATA_DIR$i" --gentx-dir "$GENTXDIR"
    metro validate-genesis --home "$DATA_DIR$i"
}

start_func() {
    PORT_MOD=$(( (i-1) * 10 ))
    echo "starting metro node $i in background..."
    p2p_port=$(( $NODE_P2P_PORT+$PORT_MOD ))
    listen_port=$(( $NODE_LISTEN_PORT+$PORT_MOD ))
    rpc_port=$(( $NODE_RPC_PORT+$PORT_MOD ))
    api_port=$(( $API_PORT+$PORT_MOD ))
    grpc_port=$(( $GRPC_PORT+$PORT_MOD ))
    echo "node p2p port: $p2p_port"
    echo "node p2p listen port: $listen_port"
    echo "node rpc port: $rpc_port"
    echo "node api port: $api_port"
    echo "node grpc port: $grpc_port"

    if [ "$i" -eq 1 ]; then
        metro start --home "$DATA_DIR$i" \
        --api.address tcp://$IP_ADDR:$api_port \
        --p2p.external-address tcp://$IP_ADDR:$p2p_port \
        --p2p.laddr tcp://$IP_ADDR:$p2p_port \
        --address tcp://$IP_ADDR:$listen_port \
        --rpc.laddr tcp://$IP_ADDR:$rpc_port \
        --grpc.address $IP_ADDR:$grpc_port \
        --grpc-web.enable=false \
        --cpu-profile=false \
        &> "$DATA_DIR$i/node.log" &
    else 
        metro start --home "$DATA_DIR$i" \
        --api.address tcp://$IP_ADDR:$api_port \
        --p2p.external-address tcp://$IP_ADDR:$p2p_port \
        --p2p.laddr tcp://$IP_ADDR:$p2p_port \
        --address tcp://$IP_ADDR:$listen_port \
        --rpc.laddr tcp://$IP_ADDR:$rpc_port \
        --grpc.address $IP_ADDR:$grpc_port \
        --grpc-web.enable=false \
        --cpu-profile=false \
        --p2p.persistent_peers "$bootnodes" \
        &> "$DATA_DIR$i/node.log" &
    fi
    
    PID=$!
    echo "started metro node, pid=$PID"
    echo "node logs are available at $DATA_DIR$i/node.log"

    # add PID to array
    pids+=("$PID")
}

for i in $(seq 1 "$NUM_NODES"); do
    init_func "$i"
done

for i in $(seq 1 "$NUM_NODES"); do
    add_genesis_accounts "$i"
done

# create genesis in first node
# copy genesis file to all other nodes
i=1
collect_gentxs
for i in $(seq 1 "$NUM_NODES"); do
    if [ "$i" -eq 1 ]; then
        continue
    fi
    cp ""$DATA_DIR"1/config/genesis.json" "$DATA_DIR$i/config/genesis.json"
done

for i in $(seq 1 "$NUM_NODES"); do
    start_func $i
    sleep 1
    echo "sleeping $SLEEP_TIMEOUT seconds for startup"
    sleep "$SLEEP_TIMEOUT"
    echo "done sleeping"
done

echo "node PIDs: ${pids[@]}"
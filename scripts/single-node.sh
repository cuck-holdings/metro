#!/bin/sh

set -o errexit -o nounset

CHAINID="private"

# Build genesis file incl account for passed address
coins="1000000000000000utick"
metro init $CHAINID --chain-id $CHAINID 
metro keys add validator --keyring-backend="test"
# this won't work because the some proto types are decalared twice and the logs output to stdout (dependency hell involving iavl)
metro add-genesis-account $(metro keys show validator -a --keyring-backend="test") $coins
metro gentx validator 5000000000utick \
  --keyring-backend="test" \
  --chain-id $CHAINID \
  --orchestrator-address $(metro keys show validator -a --keyring-backend="test") \
  --evm-address 0x966e6f22781EF6a6A82BBB4DB3df8E225DfD9488 # private key: da6ed55cb2894ac2c9c10209c09de8e8b9d109b910338d5bf3d747a7e1fc9eb9

metro collect-gentxs

# Set proper defaults and change ports
# If you encounter: `sed: -I or -i may not be used with stdin` on MacOS you can mitigate by installing gnu-sed
# https://gist.github.com/andre3k1/e3a1a7133fded5de5a9ee99c87c6fa0d?permalink_comment_id=3082272#gistcomment-3082272
sed -i'.bak' 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' ~/.metro/config/config.toml
sed -i'.bak' 's/timeout_commit = "1s"/timeout_commit = "1s"/g' ~/.metro/config/config.toml
sed -i'.bak' 's/timeout_propose = "1s"/timeout_propose = "1s"/g' ~/.metro/config/config.toml
sed -i'.bak' 's/index_all_keys = false/index_all_keys = true/g' ~/.metro/config/config.toml
sed -i'.bak' 's/mode = "full"/mode = "validator"/g' ~/.metro/config/config.toml

# Start the app
metro start

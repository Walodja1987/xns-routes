# dependencies
update          :; forge update

# install latest stable solc version
solc            :; sudo add-apt-repository ppa:ethereum/ethereum && sudo apt-get update && sudo apt-get install solc

# build
build           :; forge build
build-optimised :; forge build --optimize
clean           :; forge clean

# chmod scripts
scripts         :; chmod +x ./scripts/*

# fork mainnet with Hardhat
mainnet-fork    :; npx hardhat node --fork ${ETH_MAINNET_RPC_URL}

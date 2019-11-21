#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")"

export ETH_FROM=...
export ETH_KEYSTORE=...
export ETH_GAS=1190948
export ETH_GAS_PRICE=10000000000

cd ..
SOLC_FLAGS=--optimize dapp build --extract

export ETH_GAS=$(seth --chain kovan \
  estimate \
  --create ./out/OasisDirectMigrateProxyActions.bin \
  'OasisDirectMigrateProxyActions()')
  
seth --chain mainnet \
  send \
  --create ./out/OasisDirectMigrateProxyActions.bin \
  'OasisDirectMigrateProxyActions()'
  
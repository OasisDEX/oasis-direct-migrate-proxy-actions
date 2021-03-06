#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")"

export ETH_FROM=...
export ETH_KEYSTORE=...
export ETH_PASSWORD=...

cd ..
SOLC_FLAGS=--optimize dapp build --extract

export ETH_GAS=$(seth --chain kovan \
  estimate \
  --create ./out/OasisDirectMigrateProxyActions.bin \
  'OasisDirectMigrateProxyActions()')

seth --chain kovan \
  send \
  --create ./out/OasisDirectMigrateProxyActions.bin \
  'OasisDirectMigrateProxyActions()'
  
#!/usr/bin/env bash
set -ex
cd "$(dirname "$0")"

export ETH_FROM=...
export ETH_KEYSTORE=...
export ETH_PASSWORD=...
export ETH_GAS=6000000

seth --chain kovan \
  send \
  --create ./out/OasisDirectMigrateProxyActions.bin \
  'OasisDirectMigrateProxyActions()'
  
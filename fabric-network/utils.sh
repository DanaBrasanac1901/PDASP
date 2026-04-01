#!/usr/bin/env bash

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[1;33m'

# println echos string
function println() {
  echo -e "$1"
}

# errorln echos i red color
function errorln() {
  println "${C_RED}${1}${C_RESET}"
}

# successln echos in green color
function successln() {
  println "${C_GREEN}${1}${C_RESET}"
}

# infoln echos in blue color
function infoln() {
  println "${C_BLUE}${1}${C_RESET}"
}

# warnln echos in yellow color
function warnln() {
  println "${C_YELLOW}${1}${C_RESET}"
}

# fatalln echos in red color and exits with fail status
function fatalln() {
  errorln "$1"
  exit 1
}

export -f errorln
export -f successln
export -f infoln
export -f warnln

# setOrgPeerEnv sets the peer CLI environment variables for the given org number
# Usage: setOrgPeerEnv <org_number>
function setOrgPeerEnv() {
  local ORG=$1
  case $ORG in
    1)
      export CORE_PEER_LOCALMSPID=Org1MSP
      export CORE_PEER_TLS_ROOTCERT_FILE=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
      export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
      export CORE_PEER_ADDRESS=localhost:7051
      ;;
    2)
      export CORE_PEER_LOCALMSPID=Org2MSP
      export CORE_PEER_TLS_ROOTCERT_FILE=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem
      export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
      export CORE_PEER_ADDRESS=localhost:10051
      ;;
    3)
      export CORE_PEER_LOCALMSPID=Org3MSP
      export CORE_PEER_TLS_ROOTCERT_FILE=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/tlsca/tlsca.org3.example.com-cert.pem
      export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
      export CORE_PEER_ADDRESS=localhost:13051
      ;;
    *)
      errorln "Unknown org: $ORG"
      exit 1
      ;;
  esac
}

# fetchChannelConfig <org_number> <channel_name> <output_json>
# Fetches the current channel config block, decodes it, and extracts the config to JSON
function fetchChannelConfig() {
  local ORG=$1
  local CHANNEL_NAME=$2
  local OUTPUT=$3

  setOrgPeerEnv $ORG

  infoln "Fetching the most recent configuration block for channel ${CHANNEL_NAME}"

  set -x
  peer channel fetch config ./channel-artifacts/config_block.pb -o localhost:${ORDERER_LISTENER_PORT} --ordererTLSHostnameOverride orderer.example.com -c ${CHANNEL_NAME} --tls --cafile "${ORDERER_CA}"
  { set +x; } 2>/dev/null

  infoln "Decoding config block to JSON and isolating config to ${OUTPUT}"

  set -x
  configtxlator proto_decode --input ./channel-artifacts/config_block.pb --type common.Block --output ./channel-artifacts/config_block.json
  jq .data.data[0].payload.data.config ./channel-artifacts/config_block.json > "${OUTPUT}"
  res=$?
  { set +x; } 2>/dev/null
  verifyResult $res "Failed to decode or extract channel config"
}

# createConfigUpdate <channel_name> <original_config_json> <modified_config_json> <output_tx>
# Computes the config update between original and modified configs and wraps it in an envelope
function createConfigUpdate() {
  local CHANNEL=$1
  local ORIGINAL=$2
  local MODIFIED=$3
  local OUTPUT=$4

  set -x
  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config --output ./channel-artifacts/original_config.pb
  configtxlator proto_encode --input "${MODIFIED}" --type common.Config --output ./channel-artifacts/modified_config.pb
  configtxlator compute_update --channel_id "${CHANNEL}" --original ./channel-artifacts/original_config.pb --updated ./channel-artifacts/modified_config.pb --output ./channel-artifacts/config_update.pb
  configtxlator proto_decode --input ./channel-artifacts/config_update.pb --type common.ConfigUpdate --output ./channel-artifacts/config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL}"'", "type":2}},"data":{"config_update":'$(cat ./channel-artifacts/config_update.json)'}}}' | jq . > ./channel-artifacts/config_update_in_envelope.json
  configtxlator proto_encode --input ./channel-artifacts/config_update_in_envelope.json --type common.Envelope --output "${OUTPUT}"
  { set +x; } 2>/dev/null
}

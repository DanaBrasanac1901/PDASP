#!/usr/bin/env bash
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${ROOTDIR}/bin:$PATH
export FABRIC_CFG_PATH=${ROOTDIR}/configtx
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

SOCK="${DOCKER_HOST:-/var/run/docker.sock}"
DOCKER_SOCK="${SOCK##unix://}"

MAX_RETRY=5
DELAY=3

. ./utils.sh

function checkPrereqs() {
  ## Check if your have cloned the peer binaries and configuration files.
  peer version > /dev/null 2>&1

  if [[ $? -ne 0 || ! -d "./config" ]]; then
    errorln "Peer binary and configuration files not found.."
    errorln
    errorln "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
    errorln "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
    exit 1
  fi
  # use the fabric peer container to see if the samples and binaries match your
  # docker images
  LOCAL_VERSION=$(peer version | sed -ne 's/^ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-peer:latest peer version | sed -ne 's/^ Version: //p')

  infoln "LOCAL_VERSION=$LOCAL_VERSION"
  infoln "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    warnln "Local fabric binaries and docker images are out of sync. This may cause problems."
  fi

  for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
    infoln "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      fatalln "Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the test network."
    fi

    infoln "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      fatalln "Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the test network."
    fi
  done

  ## Check for fabric-ca
    fabric-ca-client version > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      errorln "fabric-ca-client binary not found.."
      errorln
      errorln "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
      errorln "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
      exit 1
    fi
    CA_LOCAL_VERSION=$(fabric-ca-client version | sed -ne 's/ Version: //p')
    CA_DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-ca:latest fabric-ca-client version | sed -ne 's/ Version: //p' | head -1)
    infoln "CA_LOCAL_VERSION=$CA_LOCAL_VERSION"
    infoln "CA_DOCKER_IMAGE_VERSION=$CA_DOCKER_IMAGE_VERSION"

    if [ "$CA_LOCAL_VERSION" != "$CA_DOCKER_IMAGE_VERSION" ]; then
      warnln "Local fabric-ca binaries and docker images are out of sync. This may cause problems."
    fi
}

function createOrgs() {
  if [ -d "organizations/peerOrganizations" ]; then
    rm -Rf organizations/peerOrganizations && rm -Rf organizations/ordererOrganizations
  fi

   # Create crypto material using Fabric CA
    infoln "Generating certificates using Fabric CA"
    docker-compose -f compose/compose-ca.yaml up -d 2>&1

    . organizations/registerOrgs.sh

    # Make sure CA files have been created
    while :
    do
      if [ ! -f "organizations/fabric-ca/org1/tls-cert.pem" ]; then
        sleep 1
      else
        break
      fi
    done

    # Make sure CA service is initialized and can accept requests before making register and enroll calls
    export FABRIC_CA_CLIENT_HOME=./organizations/peerOrganizations/org1.example.com/
    COUNTER=0
    rc=1
    while [[ $rc -ne 0 && $COUNTER -lt $MAX_RETRY ]]; do
      sleep 1
      set -x
      fabric-ca-client getcainfo -u https://admin:adminpw@localhost:7054 --caname ca-org1 --tls.certfiles "./organizations/fabric-ca/org1/ca-cert.pem"
      res=$?
    { set +x; } 2>/dev/null
    rc=$res  # Update rc
    COUNTER=$((COUNTER + 1))
    done

    infoln "Creating Org1 Identities"

    createOrg1

    infoln "Creating Org2 Identities"

    createOrg2
    
    infoln "Creating Org3 Identities"

    createOrg3

    infoln "Creating Orderer Org 1 Identities"

    createOrderer1
    
    infoln "Creating Orderer Org 2 Identities"

    createOrderer2

  infoln "Generating CCP files for Org1 and Org2"
  ./organizations/ccp-generate.sh
}

function networkUp() {

  checkPrereqs

  # generate artifacts if they don't exist
  if [ ! -d "organizations/peerOrganizations" ]; then
    createOrgs
  fi

  DOCKER_SOCK="${DOCKER_SOCK}" docker-compose -f compose/compose-network.yaml up -d 2>&1

  docker ps -a
  if [ $? -ne 0 ]; then
    fatalln "Unable to start network"
  fi

}

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}

# call the script to create the channel, join the peers of org1 and org2,
# and then update the anchor peers for each organization
createChannel() {
CHANNEL_ID="$1"
CHANNEL_NAME="channel${CHANNEL_ID}"

export FABRIC_CFG_PATH=${ROOTDIR}/configtx

if [ ! -d "channel-artifacts" ]; then
	mkdir channel-artifacts
fi

## Create channel genesis block
BLOCKFILE="./channel-artifacts/${CHANNEL_NAME}.block"
infoln "Generating channel genesis block '${CHANNEL_NAME}.block'"

which configtxgen
	if [ "$?" -ne 0 ]; then
		fatalln "configtxgen tool not found."
	fi

configtxgen -profile Channel${CHANNEL_ID}UsingRaft -outputBlock ./channel-artifacts/${CHANNEL_NAME}.block -channelID ${CHANNEL_NAME}

res=$?
{ set +x; } 2>/dev/null
verifyResult $res "Failed to generate channel configuration transaction..."

export FABRIC_CFG_PATH=${ROOTDIR}/config
export CORE_PEER_TLS_ENABLED=true

## Create channel
infoln "Creating channel ${CHANNEL_NAME}"

if [ ${CHANNEL_ID} -eq 1 ]; then
  export ORDERER_LISTENER_PORT=7050
  export ORDERER_ADMIN_LISTENER_PORT=7053
else 
  export ORDERER_LISTENER_PORT=8050
  export ORDERER_ADMIN_LISTENER_PORT=8053
fi

# Poll in case the raft leader is not set yet
local rc=1
local COUNTER=1
infoln "Adding orderers"
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  
  export ORDERER_CA=${ROOTDIR}/organizations/ordererOrganizations/orderer${CHANNEL_ID}.example.com/tlsca/tlsca.example.com-cert.pem
  export ORDERER_ADMIN_TLS_SIGN_CERT=${ROOTDIR}/organizations/ordererOrganizations/orderer${CHANNEL_ID}.example.com/orderers/orderer.example.com/tls/server.crt
  export ORDERER_ADMIN_TLS_PRIVATE_KEY=${ROOTDIR}/organizations/ordererOrganizations/orderer${CHANNEL_ID}.example.com/orderers/orderer.example.com/tls/server.key
  osnadmin channel join --channelID ${CHANNEL_NAME} --config-block ./channel-artifacts/${CHANNEL_NAME}.block -o localhost:${ORDERER_ADMIN_LISTENER_PORT} --ca-file ${ORDERER_CA} --client-cert ${ORDERER_ADMIN_TLS_SIGN_CERT} --client-key ${ORDERER_ADMIN_TLS_PRIVATE_KEY} >> log.txt 2>&1
  
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "Channel creation failed"

successln "Channel '$CHANNEL_NAME' created"

## Join all the peers to the channel

infoln "Joining org1 peer0 to the channel..."
export CORE_ORG1_CA=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG1_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer0.org1 has failed to join channel '$CHANNEL_NAME' "

infoln "Joining org1 peer1 to the channel..."
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG1_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:8051

local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer1.org1 has failed to join channel '$CHANNEL_NAME' "

infoln "Joining org1 peer2 to the channel..."
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG1_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051

local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer2.org1 has failed to join channel '$CHANNEL_NAME' "


infoln "Joining org2 peer0 to the channel..."
export CORE_ORG2_CA=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG2_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:10051

local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer0.org2 has failed to join channel '$CHANNEL_NAME'"

infoln "Joining org2 peer1 to the channel..."
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG2_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:11051

local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer1.org2 has failed to join channel '$CHANNEL_NAME' "

infoln "Joining org2 peer2 to the channel..."
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG2_CA
export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:12051

local rc=1
local COUNTER=1
## Sometimes Join takes time, hence retry
while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
  sleep $DELAY
  set -x
  peer channel join -b $BLOCKFILE >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  let rc=$res
  COUNTER=$(expr $COUNTER + 1)
done
cat log.txt
verifyResult $res "After $MAX_RETRY attempts, peer2.org2 has failed to join channel '$CHANNEL_NAME' "

## In channel one we want all orgs and in channel two only org1 and org2
if [ ${CHANNEL_ID} -eq 1 ]; then
  infoln "Joining org3 peer0 to the channel..."
  export CORE_ORG3_CA=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/tlsca/tlsca.org3.example.com-cert.pem
  export CORE_PEER_LOCALMSPID=Org3MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG3_CA
  export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
  export CORE_PEER_ADDRESS=localhost:13051

  local rc=1
  local COUNTER=1
  ## Sometimes Join takes time, hence retry
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  verifyResult $res "After $MAX_RETRY attempts, peer0.org3 has failed to join channel '$CHANNEL_NAME'"

  infoln "Joining org3 peer1 to the channel..."
  export CORE_PEER_LOCALMSPID=Org3MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG3_CA
  export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
  export CORE_PEER_ADDRESS=localhost:14051

  local rc=1
  local COUNTER=1
  ## Sometimes Join takes time, hence retry
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  verifyResult $res "After $MAX_RETRY attempts, peer1.org3 has failed to join channel '$CHANNEL_NAME' "

  infoln "Joining org3 peer2 to the channel..."
  export CORE_PEER_LOCALMSPID=Org3MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=$CORE_ORG3_CA
  export CORE_PEER_MSPCONFIGPATH=${ROOTDIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
  export CORE_PEER_ADDRESS=localhost:15051

  local rc=1
  local COUNTER=1
  ## Sometimes Join takes time, hence retry
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  verifyResult $res "After $MAX_RETRY attempts, peer2.org3 has failed to join channel '$CHANNEL_NAME' "
fi

## Set the anchor peers for each org in the channel
infoln "Setting anchor peer for org1..."
export CORE_PEER_LOCALMSPID=Org1MSP
infoln "Fetching channel config for channel $CHANNEL_NAME"
fetchChannelConfig 1 ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json
infoln "Generating anchor peer update transaction for Org1 on channel $CHANNEL_NAME"
HOST="peer0.org1.example.com"
PORT=7051

set -x
# Modify the configuration to append the anchor peer 
jq '.channel_group.groups.Application.groups.'${CORE_PEER_LOCALMSPID}'.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "'$HOST'","port": '$PORT'}]},"version": "0"}}' ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json > ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json
res=$?
{ set +x; } 2>/dev/null
verifyResult $res "Channel configuration update for anchor peer failed, make sure you have jq installed"

# Compute a config update, based on the differences between 
# {orgmsp}config.json and {orgmsp}modified_config.json, write
# it as a transaction to {orgmsp}anchors.tx
createConfigUpdate ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx

peer channel update -o localhost:${ORDERER_LISTENER_PORT} --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile "$ORDERER_CA" >&log.txt
res=$?
cat log.txt
verifyResult $res "Anchor peer update failed"
successln "Anchor peer set for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"


infoln "Setting anchor peer for org2..."
export CORE_PEER_LOCALMSPID=Org2MSP
infoln "Fetching channel config for channel $CHANNEL_NAME"
fetchChannelConfig 2 ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json
infoln "Generating anchor peer update transaction for Org2 on channel $CHANNEL_NAME"
HOST="peer0.org2.example.com"
PORT=10051

set -x
# Modify the configuration to append the anchor peer 
jq '.channel_group.groups.Application.groups.'${CORE_PEER_LOCALMSPID}'.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "'$HOST'","port": '$PORT'}]},"version": "0"}}' ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json > ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json
res=$?
{ set +x; } 2>/dev/null
verifyResult $res "Channel configuration update for anchor peer failed, make sure you have jq installed"

# Compute a config update, based on the differences between 
# {orgmsp}config.json and {orgmsp}modified_config.json, write
# it as a transaction to {orgmsp}anchors.tx
createConfigUpdate ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx

peer channel update -o localhost:${ORDERER_LISTENER_PORT} --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile "$ORDERER_CA" >&log.txt
res=$?
cat log.txt
verifyResult $res "Anchor peer update failed"
successln "Anchor peer set for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"

## In channel one we want all orgs and in channel two only org1 and org2
if [ ${CHANNEL_ID} -eq 1 ]; then
  infoln "Setting anchor peer for org3..."
  export CORE_PEER_LOCALMSPID=Org3MSP
  infoln "Fetching channel config for channel $CHANNEL_NAME"
  fetchChannelConfig 3 ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json
  infoln "Generating anchor peer update transaction for Org3 on channel $CHANNEL_NAME"
  HOST="peer0.org3.example.com"
  PORT=13051

  set -x
  # Modify the configuration to append the anchor peer 
  jq '.channel_group.groups.Application.groups.'${CORE_PEER_LOCALMSPID}'.values += {"AnchorPeers":{"mod_policy": "Admins","value":{"anchor_peers": [{"host": "'$HOST'","port": '$PORT'}]},"version": "0"}}' ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json > ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json
  res=$?
  { set +x; } 2>/dev/null
  verifyResult $res "Channel configuration update for anchor peer failed, make sure you have jq installed"

  # Compute a config update, based on the differences between 
  # {orgmsp}config.json and {orgmsp}modified_config.json, write
  # it as a transaction to {orgmsp}anchors.tx
  createConfigUpdate ${CHANNEL_NAME} ./channel-artifacts/${CORE_PEER_LOCALMSPID}config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}modified_config.json ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx

  peer channel update -o localhost:${ORDERER_LISTENER_PORT} --ordererTLSHostnameOverride orderer.example.com -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile "$ORDERER_CA" >&log.txt
  res=$?
  cat log.txt
  verifyResult $res "Anchor peer update failed"
  successln "Anchor peer set for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"

fi

successln "Channel '$CHANNEL_NAME' joined"
}

networkUp
createChannel 1
createChannel 2
./deploy-cc.sh
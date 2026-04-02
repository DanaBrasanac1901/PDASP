#!/bin/bash
# deployCC.sh — deploys chaincode on channel1 (Org1+Org2+Org3) and channel2 (Org1+Org2)
set -e

#!/usr/bin/env bash
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${ROOTDIR}/bin:$PATH
export FABRIC_CFG_PATH=${ROOTDIR}/config
export CORE_PEER_TLS_ENABLED=true

CC_NAME=cc
CC_VERSION=1.0
CC_SEQUENCE=1
CC_PATH=./chaincode

ORDERER1_CA="${PWD}/organizations/ordererOrganizations/orderer1.example.com/orderers/orderer.example.com/tls/ca.crt"
ORDERER1_ADDR="localhost:7050"
ORDERER1_OVERRIDE="orderer1.example.com"

ORDERER2_CA="${PWD}/organizations/ordererOrganizations/orderer2.example.com/orderers/orderer.example.com/tls/ca.crt"
ORDERER2_ADDR="localhost:8050"
ORDERER2_OVERRIDE="orderer2.example.com"

ORG1_TLS="${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS="${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
ORG3_TLS="${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt"

POLICY_CH1="OutOf(2,'Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')"
POLICY_CH2="OR('Org1MSP.peer','Org2MSP.peer')"

setOrg1() {
  export CORE_PEER_LOCALMSPID=Org1MSP
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1_TLS}
  export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
  export CORE_PEER_ADDRESS=localhost:7051
}

setOrg2() {
  export CORE_PEER_LOCALMSPID=Org2MSP
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=${ORG2_TLS}
  export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
  export CORE_PEER_ADDRESS=localhost:10051
}

setOrg3() {
  export CORE_PEER_LOCALMSPID=Org3MSP
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_TLS_ROOTCERT_FILE=${ORG3_TLS}
  export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
  export CORE_PEER_ADDRESS=localhost:13051
}


echo "============================================================"
echo " Packaging ${CC_NAME} v${CC_VERSION}"
echo "============================================================"
setOrg1
peer lifecycle chaincode package ${CC_NAME}.tar.gz \
  --path ${CC_PATH} \
  --lang golang \
  --label ${CC_NAME}_${CC_VERSION}

echo "--- Installing on Org1 peer0 ---"
setOrg1; peer lifecycle chaincode install ${CC_NAME}.tar.gz

echo "--- Installing on Org2 peer0 ---"
setOrg2; peer lifecycle chaincode install ${CC_NAME}.tar.gz

echo "--- Installing on Org3 peer0 ---"
setOrg3; peer lifecycle chaincode install ${CC_NAME}.tar.gz


setOrg1
CC_PKG_ID=$(peer lifecycle chaincode queryinstalled \
  --output json | jq -r ".installed_chaincodes[] | select(.label==\"${CC_NAME}_${CC_VERSION}\") | .package_id")
echo "Package ID: ${CC_PKG_ID}"


for approveOrg in 1 2 3; do
  echo "--- Approving for Org${approveOrg} on channel1 ---"
  setOrg${approveOrg}
  peer lifecycle chaincode approveformyorg \
    -o ${ORDERER1_ADDR} --ordererTLSHostnameOverride ${ORDERER1_OVERRIDE} \
    --tls --cafile ${ORDERER1_CA} \
    --channelID channel1 --name ${CC_NAME} \
    --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
    --package-id ${CC_PKG_ID} \
    --signature-policy "${POLICY_CH1}" \
    --waitForEventTimeout 120s
  sleep 3
done

echo "--- Checking commit readiness on channel1 ---"
setOrg1
peer lifecycle chaincode checkcommitreadiness \
  --channelID channel1 --name ${CC_NAME} \
  --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --signature-policy "${POLICY_CH1}" --output json

echo "--- Committing on channel1 ---"
setOrg1
peer lifecycle chaincode commit \
  -o ${ORDERER1_ADDR} --ordererTLSHostnameOverride ${ORDERER1_OVERRIDE} \
  --tls --cafile ${ORDERER1_CA} \
  --channelID channel1 --name ${CC_NAME} \
  --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --signature-policy "${POLICY_CH1}" \
  --peerAddresses localhost:7051  --tlsRootCertFiles ${ORG1_TLS} \
  --peerAddresses localhost:10051 --tlsRootCertFiles ${ORG2_TLS} \
  --peerAddresses localhost:13051 --tlsRootCertFiles ${ORG3_TLS}

echo "Chaincode committed on channel1."

for approveOrg in 1 2; do
  echo "--- Approving for Org${approveOrg} on channel2 ---"
  setOrg${approveOrg}
  peer lifecycle chaincode approveformyorg \
    -o ${ORDERER2_ADDR} --ordererTLSHostnameOverride ${ORDERER2_OVERRIDE} \
    --tls --cafile ${ORDERER2_CA} \
    --channelID channel2 --name ${CC_NAME} \
    --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
    --package-id ${CC_PKG_ID} \
    --signature-policy "${POLICY_CH2}" \
    --waitForEventTimeout 120s
  sleep 3
done

echo "--- Checking commit readiness on channel2 ---"
setOrg1
peer lifecycle chaincode checkcommitreadiness \
  --channelID channel2 --name ${CC_NAME} \
  --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --signature-policy "${POLICY_CH2}" --output json

echo "--- Committing on channel2 ---"
setOrg1
peer lifecycle chaincode commit \
  -o ${ORDERER2_ADDR} --ordererTLSHostnameOverride ${ORDERER2_OVERRIDE} \
  --tls --cafile ${ORDERER2_CA} \
  --channelID channel2 --name ${CC_NAME} \
  --version ${CC_VERSION} --sequence ${CC_SEQUENCE} \
  --signature-policy "${POLICY_CH2}" \
  --peerAddresses localhost:7051  --tlsRootCertFiles ${ORG1_TLS} \
  --peerAddresses localhost:10051 --tlsRootCertFiles ${ORG2_TLS}

echo "Chaincode committed on channel2."
echo ""
echo "Done. ${CC_NAME} deployed on both channels."
SOCK="${DOCKER_HOST:-/var/run/docker.sock}"
DOCKER_SOCK="${SOCK##unix://}"
DOCKER_SOCK=$DOCKER_SOCK docker-compose -f compose/compose-ca.yaml -f compose/compose-network.yaml down --volumes --remove-orphans

. ./utils.sh

# Obtain CONTAINER_IDS and remove them
# This function is called when you bring a network down
function clearContainers() {
  infoln "Removing remaining containers"
  docker rm -f $(docker ps -aq --filter label=service=hyperledger-fabric) 2>/dev/null || true
  docker rm -f $(docker ps -aq --filter name='dev-peer*') 2>/dev/null || true
  docker kill "$(docker ps -q --filter name=ccaas)" 2>/dev/null || true
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
  infoln "Removing generated chaincode docker images"
  docker image rm -f $(docker images -aq --filter reference='dev-peer*') 2>/dev/null || true
}
  
# Bring down the network, deleting the volumes
docker volume rm docker_orderer1.example.com docker_orderer2.example.com \
  docker_peer0.org1.example.com docker_peer1.org1.example.com docker_peer2.org1.example.com \
  docker_peer0.org2.example.com docker_peer1.org2.example.com docker_peer2.org2.example.com \
  docker_peer0.org3.example.com docker_peer1.org3.example.com docker_peer2.org3.example.com

  
clearContainers
removeUnwantedImages

docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations'
## remove fabric ca artifacts
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db'
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db'
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org3/msp organizations/fabric-ca/org3/tls-cert.pem organizations/fabric-ca/org3/ca-cert.pem organizations/fabric-ca/org3/IssuerPublicKey organizations/fabric-ca/org3/IssuerRevocationPublicKey organizations/fabric-ca/org3/fabric-ca-server.db'
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg1/msp organizations/fabric-ca/ordererOrg1/tls-cert.pem organizations/fabric-ca/ordererOrg1/ca-cert.pem organizations/fabric-ca/ordererOrg1/IssuerPublicKey organizations/fabric-ca/ordererOrg1/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg1/fabric-ca-server.db'
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg2/msp organizations/fabric-ca/ordererOrg2/tls-cert.pem organizations/fabric-ca/ordererOrg2/ca-cert.pem organizations/fabric-ca/ordererOrg2/IssuerPublicKey organizations/fabric-ca/ordererOrg2/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg2/fabric-ca-server.db'

# remove channel and script artifacts
docker run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
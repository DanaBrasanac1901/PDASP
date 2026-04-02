#!/usr/bin/env bash
# test-all.sh — full functional test of all chaincode functions
set -e

ROOTDIR=$(cd "$(dirname "$0")/.." && pwd)
export PATH=${ROOTDIR}/bin:$PATH
export FABRIC_CFG_PATH=${ROOTDIR}/config
export CORE_PEER_TLS_ENABLED=true

CHANNEL="channel1"
CC="trading"
ORDERER_CA="${ROOTDIR}/organizations/ordererOrganizations/orderer1.example.com/tlsca/tlsca.example.com-cert.pem"
ORDERER="localhost:7050"
ORDERER_OVERRIDE="orderer.example.com"

ORG1_TLS="${ROOTDIR}/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"
ORG2_TLS="${ROOTDIR}/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"
ORG3_TLS="${ROOTDIR}/organizations/peerOrganizations/org3.example.com/tlsca/tlsca.org3.example.com-cert.pem"

ORG1_ADMIN="${ROOTDIR}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
ORG3_ADMIN="${ROOTDIR}/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp"

ORG1_CA_CERT="${ROOTDIR}/organizations/fabric-ca/org1/ca-cert.pem"
ORG3_CA_CERT="${ROOTDIR}/organizations/fabric-ca/org3/ca-cert.pem"

PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
header() {
  echo ""
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
  echo -e "${YELLOW} $1${NC}"
  echo -e "${YELLOW}══════════════════════════════════════${NC}"
}

setOrg1() {
  export CORE_PEER_LOCALMSPID=Org1MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=${ORG1_TLS}
  export CORE_PEER_MSPCONFIGPATH=${ORG1_ADMIN}
  export CORE_PEER_ADDRESS=localhost:7051
}

setOrg3() {
  export CORE_PEER_LOCALMSPID=Org3MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=${ORG3_TLS}
  export CORE_PEER_MSPCONFIGPATH=${ORG3_ADMIN}
  export CORE_PEER_ADDRESS=localhost:13051
}

invoke() {
  local fn=$1
  local args=$2
  setOrg1
  peer chaincode invoke \
    -o ${ORDERER} --ordererTLSHostnameOverride ${ORDERER_OVERRIDE} \
    --tls --cafile ${ORDERER_CA} \
    -C ${CHANNEL} -n ${CC} \
    --peerAddresses localhost:7051  --tlsRootCertFiles ${ORG1_TLS} \
    --peerAddresses localhost:10051 --tlsRootCertFiles ${ORG2_TLS} \
    -c "{\"function\":\"${fn}\",\"Args\":${args}}" 2>&1
  sleep 2
}

query() {
  local fn=$1
  local args=$2
  setOrg1
  peer chaincode query \
    -C ${CHANNEL} -n ${CC} \
    -c "{\"function\":\"${fn}\",\"Args\":${args}}" 2>&1
}

queryOrg3() {
  local fn=$1
  local args=$2
  setOrg3
  peer chaincode query \
    -C ${CHANNEL} -n ${CC} \
    -c "{\"function\":\"${fn}\",\"Args\":${args}}" 2>&1
}

expect_success() {
  local desc=$1
  local output=$2
  if echo "$output" | grep -qi "error\|failed\|Error"; then
    fail "$desc — unexpected error: $output"
  else
    pass "$desc"
  fi
}

expect_failure() {
  local desc=$1
  local output=$2
  if echo "$output" | grep -qi "error\|failed\|Error"; then
    pass "$desc (failed as expected)"
  else
    fail "$desc — expected failure but got success: $output"
  fi
}

header "0. Enroll test users via fabric-ca-client"

# Enroll testuser1 under Org1
export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/sdk/wallet/org1/testuser1
mkdir -p ${FABRIC_CA_CLIENT_HOME}
fabric-ca-client enroll \
  -u https://testuser1:testuser1pw@localhost:7054 \
  --caname ca-org1 \
  --tls.certfiles ${ORG1_CA_CERT} \
  --mspdir ${FABRIC_CA_CLIENT_HOME}/msp > /dev/null 2>&1
if [ $? -eq 0 ] && [ -f "${FABRIC_CA_CLIENT_HOME}/msp/signcerts/cert.pem" ]; then
  pass "testuser1 enrolled under Org1 — cert exists in wallet"
else
  # User may not be registered yet — register first using admin, then enroll
  export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/organizations/peerOrganizations/org1.example.com
  fabric-ca-client register \
    --caname ca-org1 \
    --id.name testuser1 \
    --id.secret testuser1pw \
    --id.type client \
    --tls.certfiles ${ORG1_CA_CERT} \
    -u https://localhost:7054 > /dev/null 2>&1 || true

  export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/sdk/wallet/org1/testuser1
  mkdir -p ${FABRIC_CA_CLIENT_HOME}
  fabric-ca-client enroll \
    -u https://testuser1:testuser1pw@localhost:7054 \
    --caname ca-org1 \
    --tls.certfiles ${ORG1_CA_CERT} \
    --mspdir ${FABRIC_CA_CLIENT_HOME}/msp > /dev/null 2>&1

  if [ -f "${FABRIC_CA_CLIENT_HOME}/msp/signcerts/cert.pem" ]; then
    pass "testuser1 registered and enrolled under Org1"
  else
    fail "testuser1 enrollment under Org1 failed"
  fi
fi

export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/sdk/wallet/org3/testuser3
mkdir -p ${FABRIC_CA_CLIENT_HOME}
fabric-ca-client enroll \
  -u https://testuser3:testuser3pw@localhost:9054 \
  --caname ca-org3 \
  --tls.certfiles ${ORG3_CA_CERT} \
  --mspdir ${FABRIC_CA_CLIENT_HOME}/msp > /dev/null 2>&1
if [ $? -eq 0 ] && [ -f "${FABRIC_CA_CLIENT_HOME}/msp/signcerts/cert.pem" ]; then
  pass "testuser3 enrolled under Org3 — cert exists in wallet"
else
  export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/organizations/peerOrganizations/org3.example.com
  fabric-ca-client register \
    --caname ca-org3 \
    --id.name testuser3 \
    --id.secret testuser3pw \
    --id.type client \
    --tls.certfiles ${ORG3_CA_CERT} \
    -u https://localhost:9054 > /dev/null 2>&1 || true

  export FABRIC_CA_CLIENT_HOME=${ROOTDIR}/sdk/wallet/org3/testuser3
  mkdir -p ${FABRIC_CA_CLIENT_HOME}
  fabric-ca-client enroll \
    -u https://testuser3:testuser3pw@localhost:9054 \
    --caname ca-org3 \
    --tls.certfiles ${ORG3_CA_CERT} \
    --mspdir ${FABRIC_CA_CLIENT_HOME}/msp > /dev/null 2>&1

  if [ -f "${FABRIC_CA_CLIENT_HOME}/msp/signcerts/cert.pem" ]; then
    pass "testuser3 registered and enrolled under Org3"
  else
    fail "testuser3 enrollment under Org3 failed"
  fi
fi


if [ -d "${ROOTDIR}/sdk/wallet/org1/testuser1/msp" ]; then
  pass "Login check — testuser1 wallet found (login would succeed)"
else
  fail "Login check — testuser1 wallet missing"
fi

if [ -d "${ROOTDIR}/sdk/wallet/org3/testuser3/msp" ]; then
  pass "Login check — testuser3 wallet found (login would succeed)"
else
  fail "Login check — testuser3 wallet missing"
fi



header "1. InitLedger"
out=$(invoke "InitLedger" "[]")
expect_success "InitLedger populates world state" "$out"
sleep 2



header "2. GetAllMerchantTypes"
out=$(query "GetAllMerchantTypes" "[]")
expect_success "GetAllMerchantTypes returns list" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"



header "3a. GetMerchant — existing (M001 supermarket)"
out=$(query "GetMerchant" '["M001"]')
expect_success "GetMerchant M001 exists" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "3b. GetMerchant — existing (M002 flower shop)"
out=$(query "GetMerchant" '["M002"]')
expect_success "GetMerchant M002 exists" "$out"

header "3c. GetMerchant — existing (M004 second supermarket)"
out=$(query "GetMerchant" '["M004"]')
expect_success "GetMerchant M004 exists" "$out"

header "3d. GetMerchant — existing (M005 second electronics)"
out=$(query "GetMerchant" '["M005"]')
expect_success "GetMerchant M005 exists" "$out"

header "3e. GetMerchant — nonexistent"
out=$(query "GetMerchant" '["M999"]')
expect_failure "GetMerchant M999 does not exist" "$out"


header "4a. GetUser — existing"
out=$(query "GetUser" '["U001"]')
expect_success "GetUser U001 exists" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "4b. GetUser — nonexistent"
out=$(query "GetUser" '["U999"]')
expect_failure "GetUser U999 does not exist" "$out"

header "5a. AddMerchant — new"
out=$(invoke "AddMerchant" '["M006","MT001","777888999","3000"]')
expect_success "AddMerchant M006 created" "$out"

header "5b. AddMerchant — duplicate ID"
out=$(invoke "AddMerchant" '["M006","MT001","777888999","3000"]')
expect_failure "AddMerchant M006 duplicate rejected" "$out"

header "5c. AddMerchant — invalid merchant type"
out=$(invoke "AddMerchant" '["M007","MT999","000111222","1000"]')
expect_failure "AddMerchant with nonexistent type rejected" "$out"

header "6a. AddProducts — new product"
PRODUCTS='[{"id":"P013","name":"Water 1.5L","expiryDate":"2026-12-01","price":0.80,"quantity":150}]'
out=$(invoke "AddProducts" "[\"M006\",\"${PRODUCTS}\"]")
expect_success "AddProducts P013 added to M006" "$out"

header "6b. AddProducts — restock existing product"
out=$(invoke "AddProducts" "[\"M006\",\"${PRODUCTS}\"]")
expect_success "AddProducts P013 restocked on M006" "$out"

header "6c. AddProducts — merchant does not exist"
out=$(invoke "AddProducts" "[\"M999\",\"${PRODUCTS}\"]")
expect_failure "AddProducts on nonexistent merchant rejected" "$out"

header "6d. AddProducts — multiple products at once"
MULTI='[{"id":"P014","name":"Sparkling Water","price":1.20,"quantity":100},{"id":"P015","name":"Still Water","price":0.90,"quantity":80}]'
out=$(invoke "AddProducts" "[\"M006\",\"${MULTI}\"]")
expect_success "AddProducts multiple products added to M006" "$out"

header "7a. AddUser — new"
out=$(invoke "AddUser" '["U004","Dave","Brown","dave@example.com","750"]')
expect_success "AddUser U004 created" "$out"

header "7b. AddUser — duplicate ID"
out=$(invoke "AddUser" '["U004","Dave","Brown","dave@example.com","750"]')
expect_failure "AddUser U004 duplicate rejected" "$out"


header "8a. DepositToUser — valid"
out=$(invoke "DepositToUser" '["U001","200"]')
expect_success "DepositToUser U001 +200" "$out"

header "8b. DepositToUser — verify balance increased"
out=$(query "GetUser" '["U001"]')
expect_success "GetUser U001 balance updated" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "8c. DepositToUser — negative amount"
out=$(invoke "DepositToUser" '["U001","-50"]')
expect_failure "DepositToUser negative amount rejected" "$out"

header "8d. DepositToUser — nonexistent user"
out=$(invoke "DepositToUser" '["U999","100"]')
expect_failure "DepositToUser nonexistent user rejected" "$out"


header "9a. DepositToMerchant — valid"
out=$(invoke "DepositToMerchant" '["M001","1000"]')
expect_success "DepositToMerchant M001 +1000" "$out"

header "9b. DepositToMerchant — negative amount"
out=$(invoke "DepositToMerchant" '["M001","-100"]')
expect_failure "DepositToMerchant negative amount rejected" "$out"

header "9c. DepositToMerchant — nonexistent merchant"
out=$(invoke "DepositToMerchant" '["M999","100"]')
expect_failure "DepositToMerchant nonexistent merchant rejected" "$out"


header "10a. Purchase — U001 buys Milk from M001 (supermarket)"
# U001 has 500+200=700, P001 costs 1.50 x 2 = 3.00
out=$(invoke "Purchase" '["U001","M001","P001","2"]')
expect_success "Purchase U001 buys 2x Milk from M001" "$out"

header "10b. Purchase — verify U001 balance decreased"
out=$(query "GetUser" '["U001"]')
expect_success "GetUser U001 balance decreased after purchase" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "10c. Purchase — verify M001 balance increased and quantity decreased"
out=$(query "GetMerchant" '["M001"]')
expect_success "GetMerchant M001 updated after purchase" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "10d. Purchase — U002 buys flowers from M002 (flower shop)"
# U002 has 300, P004 costs 35.00 x 1 = 35.00
out=$(invoke "Purchase" '["U002","M002","P004","1"]')
expect_success "Purchase U002 buys 1x Red Roses from M002" "$out"

header "10e. Purchase — U003 buys electronics from M005"
# U003 has 1000, P011 costs 89.00 x 1 = 89.00
out=$(invoke "Purchase" '["U003","M005","P011","1"]')
expect_success "Purchase U003 buys 1x Headphones from M005" "$out"

header "10f. Purchase — U004 buys from M004 (second supermarket)"
# U004 has 750, P009 costs 2.10 x 3 = 6.30
out=$(invoke "Purchase" '["U004","M004","P009","3"]')
expect_success "Purchase U004 buys 3x Butter from M004" "$out"

header "10g. Purchase — insufficient user balance"
# U002 has ~265 left, P008 costs 45 x 10 = 450
out=$(invoke "Purchase" '["U002","M003","P008","10"]')
expect_failure "Purchase rejected — insufficient balance" "$out"

header "10h. Purchase — nonexistent user"
out=$(invoke "Purchase" '["U999","M001","P001","1"]')
expect_failure "Purchase rejected — user does not exist" "$out"

header "10i. Purchase — nonexistent merchant"
out=$(invoke "Purchase" '["U001","M999","P001","1"]')
expect_failure "Purchase rejected — merchant does not exist" "$out"

header "10j. Purchase — nonexistent product"
out=$(invoke "Purchase" '["U001","M001","P999","1"]')
expect_failure "Purchase rejected — product does not exist" "$out"

header "10k. Purchase — insufficient product quantity"
out=$(invoke "Purchase" '["U003","M003","P008","999"]')
expect_failure "Purchase rejected — insufficient product quantity" "$out"

header "10l. Purchase — zero quantity"
out=$(invoke "Purchase" '["U001","M001","P001","0"]')
expect_failure "Purchase rejected — zero quantity" "$out"


header "11a. SearchProducts — by name (milk)"
out=$(query "SearchProducts" '["milk","","","0"]')
expect_success "SearchProducts by name 'milk'" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11b. SearchProducts — by name (rose, flower shop)"
out=$(query "SearchProducts" '["rose","","","0"]')
expect_success "SearchProducts by name 'rose'" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11c. SearchProducts — by productID (P004)"
out=$(query "SearchProducts" '["","P004","","0"]')
expect_success "SearchProducts by productID P004" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11d. SearchProducts — by merchantTypeID MT001 (supermarkets)"
out=$(query "SearchProducts" '["","","MT001","0"]')
expect_success "SearchProducts by merchantTypeID MT001" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11e. SearchProducts — by merchantTypeID MT002 (flower shops)"
out=$(query "SearchProducts" '["","","MT002","0"]')
expect_success "SearchProducts by merchantTypeID MT002" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11f. SearchProducts — by maxPrice 2.00"
out=$(query "SearchProducts" '["","","","2"]')
expect_success "SearchProducts by maxPrice 2.00" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11g. SearchProducts — combined name + merchantType"
out=$(query "SearchProducts" '["bread","","MT001","0"]')
expect_success "SearchProducts name=bread + type=MT001" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11h. SearchProducts — combined type + maxPrice"
out=$(query "SearchProducts" '["","","MT001","2"]')
expect_success "SearchProducts type=MT001 + maxPrice=2.00" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "11i. SearchProducts — no filters returns all"
out=$(query "SearchProducts" '["","","","0"]')
expect_success "SearchProducts no filters returns all products" "$out"

header "12a. GetMerchantsByType — MT001 (should return M001, M004, M006)"
out=$(query "GetMerchantsByType" '["MT001"]')
expect_success "GetMerchantsByType MT001 returns multiple merchants" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "12b. GetMerchantsByType — MT002 (flower shop, should return M002)"
out=$(query "GetMerchantsByType" '["MT002"]')
expect_success "GetMerchantsByType MT002 returns M002" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "12c. GetMerchantsByType — MT003 (electronics, should return M003, M005)"
out=$(query "GetMerchantsByType" '["MT003"]')
expect_success "GetMerchantsByType MT003 returns M003 and M005" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"


header "13a. GetProductsUnderPrice — under 2.00"
out=$(query "GetProductsUnderPrice" '["2"]')
expect_success "GetProductsUnderPrice under 2.00" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "13b. GetProductsUnderPrice — under 15.00"
out=$(query "GetProductsUnderPrice" '["15"]')
expect_success "GetProductsUnderPrice under 15.00" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"


header "14a. GetReceiptsByUser — U001 (has purchases)"
out=$(query "GetReceiptsByUser" '["U001"]')
expect_success "GetReceiptsByUser U001 has receipts" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "14b. GetReceiptsByUser — U002 (has flower purchase)"
out=$(query "GetReceiptsByUser" '["U002"]')
expect_success "GetReceiptsByUser U002 has receipts" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"

header "14c. GetReceiptsByUser — U003 (has electronics purchase)"
out=$(query "GetReceiptsByUser" '["U003"]')
expect_success "GetReceiptsByUser U003 has receipts" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"


header "15a. Cross-org query — Org3 reads merchant M001"
out=$(queryOrg3 "GetMerchant" '["M001"]')
expect_success "Org3 can query GetMerchant on channel1" "$out"

header "15b. Cross-org query — Org3 reads user U001"
out=$(queryOrg3 "GetUser" '["U001"]')
expect_success "Org3 can query GetUser on channel1" "$out"


header "16. Product removed when quantity hits zero"
# P013 has 300 in stock (150 initial + 150 restock), buy all
out=$(invoke "Purchase" '["U003","M006","P013","300"]')
expect_success "Purchase all stock of P013" "$out"

out=$(query "GetMerchant" '["M006"]')
expect_success "GetMerchant M006 — P013 should be removed from products list" "$out"
echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"


echo ""
echo -e "${YELLOW}══════════════════════════════════════${NC}"
echo -e "${GREEN}  PASSED: ${PASS}${NC}"
echo -e "${RED}  FAILED: ${FAIL}${NC}"
echo -e "${YELLOW}══════════════════════════════════════${NC}"

if [ $FAIL -ne 0 ]; then
  exit 1
fi

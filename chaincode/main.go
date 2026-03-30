package main

import(
"log"
"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

func main() {
chaincode, err:= contractapi.NewChaincode(&SmartContract{})
if err != nil {
log.Panicf("Greska pri kreiranju chaincode: %v", err)
}

if err := chaincode.Start(); err != nil {
	log.Panicf("Greska pri pokretanju: %v", err)
}

}

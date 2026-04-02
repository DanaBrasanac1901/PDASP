package main

import (
	"bufio"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"github.com/hyperledger/fabric-gateway/pkg/client"
	"github.com/hyperledger/fabric-gateway/pkg/identity"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

type OrgConfig struct {
	MspID      string
	PeerAddr   string
	TLSCert    string // peer TLS CA cert
	CAUrl      string // fabric-ca server URL
	CATLSCert  string // CA TLS cert
	CAName     string // CA name
}

var orgConfigs = map[string]OrgConfig{
	"org1": {
		MspID:     "Org1MSP",
		PeerAddr:  "localhost:7051",
		TLSCert:   "${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt",
		CAUrl:     "https://localhost:7054",
		CATLSCert: "${PWD}/organizations/fabric-ca/org1/ca-cert.pem",
		CAName:    "ca-org1",
	},
	"org3": {
		MspID:     "Org3MSP",
		PeerAddr:  "localhost:13051",
		TLSCert:   "${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt",
		CAUrl:     "https://localhost:9054",
		CATLSCert: "${PWD}/organizations/fabric-ca/org3/ca-cert.pem",
		CAName:    "ca-org3",
	},
}

const chaincodeName = "trading"

const walletDir = "./wallet"


func main() {
	reader := bufio.NewReader(os.Stdin)

	if err := os.MkdirAll(walletDir, 0755); err != nil {
		fatalf("Failed to create wallet dir: %v", err)
	}

	fmt.Println("=== Hyperledger Fabric Trading SDK ===")
	fmt.Println()

	orgKey, cfg := selectOrg(reader)

	username := enrollOrLogin(reader, orgKey, cfg)

	channelName := selectChannel(reader, orgKey)

	gw, conn, err := connect(cfg, orgKey, username)
	if err != nil {
		fatalf("Failed to connect: %v", err)
	}
	defer conn.Close()
	defer gw.Close()

	network := gw.GetNetwork(channelName)
	contract := network.GetContract(chaincodeName)

	fmt.Printf("\nLogged in as '%s' (%s) on channel '%s'\n\n", username, strings.ToUpper(orgKey), channelName)

	for {
		printMenu()
		choice := prompt(reader, "Choice")

		switch choice {
		case "1":
			cmdGetMerchant(reader, contract)
		case "2":
			cmdGetUser(reader, contract)
		case "3":
			cmdGetAllMerchantTypes(contract)
		case "4":
			cmdSearchProducts(reader, contract)
		case "5":
			cmdGetMerchantsByType(reader, contract)
		case "6":
			cmdGetProductsUnderPrice(reader, contract)
		case "7":
			cmdGetReceiptsByUser(reader, contract)
		case "8":
			cmdAddMerchant(reader, contract)
		case "9":
			cmdAddProducts(reader, contract)
		case "10":
			cmdAddUser(reader, contract)
		case "11":
			cmdPurchase(reader, contract)
		case "12":
			cmdDepositToUser(reader, contract)
		case "13":
			cmdDepositToMerchant(reader, contract)
		case "14":
			cmdInitLedger(contract)
		case "0":
			fmt.Println("Goodbye.")
			return
		default:
			fmt.Println("Unknown option, try again.")
		}
		fmt.Println()
	}
}

func enrollOrLogin(r *bufio.Reader, orgKey string, cfg OrgConfig) string {
	for {
		fmt.Println("1) Enroll new user")
		fmt.Println("2) Login as existing user")
		choice := prompt(r, "Choice")
		switch choice {
		case "1":
			username := enrollUser(r, orgKey, cfg)
			if username != "" {
				return username
			}
			fmt.Println("Enrollment failed, please try again.")
		case "2":
			username := loginUser(r, orgKey, cfg)
			if username != "" {
				return username
			}
			fmt.Println("Login failed, please try again.")
		default:
			fmt.Println("Please enter 1 or 2.")
		}
	}
}

func enrollUser(r *bufio.Reader, orgKey string, cfg OrgConfig) string {
	username := prompt(r, "New username")
	password := prompt(r, "Password")

	userWallet := walletDir + "/" + orgKey + "/" + username
	if _, err := os.Stat(userWallet); err == nil {
		fmt.Printf("User '%s' already enrolled locally. Logging in.\n", username)
		return username
	}

	if err := os.MkdirAll(userWallet+"/msp/signcerts", 0755); err != nil {
		fmt.Printf("Error creating wallet dirs: %v\n", err)
		return ""
	}
	if err := os.MkdirAll(userWallet+"/msp/keystore", 0755); err != nil {
		fmt.Printf("Error creating wallet dirs: %v\n", err)
		return ""
	}

	fmt.Printf("Registering '%s' with CA %s...\n", username, cfg.CAName)
	registerCmd := exec.Command("fabric-ca-client", "register",
		"--caname", cfg.CAName,
		"--id.name", username,
		"--id.secret", password,
		"--id.type", "client",
		"--tls.certfiles", cfg.CATLSCert,
		"-u", cfg.CAUrl,
		"--mspdir", "../organizations/peerOrganizations/"+orgName(orgKey)+"/users/Admin@"+orgName(orgKey)+"/msp",
	)
	registerCmd.Stdout = os.Stdout
	registerCmd.Stderr = os.Stderr
	if err := registerCmd.Run(); err != nil {
		fmt.Printf("Registration failed: %v\n", err)
		fmt.Println("User may already be registered on the CA. Proceeding to enroll.")
	}

	fmt.Printf("Enrolling '%s'...\n", username)
	enrollCmd := exec.Command("fabric-ca-client", "enroll",
		"-u", fmt.Sprintf("%s://%s:%s@%s", "https", username, password, strings.TrimPrefix(cfg.CAUrl, "https://")),
		"--caname", cfg.CAName,
		"--tls.certfiles", cfg.CATLSCert,
		"--mspdir", userWallet+"/msp",
	)
	enrollCmd.Stdout = os.Stdout
	enrollCmd.Stderr = os.Stderr
	if err := enrollCmd.Run(); err != nil {
		fmt.Printf("Enrollment failed: %v\n", err)
		return ""
	}

	fmt.Printf("User '%s' enrolled successfully.\n", username)
	return username
}

// loginUser checks that the user's wallet entry exists locally and returns the username.
func loginUser(r *bufio.Reader, orgKey string, cfg OrgConfig) string {
	username := prompt(r, "Username")
	userWallet := walletDir + "/" + orgKey + "/" + username + "/msp"
	if _, err := os.Stat(userWallet); os.IsNotExist(err) {
		fmt.Printf("User '%s' not found in local wallet. Please enroll first.\n", username)
		return enrollOrLogin(r, orgKey, cfg)
	}
	fmt.Printf("User '%s' found in wallet.\n", username)
	return username
}

func connect(cfg OrgConfig, orgKey, username string) (*client.Gateway, *grpc.ClientConn, error) {
	tlsCert, err := os.ReadFile(cfg.TLSCert)
	if err != nil {
		return nil, nil, fmt.Errorf("reading TLS cert: %w", err)
	}
	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(tlsCert) {
		return nil, nil, fmt.Errorf("failed to add TLS cert to pool")
	}
	tlsCreds := credentials.NewClientTLSFromCert(certPool, "")

	conn, err := grpc.Dial(cfg.PeerAddr, grpc.WithTransportCredentials(tlsCreds))
	if err != nil {
		return nil, nil, fmt.Errorf("gRPC dial: %w", err)
	}

	userWallet := walletDir + "/" + orgKey + "/" + username + "/msp"

	id, err := newIdentity(cfg.MspID, userWallet+"/signcerts/cert.pem")
	if err != nil {
		conn.Close()
		return nil, nil, err
	}
	sign, err := newSigner(userWallet + "/keystore")
	if err != nil {
		conn.Close()
		return nil, nil, err
	}

	gw, err := client.Connect(id, client.WithSign(sign), client.WithClientConnection(conn))
	if err != nil {
		conn.Close()
		return nil, nil, fmt.Errorf("gateway connect: %w", err)
	}
	return gw, conn, nil
}

func newIdentity(mspID, certPath string) (*identity.X509Identity, error) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("reading cert %s: %w", certPath, err)
	}
	cert, err := identity.CertificateFromPEM(certPEM)
	if err != nil {
		return nil, fmt.Errorf("parsing cert: %w", err)
	}
	return identity.NewX509Identity(mspID, cert)
}

func newSigner(keyDir string) (identity.Sign, error) {
	entries, err := os.ReadDir(keyDir)
	if err != nil {
		return nil, fmt.Errorf("reading keystore dir %s: %w", keyDir, err)
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("no private key found in %s", keyDir)
	}
	keyPEM, err := os.ReadFile(keyDir + "/" + entries[0].Name())
	if err != nil {
		return nil, fmt.Errorf("reading private key: %w", err)
	}
	key, err := identity.PrivateKeyFromPEM(keyPEM)
	if err != nil {
		return nil, fmt.Errorf("parsing private key: %w", err)
	}
	return identity.NewPrivateKeySign(key)
}

func orgName(orgKey string) string {
	// e.g. "org1" -> "org1.example.com"
	return orgKey + ".example.com"
}

func selectOrg(r *bufio.Reader) (string, OrgConfig) {
	fmt.Println("Select organization:")
	fmt.Println("  1) Org1")
	fmt.Println("  2) Org3")
	for {
		choice := prompt(r, "Choice")
		switch choice {
		case "1":
			return "org1", orgConfigs["org1"]
		case "2":
			return "org3", orgConfigs["org3"]
		default:
			fmt.Println("Please enter 1 or 2.")
		}
	}
}

func selectChannel(r *bufio.Reader, orgKey string) string {
	fmt.Println("\nSelect channel:")
	fmt.Println("  1) channel1  (Org1 + Org2 + Org3)")
	if orgKey == "org1" {
		fmt.Println("  2) channel2  (Org1 + Org2)")
	}
	for {
		choice := prompt(r, "Choice")
		switch choice {
		case "1":
			return "channel1"
		case "2":
			if orgKey == "org1" {
				return "channel2"
			}
			fmt.Println("Org3 is not a member of channel2, please select channel1.")
		default:
			fmt.Println("Please enter 1 or 2.")
		}
	}
}

func printMenu() {
	fmt.Println("─── Query ────────────────────────────")
	fmt.Println("  1)  Get merchant")
	fmt.Println("  2)  Get user")
	fmt.Println("  3)  Get all merchant types")
	fmt.Println("  4)  Search products")
	fmt.Println("  5)  Get merchants by type")
	fmt.Println("  6)  Get products under price")
	fmt.Println("  7)  Get receipts by user")
	fmt.Println("─── Invoke ───────────────────────────")
	fmt.Println("  8)  Add merchant")
	fmt.Println("  9)  Add products to merchant")
	fmt.Println("  10) Add user")
	fmt.Println("  11) Purchase")
	fmt.Println("  12) Deposit to user")
	fmt.Println("  13) Deposit to merchant")
	fmt.Println("  14) Init ledger")
	fmt.Println("─────────────────────────────────────")
	fmt.Println("  0)  Exit")
}

func cmdGetMerchant(r *bufio.Reader, c *client.Contract) {
	id := prompt(r, "Merchant ID")
	result, err := c.EvaluateTransaction("GetMerchant", id)
	printResult(result, err)
}

func cmdGetUser(r *bufio.Reader, c *client.Contract) {
	id := prompt(r, "User ID")
	result, err := c.EvaluateTransaction("GetUser", id)
	printResult(result, err)
}

func cmdGetAllMerchantTypes(c *client.Contract) {
	result, err := c.EvaluateTransaction("GetAllMerchantTypes")
	printResult(result, err)
}

func cmdSearchProducts(r *bufio.Reader, c *client.Contract) {
	fmt.Println("Leave any field blank to skip that filter.")
	name := prompt(r, "Product name (substring)")
	productID := prompt(r, "Product ID (exact)")
	merchantTypeID := prompt(r, "Merchant type ID (exact)")
	maxPriceStr := prompt(r, "Max price (0 = no limit)")
	if maxPriceStr == "" {
		maxPriceStr = "0"
	}
	result, err := c.EvaluateTransaction("SearchProducts", name, productID, merchantTypeID, maxPriceStr)
	printResult(result, err)
}

func cmdGetMerchantsByType(r *bufio.Reader, c *client.Contract) {
	typeID := prompt(r, "Merchant type ID")
	result, err := c.EvaluateTransaction("GetMerchantsByType", typeID)
	printResult(result, err)
}

func cmdGetProductsUnderPrice(r *bufio.Reader, c *client.Contract) {
	maxPrice := prompt(r, "Max price")
	result, err := c.EvaluateTransaction("GetProductsUnderPrice", maxPrice)
	printResult(result, err)
}

func cmdGetReceiptsByUser(r *bufio.Reader, c *client.Contract) {
	userID := prompt(r, "User ID")
	result, err := c.EvaluateTransaction("GetReceiptsByUser", userID)
	printResult(result, err)
}

func cmdAddMerchant(r *bufio.Reader, c *client.Contract) {
	id := prompt(r, "Merchant ID")
	typeID := prompt(r, "Merchant type ID")
	pib := prompt(r, "PIB")
	balance := prompt(r, "Initial balance")
	_, err := c.SubmitTransaction("AddMerchant", id, typeID, pib, balance)
	printInvokeResult(err)
}

func cmdAddProducts(r *bufio.Reader, c *client.Contract) {
	merchantID := prompt(r, "Merchant ID")
	fmt.Println("Enter products as JSON array, e.g.:")
	fmt.Println(`  [{"id":"P010","name":"Water 1L","price":0.80,"quantity":50}]`)
	productsJSON := prompt(r, "Products JSON")
	_, err := c.SubmitTransaction("AddProducts", merchantID, productsJSON)
	printInvokeResult(err)
}

func cmdAddUser(r *bufio.Reader, c *client.Contract) {
	id := prompt(r, "User ID")
	firstName := prompt(r, "First name")
	lastName := prompt(r, "Last name")
	email := prompt(r, "Email")
	balance := prompt(r, "Initial balance")
	_, err := c.SubmitTransaction("AddUser", id, firstName, lastName, email, balance)
	printInvokeResult(err)
}

func cmdPurchase(r *bufio.Reader, c *client.Contract) {
	userID := prompt(r, "User ID")
	merchantID := prompt(r, "Merchant ID")
	productID := prompt(r, "Product ID")
	quantity := prompt(r, "Quantity")
	if _, err := strconv.Atoi(quantity); err != nil {
		fmt.Println("Error: quantity must be an integer")
		return
	}
	_, err := c.SubmitTransaction("Purchase", userID, merchantID, productID, quantity)
	printInvokeResult(err)
}

func cmdDepositToUser(r *bufio.Reader, c *client.Contract) {
	userID := prompt(r, "User ID")
	amount := prompt(r, "Amount")
	_, err := c.SubmitTransaction("DepositToUser", userID, amount)
	printInvokeResult(err)
}

func cmdDepositToMerchant(r *bufio.Reader, c *client.Contract) {
	merchantID := prompt(r, "Merchant ID")
	amount := prompt(r, "Amount")
	_, err := c.SubmitTransaction("DepositToMerchant", merchantID, amount)
	printInvokeResult(err)
}

func cmdInitLedger(c *client.Contract) {
	fmt.Print("This will reset the ledger to initial state. Confirm? (yes/no): ")
	r := bufio.NewReader(os.Stdin)
	confirm, _ := r.ReadString('\n')
	if strings.TrimSpace(confirm) != "yes" {
		fmt.Println("Cancelled.")
		return
	}
	_, err := c.SubmitTransaction("InitLedger")
	printInvokeResult(err)
}

func printResult(result []byte, err error) {
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}
	var pretty interface{}
	if jsonErr := json.Unmarshal(result, &pretty); jsonErr == nil {
		out, _ := json.MarshalIndent(pretty, "", "  ")
		fmt.Println(string(out))
	} else {
		fmt.Println(string(result))
	}
}

func printInvokeResult(err error) {
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}
	fmt.Println("Success.")
}

func prompt(r *bufio.Reader, label string) string {
	fmt.Printf("%s: ", label)
	text, _ := r.ReadString('\n')
	return strings.TrimSpace(text)
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", args...)
	os.Exit(1)
}
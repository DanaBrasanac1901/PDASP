package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)


type MerchantType struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type Product struct {
	ID         string  `json:"id"`
	Name       string  `json:"name"`
	ExpiryDate string  `json:"expiryDate,omitempty"`
	Price      float64 `json:"price"`
	Quantity   int     `json:"quantity"`
}

type Receipt struct {
	ID         string  `json:"id"`
	MerchantID string  `json:"merchantId"`
	UserID     string  `json:"userId"`
	ProductID  string  `json:"productId"`
	Amount     float64 `json:"amount"`
	Date       string  `json:"date"`
}

type Merchant struct {
	DocType        string    `json:"docType"`
	ID             string    `json:"id"`
	MerchantTypeID string    `json:"merchantTypeId"`
	PIB            string    `json:"pib"`
	Products       []Product `json:"products"`
	Receipts       []Receipt `json:"receipts"`
	Balance        float64   `json:"balance"`
}

type User struct {
	DocType   string    `json:"docType"`
	ID        string    `json:"id"`
	FirstName string    `json:"firstName"`
	LastName  string    `json:"lastName"`
	Email     string    `json:"email"`
	Receipts  []Receipt `json:"receipts"`
	Balance   float64   `json:"balance"`
}


type TradingContract struct {
	contractapi.Contract
}


func (t *TradingContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	merchantTypes := []MerchantType{
		{ID: "MT001", Name: "Supermarket", Description: "General grocery and household items"},
		{ID: "MT002", Name: "Flower shop", Description: "Flower related services"},
		{ID: "MT003", Name: "Electronics", Description: "Consumer electronics and gadgets"},
	}
	for _, mt := range merchantTypes {
		if err := putState(ctx, "MTYPE_"+mt.ID, mt); err != nil {
			return err
		}
	}

	merchants := []Merchant{
        {
            DocType:        "merchant",
            ID:             "M001",
            MerchantTypeID: "MT001",
            PIB:            "123456789",
            Balance:        5000.00,
            Products: []Product{
                {ID: "P001", Name: "Milk 1L", ExpiryDate: "2026-12-31", Price: 1.50, Quantity: 100},
                {ID: "P002", Name: "Bread 500g", ExpiryDate: "2026-06-30", Price: 1.20, Quantity: 80},
                {ID: "P003", Name: "Orange Juice 1L", ExpiryDate: "2026-09-15", Price: 2.30, Quantity: 60},
            },
            Receipts: []Receipt{},
        },
        {
            DocType:        "merchant",
            ID:             "M002",
            MerchantTypeID: "MT002",
            PIB:            "987654321",
            Balance:        10000.00,
            Products: []Product{
                {ID: "P004", Name: "Red Roses Bouquet", ExpiryDate: "2026-02-14", Price: 35.00, Quantity: 40},
                {ID: "P005", Name: "Tulip Arrangement", ExpiryDate: "2026-03-01", Price: 15.00, Quantity: 70},
                {ID: "P006", Name: "Sunflower Bundle", ExpiryDate: "2026-04-01", Price: 22.00, Quantity: 50},
            },
            Receipts: []Receipt{},
        },
        {
            DocType:        "merchant",
            ID:             "M003",
            MerchantTypeID: "MT003",
            PIB:            "555444333",
            Balance:        20000.00,
            Products: []Product{
                {ID: "P007", Name: "USB-C Cable 2m", Price: 12.00, Quantity: 200},
                {ID: "P008", Name: "Wireless Mouse", Price: 45.00, Quantity: 30},
            },
            Receipts: []Receipt{},
        },
        {
            DocType:        "merchant",
            ID:             "M004",
            MerchantTypeID: "MT001",
            PIB:            "111222333",
            Balance:        8000.00,
            Products: []Product{
                {ID: "P009", Name: "Butter 250g", ExpiryDate: "2026-11-30", Price: 2.10, Quantity: 90},
                {ID: "P010", Name: "Cheddar Cheese 500g", ExpiryDate: "2026-10-15", Price: 4.50, Quantity: 60},
            },
            Receipts: []Receipt{},
        },
        {
            DocType:        "merchant",
            ID:             "M005",
            MerchantTypeID: "MT003",
            PIB:            "444555666",
            Balance:        15000.00,
            Products: []Product{
                {ID: "P011", Name: "Bluetooth Headphones", Price: 89.00, Quantity: 25},
                {ID: "P012", Name: "USB Hub 4-Port", Price: 19.00, Quantity: 100},
            },
            Receipts: []Receipt{},
        },
    }
	
    for _, m := range merchants {
        if err := putState(ctx, "MERCHANT_"+m.ID, m); err != nil {
            return err
        }
    }

	users := []User{
		{DocType: "user", ID: "U001", FirstName: "Alice", LastName: "Smith", Email: "alice@example.com", Balance: 500.00, Receipts: []Receipt{}},
		{DocType: "user", ID: "U002", FirstName: "Bob", LastName: "Jones", Email: "bob@example.com", Balance: 300.00, Receipts: []Receipt{}},
		{DocType: "user", ID: "U003", FirstName: "Carol", LastName: "White", Email: "carol@example.com", Balance: 1000.00, Receipts: []Receipt{}},
	}
	for _, u := range users {
		if err := putState(ctx, "USER_"+u.ID, u); err != nil {
			return err
		}
	}

	return nil
}


func (t *TradingContract) AddMerchant(ctx contractapi.TransactionContextInterface, id, merchantTypeID, pib string, initialBalance float64) error {
	if exists, _ := keyExists(ctx, "MERCHANT_"+id); exists {
		return fmt.Errorf("merchant with ID %s already exists", id)
	}
	if exists, _ := keyExists(ctx, "MTYPE_"+merchantTypeID); !exists {
		return fmt.Errorf("merchant type %s does not exist", merchantTypeID)
	}
	m := Merchant{
		DocType:        "merchant",
		ID:             id,
		MerchantTypeID: merchantTypeID,
		PIB:            pib,
		Balance:        initialBalance,
		Products:       []Product{},
		Receipts:       []Receipt{},
	}
	return putState(ctx, "MERCHANT_"+id, m)
}


func (t *TradingContract) AddProducts(ctx contractapi.TransactionContextInterface, merchantID, productsJSON string) error {
	m, err := getMerchant(ctx, merchantID)
	if err != nil {
		return err
	}
	var newProducts []Product
	if err := json.Unmarshal([]byte(productsJSON), &newProducts); err != nil {
		return fmt.Errorf("invalid products JSON: %v", err)
	}
	if len(newProducts) == 0 {
		return fmt.Errorf("products list cannot be empty")
	}
	for _, np := range newProducts {
		found := false
		for i, p := range m.Products {
			if p.ID == np.ID {
				m.Products[i].Quantity += np.Quantity
				found = true
				break
			}
		}
		if !found {
			m.Products = append(m.Products, np)
		}
	}
	return putState(ctx, "MERCHANT_"+merchantID, *m)
}


func (t *TradingContract) AddUser(ctx contractapi.TransactionContextInterface, id, firstName, lastName, email string, initialBalance float64) error {
	if exists, _ := keyExists(ctx, "USER_"+id); exists {
		return fmt.Errorf("user with ID %s already exists", id)
	}
	u := User{
		DocType:   "user",
		ID:        id,
		FirstName: firstName,
		LastName:  lastName,
		Email:     email,
		Balance:   initialBalance,
		Receipts:  []Receipt{},
	}
	return putState(ctx, "USER_"+id, u)
}

func (t *TradingContract) Purchase(ctx contractapi.TransactionContextInterface, userID, merchantID, productID string, quantity int) error {
	if quantity <= 0 {
		return fmt.Errorf("quantity must be greater than zero")
	}
	u, err := getUser(ctx, userID)
	if err != nil {
		return err
	}
	m, err := getMerchant(ctx, merchantID)
	if err != nil {
		return err
	}

	prodIdx := -1
	for i, p := range m.Products {
		if p.ID == productID {
			prodIdx = i
			break
		}
	}
	if prodIdx == -1 {
		return fmt.Errorf("product %s not found at merchant %s", productID, merchantID)
	}

	prod := m.Products[prodIdx]
	if prod.Quantity < quantity {
		return fmt.Errorf("insufficient product quantity: available %d, requested %d", prod.Quantity, quantity)
	}

	totalCost := prod.Price * float64(quantity)
	if u.Balance < totalCost {
		return fmt.Errorf("insufficient user balance: have %.2f, need %.2f", u.Balance, totalCost)
	}

	txID := ctx.GetStub().GetTxID()
	receiptID := fmt.Sprintf("R_%s_%s_%s", userID, merchantID, txID[:8])
	receipt := Receipt{
		ID:         receiptID,
		MerchantID: merchantID,
		UserID:     userID,
		ProductID:  productID,
		Amount:     totalCost,
		Date:       time.Now().UTC().Format(time.RFC3339),
	}

	u.Balance -= totalCost
	m.Balance += totalCost

	m.Products[prodIdx].Quantity -= quantity
	if m.Products[prodIdx].Quantity == 0 {
		m.Products = append(m.Products[:prodIdx], m.Products[prodIdx+1:]...)
	}

	u.Receipts = append(u.Receipts, receipt)
	m.Receipts = append(m.Receipts, receipt)

	// Store receipt as a separate document for CouchDB rich queries
	if err := putState(ctx, "RECEIPT_"+receiptID, receipt); err != nil {
		return err
	}
	if err := putState(ctx, "USER_"+userID, *u); err != nil {
		return err
	}
	return putState(ctx, "MERCHANT_"+merchantID, *m)
}


func (t *TradingContract) DepositToUser(ctx contractapi.TransactionContextInterface, userID string, amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("deposit amount must be positive")
	}
	u, err := getUser(ctx, userID)
	if err != nil {
		return err
	}
	u.Balance += amount
	return putState(ctx, "USER_"+userID, *u)
}

func (t *TradingContract) DepositToMerchant(ctx contractapi.TransactionContextInterface, merchantID string, amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("deposit amount must be positive")
	}
	m, err := getMerchant(ctx, merchantID)
	if err != nil {
		return err
	}
	m.Balance += amount
	return putState(ctx, "MERCHANT_"+merchantID, *m)
}

func (t *TradingContract) SearchProducts(ctx contractapi.TransactionContextInterface,
	name, productID, merchantTypeID string, maxPrice float64) ([]map[string]interface{}, error) {

	selector := `"docType":"merchant"`
	if merchantTypeID != "" {
		selector += fmt.Sprintf(`,"merchantTypeId":"%s"`, merchantTypeID)
	}
	query := fmt.Sprintf(`{"selector":{%s}}`, selector)

	results, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, fmt.Errorf("CouchDB query failed: %v", err)
	}
	defer results.Close()

	var output []map[string]interface{}
	for results.HasNext() {
		res, err := results.Next()
		if err != nil {
			return nil, err
		}
		var merchant Merchant
		if err := json.Unmarshal(res.Value, &merchant); err != nil {
			continue
		}
		for _, p := range merchant.Products {
			if productID != "" && p.ID != productID {
				continue
			}
			if name != "" && !strings.Contains(strings.ToLower(p.Name), strings.ToLower(name)) {
				continue
			}
			if maxPrice > 0 && p.Price > maxPrice {
				continue
			}
			output = append(output, map[string]interface{}{
				"merchantId":     merchant.ID,
				"merchantTypeId": merchant.MerchantTypeID,
				"product":        p,
			})
		}
	}
	return output, nil
}

func (t *TradingContract) GetMerchantsByType(ctx contractapi.TransactionContextInterface, merchantTypeID string) ([]Merchant, error) {
	query := fmt.Sprintf(`{"selector":{"docType":"merchant","merchantTypeId":"%s"}}`, merchantTypeID)
	return queryMerchants(ctx, query)
}

func (t *TradingContract) GetProductsUnderPrice(ctx contractapi.TransactionContextInterface, maxPrice float64) ([]map[string]interface{}, error) {
	query := fmt.Sprintf(`{"selector":{"docType":"merchant","products":{"$elemMatch":{"price":{"$lte":%f}}}}}`, maxPrice)
	results, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer results.Close()

	var output []map[string]interface{}
	for results.HasNext() {
		res, _ := results.Next()
		var m Merchant
		if err := json.Unmarshal(res.Value, &m); err != nil {
			continue
		}
		for _, p := range m.Products {
			if p.Price <= maxPrice {
				output = append(output, map[string]interface{}{
					"merchantId": m.ID,
					"product":    p,
				})
			}
		}
	}
	return output, nil
}

func (t *TradingContract) GetReceiptsByUser(ctx contractapi.TransactionContextInterface, userID string) ([]Receipt, error) {
	query := fmt.Sprintf(`{"selector":{"userId":"%s"}}`, userID)
	results, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer results.Close()
	var receipts []Receipt
	for results.HasNext() {
		res, _ := results.Next()
		var r Receipt
		if err := json.Unmarshal(res.Value, &r); err != nil {
			continue
		}
		receipts = append(receipts, r)
	}
	return receipts, nil
}

func putState(ctx contractapi.TransactionContextInterface, key string, value interface{}) error {
	bytes, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, bytes)
}

func keyExists(ctx contractapi.TransactionContextInterface, key string) (bool, error) {
	b, err := ctx.GetStub().GetState(key)
	return b != nil, err
}

func getMerchant(ctx contractapi.TransactionContextInterface, id string) (*Merchant, error) {
	b, err := ctx.GetStub().GetState("MERCHANT_" + id)
	if err != nil {
		return nil, err
	}
	if b == nil {
		return nil, fmt.Errorf("merchant with ID %s does not exist", id)
	}
	var m Merchant
	return &m, json.Unmarshal(b, &m)
}

func getUser(ctx contractapi.TransactionContextInterface, id string) (*User, error) {
	b, err := ctx.GetStub().GetState("USER_" + id)
	if err != nil {
		return nil, err
	}
	if b == nil {
		return nil, fmt.Errorf("user with ID %s does not exist", id)
	}
	var u User
	return &u, json.Unmarshal(b, &u)
}

func queryMerchants(ctx contractapi.TransactionContextInterface, query string) ([]Merchant, error) {
	results, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer results.Close()
	var merchants []Merchant
	for results.HasNext() {
		res, err := results.Next()
		if err != nil {
			return nil, err
		}
		var m Merchant
		if err := json.Unmarshal(res.Value, &m); err != nil {
			return nil, err
		}
		merchants = append(merchants, m)
	}
	return merchants, nil
}

func main() {
	cc, err := contractapi.NewChaincode(&TradingContract{})
	if err != nil {
		panic(fmt.Sprintf("Error creating chaincode: %v", err))
	}
	if err := cc.Start(); err != nil {
		panic(fmt.Sprintf("Error starting chaincode: %v", err))
	}
}
}

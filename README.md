```markdown
# Order Management System - Comprehensive Documentation

## 📋 Table of Contents
1. [System Overview](#system-overview)
2. [Architecture & Data Flow](#architecture--data-flow)
3. [Component Structure](#component-structure)
4. [Critical Business Logic](#critical-business-logic)
5. [Integration Architecture](#integration-architecture)
6. [Deployment Guide](#deployment-guide)
7. [Technical Deep Dive](#technical-deep-dive)

---

## 🎯 System Overview

This is a **full-featured e-commerce Order Management System** built on Salesforce DX that enables:
- Multi-org product synchronization
- Real-time product browsing with search and filtering
- Shopping cart management with draft orders
- Complex checkout with account, contract, and pricebook resolution
- Automated PDF invoice generation
- Bi-directional REST API integrations

**Key Technologies:**
- Salesforce DX
- Lightning Web Components (LWC)
- Apex REST Services
- Visualforce (PDF Generation)
- Named Credentials (Secure Callouts)
- Batch/Scheduled Jobs

---

## 🏗️ Architecture & Data Flow

### **1. Product Synchronization Flow (External → Salesforce)**

```
┌─────────────────────────────────────────────────────────────────┐
│ External Server (ServerOrg)                                     │
│ Exposes: /services/apexrest/Products                            │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       │ HTTP GET (Scheduled Batch)
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│ ProductSyncBatch.cls                                            │
│ - Fetches products with nested pricebook entries                │
│ - Upserts Product2 records (matched by ExternalId)              │
│ - Auto-creates Pricebook2 if missing                            │
│ - Upserts PricebookEntry records                                │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│ Local Salesforce Org                                            │
│ - Product2 (with ExternalId = Server Product2.Id)               │
│ - Pricebook2                                                    │
│ - PricebookEntry                                                │
└─────────────────────────────────────────────────────────────────┘
```

**Scheduler Setup:**
```
// ProductSyncScheduler.cls - Runs daily at midnight
System.schedule('Product Sync Job', '0 0 0 * * ?', new ProductSyncScheduler());
```

**Key Logic:**
- **ExternalId Pattern**: `Product2.ExternalId` stores the server's Product2.Id
- **Upsert Strategy**: Prevents duplicate records across syncs
- **Pricebook Auto-Creation**: Missing pricebooks are created automatically by name
- **Partial Failure Handling**: Uses `Database.insert(records, false)` to allow partial success

---

### **2. Product Browsing Flow**

```
┌──────────────────┐
│   User Browser   │
│  (LWC: shopping  │
│     Portal)      │
└────────┬─────────┘
         │
         │ Wire: @wire(fetchProducts)
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ProductController.fetchProducts()                               │
│ @AuraEnabled(cacheable=true)                                    │
│                                                                 │
│ Inputs:                                                         │
│ - pageNumber, pageSize (pagination)                             │
│ - searchQuery (Name/ProductCode/Description LIKE)               │
│ - selectedFamilies[] (Family filter)                            │
│ - sortField, sortDir (future use)                               │
│                                                                 │
│ Query Logic:                                                    │
│ SELECT Id, Name, ProductCode, Description, Family,              │
│        ProductImage__c, StockKeepingUnit                        │
│ FROM Product2                                                   │
│ WHERE IsActive = true                                           │
│   AND (Name LIKE '%search%' OR ...)                             │
│   AND Family IN :selectedFamilies                               │
│ ORDER BY Name ASC                                               │
│ LIMIT :pageSize OFFSET :offsetRows                              │
│                                                                 │
│ PBE Enrichment:                                                 │
│ - Queries PricebookEntry by StockKeepingUnit                    │
│ - Attaches pricing info to ProductDTO.pbes[]                    │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ Returns: ProductPage                                            │
│ {                                                               │
│   records: ProductDTO[] {                                       │
│     id, name, productCode, description, family,                 │
│     productImage, sku, uom,                                     │
│     pbes: [{                                                    │
│       pricebookEntryId, pricebookName, unitPrice                │
│     }]                                                          │
│   },                                                            │
│   totalSize: 145,                                               │
│   pageNumber: 1,                                                │
│   pageSize: 12                                                  │
│ }                                                               │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ LWC: productCard (renders grid of products)                     │
│ - Displays product image, name, price                           │
│ - "Add to Cart" button                                          │
│ - Click → productDetailModal (detailed view)                    │
└─────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- **Cacheable**: `@AuraEnabled(cacheable=true)` improves performance
- **SKU-Based PBE Lookup**: Matches products to pricing via `StockKeepingUnit`
- **Family Filtering**: Product categorization support
- **Search**: Supports Name, ProductCode, and Description fields

---

### **3. Add to Cart Flow (Draft Order Management)**

```
┌──────────────────┐
│   User clicks    │
│ "Add to Cart"    │
└────────┬─────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ProductController.addToOrder()                                  │
│ @AuraEnabled                                                    │
│                                                                 │
│ Inputs:                                                         │
│ - accountId (customer)                                          │
│ - productId (Product2.Id)                                       │
│ - price (unit price)                                            │
│ - quantity (number of items)                                    │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Find or Create Draft Order                             │
│                                                                 │
│ Query:                                                          │
│ SELECT Id, Pricebook2Id                                         │
│ FROM Order                                                      │
│ WHERE AccountId = :accountId                                    │
│   AND Status = 'Draft'                                          │
│ LIMIT 1                                                         │
│                                                                 │
│ IF NOT FOUND:                                                   │
│   - Create new Order(Status='Draft')                            │
│   - Use Standard Pricebook                                      │
│   - Set EffectiveDate = TODAY                                   │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Get PricebookEntry                                      │
│                                                                 │
│ Query:                                                          │
│ SELECT Id                                                       │
│ FROM PricebookEntry                                             │
│ WHERE Pricebook2Id = :order.Pricebook2Id                        │
│   AND Product2Id = :productId                                   │
│   AND IsActive = true                                           │
│ LIMIT 1                                                         │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Check for Existing OrderItem                            │
│                                                                 │
│ Query:                                                          │
│ SELECT Id, Quantity                                             │
│ FROM OrderItem                                                  │
│ WHERE OrderId = :order.Id                                       │
│   AND Product2Id = :productId                                   │
│ LIMIT 1                                                         │
│                                                                 │
│ IF EXISTS:                                                      │
│   ✓ UPDATE: Increment Quantity                                 │
│   (existingItem.Quantity += newQuantity)                        │
│                                                                 │
│ ELSE:                                                           │
│   ✓ INSERT: New OrderItem                                      │
│   {                                                             │
│     OrderId, PricebookEntryId, Product2Id,                      │
│     UnitPrice, Quantity                                         │
│   }                                                             │
└─────────────────────────────────────────────────────────────────┘
```

**Smart Cart Behavior:**
- **One Draft Order Per Account**: Prevents cart fragmentation
- **Incremental Updates**: Adds quantities for duplicate products
- **Price Integrity**: Always uses PricebookEntry.UnitPrice

---

### **4. Checkout Flow (The Complex Engine)**

```
┌──────────────────┐
│  User navigates  │
│ to checkoutPage  │
│      (LWC)       │
└────────┬─────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ checkoutPage Component Displays:                                │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 1. Account Selection (Lookup or Create)                     │ │
│ │ 2. Billing Address Form                                     │ │
│ │ 3. Shipping Address Form                                    │ │
│ │ 4. Contract Selection (Dropdown of Activated Contracts)     │ │
│ │ 5. Cart Items (OrderItems from Draft Order)                 │ │
│ │ 6. "Place Order" Button                                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
└────────┬────────────────────────────────────────────────────────┘
         │
         │ User clicks "Place Order"
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ CheckOutController.createOrderFromCart()                        │
│ @AuraEnabled                                                    │
│                                                                 │
│ Input: JSON String                                              │
│ {                                                               │
│   orderItemsIds: [                                              │
│     "802xxx...xxx",           // Existing OrderItem ID         │
│     "01txxx...xxx",            // Product2 ID                   │
│     "temp_01txxx...xxx_12345"  // Wrapped Product2 ID          │
│   ],                                                            │
│   names: ["Product A", "Product B"],                            │
│   qtys: ,                                                 │
│   prices: [100.00, 250.50],                                     │
│   accountId: "001xxx...xxx",                                    │
│   contractId: "800xxx...xxx",                                   │
│   billingAddress: { street, city, state, postalCode, country }, │
│   shippingAddress: { street, city, state, postalCode, country }│
│ }                                                               │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 1: ID RESOLUTION (Multi-Format Support)             ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Loop through orderItemsIds[]:                                   │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ IF id.startsWith('802'):                                    ││
│ │   → Add to orderItemIds[] (Existing OrderItem)              ││
│ │   → effectiveProduct2IdsByIndex[i] = null                   ││
│ │                                                             ││
│ │ ELSE IF id.startsWith('temp_'):                             ││
│ │   → Extract 18-char Product2Id from temp_{id}_{timestamp}  ││
│ │   → Add to product2Ids[]                                    ││
│ │   → effectiveProduct2IdsByIndex[i] = extractedId            ││
│ │                                                             ││
│ │ ELSE:                                                       ││
│ │   → Treat as Product2 ID directly                           ││
│ │   → Add to product2Ids[]                                    ││
│ │   → effectiveProduct2IdsByIndex[i] = id                     ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ Result:                                                         │
│ - orderItemIds[] : [802xxx, 802yyy]                             │
│ - product2Ids[]  : [01txxx, 01tyyy]                             │
│ - effectiveProduct2IdsByIndex[] : [null, 01txxx, null, 01tyyy] │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 2: ACCOUNT RESOLUTION (3-Tier Fallback)            ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Attempt 1: Use params.accountId (if provided)                   │
│          ↓ IF NULL                                              │
│ Attempt 2: Extract from OrderItem.Order.AccountId               │
│            Query: SELECT Order.AccountId FROM OrderItem         │
│                   WHERE Id IN :orderItemIds LIMIT 1             │
│          ↓ IF STILL NULL                                        │
│ Attempt 3: Extract from Contract.AccountId                      │
│            Query: SELECT AccountId FROM Contract                │
│                   WHERE Id = :params.contractId LIMIT 1         │
│          ↓                                                      │
│ Validate: Account must exist, throw error if null               │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 3: CONTRACT RESOLUTION (3-Tier Logic)              ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Attempt A: Use provided contractId                              │
│            VALIDATE: Contract.AccountId == resolved AccountId   │
│          ↓ IF NULL                                              │
│ Attempt B: Find latest Contract for Account                     │
│            Query: SELECT Id, AccountId, Pricebook2Id, Status    │
│                   FROM Contract                                 │
│                   WHERE AccountId = :accountId                  │
│                   ORDER BY CreatedDate DESC LIMIT 1             │
│          ↓ IF STILL NULL                                        │
│ Attempt C: CREATE new Contract                                  │
│            {                                                    │
│              AccountId: accountId,                              │
│              Status: 'Draft',                                   │
│              StartDate: TODAY,                                  │
│              Pricebook2Id: (from OrderItems or Standard)        │
│            }                                                    │
│            INSERT Contract                                      │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 4: PRICEBOOK RESOLUTION                             ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Priority 1: Contract.Pricebook2Id                               │
│          ↓ IF NULL                                              │
│ Priority 2: From existing OrderItems                            │
│             Query PricebookEntry.Pricebook2Id                   │
│          ↓ IF STILL NULL                                        │
│ Priority 3: Standard Pricebook                                  │
│             Query: SELECT Id FROM Pricebook2                    │
│                    WHERE IsStandard = true LIMIT 1              │
│                                                                 │
│ Set: finalPricebook2Id                                          │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 5: DRAFT ORDER MANAGEMENT                           ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Query for existing Draft Order:                                 │
│ SELECT Id, Status                                               │
│ FROM Order                                                      │
│ WHERE AccountId = :accountId                                    │
│   AND Status = 'Draft'                                          │
│ LIMIT 1                                                         │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ IF EXISTS:                                                  ││
│ │   1. DELETE all existing OrderItems (fresh snapshot)        ││
│ │   2. UPDATE Order:                                          ││
│ │      - Pricebook2Id = finalPricebook2Id                     ││
│ │      - ContractId = resolved Contract.Id                    ││
│ │      - BillingStreet/City/State/PostalCode/Country          ││
│ │      - ShippingStreet/City/State/PostalCode/Country         ││
│ │      - EffectiveDate = TODAY                                ││
│ │                                                             ││
│ │ ELSE:                                                       ││
│ │   1. CREATE new Order:                                      ││
│ │      {                                                      ││
│ │        AccountId, Pricebook2Id, ContractId,                 ││
│ │        Status='Draft', EffectiveDate=TODAY,                 ││
│ │        Billing/Shipping Address fields                      ││
│ │      }                                                      ││
│ │   2. INSERT Order                                           ││
│ └─────────────────────────────────────────────────────────────┘│
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 6: PRICEBOOK ENTRY LOOKUP (For Product2 IDs)       ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ IF product2Ids[] is NOT EMPTY:                                  │
│                                                                 │
│   Query PricebookEntries:                                       │
│   SELECT Id, Product2Id                                         │
│   FROM PricebookEntry                                           │
│   WHERE Product2Id IN :product2Ids                              │
│     AND Pricebook2Id = :finalPricebook2Id                       │
│     AND IsActive = true                                         │
│                                                                 │
│   Build Map: pbeByProduct<Product2Id, PricebookEntry>           │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 7: ORDER ITEM CREATION (Dual Path)                 ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ List<OrderItem> newItems = []                                   │
│ Decimal total = 0                                               │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ PATH A: Clone Existing OrderItems (from 802* IDs)          ││
│ │                                                             ││
│ │ FOR EACH orderItemId IN orderItemIds[]:                     ││
│ │   Query existing OrderItem:                                 ││
│ │   SELECT Id, Quantity, UnitPrice, PricebookEntryId          ││
│ │                                                             ││
│ │   Create new OrderItem:                                     ││
│ │   {                                                         ││
│ │     OrderId: newOrder.Id,                                   ││
│ │     PricebookEntryId: existing.PricebookEntryId,            ││
│ │     Quantity: existing.Quantity,                            ││
│ │     UnitPrice: existing.UnitPrice                           ││
│ │   }                                                         ││
│ │   Add to newItems[]                                         ││
│ │   total += UnitPrice * Quantity                             ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ PATH B: Create from Product2 IDs (New Products)            ││
│ │                                                             ││
│ │ FOR i = 0 TO rawIdsStr.size():                              ││
│ │   SKIP if id is 802* (already handled in Path A)            ││
│ │                                                             ││
│ │   Get productId = effectiveProduct2IdsByIndex[i]            ││
│ │   Get pbe = pbeByProduct.get(productId)                     ││
│ │   SKIP if pbe is NULL (no pricing available)                ││
│ │                                                             ││
│ │   Get qty = params.qtys[i] (default: 1)                     ││
│ │   Get price = params.prices[i] (fallback: pbe.UnitPrice)    ││
│ │                                                             ││
│ │   Create new OrderItem:                                     ││
│ │   {                                                         ││
│ │     OrderId: newOrder.Id,                                   ││
│ │     PricebookEntryId: pbe.Id,                               ││
│ │     Quantity: qty,                                          ││
│ │     UnitPrice: price                                        ││
│ │   }                                                         ││
│ │   Add to newItems[]                                         ││
│ │   total += price * qty                                      ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ INSERT newItems[] (all OrderItems at once)                      │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 8: ORDER ACTIVATION                                 ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Ensure Contract is Activated:                                   │
│ IF contract.Status != 'Activated':                              │
│   contract.Status = 'Activated'                                 │
│   UPDATE contract                                               │
│                                                                 │
│ Activate Order:                                                 │
│ IF contract.Status == 'Activated':                              │
│   order.Status = 'Activated'                                    │
│   UPDATE order                                                  │
│                                                                 │
│ Note: Activated Orders become immutable                         │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════════════╗  │
│ ║  STEP 9: RETURN RESULT                                    ║  │
│ ╚═══════════════════════════════════════════════════════════╝  │
│                                                                 │
│ Return CreateOrderResult:                                       │
│ {                                                               │
│   orderId: "801xxx...xxx",                                      │
│   lineItemCount: 5,                                             │
│   totalAmount: 2500.00,                                         │
│   contentVersionId: null,    // Set after invoice generation   │
│   contentDocumentId: null    // Set after invoice generation   │
│ }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

**Critical Design Decisions:**

1. **Multi-Format ID Support**: Handles OrderItem IDs, Product2 IDs, and temp-wrapped IDs in a single flow
2. **Index-Based Mapping**: Uses `effectiveProduct2IdsByIndex[]` to map quantities/prices correctly
3. **3-Tier Fallback Logic**: Ensures Account, Contract, and Pricebook are always resolved
4. **Fresh Snapshot**: Deletes old OrderItems before recreating to ensure clean state
5. **Dual Path OrderItem Creation**: Efficiently handles both existing cart items and new products

---

### **5. Invoice Generation Flow**

```
┌──────────────────┐
│  User/System     │
│ triggers invoice │
│   generation     │
└────────┬─────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ CheckOutController.saveInvoicePdfToAccount()                    │
│ @AuraEnabled                                                    │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Find Most Recent Activated Order                        │
│                                                                 │
│ Query:                                                          │
│ SELECT Id, Name, EffectiveDate, AccountId                       │
│ FROM Order                                                      │
│ WHERE Status = 'Activated'                                      │
│ ORDER BY CreatedDate DESC                                       │
│ LIMIT 1                                                         │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Render Visualforce Page as PDF                          │
│                                                                 │
│ PageReference pr = Page.InvoicePdf                              │
│ pr.getParameters().put('id', orderId)                           │
│ Blob pdfBlob = pr.getContentAsPDF()                             │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ InvoicePdf.page (Visualforce)                               ││
│ │ Controller: InvoicePDFController                            ││
│ │                                                             ││
│ │ Data Loaded:                                                ││
│ │ - Order details (Name, Date, Account)                       ││
│ │ - OrderItems (Product, Qty, Price, Total)                   ││
│ │ - Calculations (Subtotal, Tax, Total)                       ││
│ │                                                             ││
│ │ renderAs="pdf"                                              ││
│ └─────────────────────────────────────────────────────────────┘│
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Save to Salesforce Files                                │
│                                                                 │
│ ContentVersion cv = new ContentVersion();                       │
│ cv.Title = "Invoice_2025-11-27"                                 │
│ cv.PathOnClient = "/Invoice_2025-11-27.pdf"                     │
│ cv.VersionData = pdfBlob                                        │
│ cv.FirstPublishLocationId = order.AccountId  // Publish to Acct │
│ INSERT cv                                                       │
│                                                                 │
│ Result: ContentVersion.Id, ContentDocumentId                    │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: Link to Order (ContentDocumentLink)                     │
│                                                                 │
│ ContentDocumentLink cdl = new ContentDocumentLink();            │
│ cdl.ContentDocumentId = cv.ContentDocumentId                    │
│ cdl.LinkedEntityId = order.Id                                   │
│ cdl.ShareType = 'V' (Viewer)                                    │
│ cdl.Visibility = 'AllUsers'                                     │
│ INSERT cdl                                                      │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: Send to External FileService (@future callout)          │
│                                                                 │
│ sendPdfToFileService(fileName, accountName, pdfBlob)            │
│ @future(callout=true)                                           │
│                                                                 │
│ HTTP Request:                                                   │
│ POST callout:ServerOrg/services/apexrest/fileservice/          │
│      ?accountName=<Account.Name>                                │
│      &fileName=<Invoice_Date.pdf>                               │
│ Headers:                                                        │
│   Content-Type: application/octet-stream                        │
│ Body: pdfBlob (binary)                                          │
└────────┬────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ Server Org: FileService.cls                                     │
│ @RestResource(urlMapping='/fileservice/')                       │
│                                                                 │
│ Receives:                                                       │
│ - Query params: accountName, fileName                           │
│ - Body: Blob data                                               │
│                                                                 │
│ Processing:                                                     │
│ 1. Lookup Account by Name in server org                         │
│ 2. Create ContentVersion with file data                         │
│ 3. Link to Account in server org                               │
│ 4. Return success response                                      │
└─────────────────────────────────────────────────────────────────┘
```

**Key Components:**

**InvoicePDFController.cls:**
```
public class InvoicePDFController {
    public Order orderRecord { get; set; }
    public List<OrderItem> orderItems { get; set; }
    public Decimal subtotal { get; set; }
    public Decimal tax { get; set; }
    public Decimal total { get; set; }
    
    public InvoicePDFController() {
        Id orderId = ApexPages.currentPage().getParameters().get('id');
        // Load order and items
        // Calculate totals
    }
}
```

**InvoicePdf.page:**
```
<apex:page controller="InvoicePDFController" renderAs="pdf">
    <h1>Invoice: {!orderRecord.Name}</h1>
    <apex:dataTable value="{!orderItems}" var="item">
        <!-- Order line items -->
    </apex:dataTable>
    <div>Subtotal: {!subtotal}</div>
    <div>Tax: {!tax}</div>
    <div>Total: {!total}</div>
</apex:page>
```

---

## 🔄 Integration Architecture

### **Named Credential Configuration**

```
Name: ServerOrg
URL: https://your-server-org.salesforce.com
Authentication: OAuth 2.0 / Username-Password
```

### **Bi-Directional API Endpoints**

| **Direction** | **Endpoint** | **Method** | **Purpose** | **Handler Class** |
|--------------|-------------|----------|------------|------------------|
| Client → Server | `/services/apexrest/Products` | GET | Fetch all products with PBE data | ProductService.cls |
| Client → Server | `/services/apexrest/product/pbeinfo` | POST | Get unit price for specific product | ProductPBEServices.cls |
| Client → Server | `/services/apexrest/fileservice/` | POST | Upload invoice PDF to server | FileService.cls |

### **REST API Handlers (Server Org)**

**1. ProductService.cls**
```
@RestResource(urlMapping='/Products')
global with sharing class ProductService {
    @HttpGet
    global static List<ProductWrapper> getProducts() {
        // Query Product2 with nested PricebookEntry data
        // Return serialized product list
    }
}
```

**2. ProductPBEServices.cls**
```
@RestResource(urlMapping='/product/pbeinfo')
global with sharing class ProductPBEServices {
    @HttpPost
    global static Decimal getUnitPrice() {
        RestRequest req = RestContext.request;
        String productId = req.requestBody.toString();
        // Query PricebookEntry for product
        // Return UnitPrice
    }
}
```

**3. FileService.cls**
```
@RestResource(urlMapping='/fileservice/')
global with sharing class FileService {
    @HttpPost
    global static String uploadFile() {
        RestRequest req = RestContext.request;
        String accountName = req.params.get('accountName');
        String fileName = req.params.get('fileName');
        Blob fileData = req.requestBody;
        
        // Lookup Account in server org
        // Create ContentVersion
        // Link to Account
        return 'Success';
    }
}
```

---

## 🧩 Component Structure

### **File Hierarchy**

```
HandsOnTraining/
├── force-app/main/default/
│   ├── classes/
│   │   ├── CheckOutController.cls                 # Main checkout logic
│   │   ├── ProductController.cls                  # Product browsing
│   │   ├── ProductCardController.cls              # Product card data
│   │   ├── InvoicePDFController.cls               # Invoice data
│   │   ├── ProductSyncBatch.cls                   # Product sync job
│   │   ├── ProductSyncScheduler.cls               # Job scheduler
│   │   ├── ProductService.cls                     # REST: Get products
│   │   ├── ProductPBEServices.cls                 # REST: Get pricing
│   │   ├── FileService.cls                        # REST: File upload
│   │   └── ContentVersionTriggerHandler.cls       # File trigger logic
│   │
│   ├── lwc/
│   │   ├── shoppingPortal/                        # Main container
│   │   │   ├── shoppingPortal.html
│   │   │   ├── shoppingPortal.js
│   │   │   └── shoppingPortal.css
│   │   │
│   │   ├── productCard/                           # Product grid item
│   │   │   ├── productCard.html
│   │   │   ├── productCard.js
│   │   │   └── productCard.css
│   │   │
│   │   ├── productDetailModal/                    # Product popup
│   │   │   ├── productDetailModal.html
│   │   │   ├── productDetailModal.js
│   │   │   └── productDetailModal.css
│   │   │
│   │   ├── productImage/                          # Image component
│   │   │   ├── productImage.html
│   │   │   ├── productImage.js
│   │   │   └── productImage.css
│   │   │
│   │   ├── productInformationDisplay/             # Product details
│   │   │   ├── productInformationDisplay.html
│   │   │   ├── productInformationDisplay.js
│   │   │   └── productInformationDisplay.css
│   │   │
│   │   └── checkoutPage/                          # Checkout form
│   │       ├── checkoutPage.html
│   │       ├── checkoutPage.js
│   │       └── checkoutPage.css
│   │
│   ├── pages/
│   │   ├── InvoicePdf.page                        # Invoice PDF template
│   │   └── InvoicePdf.page-meta.xml
│   │
│   ├── triggers/
│   │   └── ContentVersionTrigger.trigger          # File creation trigger
│   │
│   └── staticresources/                           # Images/CSS/JS assets
│
├── config/                                        # Salesforce DX configs
├── manifest/
│   └── package.xml                                # Deployment manifest
├── scripts/                                       # Deployment scripts
├── README.md
└── sfdx-project.json
```

### **Component Relationships**

```
┌───────────────────────────────────────────────────────────────┐
│                      shoppingPortal (Parent)                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Header: Search Bar, Family Filter, Account Selector   │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Product Grid Container                     │ │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐            │ │
│  │  │ productCard│ │ productCard│ │ productCard│  ...      │ │
│  │  │ ┌─────────┐│ │ ┌─────────┐│ │ ┌─────────┐│            │ │
│  │  │ │product  ││ │ │product  ││ │ │product  ││            │ │
│  │  │ │Image    ││ │ │Image    ││ │ │Image    ││            │ │
│  │  │ └─────────┘│ │ └─────────┘│ │ └─────────┘│            │ │
│  │  └───────────┘ └───────────┘ └───────────┘            │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Pagination: << Prev | Page 1 of 10 | Next >>          │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                             │
                             │ User clicks product
                             ↓
┌───────────────────────────────────────────────────────────────┐
│            productDetailModal (Popup Overlay)                 │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Large Product Image                                    │ │
│  │  Product Name                                           │ │
│  │  Description                                            │ │
│  │  Price: $100.00                                         │ │
│  │  Quantity: [ 1 ] [+] [-]                                │ │
│  │  [ Add to Cart ]  [ Close ]                             │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                             │
                             │ Navigate to Checkout
                             ↓
┌───────────────────────────────────────────────────────────────┐
│                    checkoutPage (Form)                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Account Selection: [Lookup] or [Create New]           │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Billing Address:                                       │ │
│  │  Street: ___________  City: __________                  │ │
│  │  State: ______  Postal Code: ______  Country: ______    │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Shipping Address: [ Same as Billing ] or separate     │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Contract: [Dropdown of Activated Contracts]            │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Cart Items:                                            │ │
│  │  Product A  |  Qty: 2  |  $100  |  $200  | [Remove]    │ │
│  │  Product B  |  Qty: 5  |  $250  |  $1250 | [Remove]    │ │
│  │  ───────────────────────────────────────────            │ │
│  │  Total: $1450                                           │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              [ Place Order ]                            │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

---

## 🔑 Critical Business Logic

### **1. ExternalId Pattern for Synchronization**

```
// Product2 Custom Field
Product2.ExternalId__c = Server Product2.Id (18-char)

// Upsert Logic
Database.upsert(productList, Product2.ExternalId__c, false);
```

**Benefits:**
- Prevents duplicate products across syncs
- Maintains referential integrity between orgs
- Supports bi-directional updates

---

### **2. Temp ID Wrapper Pattern**

```
// Client-side cart item identifier
const tempId = `temp_${product2Id}_${Date.now()}`;

// Server-side extraction
if (id.startsWith('temp_')) {
    String productId = id.substring(5, 23); // Extract 18-char ID
}
```

**Use Case:**
- Allows client-side cart management before server persistence
- Supports multiple instances of same product with different prices
- Preserves quantity/price mapping during checkout

---

### **3. Contract-Order-Pricebook Chain**

```
Contract
  │
  ├─ AccountId (required)
  ├─ Pricebook2Id (optional, can be null)
  └─ Status (Draft → Activated)
       │
       ↓
Order
  │
  ├─ AccountId (from Contract)
  ├─ ContractId (required for activation)
  ├─ Pricebook2Id (from Contract or fallback)
  └─ Status (Draft → Activated)
       │
       ↓
OrderItem
  │
  ├─ OrderId (required)
  ├─ Product2Id (required)
  └─ PricebookEntryId (Product2 + Pricebook2)
```

**Validation Rules:**
- Order can only be Activated if Contract.Status = 'Activated'
- OrderItem requires PricebookEntry from Order.Pricebook2Id
- PricebookEntry must link Product2 to Pricebook2

---

### **4. Draft-to-Activated Order Flow**

```
State 1: Draft Order (Status = 'Draft')
  - User can modify cart items
  - OrderItems can be added/removed/updated
  - Order fields are editable
       │
       ↓ User clicks "Place Order"
       ↓
State 2: Activated Order (Status = 'Activated')
  - Order becomes IMMUTABLE
  - OrderItems are locked
  - Invoice generation triggered
  - Inventory/fulfillment processes begin
```

**Implementation:**
```
// Only activate if Contract is ready
if (contract.Status == 'Activated') {
    order.Status = 'Activated';
    update order;
}
```

---

### **5. Multi-Format ID Resolution Algorithm**

```
// Input: ["802xxx", "01txxx", "temp_01txxx_12345"]
// Output: 
//   - orderItemIds: ["802xxx"]
//   - product2Ids: ["01txxx", "01txxx"]
//   - effectiveProduct2IdsByIndex: [null, "01txxx", "01txxx"]

for (Integer i = 0; i < rawIdsStr.size(); i++) {
    String id = rawIdsStr[i];
    
    if (id.startsWith('802')) {
        orderItemIds.add((Id)id);
        effectiveProduct2IdsByIndex.add(null);
    }
    else if (id.startsWith('temp_')) {
        String productId = extractProductIdFromTemp(id);
        product2Ids.add((Id)productId);
        effectiveProduct2IdsByIndex.add((Id)productId);
    }
    else {
        product2Ids.add((Id)id);
        effectiveProduct2IdsByIndex.add((Id)id);
    }
}

// Later: Map quantities/prices by index
for (Integer i = 0; i < effectiveProduct2IdsByIndex.size(); i++) {
    Id productId = effectiveProduct2IdsByIndex[i];
    if (productId != null) {
        Integer qty = params.qtys[i];
        Decimal price = params.prices[i];
        // Create OrderItem...
    }
}
```

---

## 🚀 Deployment Guide

### **Prerequisites**

1. **Salesforce DX CLI**
   ```
   npm install -g @salesforce/cli
   ```

2. **Dev Hub Enabled**
   - Navigate to Setup → Dev Hub → Enable Dev Hub

3. **Two Salesforce Orgs**
   - **Server Org**: Source of product data
   - **Client Org**: Consumer org (this project)

---

### **Step 1: Clone Repository**

```
git clone https://github.com/suyashmarathe512/Order_Management_System.git
cd Order_Management_System
git checkout OnlinePortal
cd HandsOnTraining
```

---

### **Step 2: Authenticate to Salesforce Org**

```
# Client Org (deployment target)
sf org login web --set-default-dev-hub --alias ClientOrg

# Server Org (product source)
sf org login web --alias ServerOrg
```

---

### **Step 3: Create Named Credential**

**Manual Setup (Recommended):**

1. Navigate to **Setup → Named Credentials**
2. Click **New Named Credential**
3. Configure:
   - **Label**: ServerOrg
   - **Name**: ServerOrg
   - **URL**: `https://your-server-org.salesforce.com`
   - **Authentication Protocol**: OAuth 2.0 or Username-Password
   - **Username**: [Server Org Username]
   - **Password**: [Server Org Password + Security Token]
4. Click **Save**

---

### **Step 4: Deploy Metadata**

```
# Deploy all metadata
sf project deploy start --source-path force-app/main/default --target-org ClientOrg

# Or deploy specific components
sf project deploy start --source-path force-app/main/default/classes --target-org ClientOrg
sf project deploy start --source-path force-app/main/default/lwc --target-org ClientOrg
sf project deploy start --source-path force-app/main/default/pages --target-org ClientOrg
```

---

### **Step 5: Create Custom Fields (If Not in Metadata)**

Navigate to **Setup → Object Manager**:

**Product2:**
- **ExternalId__c** (Text, External ID, Unique, 18 chars)
- **ProductImage__c** (URL, 255 chars)

**Contract:**
- **Contract_Name__c** (Text, 80 chars)

---

### **Step 6: Schedule Product Sync Job**

**Option A: Execute Anonymous Apex**
```
ProductSyncScheduler scheduler = new ProductSyncScheduler();
String cronExpression = '0 0 0 * * ?'; // Daily at midnight
System.schedule('Product Sync Job', cronExpression, scheduler);
```

**Option B: Developer Console**
1. Open **Developer Console**
2. Navigate to **Debug → Open Execute Anonymous Window**
3. Paste above code
4. Click **Execute**

**Verify:**
```
List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, State, NextFireTime 
                          FROM CronTrigger 
                          WHERE CronJobDetail.Name = 'Product Sync Job'];
System.debug(jobs);
```

---

### **Step 7: Create Lightning Page**

1. Navigate to **Setup → Lightning App Builder**
2. Click **New**
3. Choose **App Page**
4. Name: **Shopping Portal**
5. Select **One Region** template
6. Drag **shoppingPortal** LWC to canvas
7. Activate page and assign to app

---

### **Step 8: Test Integration**

**Test Product Sync:**
```
// Manual batch execution
Database.executeBatch(new ProductSyncBatch(), 200);

// Verify products synced
List<Product2> products = [SELECT Id, Name, ExternalId__c FROM Product2 WHERE ExternalId__c != null];
System.debug('Synced Products: ' + products.size());
```

**Test REST Endpoints:**
```
# Get products from server
curl -X GET "https://your-server-org.salesforce.com/services/apexrest/Products" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Test file upload
curl -X POST "https://your-server-org.salesforce.com/services/apexrest/fileservice/?accountName=Test&fileName=test.pdf" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @test.pdf
```

---

## 🔍 Technical Deep Dive

### **Performance Optimizations**

#### **1. Cacheable Wire Services**
```
// productCard.js
@wire(fetchProducts, { 
    pageNumber: '$pageNumber',
    pageSize: '$pageSize',
    searchQuery: '$searchTerm',
    selectedFamilies: '$selectedFamilies'
})
```
- **@AuraEnabled(cacheable=true)** reduces server calls
- Client-side caching improves perceived performance
- Refresh strategy on cart updates

#### **2. Batch Query Optimization**
```
// ProductSyncBatch.cls - Process 200 records per batch
Database.executeBatch(new ProductSyncBatch(), 200);

// Bulkified PBE lookups
List<PricebookEntry> pbes = [SELECT Id, Product2Id 
                             FROM PricebookEntry 
                             WHERE Product2Id IN :product2Ids 
                               AND Pricebook2Id = :finalPB2
                               AND IsActive = true];
Map<Id, PricebookEntry> pbeByProduct = new Map<Id, PricebookEntry>();
for (PricebookEntry pbe : pbes) {
    pbeByProduct.put(pbe.Product2Id, pbe);
}
```

#### **3. Index-Based Mapping Pattern**
```
// Avoids nested loops O(n²) → O(n)
List<Id> effectiveProduct2IdsByIndex = new List<Id>();
for (Integer i = 0; i < rawIdsStr.size(); i++) {
    // Build index mapping
}
// Single-pass OrderItem creation
for (Integer i = 0; i < effectiveProduct2IdsByIndex.size(); i++) {
    Integer qty = params.qtys[i];
    Decimal price = params.prices[i];
    // Create OrderItem
}
```

---

### **Error Handling Patterns**

#### **1. Graceful Degradation**
```
try {
    PricebookEntry pbe = [SELECT UnitPrice FROM PricebookEntry WHERE Id = :pbeId LIMIT 1];
    finalPrice = pbe.UnitPrice;
} catch (Exception e) {
    // Fallback: Use price from params or set to 0
    finalPrice = (params.prices != null && i < params.prices.size()) ? params.prices[i] : 0;
}
```

#### **2. Partial Success with Database Methods**
```
// Allow partial insert/update success
Database.SaveResult[] results = Database.insert(productList, false);
for (Database.SaveResult sr : results) {
    if (!sr.isSuccess()) {
        System.debug('Failed: ' + sr.getErrors().getMessage());
    }
}
```

#### **3. User-Friendly AuraHandledExceptions**
```
if (accountId == null) {
    throw new AuraHandledException('Account is required to place an order.');
}
```

---

### **Security Considerations**

#### **1. Object and Field-Level Security**
```
// User mode enforced
public with sharing class CheckOutController {
    // Respects user permissions and sharing rules
}

// Explicit user mode for DML
Database.delete(orderItemList, AccessLevel.USER_MODE);
```

#### **2. Named Credential Security**
- Credentials stored encrypted in Salesforce
- No hardcoded passwords in code
- OAuth token refresh handled automatically

#### **3. Input Validation**
```
// Sanitize SOQL inputs
String likePattern = '%' + String.escapeSingleQuotes(searchQuery) + '%';

// Validate required parameters
if (String.isBlank(accountId) || String.isBlank(productId)) {
    throw new AuraHandledException('Required parameters missing');
}
```

---

### **Scalability Patterns**

#### **1. Asynchronous Processing**
```
// Future method for long-running callouts
@future(callout=true)
public static void sendPdfToFileService(String fileName, String accountName, Blob pdfBlob) {
    // HTTP callout doesn't block user transaction
}
```

#### **2. Batch Processing**
```
// Handle large datasets without governor limits
global class ProductSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Process up to 200 records per batch
    }
}
```

#### **3. Pagination Strategy**
```
// Client-side pagination reduces payload size
const pageSize = 12;
const offsetRows = (pageNumber - 1) * pageSize;
// Only fetch current page data
```

---

## 📊 Data Model

### **Standard Objects**

```
Account
  │
  ├─ Contract
  │    ├─ Pricebook2Id
  │    ├─ Status (Draft | Activated)
  │    └─ StartDate, EndDate
  │
  ├─ Order
  │    ├─ AccountId
  │    ├─ ContractId
  │    ├─ Pricebook2Id
  │    ├─ Status (Draft | Activated)
  │    ├─ BillingAddress fields
  │    ├─ ShippingAddress fields
  │    └─ EffectiveDate
  │         │
  │         └─ OrderItem
  │              ├─ OrderId
  │              ├─ Product2Id
  │              ├─ PricebookEntryId
  │              ├─ Quantity
  │              ├─ UnitPrice
  │              └─ TotalPrice
  │
  └─ ContentDocumentLink (Files/Invoices)
       └─ ContentDocument
            └─ ContentVersion

Product2
  ├─ Name
  ├─ ProductCode
  ├─ Description
  ├─ Family
  ├─ IsActive
  ├─ StockKeepingUnit (SKU)
  ├─ ExternalId__c (Custom)
  ├─ ProductImage__c (Custom)
  └─ PricebookEntry
       ├─ Product2Id
       ├─ Pricebook2Id
       ├─ UnitPrice
       └─ IsActive

Pricebook2
  ├─ Name
  ├─ IsActive
  └─ IsStandard
```

---

## 🐛 Troubleshooting

### **Issue 1: Products Not Syncing**

**Symptoms:**
- ProductSyncBatch runs but no products appear
- External callout fails

**Solutions:**
1. **Verify Named Credential:**
   ```
   # Test callout
   System.debug(new Http().send(new HttpRequest().setEndpoint('callout:ServerOrg/services/apexrest/Products')));
   ```

2. **Check Remote Site Settings:**
   - Setup → Remote Site Settings
   - Add: `https://your-server-org.salesforce.com`

3. **Verify Server REST Endpoints:**
   - Ensure ProductService.cls is deployed on server
   - Test endpoint with Postman/curl

---

### **Issue 2: PricebookEntry Missing**

**Symptoms:**
- "No pricebook is configured" error during checkout
- OrderItems fail to create

**Solutions:**
1. **Create Standard Pricebook Entries:**
   ```
   Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
   
   List<PricebookEntry> pbes = new List<PricebookEntry>();
   for (Product2 p : [SELECT Id FROM Product2]) {
       pbes.add(new PricebookEntry(
           Product2Id = p.Id,
           Pricebook2Id = stdPbId,
           UnitPrice = 100.00,
           IsActive = true
       ));
   }
   insert pbes;
   ```

2. **Verify Contract Pricebook:**
   - Ensure Contract.Pricebook2Id is populated
   - Run sync to pull pricebooks from server

---

### **Issue 3: Order Activation Fails**

**Symptoms:**
- Order stays in Draft status
- "Contract must be activated" error

**Solutions:**
1. **Activate Contract First:**
   ```
   Contract c = [SELECT Id, Status FROM Contract WHERE Id = :contractId LIMIT 1];
   c.Status = 'Activated';
   update c;
   ```

2. **Check Validation Rules:**
   - Review Contract/Order validation rules
   - Temporarily disable for testing

---

### **Issue 4: Invoice PDF Not Generating**

**Symptoms:**
- saveInvoicePdfToAccount() returns null
- PDF blank or corrupt

**Solutions:**
1. **Verify Visualforce Page:**
   - Test InvoicePdf.page directly with `?id=<OrderId>`
   - Check InvoicePDFController query

2. **Check ContentVersion Creation:**
   ```
   List<ContentVersion> cvs = [SELECT Id, Title, ContentDocumentId 
                                FROM ContentVersion 
                                WHERE CreatedDate = TODAY];
   System.debug(cvs);
   ```

3. **Future Method Debugging:**
   - Check debug logs for @future method execution
   - Verify callout not hitting governor limits

---

## 📚 Best Practices

### **1. Always Use Bulkified Queries**
```
// ❌ BAD: Query inside loop
for (Id productId : productIds) {
    Product2 p = [SELECT Name FROM Product2 WHERE Id = :productId];
}

// ✅ GOOD: Single query with IN clause
Map<Id, Product2> productMap = new Map<Id, Product2>(
    [SELECT Id, Name FROM Product2 WHERE Id IN :productIds]
);
```

### **2. Implement Proper Error Handling**
```
try {
    // Risky operation
} catch (DmlException e) {
    System.debug('DML Error: ' + e.getMessage());
    throw new AuraHandledException('User-friendly message');
} catch (Exception e) {
    System.debug('Unexpected Error: ' + e.getMessage());
    throw e;
}
```

### **3. Use With Sharing for Security**
```
// Enforces sharing rules
public with sharing class CheckOutController {
    // User can only see records they have access to
}
```

### **4. Leverage Platform Events for Decoupling**
```
// Publish event after order activation
Order_Activated__e evt = new Order_Activated__e(Order_Id__c = orderId);
EventBus.publish(evt);

// Subscribers handle invoice generation, notifications, etc.
```

### **5. Write Comprehensive Test Classes**
```
@isTest
private class CheckOutControllerTest {
    @testSetup
    static void setup() {
        // Create test data
    }
    
    @isTest
    static void testCreateOrder_Success() {
        // Test successful order creation
    }
    
    @isTest
    static void testCreateOrder_MissingAccount() {
        // Test error handling
    }
}
```

---

## 🎓 Learning Resources

### **Salesforce Documentation**
- [Lightning Web Components Developer Guide](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)
- [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
- [REST API Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/)

### **Trailhead Modules**
- [Build Lightning Web Components](https://trailhead.salesforce.com/content/learn/trails/build-lightning-web-components)
- [Apex Integration Services](https://trailhead.salesforce.com/content/learn/modules/apex_integration_services)
- [Order Management Basics](https://trailhead.salesforce.com/content/learn/modules/orders-quick-start)

---

## 🤝 Contributing

### **Branching Strategy**
```
# Feature development
git checkout -b feature/new-feature-name

# Bug fixes
git checkout -b bugfix/issue-description

# Hotfixes
git checkout -b hotfix/critical-fix
```

### **Commit Message Convention**
```
feat: Add product image carousel
fix: Resolve PricebookEntry lookup issue
docs: Update README with deployment steps
refactor: Optimize CheckOutController logic
test: Add test coverage for ProductSync
```

---

## 📄 License

This project is internal to CRM Team Innovation.

---

## 📞 Support

**Developer:** Suyash Marathe  
**GitHub:** [suyashmarathe512](https://github.com/suyashmarathe512)  
**Repository:** [Order_Management_System](https://github.com/suyashmarathe512/Order_Management_System)

---

## 🔖 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-11-27 | Initial comprehensive documentation |
| 0.9.0 | 2025-11-XX | Beta release with core features |
| 0.1.0 | 2025-XX-XX | Project initialization |

---

**Last Updated:** November 27, 2025  
**Documentation Version:** 1.0.0
```

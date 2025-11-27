# Order Management System – Documentation

Version: 1.0.0
Last Updated: November 27, 2025

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture and Data Flow](#2-architecture-and-data-flow)

   * [Product Synchronization](#21-product-synchronization-server--client-org)
   * [Product Browsing](#22-product-browsing-flow)
   * [Add to Cart](#23-add-to-cart-flow)
   * [Checkout](#24-checkout-flow)
   * [Invoice Generation](#25-invoice-generation-flow)
3. [Integration Architecture](#3-integration-architecture)
4. [Component Structure](#4-component-structure)
5. [Critical Business Logic](#5-critical-business-logic)
6. [Deployment Guide](#6-deployment-guide)
7. [Technical Deep Dive](#7-technical-deep-dive)
8. [Data Model](#8-data-model)
9. [Troubleshooting](#9-troubleshooting)
10. [Best Practices](#10-best-practices)
11. [Learning Resources](#11-learning-resources)
12. [Contributing](#12-contributing)
13. [License and Support](#13-license-and-support)
14. [Version History](#14-version-history)

---

## 1. System Overview

This is an e-commerce Order Management System built on Salesforce DX. It supports:

* Product sync between a server org and a client org
* Real-time product browsing with search and filters
* Shopping cart with draft orders
* Checkout with account, contract, and pricebook logic
* PDF invoice generation and file storage
* Bi-directional REST API integrations

**Main technologies:**

* Salesforce DX
* Lightning Web Components (LWC)
* Apex (Controllers, REST services, Batch, Schedulable)
* Visualforce (PDF generation)
* Named Credentials (secure HTTP callouts)
* Batch and scheduled jobs

---

## 2. Architecture and Data Flow

### 2.1 Product Synchronization (Server → Client Org)

**High-level flow:**

1. Server org exposes an Apex REST endpoint `/services/apexrest/Products`.
2. Client org uses a scheduled job to call this endpoint.
3. The batch class parses the response and:

   * Upserts `Product2` records using an External Id.
   * Ensures `Pricebook2` exists.
   * Upserts `PricebookEntry` records.

**Simple diagram:**

* Server Org (Product REST API)
  → HTTP GET (by Named Credential + Batch)
  → Client Org `ProductSyncBatch`
  → Upsert `Product2`, `Pricebook2`, `PricebookEntry`

**Scheduler example:**

```apex
// Runs daily at midnight
System.schedule(
    'Product Sync Job',
    '0 0 0 * * ?',
    new ProductSyncScheduler()
);
```

**Key patterns:**

* `Product2.ExternalId__c` stores the server `Product2.Id` (18-char)
* `Database.upsert(list, field, false)` used to avoid duplicates and allow partial success
* Missing pricebooks are auto-created by name

---

### 2.2 Product Browsing Flow

**Flow:**

1. LWC (shopping portal / product grid) calls Apex method `fetchProducts`.
2. Apex queries active `Product2` records with filters and pagination.
3. Apex also loads pricing from `PricebookEntry`.
4. Apex returns a DTO structure to the LWC.
5. LWC renders product cards and details.

**Key Apex features:**

* `@AuraEnabled(cacheable=true)` to support LWC wire and caching
* Inputs: `pageNumber`, `pageSize`, `searchQuery`, `selectedFamilies`
* Query filters on `Name`, `ProductCode`, `Description`, `Family`
* Pricing is looked up using `StockKeepingUnit` (SKU) or `Product2Id`

**Example query (simplified):**

```apex
SELECT Id, Name, ProductCode, Description, Family,
       ProductImage__c, StockKeepingUnit
FROM Product2
WHERE IsActive = true
AND (Name LIKE :search OR ProductCode LIKE :search OR Description LIKE :search)
AND (Family IN :selectedFamilies OR :selectedFamilies = null)
ORDER BY Name
LIMIT :pageSize
OFFSET :offsetRows;
```

The controller then enriches each product with a list of pricebook entries.

---

### 2.3 Add-to-Cart Flow

**User flow:**

1. User clicks "Add to Cart" on a product.
2. LWC calls `ProductController.addToOrder(...)`.
3. Apex:

   * Finds or creates a single Draft `Order` for the Account.
   * Ensures a `Pricebook2` is set (usually Standard Pricebook).
   * Finds matching `PricebookEntry`.
   * Creates or updates an `OrderItem`.

**Main steps in Apex:**

1. Find Draft order for the account:

```apex
SELECT Id, Pricebook2Id
FROM Order
WHERE AccountId = :accountId
AND Status = 'Draft'
LIMIT 1;
```

2. If no Draft order: create one with Standard Pricebook.
3. Lookup `PricebookEntry` for the given `Product2Id` and `Pricebook2Id`.
4. If `OrderItem` exists for the same `Product2Id`, increase quantity.
5. Else, insert a new `OrderItem`.

**Business rules:**

* Only one Draft order per Account at a time
* Quantity is incremented if user adds the same product again
* Price is always taken from `PricebookEntry.UnitPrice`

---

### 2.4 Checkout Flow

Checkout is driven by `CheckOutController.createOrderFromCart()`.

**Input:**

A JSON string with:

* `orderItemsIds[]`
* `names[]`
* `qtys[]`
* `prices[]`
* `accountId`
* `contractId`
* `billingAddress` (street, city, state, postalCode, country)
* `shippingAddress` (same fields)

The `orderItemsIds[]` can contain three kinds of values:

* Existing `OrderItem` Ids (start with `"802"`)
* Real `Product2` Ids (start with `"01t"`)
* Temp-wrapped Product Ids: `temp_{Product2Id}_{timestamp}`

**Step 1: Multi-format ID resolution**

For each element in `orderItemsIds`:

* If starts with `"802"` → treat as `OrderItem` Id.
* If starts with `"temp_"` → extract inner 18-char `Product2Id`.
* Else → treat as direct `Product2Id`.

Data structures built:

* `orderItemIds[]` – real existing `OrderItem` Ids
* `product2Ids[]` – list of `Product2` Ids from both direct and temp IDs
* `effectiveProduct2IdsByIndex[]` – same size as input, maps each index to a `Product2Id` or `null` (when it is an `OrderItem` Id)

**Pseudo-code:**

```apex
for (Integer i = 0; i < rawIdsStr.size(); i++) {
    String id = rawIdsStr[i];

    if (id.startsWith('802')) {
        orderItemIds.add((Id)id);
        effectiveProduct2IdsByIndex.add(null);
    } else if (id.startsWith('temp_')) {
        String productId = extractProductIdFromTemp(id);
        product2Ids.add((Id)productId);
        effectiveProduct2IdsByIndex.add((Id)productId);
    } else {
        product2Ids.add((Id)id);
        effectiveProduct2IdsByIndex.add((Id)id);
    }
}
```

**Step 2: Account resolution (3-level fallback)**

1. Use `params.accountId` if provided.
2. If null, read `OrderItem.Order.AccountId` from any existing `OrderItem` Id.
3. If still null, read `Contract.AccountId` from `params.contractId`.
4. If no Account found, throw an error.

**Step 3: Contract resolution**

1. If `contractId` is passed, validate that `Contract.AccountId` matches resolved Account.
2. If not passed, find the latest `Contract` for that Account.
3. If still not found, create a new `Contract` with:

   * `AccountId`
   * `Status = 'Draft'`
   * `StartDate = TODAY`
   * `Pricebook2Id` set from Order or Standard Pricebook.

**Step 4: Pricebook resolution**

Priority:

1. `Contract.Pricebook2Id`
2. Pricebook from existing `OrderItems`
3. Standard Pricebook (query `Pricebook2` where `IsStandard = true`)

**Step 5: Draft order management**

1. Check if a Draft `Order` exists for that Account.
2. If exists:

   * Delete all old `OrderItems` of that order (fresh snapshot).
   * Update `Order` with final `Pricebook2Id`, `ContractId`, addresses, and `EffectiveDate`.
3. If not exists:

   * Create new Draft `Order` with Account, Contract, Pricebook, addresses, and `EffectiveDate`.

**Step 6: PricebookEntry lookup**

If `product2Ids[]` is not empty, query:

```apex
SELECT Id, Product2Id
FROM PricebookEntry
WHERE Product2Id IN :product2Ids
AND Pricebook2Id = :finalPricebook2Id
AND IsActive = true;
```

Build a map: `Map<Id, PricebookEntry> pbeByProduct`.

**Step 7: OrderItem creation**

Two paths:

* Path A: clone from existing `OrderItem` Ids (those starting with `"802"`).
* Path B: create items from `Product2Id` (direct or temp-based).

For each index `i`:

* If `effectiveProduct2IdsByIndex[i]` is `null` → belongs to Path A (cloned items already handled).
* Else, get `Product2Id`, find PricebookEntry, quantity, and price from `params.qtys[i]` and `params.prices[i]`.

Finally, insert all new `OrderItem` records in bulk and compute total amount.

**Step 8: Order activation**

* If `Contract.Status != 'Activated'`, set it to `Activated` and update.
* When `Contract.Status = 'Activated'`, set `Order.Status = 'Activated'` and update.
* Activated orders become read-only.

**Step 9: Return result**

Return an object like:

```json
{
  "orderId": "801xxx...",
  "lineItemCount": 5,
  "totalAmount": 2500.00,
  "contentVersionId": null,
  "contentDocumentId": null
}
```

---

### 2.5 Invoice Generation Flow

Handled by `CheckOutController.saveInvoicePdfToAccount()`.

**Steps:**

1. Find the most recent Activated `Order`:

```apex
SELECT Id, Name, EffectiveDate, AccountId
FROM Order
WHERE Status = 'Activated'
ORDER BY CreatedDate DESC
LIMIT 1;
```

2. Render Visualforce page as PDF:

```apex
PageReference pr = Page.InvoicePdf;
pr.getParameters().put('id', orderId);
Blob pdfBlob = pr.getContentAsPDF();
```

3. Create `ContentVersion` linked to the `Account` (FirstPublishLocationId):

```apex
ContentVersion cv = new ContentVersion();
cv.Title = 'Invoice_2025-11-27';
cv.PathOnClient = '/Invoice_2025-11-27.pdf';
cv.VersionData = pdfBlob;
cv.FirstPublishLocationId = order.AccountId;
insert cv;
```

4. Create `ContentDocumentLink` to the `Order`:

```apex
ContentDocumentLink cdl = new ContentDocumentLink();
cdl.ContentDocumentId = cv.ContentDocumentId;
cdl.LinkedEntityId = order.Id;
cdl.ShareType = 'V';
cdl.Visibility = 'AllUsers';
insert cdl;
```

5. Send PDF to external File Service using a future callout:

```apex
@future(callout=true)
public static void sendPdfToFileService(String fileName, String accountName, Blob pdfBlob) {
    // HTTP POST to server org /fileservice/
}
```

---

## 3. Integration Architecture

### 3.1 Named Credential

Configuration example:

```text
Name: ServerOrg
URL: https://your-server-org.salesforce.com
Authentication: OAuth 2.0 or Username-Password
```

The Named Credential is used for callouts like:

* `/services/apexrest/Products`
* `/services/apexrest/product/pbeinfo`
* `/services/apexrest/fileservice/`

### 3.2 REST Endpoints (Server Org)

**1. ProductService.cls**

```apex
@RestResource(urlMapping='/Products')
global with sharing class ProductService {
    @HttpGet
    global static List<ProductWrapper> getProducts() {
        // Query Product2 and PricebookEntry
        // Return serialized list
    }
}
```

**2. ProductPBEServices.cls**

```apex
@RestResource(urlMapping='/product/pbeinfo')
global with sharing class ProductPBEServices {
    @HttpPost
    global static Decimal getUnitPrice() {
        RestRequest req = RestContext.request;
        String productId = req.requestBody.toString();
        // Query PricebookEntry for this product
        // Return UnitPrice
    }
}
```

**3. FileService.cls**

```apex
@RestResource(urlMapping='/fileservice/')
global with sharing class FileService {
    @HttpPost
    global static String uploadFile() {
        RestRequest req = RestContext.request;
        String accountName = req.params.get('accountName');
        String fileName = req.params.get('fileName');
        Blob fileData = req.requestBody;

        // Lookup Account by name
        // Create ContentVersion
        // Link to Account
        return 'Success';
    }
}
```

---

## 4. Component Structure

### 4.1 File hierarchy (simplified)

```text
HandsOnTraining/
├─ force-app/main/default/
│  ├─ classes/
│  │  ├─ CheckOutController.cls
│  │  ├─ ProductController.cls
│  │  ├─ ProductCardController.cls
│  │  ├─ InvoicePDFController.cls
│  │  ├─ ProductSyncBatch.cls
│  │  ├─ ProductSyncScheduler.cls
│  │  ├─ ProductService.cls
│  │  ├─ ProductPBEServices.cls
│  │  ├─ FileService.cls
│  │  └─ ContentVersionTriggerHandler.cls
│  ├─ lwc/
│  │  ├─ shoppingPortal/
│  │  ├─ productCard/
│  │  ├─ productDetailModal/
│  │  ├─ productImage/
│  │  ├─ productInformationDisplay/
│  │  └─ checkoutPage/
│  ├─ pages/
│  │  ├─ InvoicePdf.page
│  │  └─ InvoicePdf.page-meta.xml
│  ├─ triggers/
│  │  └─ ContentVersionTrigger.trigger
│  └─ staticresources/
├─ config/
├─ manifest/package.xml
├─ scripts/
├─ README.md
└─ sfdx-project.json
```

### 4.2 Component relationships (LWC)

* `shoppingPortal` (main parent)

  * Header: search, filters, account selector
  * Product grid of `productCard` components
* `productCard`

  * Shows product image, name, price, and “Add to Cart”
  * Opens `productDetailModal` on click
* `productDetailModal`

  * Large product image, price, quantity, Add to Cart
* `checkoutPage`

  * Account selection or creation
  * Billing and shipping address
  * Contract selection
  * Cart items list
  * Place Order button

---

## 5. Critical Business Logic

### 5.1 External Id Pattern for Sync

```apex
// Product2 custom field
Product2.ExternalId__c = serverProduct.Id;

// Upsert by external id
Database.upsert(productList, Product2.ExternalId__c, false);
```

Benefits:

* Avoids duplicate products
* Keeps reference between server and client org
* Supports updates on later sync runs

### 5.2 Temp ID Wrapper Pattern

Used for cart items that are not yet stored as `OrderItem`.

Client-side:

```js
const tempId = `temp_${product2Id}_${Date.now()}`;
```

Server-side:

```apex
if (id.startsWith('temp_')) {
    String productId = id.substring(5, 23); // 18-char Product2 Id
}
```

This allows:

* Local cart management in the client
* Multiple instances of same product
* Accurate mapping of `qtys[]` and `prices[]` by index

### 5.3 Contract–Order–Pricebook Chain

* `Contract`

  * Has `AccountId`
  * Can have `Pricebook2Id`
  * Has `Status` (Draft → Activated)

* `Order`

  * Has `AccountId` and `ContractId`
  * Has `Pricebook2Id`
  * Status (Draft → Activated)
  * Needs Contract to be Activated before Order can be Activated

* `OrderItem`

  * Has `OrderId`, `Product2Id`, and `PricebookEntryId`

Validation:

* Order can be Activated only if Contract is Activated.
* `OrderItem.PricebookEntryId` must be a row that matches `Order.Pricebook2Id` and `Product2Id`.

---

## 6. Deployment Guide

### 6.1 Prerequisites

1. Salesforce CLI:

```bash
npm install -g @salesforce/cli
```

2. Dev Hub enabled in your main org.
3. Two Salesforce orgs:

   * Server Org (source for products)
   * Client Org (this project)

### 6.2 Clone repository

```bash
git clone https://github.com/suyashmarathe512/Order_Management_System.git
cd Order_Management_System
git checkout OnlinePortal
cd HandsOnTraining
```

### 6.3 Authenticate orgs

```bash
# Client Org
sf org login web --set-default-dev-hub --alias ClientOrg

# Server Org
sf org login web --alias ServerOrg
```

### 6.4 Create Named Credential (manual)

1. Setup → Named Credentials → New.
2. Label: `ServerOrg`
3. Name: `ServerOrg`
4. URL: `https://your-server-org.salesforce.com`
5. Set OAuth or Username-Password.
6. Save.

### 6.5 Deploy metadata

```bash
sf project deploy start \
  --source-path force-app/main/default \
  --target-org ClientOrg
```

You can also deploy directories (classes, lwc, pages) separately if needed.

### 6.6 Custom fields (if not in metadata)

**On Product2:**

* `ExternalId__c` (Text, 18, External ID, Unique)
* `ProductImage__c` (URL, 255)

**On Contract:**

* `Contract_Name__c` (Text, 80)

### 6.7 Schedule product sync

Execute anonymous:

```apex
ProductSyncScheduler scheduler = new ProductSyncScheduler();
String cronExpression = '0 0 0 * * ?'; // Daily at midnight
System.schedule('Product Sync Job', cronExpression, scheduler);
```

### 6.8 Create Lightning page

1. Setup → Lightning App Builder → New.
2. Type: App Page.
3. Name: `Shopping Portal`.
4. Template: One Region.
5. Drag `shoppingPortal` LWC to page.
6. Activate and assign.

### 6.9 Test integration

Manual batch:

```apex
Database.executeBatch(new ProductSyncBatch(), 200);
```

Test REST endpoints with curl/Postman as needed.

---

## 7. Technical Deep Dive

### 7.1 Performance

* Use `@AuraEnabled(cacheable=true)` on read-only Apex methods.
* Use pagination (`LIMIT` + `OFFSET`) to avoid large payloads.
* Use batch size of 200 in `Database.executeBatch`.

Example bulk PBE lookup:

```apex
List<PricebookEntry> pbes = [
    SELECT Id, Product2Id
    FROM PricebookEntry
    WHERE Product2Id IN :product2Ids
    AND Pricebook2Id = :finalPb2Id
    AND IsActive = true
];

Map<Id, PricebookEntry> pbeByProduct = new Map<Id, PricebookEntry>();
for (PricebookEntry pbe : pbes) {
    pbeByProduct.put(pbe.Product2Id, pbe);
}
```

### 7.2 Error handling

* Wrap risky operations in try-catch.
* Use `AuraHandledException` for user-friendly messages.
* Use `Database.insert(list, false)` for partial success.

```apex
if (accountId == null) {
    throw new AuraHandledException('Account is required to place an order.');
}
```

### 7.3 Security

* Use `with sharing` on controllers.
* Respect field and object-level security where needed.
* Use Named Credentials instead of hardcoded URLs and credentials.
* Escape user input in SOQL:

```apex
String likePattern = '%' + String.escapeSingleQuotes(searchQuery) + '%';
```

### 7.4 Scalability

* Use `@future(callout=true)` for long-running HTTP calls.
* Use batch Apex for large data sets.
* Use pagination in UI for product browsing.

---

## 8. Data Model

### 8.1 Standard objects

**Account**

* Has many `Contract`, `Order`, and `ContentDocumentLink`.

**Contract**

* Fields: `AccountId`, `Pricebook2Id`, `Status`, `StartDate`, `EndDate`.

**Order**

* Fields: `AccountId`, `ContractId`, `Pricebook2Id`, `Status`, `EffectiveDate`, billing & shipping address fields.
* Has many `OrderItem`.

**OrderItem**

* Fields: `OrderId`, `Product2Id`, `PricebookEntryId`, `Quantity`, `UnitPrice`, `TotalPrice`.

**Product2**

* Fields: `Name`, `ProductCode`, `Description`, `Family`, `IsActive`, `StockKeepingUnit`, `ExternalId__c`, `ProductImage__c`.
* Related to `PricebookEntry`.

**Pricebook2**

* Fields: `Name`, `IsActive`, `IsStandard`.

**ContentDocument / ContentVersion / ContentDocumentLink**

* Used for storing and linking invoice PDFs.

---

## 9. Troubleshooting

### 9.1 Products not syncing

Possible issues:

* Named Credential not configured correctly.
* Remote Site Settings missing.
* Server REST service not deployed or not working.

Check with an anonymous callout or Postman.

### 9.2 Missing PricebookEntry

Symptoms:

* Error: no pricebook configured during checkout.

Fix:

* Ensure Standard Pricebook exists and is active.
* Create `PricebookEntry` rows for all `Product2`:

```apex
Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
List<PricebookEntry> pbes = new List<PricebookEntry>();

for (Product2 p : [SELECT Id FROM Product2]) {
    pbes.add(new PricebookEntry(
        Product2Id = p.Id,
        Pricebook2Id = stdPbId,
        UnitPrice = 100,
        IsActive = true
    ));
}

insert pbes;
```

### 9.3 Order activation fails

* Check if related `Contract` is Activated.
* Check validation rules on Contract and Order.

### 9.4 Invoice PDF not generating

* Test `InvoicePdf.page?id=<OrderId>` in browser.
* Check that `InvoicePDFController` queries the Order and OrderItems correctly.
* Verify `ContentVersion` is created.

---

## 10. Best Practices

* Always bulkify queries and DML.
* Use `with sharing` on controllers.
* Handle errors with user-friendly messages.
* Keep business logic in Apex classes, not in LWC.
* Write test classes with good coverage, including negative paths.

Example test pattern:

```apex
@isTest
private class CheckOutControllerTest {
    @testSetup
    static void setup() {
        // Create test data
    }

    @isTest
    static void testCreateOrder_Success() {
        // Assert success path
    }

    @isTest
    static void testCreateOrder_MissingAccount() {
        // Assert error path
    }
}
```

---

## 11. Learning Resources

* Salesforce Lightning Web Components Developer Guide
* Salesforce Apex Developer Guide
* Salesforce REST API Developer Guide
* Trailhead modules:

  * Build Lightning Web Components
  * Apex Integration Services
  * Order Management Basics

---

## 12. Contributing

### 12.1 Branch strategy

```text
feature/new-feature-name
bugfix/issue-description
hotfix/critical-fix
```

### 12.2 Commit conventions

```text
feat: Add product image carousel
fix: Resolve PricebookEntry lookup issue
docs: Update README with deployment steps
refactor: Optimize CheckOutController logic
test: Add test coverage for ProductSync
```

---

## 13. License and Support

This project is internal to CRM Team Innovation.

**Developer:** Suyash Marathe
**GitHub:** [https://github.com/suyashmarathe512](https://github.com/suyashmarathe512)
**Repository:** [https://github.com/suyashmarathe512/Order_Management_System](https://github.com/suyashmarathe512/Order_Management_System)

---

## 14. Version History

| Version | Date       | Changes                             |
| ------- | ---------- | ----------------------------------- |
| 1.0.0   | 2025-11-27 | Initial comprehensive documentation |
| 0.9.0   | 2025-11-XX | Beta release with core features     |
| 0.1.0   | 2025-XX-XX | Project initialization              |

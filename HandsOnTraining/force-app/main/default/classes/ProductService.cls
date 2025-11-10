@RestResource(urlMapping='/products')
global with sharing class ProductService {
    
    global class ProductWrapper {
        global String name;
        global String productCode;
        global String description;
        global String family;
        global Boolean isActive;
        global String sku;
        global String quantityUnitOfMeasure;
        global List<PricebookEntryWrapper> pricebookEntries;
    }
    
    global class PricebookEntryWrapper {
        global String pricebook2Id;
        global Decimal unitPrice;
        global Boolean isActive;
        global Boolean useStandardPrice;
    }

    @HttpPost
    global static void upsertProducts() {
        RestResponse res = RestContext.response;
        try {
            // Deserialize incoming JSON
            String requestBody = RestContext.request.requestBody.toString();
            List<ProductWrapper> productWrappers = 
                (List<ProductWrapper>) JSON.deserialize(requestBody, List<ProductWrapper>.class);

            // Collect all product codes
            Set<String> productCodes = new Set<String>();
            for (ProductWrapper pw : productWrappers) {
                productCodes.add(pw.productCode);
            }

            // Fetch existing products
            Map<String, Product2> existingProducts = new Map<String, Product2>();
            for (Product2 p : [
                SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode IN :productCodes
            ]) {
                existingProducts.put(p.ProductCode, p);
            }

            List<Product2> toInsert = new List<Product2>();
            List<Product2> toUpdate = new List<Product2>();
            Map<String, Id> productCodeToId = new Map<String, Id>();

            // Upsert products
            for (ProductWrapper pw : productWrappers) {
                if (existingProducts.containsKey(pw.productCode)) {
                    Product2 existing = existingProducts.get(pw.productCode);
                    existing.Name = pw.name;
                    existing.Description = pw.description;
                    existing.Family = pw.family;
                    existing.IsActive = pw.isActive;
                    existing.StockKeepingUnit = pw.sku;
                    existing.QuantityUnitOfMeasure = pw.quantityUnitOfMeasure;
                    toUpdate.add(existing);
                    productCodeToId.put(pw.productCode, existing.Id);
                } else {
                    Product2 prod = new Product2(
                        Name = pw.name,
                        ProductCode = pw.productCode,
                        Description = pw.description,
                        Family = pw.family,
                        IsActive = pw.isActive,
                        StockKeepingUnit = pw.sku,
                        QuantityUnitOfMeasure = pw.quantityUnitOfMeasure
                    );
                    toInsert.add(prod);
                }
            }

            // Perform DML
            if (!toInsert.isEmpty()) {
                Database.SaveResult[] insRes = Database.insert(toInsert, false);
                for (Integer i = 0; i < insRes.size(); i++) {
                    if (insRes[i].isSuccess()) {
                        productCodeToId.put(toInsert[i].ProductCode, insRes[i].getId());
                    }
                }
            }
            if (!toUpdate.isEmpty()) Database.update(toUpdate, false);

            // Now handle PricebookEntries
            List<PricebookEntry> toUpsertPBEs = new List<PricebookEntry>();
            for (ProductWrapper pw : productWrappers) {
                if (pw.pricebookEntries == null) continue;
                Id prodId = productCodeToId.get(pw.productCode);
                if (prodId == null) continue;

                for (PricebookEntryWrapper pbew : pw.pricebookEntries) {
                    if (pbew.pricebook2Id == null) continue;

                    // Check if this PBE already exists
                    List<PricebookEntry> existing = [
                        SELECT Id, UnitPrice, IsActive, UseStandardPrice
                        FROM PricebookEntry
                        WHERE Product2Id = :prodId AND Pricebook2Id = :pbew.pricebook2Id
                        LIMIT 1
                    ];

                    if (existing.isEmpty()) {
                        toUpsertPBEs.add(new PricebookEntry(
                            Product2Id = prodId,
                            Pricebook2Id = pbew.pricebook2Id,
                            UnitPrice = pbew.unitPrice,
                            IsActive = pbew.isActive,
                            UseStandardPrice = pbew.useStandardPrice
                        ));
                    } else {
                        PricebookEntry pbe = existing[0];
                        pbe.UnitPrice = pbew.unitPrice;
                        pbe.IsActive = pbew.isActive;
                        pbe.UseStandardPrice = pbew.useStandardPrice;
                        toUpsertPBEs.add(pbe);
                    }
                }
            }

            if (!toUpsertPBEs.isEmpty()) {
                Database.upsert(toUpsertPBEs);
            }

            // Success response
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'message' => 'Sync successful',
                'insertedProducts' => toInsert.size(),
                'updatedProducts' => toUpdate.size(),
                'pricebookEntriesProcessed' => toUpsertPBEs.size()
            }));
            res.statusCode = 200;
        } catch (Exception e) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{'error' => e.getMessage()}
            ));
            res.statusCode = 500;
        }
    }
}

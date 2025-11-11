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
        global String pricebook2Name;
        global Decimal unitPrice;
        global Boolean isActive;
        global Boolean useStandardPrice;
    }

    class PBEWrapper {
        Id productId;
        Id pricebookId;
        Decimal unitPrice;
        Boolean isActive;
        Boolean useStandardPrice;
        Integer payloadIndex;
    }

    @HttpPost
    global static void upsertProducts() {
        RestResponse res = RestContext.response;
        try {
            String requestBody = RestContext.request.requestBody.toString();
            List<ProductWrapper> payload = (List<ProductWrapper>) JSON.deserialize(requestBody, List<ProductWrapper>.class);

            if (payload == null || payload.isEmpty()) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String,String>{ 'error' => 'Empty payload' }));
                return;
            }

            Set<String> skus = new Set<String>();
            Set<String> pbNames = new Set<String>();
            for (ProductWrapper pw : payload) {
                if (pw.sku != null) skus.add(pw.sku);
                if (pw.pricebookEntries != null) {
                    for (PricebookEntryWrapper pbw : pw.pricebookEntries) {
                        if (pbw.pricebook2Name != null) pbNames.add(pbw.pricebook2Name);
                    }
                }
            }

            Map<String, Product2> existingBySKU = new Map<String, Product2>();
            if (!skus.isEmpty()) {
                for (Product2 p : [SELECT 
                                        Id, StockKeepingUnit, Name, Description, Family, IsActive, QuantityUnitOfMeasure
                                   FROM 
                                        Product2 
                                    WHERE 
                                        StockKeepingUnit 
                                    IN 
                                        :skus]) {
                    if (p.StockKeepingUnit != null) existingBySKU.put(p.StockKeepingUnit, p);
                }
            }

            Map<String, Id> pricebookNameToId = new Map<String, Id>();
            if (!pbNames.isEmpty()) {
                for (Pricebook2 pb : [SELECT
                                            Id, Name
                                    FROM
                                        Pricebook2
                                    WHERE
                                        Name
                                    IN
                                        :pbNames]) {
                    pricebookNameToId.put(pb.Name, pb.Id);
                }
            }

            // Query existing PBEs for existing products to check for notification
            Map<Id, List<PricebookEntry>> productPBEs = new Map<Id, List<PricebookEntry>>();
            if (!existingBySKU.isEmpty()) {
                Set<Id> existingProductIds = new Set<Id>();
                for (Product2 p : existingBySKU.values()) {
                    existingProductIds.add(p.Id);
                }
                for (PricebookEntry pbe : [SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive, UseStandardPrice
                                           FROM PricebookEntry
                                           WHERE Product2Id IN :existingProductIds]) {
                    if (!productPBEs.containsKey(pbe.Product2Id)) {
                        productPBEs.put(pbe.Product2Id, new List<PricebookEntry>());
                    }
                    productPBEs.get(pbe.Product2Id).add(pbe);
                }
            }
            List<String> affectedProducts = new List<String>();
            List<Product2> toInsert = new List<Product2>();
            Map<Id, Product2> toUpdateById = new Map<Id, Product2>();

            Map<String, Id> productKeyToId = new Map<String, Id>();

            List<Integer> insertPayloadIndices = new List<Integer>();

            for (Integer i = 0; i < payload.size(); i++) {
                ProductWrapper pw = payload[i];
                if (pw.sku != null && existingBySKU.containsKey(pw.sku)) {
                    Product2 existing = existingBySKU.get(pw.sku);
                    existing.Name = pw.name;
                    existing.Description = pw.description;
                    existing.Family = pw.family;
                    existing.IsActive = pw.isActive;
                    existing.QuantityUnitOfMeasure = pw.quantityUnitOfMeasure;
                    existing.StockKeepingUnit = pw.sku;
                    toUpdateById.put(existing.Id, existing);
                    productKeyToId.put('SKU::' + pw.sku, existing.Id);

                    // Check for escalation: if product has PBEs in org but payload has none
                    if (productPBEs.containsKey(existing.Id) && !productPBEs.get(existing.Id).isEmpty() &&
                        (pw.pricebookEntries == null || pw.pricebookEntries.isEmpty())) {
                        affectedProducts.add('SKU: ' + pw.sku + ', Name: ' + existing.Name);
                    }
                } else {
                    Product2 newP = new Product2(
                        Name = pw.name,
                        ProductCode = pw.productCode,
                        Description = pw.description,
                        Family = pw.family,
                        IsActive = pw.isActive,
                        StockKeepingUnit = pw.sku,
                        QuantityUnitOfMeasure = pw.quantityUnitOfMeasure
                    );
                    toInsert.add(newP);
                    insertPayloadIndices.add(i);
                    productKeyToId.put('PAYIDX::' + String.valueOf(i), null);
                    if (pw.sku != null) {
                        productKeyToId.put('SKU::' + pw.sku, null);
                    }
                }
            }

            if (!toInsert.isEmpty()) {
                Database.SaveResult[] insRes = Database.insert(toInsert, false);
                for (Integer j = 0; j < insRes.size(); j++) {
                    Database.SaveResult sr = insRes[j];
                    Integer payloadIndex = insertPayloadIndices[j];
                    if (sr.isSuccess()) {
                        Id newId = sr.getId();
                        productKeyToId.put('PAYIDX::' + String.valueOf(payloadIndex), newId);
                        ProductWrapper pw = payload[payloadIndex];
                        if (pw.sku != null) productKeyToId.put('SKU::' + pw.sku, newId);
                    } else {
                    }
                }
            }
            Set<String> allSKUsToCheck = new Set<String>();
            for (ProductWrapper pw : payload) if (pw.sku != null) allSKUsToCheck.add(pw.sku);
            if (!allSKUsToCheck.isEmpty()) {
                for (Product2 p : [SELECT 
                                        Id, StockKeepingUnit 
                                    FROM 
                                        Product2 
                                    WHERE 
                                        StockKeepingUnit 
                                    IN 
                                        :allSKUsToCheck]) {
                    productKeyToId.put('SKU::' + p.StockKeepingUnit, p.Id);
                }
            }

            if (!toUpdateById.isEmpty()) {
                Database.update(toUpdateById.values(), false);
            }

            List<PBEWrapper> desiredPBEs = new List<PBEWrapper>();
            Set<Id> productIdsForPBEs = new Set<Id>();
            Set<Id> pricebookIdsForPBEs = new Set<Id>();

            for (Integer i = 0; i < payload.size(); i++) {
                ProductWrapper pw = payload[i];
                Id prodId = null;
                if (pw.sku != null && productKeyToId.containsKey('SKU::' + pw.sku)) prodId = productKeyToId.get('SKU::' + pw.sku);
                if (prodId == null && productKeyToId.containsKey('PAYIDX::' + String.valueOf(i))) prodId = productKeyToId.get('PAYIDX::' + String.valueOf(i));
                if (prodId == null) {
                    continue;
                }
                if (pw.pricebookEntries == null) continue;
                for (PricebookEntryWrapper pbw : pw.pricebookEntries) {
                    if (pbw.pricebook2Name == null) continue;
                    PBEWrapper t = new PBEWrapper();
                    t.productId = prodId;
                    t.pricebookId = pricebookNameToId.get(pbw.pricebook2Name);
                    t.unitPrice = pbw.unitPrice;
                    t.isActive = pbw.isActive;
                    t.useStandardPrice = pbw.useStandardPrice;
                    t.payloadIndex = i;
                    desiredPBEs.add(t);
                    productIdsForPBEs.add(prodId);
                }
            }
            Set<String> unresolvedPBNames = new Set<String>();
            for (ProductWrapper pw : payload) {
                if (pw.pricebookEntries == null) continue;
                for (PricebookEntryWrapper pbw : pw.pricebookEntries) {
                    if (pbw.pricebook2Name != null && !pricebookNameToId.containsKey(pbw.pricebook2Name)) unresolvedPBNames.add(pbw.pricebook2Name);
                }
            }
            if (!unresolvedPBNames.isEmpty()) {
                for (Pricebook2 pb : [SELECT 
                                            Id, Name 
                                        FROM 
                                            Pricebook2 
                                        WHERE 
                                            Name 
                                        IN 
                                            :unresolvedPBNames]) {
                    pricebookNameToId.put(pb.Name, pb.Id);
                }
            }
            for (PBEWrapper t : desiredPBEs) {
                if (t.pricebookId == null) {
                    ProductWrapper pw = payload[t.payloadIndex];
                    for (PricebookEntryWrapper pbw : pw.pricebookEntries) {
                        if (pbw.pricebook2Name != null && pricebookNameToId.containsKey(pbw.pricebook2Name)) {
                            t.pricebookId = pricebookNameToId.get(pbw.pricebook2Name);
                            break;
                        }
                    }
                }
                if (t.pricebookId != null) pricebookIdsForPBEs.add(t.pricebookId);
            }
            Map<String, PricebookEntry> existingPBEMap = new Map<String, PricebookEntry>();
            if (!productIdsForPBEs.isEmpty() && !pricebookIdsForPBEs.isEmpty()) {
                for (PricebookEntry ex : [SELECT 
                                                Id, Product2Id, Pricebook2Id, UnitPrice, IsActive, UseStandardPrice
                                          FROM 
                                                PricebookEntry
                                          WHERE    
                                                Product2Id 
                                            IN 
                                                :productIdsForPBEs 
                                            AND 
                                                Pricebook2Id 
                                            IN 
                                                :pricebookIdsForPBEs]) {
                    existingPBEMap.put(String.valueOf(ex.Product2Id) + '::' + String.valueOf(ex.Pricebook2Id), ex);
                }
            }
            List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
            List<PricebookEntry> pbesToUpdate = new List<PricebookEntry>();
            for (PBEWrapper t : desiredPBEs) {
                if (t.pricebookId == null || t.productId == null) continue;
                String key = String.valueOf(t.productId) + '::' + String.valueOf(t.pricebookId);
                if (existingPBEMap.containsKey(key)) {
                    PricebookEntry existing = existingPBEMap.get(key);
                    existing.UnitPrice = t.unitPrice;
                    existing.IsActive = t.isActive;
                    existing.UseStandardPrice = t.useStandardPrice;
                    pbesToUpdate.add(existing);
                } else {
                    pbesToInsert.add(new PricebookEntry(
                        Product2Id = t.productId,
                        Pricebook2Id = t.pricebookId,
                        UnitPrice = t.unitPrice,
                        IsActive = t.isActive,
                        UseStandardPrice = t.useStandardPrice
                    ));
                }
            }
            if (!pbesToInsert.isEmpty()) Database.insert(pbesToInsert, false);
            if (!pbesToUpdate.isEmpty()) Database.update(pbesToUpdate, false);

            // Escalate a case if there are affected products
            if (!affectedProducts.isEmpty()) {
                Group salesTeamGroup = [SELECT Id FROM Group WHERE Name = 'Sales_Team' AND Type = 'Regular' LIMIT 1];
                if (salesTeamGroup != null) {
                    Case escalationCase = new Case(
                        Subject = 'Escalation: Products with PBEs in org but missing in payload',
                        Description = 'The following products have Pricebook Entries in the org but the payload does not include any PBEs:\n' + String.join(affectedProducts, '\n'),
                        OwnerId = salesTeamGroup.Id,
                        Status = 'New',
                        Origin = 'Web'
                    );
                    Database.insert(escalationCase, false);
                }
            }

            Map<String, Object> resp = new Map<String, Object>{
                'message' => 'Sync completed (SKU-only matching).',
                'productsInserted' => toInsert.size(),
                'productsUpdated' => toUpdateById.size(),
                'pbesInserted' => pbesToInsert.size(),
                'pbesUpdated' => pbesToUpdate.size()
            };
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(resp));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String,String>{ 'error' => e.getMessage() }));
        }
    }
}

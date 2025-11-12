@RestResource(urlMapping='/product/pbeinfo')
global with sharing class ProductPBEServices {

    public class ProductPBEInfo {
        public Id pricebookEntryId;
        public Id pricebookId;
        public String pricebookName;
        public Decimal unitPrice;
        public Boolean isActive;
        public Id productId;
        public String productName;
        public String sku;
    }

    @HttpPost
    global static Map<String, List<ProductPBEInfo>> getPBEInfo() {
        // Parse request body
        String body = RestContext.request.requestBody != null 
            ? RestContext.request.requestBody.toString() 
            : null;

        if (String.isBlank(body)) {
           RestContext.response.statusCode = 400;
           RestContext.response.responseBody = Blob.valueOf('No request body provided');
        }

        // Expecting: ["SKU1", "SKU2"]
        List<String> skus = (List<String>) JSON.deserialize(body, List<String>.class);
        if (skus == null || skus.isEmpty()) {
              RestContext.response.statusCode = 400;
              RestContext.response.responseBody = Blob.valueOf('No SKUs provided in request body');
        }

        Set<String> skuSet = new Set<String>();
        for (String s : skus) {
            if (!String.isBlank(s)) skuSet.add(s.trim());
        }

        Map<String, List<ProductPBEInfo>> result = new Map<String, List<ProductPBEInfo>>();
        if (skuSet.isEmpty()) return result;

        // Fetch Products
        Map<Id, Product2> prodMap = new Map<Id, Product2>();
        for (Product2 p : [
            SELECT Id, Name, StockKeepingUnit
            FROM Product2
            WHERE StockKeepingUnit IN :skuSet
        ]) {
            prodMap.put(p.Id, p);
            result.put(p.StockKeepingUnit, new List<ProductPBEInfo>());
        }

        if (prodMap.isEmpty()) return result;

        // Fetch PBE records for those Products
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :prodMap.keySet()
        ]) {
            Product2 prod = prodMap.get(pbe.Product2Id);
            if (prod == null) continue;
            ProductPBEInfo info = new ProductPBEInfo();
            info.pricebookEntryId = pbe.Id;
            info.pricebookId = pbe.Pricebook2Id;
            info.pricebookName = pbe.Pricebook2 != null ? pbe.Pricebook2.Name : null;
            info.unitPrice = pbe.UnitPrice;
            info.isActive = pbe.IsActive;
            info.productId = prod.Id;
            info.productName = prod.Name;
            info.sku = prod.StockKeepingUnit;
            result.get(prod.StockKeepingUnit).add(info);
        }

        return result;
    }
}

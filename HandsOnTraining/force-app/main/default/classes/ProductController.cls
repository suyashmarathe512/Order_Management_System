public with sharing class ProductController {
    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:ServerOrg/product/pbeinfo';
    @AuraEnabled
    public static ProductPage fetchProducts(Integer pageNumber, Integer pageSize, String searchQuery, List<String> selectedFamilies, String sortField, String sortDir) {
        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 12;
        Integer offsetRows = (pageNumber - 1) * pageSize;
        String likePattern;
        Boolean hasSearch = false;
        Integer total = 0;
        if (String.isNotBlank(searchQuery)) {
            hasSearch = true;
            likePattern = '%' + searchQuery + '%';
        }
        List<Product2> products;
        if (selectedFamilies != null && !selectedFamilies.isEmpty()) {
            if (hasSearch) {
                products = [SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE 
                        IsActive = true
                     AND 
                            (Name LIKE :likePattern OR ProductCode LIKE :likePattern OR Description LIKE :likePattern)
                     AND 
                        Family IN :selectedFamilies
                    ORDER BY 
                        Name ASC
                    LIMIT 
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            } else {
                products = [SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE    
                        IsActive = true
                     AND 
                        Family IN :selectedFamilies
                    ORDER BY 
                        Name 
                    ASC
                    LIMIT   
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            }
            // Count total products matching the family filter (and search if applicable)
            if (hasSearch) {
                Integer totalFiltered = [SELECT COUNT() FROM Product2 WHERE IsActive = true AND (Name LIKE :likePattern OR ProductCode LIKE :likePattern OR Description LIKE :likePattern) AND Family IN :selectedFamilies];
                total = totalFiltered;
            } else {
                Integer totalFiltered = [SELECT COUNT() FROM Product2 WHERE IsActive = true AND Family IN :selectedFamilies];
                total = totalFiltered;
            }
        } else {
            if (hasSearch) {
                products = [SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE 
                        IsActive = true
                     AND 
                            (Name LIKE :likePattern OR ProductCode LIKE :likePattern OR Description LIKE :likePattern)
                    ORDER BY 
                        Name ASC
                    LIMIT 
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            } else {
                products = [SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE    
                        IsActive = true
                    ORDER BY 
                        Name 
                    ASC
                    LIMIT   
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            }
            // Count all active products
            Integer totalFiltered = [SELECT COUNT() FROM Product2 WHERE IsActive = true];
            total = totalFiltered;
        }
        List<ProductDTO> dtos = new List<ProductDTO>();
        Map<String, Id> skuToProductId = new Map<String, Id>();
        for (Product2 p : products) {
            ProductDTO dto = new ProductDTO();
            dto.id = p.Id;
            dto.name = p.Name;
            dto.productCode = p.ProductCode;
            dto.description = p.Description;
            dto.family = p.Family;
            dto.isActive = p.IsActive;
            dto.sku = p.StockKeepingUnit;
            dto.uom = p.QuantityUnitOfMeasure;
            dto.productImage = p.ProductImage__c;
            dto.pbes = new List<ProductPBEInfo>();
            if (!String.isBlank(dto.sku)) skuToProductId.put(dto.sku.trim(), p.Id);
            dtos.add(dto);
        }
        if (skuToProductId.isEmpty()) return new ProductPage(dtos, total, pageNumber, pageSize);
        List<String> skuList = new List<String>(skuToProductId.keySet());
        String payload = JSON.serialize(skuList);
        Map<String, List<ProductPBEInfo>> combinedPbeMap = new Map<String, List<ProductPBEInfo>>();
        Boolean calloutSucceeded = false;
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(payload);
            Http http = new Http();
            HttpResponse resp = http.send(req);
            if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
                Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                if (raw != null) {
                    for (String k : raw.keySet()) {
                        Object v = raw.get(k);
                        if (v == null || !(v instanceof List<Object>)) {
                            combinedPbeMap.put(k, new List<ProductPBEInfo>());
                            continue;
                        }
                        List<Object> arr = (List<Object>) v;
                        List<ProductPBEInfo> parsedList = new List<ProductPBEInfo>();
                        for (Object item : arr) {
                            if (!(item instanceof Map<String, Object>)) continue;
                            Map<String, Object> m = (Map<String, Object>) item;
                            ProductPBEInfo pi = new ProductPBEInfo();
                            pi.pricebookEntryId = (m.containsKey('pricebookEntryId') && m.get('pricebookEntryId') != null) ? (Id) String.valueOf(m.get('pricebookEntryId')) : null;
                            pi.pricebookId = (m.containsKey('pricebookId') && m.get('pricebookId') != null) ? (Id) String.valueOf(m.get('pricebookId')) : null;
                            pi.pricebookName = (String) m.get('pricebookName');
                            if (m.containsKey('unitPrice') && m.get('unitPrice') != null)
                                pi.unitPrice = Decimal.valueOf(String.valueOf(m.get('unitPrice')));
                            pi.isActive = (m.containsKey('isActive') && m.get('isActive') != null) ? (Boolean) m.get('isActive') : null;
                            pi.productId = (m.containsKey('productId') && m.get('productId') != null) ? (Id) String.valueOf(m.get('productId')) : null;
                            pi.productName = (String) m.get('productName');
                            pi.sku = (String) m.get('sku');
                            pi.isFetchedFromOrg = false;
                            parsedList.add(pi);
                        }
                        combinedPbeMap.put(k, parsedList);
                    }
                }
                calloutSucceeded = true;
            }
        } catch (Exception ex) {
            calloutSucceeded = false;
        }
        Set<String> fallbackSkus = new Set<String>();
        for (String sku : skuToProductId.keySet()) {
            if (!calloutSucceeded || !combinedPbeMap.containsKey(sku) || combinedPbeMap.get(sku).isEmpty())
                fallbackSkus.add(sku);
        }
        if (!fallbackSkus.isEmpty()) {
            Set<Id> prodIds = new Set<Id>();
            for (String s : fallbackSkus)
                if (skuToProductId.containsKey(s)) prodIds.add(skuToProductId.get(s));

            if (!prodIds.isEmpty()) {
                List<PricebookEntry> localPbes = [
                    SELECT 
                        Id, Product2Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive
                    FROM 
                        PricebookEntry
                    WHERE 
                        Product2Id 
                    IN 
                        :prodIds 
                    AND 
                        IsActive = true
                    ORDER BY 
                        UnitPrice ASC
                ];
                Map<Id, PricebookEntry> lowestByProd = new Map<Id, PricebookEntry>();
                for (PricebookEntry pbe : localPbes)
                    if (!lowestByProd.containsKey(pbe.Product2Id))
                        lowestByProd.put(pbe.Product2Id, pbe);

                for (String sku : fallbackSkus) {
                    Id pid = skuToProductId.get(sku);
                    List<ProductPBEInfo> listForSku = combinedPbeMap.containsKey(sku)
                        ? combinedPbeMap.get(sku)
                        : new List<ProductPBEInfo>();
                    if (pid != null && lowestByProd.containsKey(pid)) {
                        PricebookEntry pbe = lowestByProd.get(pid);
                        ProductPBEInfo pi = new ProductPBEInfo();
                        pi.pricebookEntryId = pbe.Id;
                        pi.pricebookId = pbe.Pricebook2Id;
                        pi.pricebookName = pbe.Pricebook2 != null ? pbe.Pricebook2.Name : null;
                        pi.unitPrice = pbe.UnitPrice;
                        pi.isActive = pbe.IsActive;
                        pi.productId = pbe.Product2Id;
                        pi.productName = null;
                        for (Product2 product : products) {
                            if (product.Id == pid) {
                                pi.productName = product.Name;
                                break;
                            }
                        }
                        pi.sku = sku;
                        pi.isFetchedFromOrg = true; 
                        listForSku.add(pi);
                    }
                    combinedPbeMap.put(sku, listForSku);
                }
            }
        }
        for (ProductDTO dto : dtos) {
            if (String.isBlank(dto.sku)) continue;
            String key = dto.sku.trim();
            dto.pbes = combinedPbeMap.containsKey(key)
                ? combinedPbeMap.get(key)
                : new List<ProductPBEInfo>();
        }
        return new ProductPage(dtos, total, pageNumber, pageSize);
    }
    public class ProductDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String description;
        @AuraEnabled public String family;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String sku;
        @AuraEnabled public String uom;
        @AuraEnabled public String productImage;
        @AuraEnabled public List<ProductPBEInfo> pbes;
    }
    public class ProductPBEInfo {
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public Id pricebookId;
        @AuraEnabled public String pricebookName;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String sku;
        @AuraEnabled public Boolean isFetchedFromOrg;
    }
    public class ProductPage {
        @AuraEnabled public List<ProductDTO> records;
        @AuraEnabled public Integer totalSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        public ProductPage(List<ProductDTO> recs, Integer total, Integer pageNum, Integer pSize) {
            this.records = recs;
            this.totalSize = total;
            this.pageNumber = pageNum;
            this.pageSize = pSize;
        }
    }
    @AuraEnabled
    public static List<String> fetchProductFamilies() {
        Set<String> families = new Set<String>();
        List<Product2> products = [SELECT Family FROM Product2 WHERE Family != null ORDER BY Family];
        for (Product2 product : products) {
            families.add(product.Family);
        }
        List<String> sortedFamilies = new List<String>(families);
        sortedFamilies.sort();
        return sortedFamilies;
    }
}

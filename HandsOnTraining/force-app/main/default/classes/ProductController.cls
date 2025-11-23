/*****************************************************************************
 * @AuthorName:     CRM Team Innovation (patched)
 * @ClassName:      ProductController
 * @Description:    Fetch products and product PBE info. Supports LWC usage.
 *                 Preserves original logic; fixes compile errors.
 ***********************************************************************************/
public with sharing class ProductController{
    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:ServerOrg/services/apexrest/product/pbeinfo';
    public enum CART_ACTION {
        ADD,
        REMOVE
    }
    /*****************************************************************************
     * @MethodName:      fetchProducts
     * @Description:    Fetches products with pagination, filtering, and search capabilities.
     *                   Supports family filtering and search by name, product code, or description.
     *********************************************************************************/
    @AuraEnabled(cacheable=true)
    public static ProductPage fetchProducts(Integer pageNumber, Integer pageSize, String searchQuery, List<String> selectedFamilies, String sortField, String sortDir) {
        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 12;
        Integer offsetRows = (pageNumber - 1) * pageSize;
        String likePattern;
        Boolean hasSearch = false;
        Integer total = 0;

        if (String.isNotBlank(searchQuery)) {
            hasSearch = true;
            searchQuery = searchQuery.trim();
            likePattern = '%' + String.escapeSingleQuotes(searchQuery) + '%';
        }

        // Use static ORDER BY to avoid dynamic SOQL complications (original used Name ASC).
        List<Product2> products;

        if (selectedFamilies != null && !selectedFamilies.isEmpty()) {
            if (hasSearch) {
                products = [
                    SELECT 
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
                        :offsetRows
                ];
            } else {
                products = [
                    SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE 
                        IsActive = true
                      AND 
                        Family IN :selectedFamilies
                    ORDER BY 
                        Name ASC
                    LIMIT 
                        :pageSize
                    OFFSET 
                        :offsetRows
                ];
            }

            if (hasSearch) {
                total = (Integer) Database.countQuery(
                    'SELECT COUNT() FROM Product2 WHERE IsActive = true AND (Name LIKE \'' + String.escapeSingleQuotes(searchQuery) + '\' OR ProductCode LIKE \'' + String.escapeSingleQuotes(searchQuery) + '\' OR Description LIKE \'' + String.escapeSingleQuotes(searchQuery) + '\') AND Family IN (' + buildQuotedList(selectedFamilies) + ')'
                );
            } else {
                total = (Integer) Database.countQuery(
                    'SELECT COUNT() FROM Product2 WHERE IsActive = true AND Family IN (' + buildQuotedList(selectedFamilies) + ')'
                );
            }
        } else {
            if (hasSearch) {
                products = [
                    SELECT 
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
                        :offsetRows
                ];
            } else {
                products = [
                    SELECT Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM Product2
                    WHERE IsActive = true
                    ORDER BY Name ASC
                    LIMIT :pageSize
                    OFFSET :offsetRows
                ];
            }

            total = [SELECT COUNT() FROM Product2 WHERE IsActive = true];
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

        // If SKUs exist, attach PricebookEntry info from current org
        if (!skuToProductId.isEmpty()) {
            List<String> skuList = new List<String>(skuToProductId.keySet());
            try {
                List<PricebookEntry> pbeList = [
                    SELECT Id, UnitPrice, Pricebook2Id, Pricebook2.Name, IsActive, Product2Id, Product2.StockKeepingUnit
                    FROM PricebookEntry
                    WHERE Product2.StockKeepingUnit IN :skuList
                      AND IsActive = true
                    ORDER BY CreatedDate DESC
                ];
                // group by Product2Id
                Map<Id, List<PricebookEntry>> pbeByProd = new Map<Id, List<PricebookEntry>>();
                for (PricebookEntry pb : pbeList) {
                    if (!pbeByProd.containsKey(pb.Product2Id)) pbeByProd.put(pb.Product2Id, new List<PricebookEntry>());
                    pbeByProd.get(pb.Product2Id).add(pb);
                }
                // attach PBEs to DTOs
                for (ProductDTO dto : dtos) {
                    if (!String.isBlank(dto.sku)) {
                        Id prodId = skuToProductId.get(dto.sku.trim());
                        if (prodId != null && pbeByProd.containsKey(prodId)) {
                            List<PricebookEntry> pbList = pbeByProd.get(prodId);
                            for (PricebookEntry pb : pbList) {
                                ProductPBEInfo pi = new ProductPBEInfo();
                                pi.pricebookEntryId = pb.Id;
                                pi.pricebookId = pb.Pricebook2Id;
                                pi.pricebookName = (pb.Pricebook2 != null) ? pb.Pricebook2.Name : null;
                                pi.unitPrice = pb.UnitPrice;
                                pi.isActive = pb.IsActive;
                                pi.productId = pb.Product2Id;
                                pi.productName = pb.Product2 != null ? pb.Product2.Name : null;
                                pi.sku = pb.Product2 != null ? pb.Product2.StockKeepingUnit : null;
                                pi.isFetchedFromOrg = true;
                                dto.pbes.add(pi);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('fetchProducts: PBE lookup failed: ' + e.getMessage());
            }
        }

        return new ProductPage(dtos, total, pageNumber, pageSize);
    }

    /*****************************************************************************
     * @MethodName:      fetchProductFamilies
     * @Description:    Fetches all distinct product families from the database.
     *********************************************************************************/
    @AuraEnabled(cacheable=true)
    public static List<String> fetchProductFamilies() {
        List<String> sortedFamilies = new List<String>();
        try {
            for (AggregateResult ar : [SELECT Family FROM Product2 WHERE Family != null GROUP BY Family ORDER BY Family]) {
                sortedFamilies.add((String) ar.get('Family'));
            }
        } catch (Exception e) {
            System.debug('fetchProductFamilies failed: ' + e.getMessage());
        }
        return sortedFamilies;
    }

    /*****************************************************************************
     * @MethodName:      caller
     * @Description:    Retrieves product PBE information, first checking remote endpoint and falling back to local pricebook entries.
     *********************************************************************************/
    @AuraEnabled
    public static ProductPBEInfo caller(Id recordId, Id accountId) {
        if (recordId == null) return null;
        Product2 prod;
        try {
            prod = [
                SELECT Id, Name, StockKeepingUnit, ExternalId
                FROM Product2
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Product query failed: ' + e.getMessage());
            return null;
        }
        if (prod == null) return null;

        ProductPBEInfo result = new ProductPBEInfo();
        result.productId = prod.Id;
        result.productName = prod.Name;
        result.sku = prod.StockKeepingUnit;
        result.isFetchedFromOrg = false;

        Decimal unitPriceFromRemote = null;
        Boolean remoteSucceeded = false;
        String externalId = prod.ExternalId != null ? String.valueOf(prod.ExternalId).trim() : null;

        if (String.isNotBlank(externalId)) {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'text/plain');
            req.setHeader('Accept', 'application/json');
            req.setBody(externalId);
            try {
                HttpResponse resp = http.send(req);
                Integer status = resp.getStatusCode();
                String body = resp.getBody();
                if (status >= 200 && status < 300) {
                    if (body == 'null') {
                        unitPriceFromRemote = null;
                    } else {
                        Object parsed = JSON.deserializeUntyped(body);
                        if (parsed != null) {
                            try {
                                unitPriceFromRemote = Decimal.valueOf(String.valueOf(parsed));
                            } catch (Exception ex2) {
                                unitPriceFromRemote = null;
                            }
                        }
                    }
                    remoteSucceeded = true;
                } else {
                    System.debug('caller - remote returned non-2xx: ' + status + ' body:' + body);
                }
            } catch (Exception e) {
                remoteSucceeded = false;
                System.debug('caller - remote call failed: ' + e.getMessage());
            }
        }

        if (remoteSucceeded && unitPriceFromRemote != null) {
            result.unitPrice = unitPriceFromRemote;
            result.isFetchedFromOrg = false;
            result.isActive = true;
            return result;
        }

        try {
            PricebookEntry pb = [
                SELECT Id, UnitPrice, Pricebook2Id, Pricebook2.Name, IsActive
                FROM PricebookEntry
                WHERE Product2Id = :recordId
                  AND IsActive = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (pb != null) {
                result.pricebookEntryId = pb.Id;
                result.pricebookId = pb.Pricebook2Id;
                result.pricebookName = (pb.Pricebook2 != null) ? pb.Pricebook2.Name : null;
                result.unitPrice = pb.UnitPrice;
                result.isActive = pb.IsActive;
            }
        } catch (Exception e) {
            System.debug('PricebookEntry fallback query failed: ' + e.getMessage());
        }

        result.isFetchedFromOrg = true;
        return result;
    }
    /*****************************************************************************
     * @MethodName:      getAccountName
     * @Description:    Retrieves the name of an account by its ID.
     *********************************************************************************/
    @AuraEnabled(cacheable=true)
    public static String getAccountName(Id recordId) {
        if (recordId == null) return null;
        try {
            if (recordId.getSObjectType() == Account.SObjectType) {
                Account acc = [SELECT Name FROM Account WHERE Id = :recordId LIMIT 1];
                return acc != null ? acc.Name : null;
            }
        } catch (Exception e) {
            System.debug('getAccountName failed: ' + e.getMessage());
        }
        return null;
    }
    /*****************************************************************************
     * @MethodName:      OrderWrapper
     * @Description:    Wrapper class for order and its items to support LWC data binding.
     *********************************************************************************/
    public class OrderWrapper {
        @AuraEnabled public Order order;
        @AuraEnabled public List<OrderItem> orderItems;
    }
    /*****************************************************************************
     * @MethodName:      getOrdersForAccount
     * @Description:    Retrieves all draft orders for a given account along with their items.
     *********************************************************************************/
    @AuraEnabled(cacheable=true)
    public static List<OrderWrapper> getOrdersForAccount(Id accountId) {
        if (accountId == null) return new List<OrderWrapper>();
        List<OrderWrapper> wrappers = new List<OrderWrapper>();
        try {
            List<Order> orders = [
                SELECT Id, Name, Status, TotalAmount, CreatedDate
                FROM Order
                WHERE AccountId = :accountId
                  AND Status = 'Draft'
                ORDER BY CreatedDate DESC
            ];
            for (Order o : orders) {
                OrderWrapper wrapper = new OrderWrapper();
                wrapper.order = o;
                wrapper.orderItems = [
                    SELECT Id, Product2Id, Product2.Name, Product2.ProductCode, Product2.Description, Product2.Family, Product2.IsActive, Product2.QuantityUnitOfMeasure, Product2.StockKeepingUnit, Product2.ProductImage__c, Quantity, UnitPrice, TotalPrice
                    FROM OrderItem
                    WHERE OrderId = :o.Id
                ];
                wrappers.add(wrapper);
            }
        } catch (Exception e) {
            System.debug('getOrdersForAccount failed: ' + e.getMessage());
        }
        return wrappers;
    }
    /*****************************************************************************
     * @MethodName:      removeOrderItem
     * @Description:    Removes an order item from an order by its ID.
     *********************************************************************************/
    @AuraEnabled
    public static void removeOrderItem(Id orderItemId) {
        if (orderItemId == null) return;
        try {
            Database.delete(new List<OrderItem>{ new OrderItem(Id = orderItemId) }, AccessLevel.USER_MODE);
        } catch (Exception e) {
            System.debug('removeOrderItem failed: ' + e.getMessage());
        }
    }
    /*****************************************************************************
     * @MethodName:      addToOrder
     * @Description:    Adds a product to a customer's draft order or updates quantity if item already exists.
     *********************************************************************************/
    @AuraEnabled
    public static void addToOrder(Id accountId, Id productId, Decimal price, Integer quantity) {
        if (accountId == null || productId == null || price == null || quantity == null || quantity <= 0) return;
        try {
            List<Order> draftOrders = [SELECT Id, Pricebook2Id FROM Order WHERE AccountId = :accountId AND Status = 'Draft' LIMIT 1];
            Order targetOrder;

            if (draftOrders.isEmpty()) {
                Id stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
                targetOrder = new Order(
                    AccountId = accountId,
                    Status = 'Draft',
                    Pricebook2Id = stdPbId,
                    EffectiveDate = Date.today()
                );
                Database.SaveResult srOrder = Database.insert(targetOrder, false);
                if (!srOrder.isSuccess()) {
                    throw new AuraHandledException('Failed to create draft order: ' + srOrder.getErrors()[0].getMessage());
                }
            } else {
                targetOrder = draftOrders[0];
            }

            PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :targetOrder.Pricebook2Id AND Product2Id = :productId AND IsActive = true LIMIT 1];

            List<OrderItem> existingItems = [SELECT Id, Quantity FROM OrderItem WHERE OrderId = :targetOrder.Id AND Product2Id = :productId LIMIT 1];
            if (existingItems.isEmpty()) {
                OrderItem newItem = new OrderItem(
                    OrderId = targetOrder.Id,
                    PricebookEntryId = pbe.Id,
                    Product2Id = productId,
                    UnitPrice = price,
                    Quantity = quantity
                );
                Database.SaveResult srItem = Database.insert(newItem, false);
                if (!srItem.isSuccess()) {
                    throw new AuraHandledException('Failed to add order item: ' + srItem.getErrors()[0].getMessage());
                }
            } else {
                OrderItem existingItem = existingItems[0];
                existingItem.Quantity = (existingItem.Quantity == null ? 0 : existingItem.Quantity) + quantity;
                existingItem.PricebookEntryId = pbe.Id;
                Database.SaveResult srUpdate = Database.update(existingItem, false);
                if (!srUpdate.isSuccess()) {
                    throw new AuraHandledException('Failed to update order item: ' + srUpdate.getErrors()[0].getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('addToOrder failed: ' + e.getMessage());
            throw e;
        }
    }
    /*****************************************************************************
     * @ClassName:      ProductDTO
     * @Description:    Data Transfer Object for product information used in LWC components.
     *********************************************************************************/
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

    /*****************************************************************************
     * @ClassName:      ProductPBEInfo
     * @Description:    Data Transfer Object for product pricebook entry information.
     *********************************************************************************/
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

    /*****************************************************************************
     * ClassName:       ProductPage
     * @Description:    Wrapper class for paginated product data to support LWC pagination controls.
     *********************************************************************************/
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
    /*****************************************************************************
     * buildQuotedList
     * @Description:    Helper method to build a quoted, escaped list for dynamic SOQL queries.
     *                   Helper: build quoted, escaped list for dynamic COUNT() queries (used only for COUNT branch).
     *                     Input values are escaped via String.escapeSingleQuotes.
     *********************************************************************************/
    private static String buildQuotedList(List<String> values) {
        if (values == null || values.isEmpty()) return '\'\'';
        List<String> q = new List<String>();
        for (String v : values) {
            if (v == null) continue;
            q.add('\'' + String.escapeSingleQuotes(v) + '\'');
        }
        return String.join(q, ',');
    }
}

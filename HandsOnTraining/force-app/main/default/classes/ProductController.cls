public with sharing class ProductController {
    @AuraEnabled(cacheable=true)
    public static ProductPage fetchProducts(Integer pageNumber, Integer pageSize, String searchQuery, String sortField, String sortDir) {
        if (pageNumber == null) pageNumber = 1;
        if (pageSize == null) pageSize = 12;
        Integer offsetRows = (pageNumber - 1) * pageSize;
        String likePattern;
        Boolean hasSearch = false;
        if (String.isNotBlank(searchQuery)) {
            hasSearch = true;
            likePattern = '%' + searchQuery + '%';
        }
        String orderBy = 'Name';
        String orderDir = 'ASC';
        if (String.isNotBlank(sortField)) orderBy = sortField;
        if (String.isNotBlank(sortDir)) orderDir = sortDir.toUpperCase() == 'DESC' ? 'DESC' : 'ASC';
        List<Product2> products;
        if (hasSearch) {
            products = [
                SELECT 
                    Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit,
                       (SELECT 
                            Pricebook2Id, UnitPrice 
                        FROM 
                            PricebookEntries 
                        WHERE 
                            IsActive = true 
                        LIMIT 1)
                FROM 
                    Product2
                WHERE 
                    IsActive = true
                  AND 
                    (Name 
                        LIKE 
                            :likePattern 
                        OR 
                            ProductCode 
                        LIKE 
                            :likePattern
                        OR 
                            Description 
                        LIKE 
                            :likePattern)
                ORDER BY
                   Name ASC
                LIMIT :pageSize
                OFFSET :offsetRows
            ];
        } else {
            products = [
                SELECT 
                    Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit,
                    (SELECT 
                        Pricebook2Id, UnitPrice 
                    FROM 
                        PricebookEntries 
                    WHERE 
                        IsActive = true 
                    LIMIT 
                        1)
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
                    :offsetRows
            ];
        }
        Integer total = [SELECT 
                            count() 
                        FROM 
                            Product2 
                        WHERE 
                            IsActive = true];

        List<ProductDTO> dtos = new List<ProductDTO>();
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
            if (p.PricebookEntries != null && p.PricebookEntries.size() > 0) {
                PricebookEntry pbe = p.PricebookEntries[0];
                dto.price = pbe.UnitPrice;
                dto.pricebookId = pbe.Pricebook2Id;
            }
            dtos.add(dto);
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
        @AuraEnabled public Decimal price;
        @AuraEnabled public Id pricebookId;
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
}

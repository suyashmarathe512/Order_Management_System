/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      ProductController
 * @Description:     This class is used to fetch the products from the server org.
 *                    It also allowed the POST method to accept the product Id 
 *                     and return the PBE for the product.
 *                    It is a contoller of LWC.
 ***********************************************************************************/
public with sharing class ProductController{
    private static final String NAMED_CREDENTIAL_ENDPOINT='callout:ServerOrg/services/apexrest/product/pbeinfo';
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      fetchProducts
 * @params :        pageNumber, pageSize, searchQuery, selectedFamilies, sortField, sortDir
 * @Description:     This method is used to fetch the products from the server org.
 *                    It also used to Sort the product based on the family.
 *                    It helps the LWC with the pagination and searchquery.
 ***********************************************************************************/
    @AuraEnabled
    public static ProductPage fetchProducts(Integer pageNumber, Integer pageSize, String searchQuery, List<String> selectedFamilies, String sortField, String sortDir){
        if(pageNumber == null) pageNumber=1;
        if(pageSize == null) pageSize=12;
        Integer offsetRows =(pageNumber - 1) * pageSize;
        String likePattern;
        Boolean hasSearch=false;
        Integer total=0;
        if(String.isNotBlank(searchQuery)){
            hasSearch=true;
            likePattern='%' + searchQuery + '%';
        }
        List<Product2> products;
        if(selectedFamilies != null && !selectedFamilies.isEmpty()){
            if(hasSearch){
                products=[SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE 
                        IsActive=true
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
            }else{
                products=[SELECT 
                                Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                            FROM 
                                Product2
                            WHERE    
                                IsActive=true
                            AND 
                                Family 
                            IN 
                                :selectedFamilies
                            ORDER BY 
                                Name 
                            ASC
                            LIMIT   
                                :pageSize 
                            OFFSET 
                                :offsetRows];
            }
            if(hasSearch){
                Integer totalFiltered=[SELECT 
                                            COUNT() 
                                        FROM 
                                            Product2 
                                        WHERE 
                                            IsActive=true 
                                        AND 
                                        (Name LIKE :likePattern OR ProductCode LIKE :likePattern OR Description LIKE :likePattern) 
                                        AND 
                                            Family 
                                        IN 
                                            :selectedFamilies];
                total=totalFiltered;
            }else{
                Integer totalFiltered=[SELECT 
                                            COUNT() 
                                        FROM 
                                            Product2 
                                        WHERE 
                                            IsActive=true 
                                        AND 
                                            Family 
                                        IN 
                                            :selectedFamilies];
                total=totalFiltered;
            }
        }else{
            if(hasSearch){
                products=[SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE 
                        IsActive=true
                     AND 
                        (Name LIKE :likePattern OR ProductCode LIKE :likePattern OR Description LIKE :likePattern)
                    ORDER BY 
                        Name ASC
                    LIMIT 
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            }else{
                products=[SELECT 
                        Id, Name, ProductCode, Description, Family, IsActive, QuantityUnitOfMeasure, StockKeepingUnit, ProductImage__c
                    FROM 
                        Product2
                    WHERE    
                        IsActive=true
                    ORDER BY 
                        Name 
                    ASC
                    LIMIT   
                        :pageSize 
                    OFFSET 
                        :offsetRows];
            }
            Integer totalFiltered=[SELECT 
                                        COUNT() 
                                    FROM 
                                        Product2 
                                    WHERE 
                                        IsActive=true];
            total=totalFiltered;
        }
        List<ProductDTO> dtos=new List<ProductDTO>();
        Map<String, Id> skuToProductId=new Map<String, Id>();
        for(Product2 p : products){
            ProductDTO dto=new ProductDTO();
            dto.id=p.Id;
            dto.name=p.Name;
            dto.productCode=p.ProductCode;
            dto.description=p.Description;
            dto.family=p.Family;
            dto.isActive=p.IsActive;
            dto.sku=p.StockKeepingUnit;
            dto.uom=p.QuantityUnitOfMeasure;
            dto.pbes=new List<ProductPBEInfo>();
            if(!String.isBlank(dto.sku)) skuToProductId.put(dto.sku.trim(), p.Id);
            dtos.add(dto);
        }
        if(skuToProductId.isEmpty()) return new ProductPage(dtos, total, pageNumber, pageSize);
        List<String> skuList=new List<String>(skuToProductId.keySet());
        return new ProductPage(dtos, total, pageNumber, pageSize);
    }
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      ProductDTO
 * @Description:     This wrapper class is used to return the product details.
 ***********************************************************************************/
    public class ProductDTO{
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
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      ProductPBEInfo
 * @Description:     This wrapper class is used to return the pricebook entry details.
 ***********************************************************************************/
    public class ProductPBEInfo{
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
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      ProductPage
 * @Description:     This wrapper class is used to return the pagination details.
 ***********************************************************************************/
    public class ProductPage{
        @AuraEnabled public List<ProductDTO> records;
        @AuraEnabled public Integer totalSize;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      ProductPage
 * @params :        recs, total, pageNum, pSize
 * @Description:     This method is used to map the pagination details.
 ***********************************************************************************/
        public ProductPage(List<ProductDTO> recs, Integer total, Integer pageNum, Integer pSize){
            this.records=recs;
            this.totalSize=total;
            this.pageNumber=pageNum;
            this.pageSize=pSize;
        }
    }
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      fetchProductFamilies
 * @Description:     This method is used to fetch the product families from the server org.
 ***********************************************************************************/
    @AuraEnabled
    public static List<String> fetchProductFamilies(){
        Set<String> families=new Set<String>();
        List<Product2> products=[SELECT 
                                        Family 
                                    FROM   
                                        Product2 
                                    WHERE 
                                        Family != null 
                                    ORDER BY 
                                        Family];
        for(Product2 product : products){
            families.add(product.Family);
        }
        List<String> sortedFamilies=new List<String>(families);
        sortedFamilies.sort();
        return sortedFamilies;
    }
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      caller
 * @param :        recordId
 * @Description:     This method is used to fetch the product details from the server org.
 ***********************************************************************************/
   @AuraEnabled
    public static ProductPBEInfo caller(Id recordId){
        if(recordId == null) return null;
        Product2 prod;
        try{
            prod=[
                SELECT 
                    Id, Name, StockKeepingUnit, ExternalId
                FROM 
                    Product2
                WHERE 
                    Id=:recordId
                LIMIT 1
            ];
        }catch(Exception e){
            System.debug('Product query failed: ' + e.getMessage());
            return null;
        }
        if(prod == null) return null;
        ProductPBEInfo result=new ProductPBEInfo();
        result.productId=prod.Id;
        result.productName=prod.Name;
        result.sku=prod.StockKeepingUnit;
        result.isFetchedFromOrg=false;
        Decimal unitPriceFromRemote=null;
        Boolean remoteSucceeded=false;
        String externalId=prod.ExternalId != null ? String.valueOf(prod.ExternalId).trim() : null;
        if(String.isNotBlank(externalId)){
            Http http=new Http();
            HttpRequest req=new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'text/plain');
            req.setHeader('Accept', 'application/json');
            req.setBody(externalId); 
            try{
                HttpResponse resp=http.send(req);
                Integer status=resp.getStatusCode();
                String body=resp.getBody();
                if(status >= 200 && status < 300){
                    if(body == 'null'){
                        unitPriceFromRemote=null;
                    }else{
                        Object parsed=JSON.deserializeUntyped(body); 
                        unitPriceFromRemote=Decimal.valueOf(String.valueOf(parsed));
                    }
                    remoteSucceeded=true;
                }
            }catch(Exception e){
                remoteSucceeded=false;
            }
        }
        if(remoteSucceeded && unitPriceFromRemote != null){
            result.unitPrice=unitPriceFromRemote;
            result.isFetchedFromOrg=false;
            result.isActive=true;
            return result;
        }
        try{
            PricebookEntry pb=[
                SELECT 
                    Id, UnitPrice, Pricebook2Id, Pricebook2.Name, IsActive
                FROM 
                    PricebookEntry
                WHERE 
                    Product2Id=:recordId
                AND 
                    IsActive=true
                ORDER BY
                     CreatedDate DESC
                LIMIT 1
            ];
            if(pb != null){
                result.pricebookEntryId=pb.Id;
                result.pricebookId=pb.Pricebook2Id;
                result.pricebookName =(pb.Pricebook2 != null) ? pb.Pricebook2.Name : null;
                result.unitPrice=pb.UnitPrice;
                result.isActive=pb.IsActive;
            }
        }catch(Exception e){
            System.debug('PricebookEntry fallback query failed: ' + e.getMessage());
        }
        result.isFetchedFromOrg=true;
        return result;
    }
}
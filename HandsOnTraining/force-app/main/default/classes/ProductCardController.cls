/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      ProductCardController
 * @Description:    Card-scoped product actions: fetch PBE info for a single product, etc.
 ***********************************************************************************/
public with sharing class ProductCardController{

    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:ServerOrg/services/apexrest/product/pbeinfo';

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
     * @ClassName:       ProductPage
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

    /**
     * Retrieves product PBE information for a single product. Attempts remote lookup via Named Credential
     * using Product2.ExternalId, falls back to latest active PricebookEntry in the org.
     */
    @AuraEnabled
    public static ProductCardController.ProductPBEInfo caller(Id recordId, Id accountId) {
        if (recordId == null) return null;
        Product2 prod;
        try {
            prod = [
                SELECT 
                    Id, Name, StockKeepingUnit, ExternalId
                FROM 
                    Product2
                WHERE 
                    Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('ProductCardController.caller - Product query failed: ' + e.getMessage());
            return null;
        }
        if (prod == null) return null;
        ProductCardController.ProductPBEInfo result = new ProductCardController.ProductPBEInfo();
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
                    System.debug('ProductCardController.caller - remote returned non-2xx: ' + status + ' body:' + body);
                }
            } catch (Exception e) {
                remoteSucceeded = false;
                System.debug('ProductCardController.caller - remote call failed: ' + e.getMessage());
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
                SELECT 
                    Id, UnitPrice, Pricebook2Id, Pricebook2.Name, IsActive
                FROM 
                    PricebookEntry
                WHERE 
                    Product2Id = :recordId
                  AND 
                    IsActive = true
                ORDER BY 
                    CreatedDate DESC
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
            System.debug('ProductCardController.caller - PricebookEntry fallback query failed: ' + e.getMessage());
        }
        result.isFetchedFromOrg = true;
        return result;
    }
}

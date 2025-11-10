@RestResource(urlMapping='/products/*')
global class ProductService {
    global class ProductWrapper {
        global String externalId;
        global String name;
        global String productCode;
        global String description;
        global String displayUrl;
        global String family;
        global Boolean isActive;
        global String sku;
        global String quantityUnitOfMeasure;
        global DateTime createdDate;
        global DateTime lastModifiedDate;
        global List<PricebookEntryWrapper> pricebookEntries;
        global ProductWrapper(Product2 prod, List<PricebookEntry> pbes) {
            this.externalId = prod.ProductCode;
            this.name = prod.Name;
            this.productCode = prod.ProductCode;
            this.description = prod.Description;
            this.displayUrl = prod.DisplayUrl;
            this.family = prod.Family;
            this.isActive = prod.IsActive;
            this.sku = prod.StockKeepingUnit;
            this.quantityUnitOfMeasure = prod.QuantityUnitOfMeasure;
            this.createdDate = prod.CreatedDate;
            this.lastModifiedDate = prod.LastModifiedDate;
            this.pricebookEntries = new List<PricebookEntryWrapper>();
            if (pbes != null) {
                for (PricebookEntry pbe : pbes) {
                    this.pricebookEntries.add(new PricebookEntryWrapper(pbe));
                }
            }
        }
    }
    global class PricebookEntryWrapper {
        global String pricebookEntryId;
        global String pricebook2Id;
        global String pricebook2Name;
        global Decimal unitPrice;
        global Boolean isActive;
        global Boolean useStandardPrice;
        global DateTime createdDate;
        global DateTime lastModifiedDate;

        global PricebookEntryWrapper(PricebookEntry pbe) {
            this.pricebookEntryId = pbe.Id;
            this.pricebook2Id = pbe.Pricebook2Id;
            this.pricebook2Name = pbe.Pricebook2.Name;
            this.unitPrice = pbe.UnitPrice;
            this.isActive = pbe.IsActive;
            this.useStandardPrice = pbe.UseStandardPrice;
            this.createdDate = pbe.CreatedDate;
            this.lastModifiedDate = pbe.LastModifiedDate;
        }
    }
    global class ProductResponse {
        global List<ProductWrapper> products;
        global Integer count;
        global String status;

        global ProductResponse(List<ProductWrapper> prods, String stat) {
            this.products = prods;
            this.count = (prods != null) ? prods.size() : 0;
            this.status = stat;
        }
    }
    @HttpGet
    global static ProductResponse getProducts() {
        RestRequest req = RestContext.request;
        String externalIdsParam = req.params.get('externalIds');

        if (String.isNotBlank(externalIdsParam)) {
            List<String> externalIdList = new List<String>();
            for (String id : externalIdsParam.split(',')) {
                String trimmedId = id.trim();
                if (String.isNotBlank(trimmedId)) {
                    externalIdList.add(trimmedId);
                }
            }
            if (externalIdList.isEmpty()) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Empty external IDs list');
            }
            if (externalIdList.size() > 100) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Too many external IDs (max 100)');
            }
            try {
                List<Product2> products = [SELECT
                                                Id, Name, ProductCode, Description, DisplayUrl, Family, IsActive, StockKeepingUnit, QuantityUnitOfMeasure,
                                                (SELECT Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive, UseStandardPrice
                                            FROM
                                                PricebookEntries
                                            ORDER BY
                                                Pricebook2.Name)
                                           FROM
                                                Product2
                                            WHERE
                                                ProductCode
                                            IN
                                                :externalIdList
                                            ORDER BY
                                                Name];
                if (products.isEmpty()) {
                    RestContext.response.statusCode = 404;
                    return new ProductResponse(null, 'Not Found: No products found for the provided external IDs');
                }

                List<ProductWrapper> productWrappers = new List<ProductWrapper>();
                for (Product2 prod : products) {
                    productWrappers.add(new ProductWrapper(prod, prod.PricebookEntries));
                }
                return new ProductResponse(productWrappers, 'Success');
            } catch (QueryException e) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Invalid external IDs');
            } catch (Exception e) {
                RestContext.response.statusCode = 500;
                return new ProductResponse(null, 'Internal Server Error');
            }
        } else {
            try {
                List<Product2> products = [SELECT
                                                Id, Name, ProductCode, Description, DisplayUrl, Family, IsActive, StockKeepingUnit, QuantityUnitOfMeasure,
                                                (SELECT Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive, UseStandardPrice
                                                FROM
                                                    PricebookEntries
                                                ORDER BY
                                                    Pricebook2.Name)
                                            FROM
                                                Product2
                                            ORDER BY
                                                Name
                                            LIMIT
                                                50];

                List<ProductWrapper> productWrappers = new List<ProductWrapper>();
                for (Product2 prod : products) {
                    productWrappers.add(new ProductWrapper(prod, prod.PricebookEntries));
                }

                return new ProductResponse(productWrappers, 'Success');
            } catch (Exception e) {
                RestContext.response.statusCode = 500;
                return new ProductResponse(null, 'Internal Server Error');
            }
        }
    }
}

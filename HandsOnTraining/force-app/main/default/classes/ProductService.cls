@RestResource(urlMapping='/products/*')
global class ProductService {
    global class ProductWrapper {
        global String productId;
        global String name;
        global String productCode;
        global String description;
        global String family;
        global Boolean isActive;
        global DateTime createdDate;
        global DateTime lastModifiedDate;
        global List<PricebookEntryWrapper> pricebookEntries;
        global ProductWrapper(Product2 prod, List<PricebookEntry> pbes) {
            this.productId = prod.ProductId__c;
            this.name = prod.Name;
            this.productCode = prod.ProductCode;
            this.description = prod.Description;
            this.family = prod.Family;
            this.isActive = prod.IsActive;
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
        String productIdsParam = req.params.get('productIds');

        if (String.isNotBlank(productIdsParam)) {
            List<String> productIdList = new List<String>();
            for (String id : productIdsParam.split(',')) {
                String trimmedId = id.trim();
                if (String.isNotBlank(trimmedId)) {
                    productIdList.add(trimmedId);
                }
            }
            if (productIdList.isEmpty()) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Empty product IDs list');
            }
            if (productIdList.size() > 100) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Too many product IDs (max 100)');
            }try {
                List<Product2> products = [SELECT 
                                                Id, ProductId__c, Name, ProductCode, Description, Family, IsActive,
                                                (SELECT Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive, UseStandardPrice
                                            FROM 
                                                PricebookEntries 
                                            ORDER BY 
                                                Pricebook2.Name)
                                           FROM 
                                                Product2 
                                            WHERE 
                                                ProductId__c
                                            IN 
                                                :productIdList 
                                            ORDER BY 
                                                Name];
                if (products.isEmpty()) {
                    RestContext.response.statusCode = 404;
                    return new ProductResponse(null, 'Not Found: No products found for the provided IDs');
                }

                List<ProductWrapper> productWrappers = new List<ProductWrapper>();
                for (Product2 prod : products) {
                    productWrappers.add(new ProductWrapper(prod, prod.PricebookEntries));
                }
                return new ProductResponse(productWrappers, 'Success');
            } catch (QueryException e) {
                RestContext.response.statusCode = 400;
                return new ProductResponse(null, 'Bad Request: Invalid product IDs');
            } catch (Exception e) {
                RestContext.response.statusCode = 500;
                return new ProductResponse(null, 'Internal Server Error');
            }
        } else {
            try {
                List<Product2> products = [SELECT 
                                                Id, ProductId__c, Name, ProductCode, Description, Family, IsActive,
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

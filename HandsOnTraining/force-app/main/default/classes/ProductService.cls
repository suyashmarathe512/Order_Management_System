/***************************************************************************************************
* @Author:        CRM Developer
* @className:     ProductService
* @Description:   REST service to expose Product2 and related PricebookEntry data as JSON.
***************************************************************************************************/
@RestResource(urlMapping='/Products')
global with sharing class ProductService {
/************************************************************************************************
 * @author         CRM Developer
 * @methodname     getProductsWithPBE
 * @description    Handles HTTP GET. Queries Product2 with related PricebookEntries and returns a JSON payload.
 ***********************************************************************************************/
@HttpGet
global static void getProductsWithPBE() {
        RestResponse res = RestContext.response;
        ResponseWrapper responseWrapper = new ResponseWrapper();
        responseWrapper.status = 'ERROR';
        responseWrapper.message = 'Unknown error';
        responseWrapper.products = new List<ProductWrapper>();
        try {
            List<Product2> products = [
                SELECT
                    Id,Name,ProductCode,Description,IsActive,Family,StockKeepingUnit,
                    (SELECT
                        Id,UnitPrice,IsActive,UseStandardPrice,Product2Id,Pricebook2.Name
                     FROM 
                        PricebookEntries)
                FROM 
                    Product2
            ];

            if (products != null && !products.isEmpty()) {
                for (Product2 p : products) {
                    ProductWrapper pw = new ProductWrapper();
                    pw.Id = p.Id;
                    pw.Name = p.Name;
                    pw.ProductCode = p.ProductCode;
                    pw.Description = p.Description;
                    pw.IsActive = (p.IsActive == null) ? false : p.IsActive;
                    pw.Family = p.Family;
                    pw.StockKeepingUnit = p.StockKeepingUnit;
                    pw.pricebookEntries = new List<PricebookEntryWrapper>();

                    if (p.PricebookEntries != null && !p.PricebookEntries.isEmpty()) {
                        for (PricebookEntry pe : p.PricebookEntries) {
                            PricebookEntryWrapper pbe = new PricebookEntryWrapper();
                            pbe.Id = pe.Id;
                            pbe.UnitPrice = pe.UnitPrice;
                            pbe.IsActive = (pe.IsActive == null) ? false : pe.IsActive;
                            pbe.UseStandardPrice = (pe.UseStandardPrice == null) ? false : pe.UseStandardPrice;
                            pbe.Product2Id = pe.Product2Id;
                            pbe.PricebookName = (pe.Pricebook2 != null) ? pe.Pricebook2.Name : null;

                            pw.pricebookEntries.add(pbe);
                        }
                    }

                    responseWrapper.products.add(pw);
                }
            }

            responseWrapper.status = 'OK';
            responseWrapper.message = 'Success';
            String jsonString = JSON.serialize(responseWrapper);
            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json; charset=UTF-8');
            res.responseBody = Blob.valueOf(jsonString);
        } catch (Exception ex) {
            responseWrapper.status = 'ERROR';
            responseWrapper.message = 'Exception: ' + ex.getMessage();
            String errJson = JSON.serialize(responseWrapper);
            res.statusCode = 500;
            res.addHeader('Content-Type', 'application/json; charset=UTF-8');
            res.responseBody = Blob.valueOf(errJson);
        }
    }
/**************************************************************************************
 * @author         CRM Developer
 * @classname      ProductService.ResponseWrapper
 * @description    Top-level API response wrapper carrying status, message and product list.
 *************************************************************************************/
global class ResponseWrapper {
        public String status;
        public String message;
        public List<ProductWrapper> products;
    }
/**************************************************************************************
 * @author         CRM Developer
 * @classname      ProductService.ProductWrapper
 * @description    Represents a simplified Product2 payload returned by this API.
 *************************************************************************************/
global class ProductWrapper {
        public Id Id;
        public String Name;
        public String ProductCode;
        public String Description;
        public Boolean IsActive;
        public String Family;
        public String StockKeepingUnit;
        public List<PricebookEntryWrapper> pricebookEntries;
    }
/**************************************************************************************
 * @author         CRM Developer
 * @classname      ProductService.PricebookEntryWrapper
 * @description    Represents a simplified PricebookEntry payload with pricebook name reference.
 *************************************************************************************/
global class PricebookEntryWrapper {
        public Id Id;
        public Decimal UnitPrice;
        public Boolean IsActive;
        public Boolean UseStandardPrice;
        public Id Product2Id;
        public String PricebookName;
    }
}

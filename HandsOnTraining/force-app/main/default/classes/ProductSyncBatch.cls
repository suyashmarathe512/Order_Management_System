global with sharing class ProductSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public class ProductWrapper {
        public String name;
        public String productCode;
        public String description;
        public String family;
        public Boolean isActive;
        public String recordId;
        public String sku;
        public String quantityUnitOfMeasure;
        public List<PricebookEntryWrapper> pricebookEntries;
    }
    public class PricebookEntryWrapper {
        public String pricebook2Id;
        public String pricebook2Name;
        public Decimal unitPrice;
        public Boolean isActive;
        public Boolean useStandardPrice;
    }
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Name, ProductCode, StockKeepingUnit, Description, Family, IsActive, QuantityUnitOfMeasure, ' +
            '(SELECT Id, Pricebook2Id, Pricebook2.Name, UnitPrice, IsActive, UseStandardPrice FROM PricebookEntries) ' +
            'FROM Product2 WITH USER_MODE ORDER BY Id';
        return Database.getQueryLocator(query);
    }
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<ProductWrapper> payload = new List<ProductWrapper>();
        for (SObject sobj : scope) {
            Product2 p = (Product2)sobj;
            ProductWrapper pw = new ProductWrapper();
            pw.name = p.Name;
            pw.productCode = p.ProductCode;
            pw.description = p.Description;
            pw.family = p.Family;
            pw.isActive = p.IsActive;
            pw.recordId = p.Id;
            pw.sku = p.StockKeepingUnit;
            pw.quantityUnitOfMeasure = p.QuantityUnitOfMeasure;
            pw.pricebookEntries = new List<PricebookEntryWrapper>();
            for (PricebookEntry pe : p.PricebookEntries) {
                PricebookEntryWrapper pbew = new PricebookEntryWrapper();
                pbew.pricebook2Name = pe.Pricebook2 != null ? pe.Pricebook2.Name : null;
                pbew.unitPrice = pe.UnitPrice;
                pbew.isActive = pe.IsActive;
                pbew.useStandardPrice = pe.UseStandardPrice;
                pw.pricebookEntries.add(pbew);
            }
            payload.add(pw);
        }
        String body = JSON.serialize(payload);
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:customerOrg/services/apexrest/products');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
        } catch (Exception e) {
        }
    }
    global void finish(Database.BatchableContext bc) {
    }
}

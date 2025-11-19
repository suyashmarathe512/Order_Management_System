/***************************************************************************************************
* @Author:        CRM Developer
* @className:     ProductSyncBatch
* @Description:   This class implements a batch job to synchronize Product2 and PricebookEntry records
*                 from a remote server via a RESTful API callout. It retrieves product data,processes it,
*                 and updates or inserts records in the local Salesforce org accordingly.
***************************************************************************************************/
global with sharing class ProductSyncBatch implements Database.Batchable<SObject>,Database.AllowsCallouts {
    private static final String ENDPOINT='callout:ServerOrg/services/apexrest/Products';
/**************************************************************************************
 * @Author         CRM Developer
 * @classname      ProductSyncBatch.ServiceResponseWrapper
 * @description    Wrapper for the external service JSON response. Holds the list of ProductWrapper items.
 *************************************************************************************/
global class ServiceResponseWrapper { public List<ProductWrapper> products; }
/**************************************************************************************
 * @Author         CRM Developer
 * @classname      ProductSyncBatch.ProductWrapper
 * @description    Represents a product payload from the remote system,including nested pricebook entries.
 * @fields         Id,Product2Id,Name,ProductCode,Description,IsActive,Family,StockKeepingUnit,pricebookEntries
 *************************************************************************************/
global class ProductWrapper {
        public String Id;
        public String Product2Id;
        public String Name;
        public String ProductCode;
        public String Description;
        public Boolean IsActive;
        public String Family;
        public String StockKeepingUnit;
        public List<PbeWrapper> pricebookEntries;
/**************************************************************************************
 * @Author         CRM Developer
 * @methodname     getServerId
 * @description    Returns the external server identifier preferring Product2Id if present,otherwise Id.
 *************************************************************************************/
public String getServerId(){
            if(!String.isBlank(Product2Id))return Product2Id;
            return Id;
        }
    }
/************************************************************************************
 * @Author         CRM Developer
 * @classname      ProductSyncBatch.PbeWrapper
 * @description    Represents a PricebookEntry payload for a given product from the remote system.
 ***********************************************************************************/
global class PbeWrapper {
        public String PricebookName;
        public Decimal UnitPrice;
        public Boolean IsActive;
        public Boolean UseStandardPrice;
    }
/************************************************************************************
 * @Author         CRM Developer
 * @methodname     start
 * @Param          Database.BatchableContext
 * @description    Provides a lightweight query locator to initialize the batch execution.
 ***********************************************************************************/
global Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator('SELECT Id FROM Product2 LIMIT 1');
    }
/************************************************************************************
 * @Author         CRM Developer
 * @methodname     execute
 * @Param          Database.BatchableContext
 * @Param          List<SObject>
 * @description    Performs callout to remote service,upserts Product2 and synchronizes PricebookEntries.
 ***********************************************************************************************/
global void execute(Database.BatchableContext bc,List<SObject> scope){
        HttpRequest request=new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod('GET');
        request.setHeader('Content-Type','application/json');
        HttpResponse response;
        try { response=new Http().send(request); }
        catch(Exception ex){ return; }
        if(response.getStatusCode()< 200 || response.getStatusCode()> 299)return;
        ServiceResponseWrapper parsed;
        try { parsed =(ServiceResponseWrapper)JSON.deserialize(response.getBody(),ServiceResponseWrapper.class); }
        catch(Exception ex){ return; }
        if(parsed == null || parsed.products == null || parsed.products.isEmpty())return;
        Map<String,ProductWrapper> serverProducts=new Map<String,ProductWrapper>();
        for(ProductWrapper p : parsed.products){
            String sid=p.getServerId();
            if(!String.isBlank(sid))serverProducts.put(sid,p);
        }
        Map<String,Product2> localProducts=new Map<String,Product2>();
        if(!serverProducts.isEmpty()){
            for(Product2 p :[
                SELECT 
                    Id,ExternalId
                FROM 
                    Product2
                WHERE  
                    ExternalId IN :serverProducts.keySet()
            ]){
                localProducts.put(p.ExternalId,p);
            }
        }
        List<Product2> insertList=new List<Product2>();
        List<Product2> updateList=new List<Product2>();
        for(String serverId : serverProducts.keySet()){
            ProductWrapper incoming=serverProducts.get(serverId);
            Product2 target;
            if(localProducts.containsKey(serverId)){
                target=localProducts.get(serverId);
                updateList.add(target);
            } else {
                target=new Product2();
                target.ExternalId=serverId;
                insertList.add(target);
            }
            target.Name=incoming.Name;
            target.ProductCode=incoming.ProductCode;
            target.Description=incoming.Description;
            target.Family=incoming.Family;
            target.StockKeepingUnit=incoming.StockKeepingUnit;
            target.IsActive=incoming.IsActive == null ? true : incoming.IsActive;
        }
        if(!insertList.isEmpty())Database.insert(insertList,false);
        if(!updateList.isEmpty())Database.update(updateList,false);
        Map<String,Id> productIdByServer=new Map<String,Id>();
        for(Product2 p :[
            SELECT 
                Id,ExternalId
            FROM 
                Product2
            WHERE 
                ExternalId IN :serverProducts.keySet()
        ]){
            productIdByServer.put(p.ExternalId,p.Id);
        }
        Set<String> pricebookNames=new Set<String>();
        for(ProductWrapper p : parsed.products){
            if(p.pricebookEntries != null){
                for(PbeWrapper pe : p.pricebookEntries){
                    if(pe.PricebookName != null)pricebookNames.add(pe.PricebookName);
                }
            }
        }
        Map<String,Pricebook2> pricebooks=new Map<String,Pricebook2>();
        if(!pricebookNames.isEmpty()){
            for(Pricebook2 pb :[
                SELECT 
                    Id,Name
                FROM 
                    Pricebook2
                WHERE 
                    Name IN :pricebookNames
            ])pricebooks.put(pb.Name,pb);
        }
        List<Pricebook2> newPricebooks=new List<Pricebook2>();
        for(String name : pricebookNames)
            if(!pricebooks.containsKey(name))
                newPricebooks.add(new Pricebook2(Name=name,IsActive=true));
        if(!newPricebooks.isEmpty()){
            Database.insert(newPricebooks,false);
            for(Pricebook2 pb : newPricebooks)pricebooks.put(pb.Name,pb);
        }
        Map<String,PricebookEntry> existingPbeMap=new Map<String,PricebookEntry>();
        Set<Id> allLocalProductIds=new Set<Id>();
        allLocalProductIds.addAll(productIdByServer.values());
        if(!allLocalProductIds.isEmpty()){
            for(PricebookEntry ex :[
                SELECT 
                    Id,Pricebook2Id,Product2Id
                FROM 
                    PricebookEntry
                WHERE 
                    Product2Id IN :allLocalProductIds
            ]){
                String key=ex.Pricebook2Id + '_' + ex.Product2Id;
                existingPbeMap.put(key,ex);
            }
        }
        List<PricebookEntry> pbeInsertList=new List<PricebookEntry>();
        List<PricebookEntry> pbeUpdateList=new List<PricebookEntry>();
        for(ProductWrapper pw : parsed.products){
            Id localId=productIdByServer.get(pw.getServerId());
            if(localId == null || pw.pricebookEntries == null)continue;
            for(PbeWrapper pe : pw.pricebookEntries){
                Pricebook2 pb=pricebooks.get(pe.PricebookName);
                if(pb == null)continue;
                String key=pb.Id + '_' + localId;
                if(existingPbeMap.containsKey(key)){
                    PricebookEntry ex=existingPbeMap.get(key);
                    ex.UnitPrice=pe.UnitPrice;
                    ex.IsActive=pe.IsActive;
                    ex.UseStandardPrice=pe.UseStandardPrice;
                    pbeUpdateList.add(ex);
                }else{
                    pbeInsertList.add(new PricebookEntry(
                        Product2Id=localId,
                        Pricebook2Id=pb.Id,
                        UnitPrice=pe.UnitPrice,
                        IsActive=pe.IsActive,
                        UseStandardPrice=pe.UseStandardPrice
                    ));
                }
            }
        }
        if(!pbeInsertList.isEmpty())Database.insert(pbeInsertList,false);
        if(!pbeUpdateList.isEmpty())Database.update(pbeUpdateList,false);
    }
/************************************************************************************
 * @Author         CRM Developer
 * @methodname     finish
 * @Param         Database.BatchableContext
 * @description    batch completion.
 **********************************************************************************/
global void finish(Database.BatchableContext bc){}
}
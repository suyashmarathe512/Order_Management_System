/**************************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    CheckOutController
 * @Description:   This class allowed the POST method to accept the product Id 
 *                 and return the PBE for the product.
 **************************************************************************************************/
public with sharing class CheckOutController{
/************************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    CreateOrderResult
 * @Description:   this wrapper class is used to return the order id,line item count,
 *                     total amount,content version id and content document id.
 **************************************************************************************************/
    public class CreateOrderResult{
        @AuraEnabled public Id orderId;
        @AuraEnabled public Integer lineItemCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
    }
    
    // Wrapper class for billing address information
    public class BillingAddress {
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
    }
    
    // Wrapper class for shipping address information
    public class ShippingAddress {
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
    }
    
    // Wrapper class for order creation parameters
    public class OrderCreationParams {
        @AuraEnabled public List<Id> productIds;
        @AuraEnabled public List<String> names;
        @AuraEnabled public List<String> skus;
        @AuraEnabled public List<Integer> qtys;
        @AuraEnabled public List<Decimal> prices;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contractId;
        @AuraEnabled public BillingAddress billingAddress;
        @AuraEnabled public ShippingAddress shippingAddress;
    }
/************************************************************************************************
 * @Author :      CRM Team Innovation
 * @MethodName:    createOrderFromCart
 * @params :      productIds,names,skus,qtys,prices,accountId,contractId,billingStreet,billingCity,
 * @Description:   this wrapper class is used to return the order id,line item count,
 *                     total amount,content version id and content document id.
 **************************************************************************************************/
    @AuraEnabled
    public static CreateOrderResult createOrderFromCart(List<Id> orderProductIds,List<String> names,List<String> skus,List<Integer> qtys,List<Decimal> prices,Id accountId,Id contractId,String billingStreet,String billingCity,String billingState,String billingPostalCode,String billingCountry,String shippingStreet,String shippingCity,String shippingState,String shippingPostalCode,String shippingCountry){
        if(orderProductIds == null || orderProductIds.isEmpty()){
            throw new AuraHandledException('Cart is empty');
        }
        if(accountId == null){
            throw new AuraHandledException('Account is required');
        }
        if(contractId == null){
            throw new AuraHandledException('Contract is required');
        }
                List<Account> accList = [SELECT 
                                        Id 
                                    FROM 
                                        Account 
                                    WHERE 
                                        Id = :accountId 
                                    LIMIT 1];
        if(accList.isEmpty()){
            throw new AuraHandledException('Account not found');
        }
        // Instead of querying PricebookEntry, we'll work directly with OrderItem records
        // which already contain the necessary pricing information
        
        // Query the OrderItem records to get their details
        List<OrderItem> orderItems = [SELECT 
                                            Id, OrderId, PricebookEntryId, Quantity, UnitPrice, Product2Id 
                                      FROM 
                                        OrderItem 
                                      WHERE 
                                        Id IN :orderProductIds];
        
        // Validate that all requested OrderItems exist
        Set<Id> requestedOrderItemIds = new Set<Id>(orderProductIds);
        Set<Id> foundOrderItemIds = new Set<Id>();
        for(OrderItem oi : orderItems) {
            foundOrderItemIds.add(oi.Id);
        }
        // Check for missing OrderItems
        Set<Id> missingOrderItemIds = requestedOrderItemIds.clone();
        missingOrderItemIds.removeAll(foundOrderItemIds);
        if(!missingOrderItemIds.isEmpty()){
            throw new AuraHandledException('Missing OrderItems: ' + String.join(missingOrderItemIds, ','));
        }
        // Build map of OrderItems by Id for easy lookup
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>();
        for(OrderItem oi : orderItems) {
            orderItemMap.put(oi.Id, oi);
        }
        // Check for existing draft order for the account
        List<Order> existingOrders = [
            SELECT 
                    Id, Status, EffectiveDate, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM 
                Order
            WHERE 
                AccountId = :accountId 
            AND 
                Status = 'Draft'
            LIMIT 1
        ];

        Order ord;
        Boolean isNewOrder = false;
        if (!existingOrders.isEmpty()) {
            ord = existingOrders[0];
            // Update addresses and effective date
            ord.ContractId = contractId;
            ord.EffectiveDate = Date.today();
            ord.BillingStreet = billingStreet;
            ord.BillingCity = billingCity;
            ord.BillingState = billingState;
            ord.BillingPostalCode = billingPostalCode;
            ord.BillingCountry = billingCountry;
            ord.ShippingStreet = shippingStreet;
            ord.ShippingCity = shippingCity;
            ord.ShippingState = shippingState;
            ord.ShippingPostalCode = shippingPostalCode;
            ord.ShippingCountry = shippingCountry;
            update ord;
        } else {
            ord = new Order();
            ord.AccountId = accountId;
            ord.Status = 'Draft';
            ord.EffectiveDate = Date.today();
            ord.BillingStreet = billingStreet;
            ord.BillingCity = billingCity;
            ord.BillingState = billingState;
            ord.BillingPostalCode = billingPostalCode;
            ord.BillingCountry = billingCountry;
            ord.ShippingStreet = shippingStreet;
            ord.ShippingCity = shippingCity;
            ord.ShippingState = shippingState;
            ord.ShippingPostalCode = shippingPostalCode;
            ord.ShippingCountry = shippingCountry;
            insert ord;
            isNewOrder = true;
        }
        List<OrderItem> itemsToInsert=new List<OrderItem>();
        Decimal total=0;
        Integer lineCount=0;
        // Process each OrderItem directly
        for(Id orderItemId : orderProductIds) {
            OrderItem oi = orderItemMap.get(orderItemId);
            if(oi == null) continue;
            
            // Use the existing OrderItem's pricing information
            OrderItem newItem = new OrderItem();
            newItem.OrderId = ord.Id;
            newItem.PricebookEntryId = oi.PricebookEntryId;
            newItem.Quantity = oi.Quantity;
            newItem.UnitPrice = oi.UnitPrice;
            itemsToInsert.add(newItem);
            
            total += (oi.UnitPrice == null ? 0 : oi.UnitPrice) * oi.Quantity;
            lineCount++;
        }
        if(!itemsToInsert.isEmpty()) insert itemsToInsert;
        // Activate the order after inserting items
        ord.Status = 'Activated';
        update ord;
        Id contentVersionId=null;
        Id contentDocumentId=null;
        try{
            Map<String,Id> fileIds=saveInvoicePdfToAccount(ord.Id,accountId,'Invoice-' + String.valueOf(ord.Id) + '.pdf');
            if(fileIds != null){
                contentVersionId=fileIds.get('contentVersionId');
                contentDocumentId=fileIds.get('contentDocumentId');
            }
        }catch(Exception e){System.debug('PDF generation failed: ' + e);
        }
        CreateOrderResult result=new CreateOrderResult();
        result.orderId=ord.Id;
        result.lineItemCount=lineCount;
        result.totalAmount=total;
        result.contentVersionId=contentVersionId;
        result.contentDocumentId=contentDocumentId;
        return result;
    }
/************************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    saveInvoicePdfToAccount
 * @params :      orderId,accountId,fileName
 * @Description:   this method is used to save the invoice pdf to the account.
 **************************************************************************************************/
    public static Map<String,Id> saveInvoicePdfToAccount(Id orderId,Id accountId,String fileName){
        if(orderId == null) return null;PageReference pr=Page.InvoicePDF;
        pr.getParameters().put('id',String.valueOf(orderId));
        Blob pdfBlob;
        try{
            pdfBlob=pr.getContentAsPDF();
        }catch(VisualforceException vfEx){
            throw new AuraHandledException('Failed to render PDF: ' + vfEx.getMessage());
        }
        ContentVersion cv=new ContentVersion();
        cv.Title=fileName != null ? fileName.replace('.pdf','') : 'Invoice';
        cv.PathOnClient='/' +(fileName == null ?('Invoice-' + String.valueOf(orderId) + '.pdf') : fileName);
        cv.VersionData=pdfBlob;
        if(accountId != null){
            cv.FirstPublishLocationId=accountId;
        }
        insert cv;
        ContentVersion insertedCv=[SELECT 
                                        Id,ContentDocumentId 
                                    FROM 
                                        ContentVersion 
                                    WHERE 
                                        Id=:cv.Id 
                                    LIMIT 1];
        sendPdfToFileService(orderId,fileName);
        Map<String,Id> out=new Map<String,Id>();
        out.put('contentVersionId',insertedCv.Id);
        out.put('contentDocumentId',insertedCv.ContentDocumentId);
        return out;
    }
    public class AccountInfo{
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String shippingStreet;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingPostalCode;
        @AuraEnabled public String shippingCountry;
    }
    @AuraEnabled
    public static AccountInfo getAccountInfo(Id accountId){
        if(accountId == null){
            return null;
        }
        Account acc=[SELECT 
                            Id,Name,BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                            ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry
                        FROM 
                            Account 
                        WHERE 
                            Id=:accountId 
                        LIMIT 1];
        if(acc != null){
            AccountInfo accInfo=new AccountInfo();
            accInfo.id=acc.Id;
            accInfo.name=acc.Name;
            accInfo.billingStreet=acc.BillingStreet;
            accInfo.billingCity=acc.BillingCity;
            accInfo.billingState=acc.BillingState;
            accInfo.billingPostalCode=acc.BillingPostalCode;
            accInfo.billingCountry=acc.BillingCountry;
            accInfo.shippingStreet=acc.ShippingStreet;
            accInfo.shippingCity=acc.ShippingCity;
            accInfo.shippingState=acc.ShippingState;
            accInfo.shippingPostalCode=acc.ShippingPostalCode;
            accInfo.shippingCountry=acc.ShippingCountry;
            return accInfo;
        }
        return null;
    }
/*******************************************************************************************
 * @AuthorName:    CRM Team Innovation
 * @MethodName:     sendPdfToFileService
 * @params :        orderId,fileName
 * @Description:    this method is used to send the invoice pdf to the file service.
 ********************************************************************************************/
    @AuraEnabled
    public static List<Contract> getContractsForAccount(Id accountId){
        if(accountId == null){
            return new List<Contract>();
        }
        return [SELECT 
                    Id, ContractNumber, Status, StartDate, EndDate, Contract_Name__c 
                FROM 
                    Contract 
                WHERE 
                    AccountId = :accountId 
                AND 
                    Status = 'Activated' 
                ORDER BY 
                    ContractNumber];
    }
    /*****************************************************************************
     * @methodName:     deletOrderItem
     * @Param orderItemId The Id of the OrderItem to delete
     * @description:    Deletes an OrderItem from the database.
     *********************************************************************************/
    @AuraEnabled
    public static void deleteOrderItem(Id orderItemId) {
        if (orderItemId == null) {
            throw new AuraHandledException('OrderItem Id is required');
        }
        // Query the OrderItem to verify it exists
        List<OrderItem> orderItems = [SELECT 
                                        Id 
                                    FROM 
                                        OrderItem 
                                    WHERE 
                                        Id = :orderItemId 
                                    LIMIT 1];
        if (orderItems.isEmpty()) {
            throw new AuraHandledException('OrderItem not found');
        }
        // Delete the OrderItem
        delete orderItems[0];
    }
    @future(callout=true)
    public static void sendPdfToFileService(Id orderId,String fileName){
        PageReference pr=new PageReference('/apex/InvoicePDF');
        pr.getParameters().put('id',String.valueOf(orderId));
        Blob pdfBlob=pr.getContentAsPDF();
        try{
            Http http=new Http();
            HttpRequest req=new HttpRequest();
            req.setEndpoint('callout:ServerOrg/services/apexrest/fileservice/');
            req.setMethod('POST');
            req.setHeader('Content-Type','application/octet-stream');
            req.setBodyAsBlob(pdfBlob);
            HttpResponse res=http.send(req);
        }catch(Exception e){
        }
    }
}

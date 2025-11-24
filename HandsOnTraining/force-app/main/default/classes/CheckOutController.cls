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
 * @params :      productIds,names,skus,qtys,prices,accountId,billingStreet,billingCity,
 *                 billingState,billingPostalCode,billingCountry,shippingStreet,shippingCity,
 *                 shippingState,shippingPostalCode,shippingCountry
 * @Description:   this wrapper class is used to return the order id,line item count,
 *                     total amount,content version id and content document id.
 **************************************************************************************************/
    @AuraEnabled
    public static CreateOrderResult createOrderFromCart(List<Id> productIds,List<String> names,List<String> skus,List<Integer> qtys,List<Decimal> prices,Id accountId,Id contractId,String billingStreet,String billingCity,String billingState,String billingPostalCode,String billingCountry,String shippingStreet,String shippingCity,String shippingState,String shippingPostalCode,String shippingCountry){
        if(productIds == null || productIds.isEmpty()){
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
        Id pricebookId=[SELECT 
                                Id 
                        FROM 
                            Pricebook2 
                        WHERE 
                            IsStandard=true 
                        LIMIT 1].Id;
        Map<Id,Integer> productIdToQty=new Map<Id,Integer>();
        for(Integer i=0; i < productIds.size(); i++){
            Id pid=productIds[i];
            Integer qty=(qtys != null && i < qtys.size()) ? qtys[i] : 1;
            if(pid != null){
                productIdToQty.put(pid,qty);
            }
        }
        if(productIdToQty.isEmpty()) throw new AuraHandledException('No valid productIds in cart');

        Set<Id> prodIds=productIdToQty.keySet();
        String query='SELECT Id,Product2Id,Pricebook2Id,UnitPrice,IsActive FROM PricebookEntry WHERE Product2Id IN :prodIds AND IsActive=true';
        if(pricebookId != null){
            query += ' AND Pricebook2Id=:pricebookId';
        }
        query += ' ORDER BY UnitPrice ASC';
        List<PricebookEntry> pbeList=Database.query(query);
        Map<Id,PricebookEntry> chosenPbeByProd=new Map<Id,PricebookEntry>();
        Map<Id,List<PricebookEntry>> pbesByProd=new Map<Id,List<PricebookEntry>>();
        for(PricebookEntry pbe : pbeList){
            if(!pbesByProd.containsKey(pbe.Product2Id)) pbesByProd.put(pbe.Product2Id,new List<PricebookEntry>());
            pbesByProd.get(pbe.Product2Id).add(pbe);
        }
        for(Id pid : pbesByProd.keySet()){
            PricebookEntry chosen=null;
            List<PricebookEntry> listForProd=pbesByProd.get(pid);
            if(pricebookId != null){
                for(PricebookEntry pb : listForProd){
                    if(pb.Pricebook2Id == pricebookId){ chosen=pb; break; }
                }
            }
            if(chosen == null && !listForProd.isEmpty()) chosen=listForProd[0];
            if(chosen != null) chosenPbeByProd.put(pid,chosen);
        }
        Map<Id,PricebookEntry> chosenPbeByProductId=new Map<Id,PricebookEntry>();
        List<Id> missingProductIds=new List<Id>();
        for(Id pid : prodIds){
            if(chosenPbeByProd.containsKey(pid)){
                chosenPbeByProductId.put(pid,chosenPbeByProd.get(pid));
            }else{
                missingProductIds.add(pid);
            }
        }
        if(!missingProductIds.isEmpty()){
            throw new AuraHandledException('Missing PricebookEntry for ProductIds: ' + String.join(missingProductIds,','));
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
            if (pricebookId != null) ord.Pricebook2Id = pricebookId;
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
        for(Id productId : chosenPbeByProductId.keySet()){
            Integer qty=productIdToQty.get(productId);
            PricebookEntry pbe=chosenPbeByProductId.get(productId);
            if(qty == null || pbe == null) continue;
            qty=(qty < 1) ? 1 : qty;
            OrderItem oi=new OrderItem();
            oi.OrderId=ord.Id;
            oi.PricebookEntryId=pbe.Id;
            oi.Quantity=qty;
            oi.UnitPrice=pbe.UnitPrice;
            itemsToInsert.add(oi);
            total +=(oi.UnitPrice == null ? 0 : oi.UnitPrice) * qty;
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
 * @MethodName:    saveOrderAsDraft
 * @params :      productIds,names,skus,qtys,prices,accountId,billingStreet,billingCity,
 *                 billingState,billingPostalCode,billingCountry,shippingStreet,shippingCity,
 *                 shippingState,shippingPostalCode,shippingCountry
 * @Description:   this method saves the order as draft without generating PDF.
 **************************************************************************************************/
    @AuraEnabled
    public static CreateOrderResult saveOrderAsDraft(OrderCreationParams params){
        // Extract parameters from the wrapper
        List<Id> productIds = params.productIds;
        List<String> names = params.names;
        List<String> skus = params.skus;
        List<Integer> qtys = params.qtys;
        List<Decimal> prices = params.prices;
        Id accountId = params.accountId;
        Id contractId = params.contractId;
        BillingAddress billingAddress = params.billingAddress;
        ShippingAddress shippingAddress = params.shippingAddress;
        
        if(productIds == null || productIds.isEmpty()){
            throw new AuraHandledException('Cart is empty');
        }
        if(accountId == null){
            throw new AuraHandledException('Account is required');
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
        Id pricebookId=[SELECT 
                                Id 
                        FROM 
                            Pricebook2 
                        WHERE 
                            IsStandard=true 
                        LIMIT 1].Id;
        Map<Id,Integer> productIdToQty=new Map<Id,Integer>();
        for(Integer i=0; i < productIds.size(); i++){
            Id pid=productIds[i];
            Integer qty=(qtys != null && i < qtys.size()) ? qtys[i] : 1;
            if(pid != null){
                productIdToQty.put(pid,qty);
            }
        }
        if(productIdToQty.isEmpty()) throw new AuraHandledException('No valid productIds in cart');

        Set<Id> prodIds=productIdToQty.keySet();
        String query='SELECT Id,Product2Id,Pricebook2Id,UnitPrice,IsActive FROM PricebookEntry WHERE Product2Id IN :prodIds AND IsActive=true';
        if(pricebookId != null){
            query += ' AND Pricebook2Id=:pricebookId';
        }
        query += ' ORDER BY UnitPrice ASC';
        List<PricebookEntry> pbeList=Database.query(query);
        Map<Id,PricebookEntry> chosenPbeByProd=new Map<Id,PricebookEntry>();
        Map<Id,List<PricebookEntry>> pbesByProd=new Map<Id,List<PricebookEntry>>();
        for(PricebookEntry pbe : pbeList){
            if(!pbesByProd.containsKey(pbe.Product2Id)) pbesByProd.put(pbe.Product2Id,new List<PricebookEntry>());
            pbesByProd.get(pbe.Product2Id).add(pbe);
        }
        for(Id pid : pbesByProd.keySet()){
            PricebookEntry chosen=null;
            List<PricebookEntry> listForProd=pbesByProd.get(pid);
            if(pricebookId != null){
                for(PricebookEntry pb : listForProd){
                    if(pb.Pricebook2Id == pricebookId){ chosen=pb; break; }
                }
            }
            if(chosen == null && !listForProd.isEmpty()) chosen=listForProd[0];
            if(chosen != null) chosenPbeByProd.put(pid,chosen);
        }
        Map<Id,PricebookEntry> chosenPbeByProductId=new Map<Id,PricebookEntry>();
        List<Id> missingProductIds=new List<Id>();
        for(Id pid : prodIds){
            if(chosenPbeByProd.containsKey(pid)){
                chosenPbeByProductId.put(pid,chosenPbeByProd.get(pid));
            }else{
                missingProductIds.add(pid);
            }
        }
        if(!missingProductIds.isEmpty()){
            throw new AuraHandledException('Missing PricebookEntry for ProductIds: ' + String.join(missingProductIds,','));
        }
        // Check for existing draft order for the account
        List<Order> existingOrders = [
            SELECT 
                    Id, Status, EffectiveDate, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM 
                Order
            WHERE 
                AccountId = :accountId AND Status = 'Draft'
            LIMIT 1
        ];

        Order ord;
        Boolean isNewOrder = false;
        if (!existingOrders.isEmpty()) {
            ord = existingOrders[0];
            // Update addresses and effective date
            ord.ContractId = contractId;
            ord.EffectiveDate = Date.today();
            ord.BillingStreet = billingAddress.street;
            ord.BillingCity = billingAddress.city;
            ord.BillingState = billingAddress.state;
            ord.BillingPostalCode = billingAddress.postalCode;
            ord.BillingCountry = billingAddress.country;
            ord.ShippingStreet = shippingAddress.street;
            ord.ShippingCity = shippingAddress.city;
            ord.ShippingState = shippingAddress.state;
            ord.ShippingPostalCode = shippingAddress.postalCode;
            ord.ShippingCountry = shippingAddress.country;
            update ord;
            // Delete existing order items to replace with current cart
            delete [SELECT 
                        Id FROM OrderItem WHERE OrderId = :ord.Id];
        } else {
            ord = new Order();
            ord.AccountId = accountId;
            ord.ContractId = contractId;
            ord.Status = 'Draft';
            ord.EffectiveDate = Date.today();
            if (pricebookId != null) ord.Pricebook2Id = pricebookId;
            ord.BillingStreet = billingAddress.street;
            ord.BillingCity = billingAddress.city;
            ord.BillingState = billingAddress.state;
            ord.BillingPostalCode = billingAddress.postalCode;
            ord.BillingCountry = billingAddress.country;
            ord.ShippingStreet = shippingAddress.street;
            ord.ShippingCity = shippingAddress.city;
            ord.ShippingState = shippingAddress.state;
            ord.ShippingPostalCode = shippingAddress.postalCode;
            ord.ShippingCountry = shippingAddress.country;
            insert ord;
            isNewOrder = true;
        }
        List<OrderItem> itemsToInsert=new List<OrderItem>();
        Decimal total=0;
        Integer lineCount=0;
        for(Id productId : chosenPbeByProductId.keySet()){
            Integer qty=productIdToQty.get(productId);
            PricebookEntry pbe=chosenPbeByProductId.get(productId);
            if(qty == null || pbe == null) continue;

            qty=(qty < 1) ? 1 : qty;
            OrderItem oi=new OrderItem();
            oi.OrderId=ord.Id;
            oi.PricebookEntryId=pbe.Id;
            oi.Quantity=qty;
            oi.UnitPrice=pbe.UnitPrice;
            itemsToInsert.add(oi);
            total +=(oi.UnitPrice == null ? 0 : oi.UnitPrice) * qty;
            lineCount++;
        }
        if(!itemsToInsert.isEmpty()) insert itemsToInsert;
        // No PDF generation for draft save
        CreateOrderResult result=new CreateOrderResult();
        result.orderId=ord.Id;
        result.lineItemCount=lineCount;
        result.totalAmount=total;
        result.contentVersionId=null;
        result.contentDocumentId=null;
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
        return [SELECT Id, ContractNumber, Status, StartDate, EndDate FROM Contract WHERE AccountId = :accountId AND Status = 'Activated' ORDER BY ContractNumber];
    }

    /**
     * Deletes an OrderItem record by Id
     * @param orderItemId The Id of the OrderItem to delete
     */
    @AuraEnabled
    public static void deleteOrderItem(Id orderItemId) {
        if (orderItemId == null) {
            throw new AuraHandledException('OrderItem Id is required');
        }
        
        // Query the OrderItem to verify it exists
        List<OrderItem> orderItems = [SELECT Id FROM OrderItem WHERE Id = :orderItemId LIMIT 1];
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

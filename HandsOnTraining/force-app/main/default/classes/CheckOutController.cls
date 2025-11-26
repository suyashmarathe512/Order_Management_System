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
    public class BillingAddress{
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
    }
    // Wrapper class for shipping address information
    public class ShippingAddress{
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
    }
    // Wrapper class for order creation parameters
    public class OrderCreationParams{
        // Accept raw identifiers as strings to support formats like:
        // - '802xxxxxxxxxxxxxxx'(OrderItem Id)
        // - '01txxxxxxxxxxxxxxx'(Product2 Id)
        // - 'temp_01txxxxxxxxxxxxxxx_1764048937359'(wrapped Product2 Id)
        @AuraEnabled public List<String> orderItemsIds;
        @AuraEnabled public List<String> names;
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
 * @params :      orderItemsIds,names,skus,qtys,prices,accountId,contractId,billingStreet,billingCity,
 * @Description:   this wrapper class is used to return the order id,line item count,
 *                     total amount,content version id and content document id.
 **************************************************************************************************/
@AuraEnabled
public static CreateOrderResult createOrderFromCart(String jsonParams){
    try{
        OrderCreationParams params=(OrderCreationParams) JSON.deserialize(jsonParams,OrderCreationParams.class);
        /******************* BASIC VALIDATION *******************/
        if(params==null){
        
            throw new AuraHandledException('Order parameters are required.');
        }
        /******************* SPLIT IDS: 802* vs PRODUCT2(supports temp_... wrapper) *******************/
        List<String> rawIdsStr=(params.orderItemsIds==null)?new List<String>() : params.orderItemsIds;
        List<Id> orderItemIds=new List<Id>(); // 802*=> OrderItem
        List<Id> product2Ids=new List<Id>(); // baaki=> Product2
        // Maintain a parallel list of "effective" Product2Ids for index-based qty/price mapping
        List<Id> effectiveProduct2IdsByIndex=new List<Id>();
        for(String s : rawIdsStr){
            if(String.isBlank(s)){
                effectiveProduct2IdsByIndex.add(null);
                continue;
            }
            // Handle temp_ prefix: expected format "temp_{18charProduct2Id}_<suffix>"
            if(s.startsWith('temp_')){
                Integer startIdx=5; // length of 'temp_'
                if(s.length() >= startIdx+18){
                    String maybeId=s.substring(startIdx,startIdx+18);
                    try{
                        Id parsedId=(Id) maybeId;
                        product2Ids.add(parsedId);
                        effectiveProduct2IdsByIndex.add(parsedId);
                        continue;
                    } catch(Exception eCast){
                        // will fallthrough to treat as unresolved
                    }
                }
                effectiveProduct2IdsByIndex.add(null);
                continue;
            }
            // 802* are OrderItem Ids
            if(s.length() >= 3 && s.substring(0,3)=='802'){
                try{
                   orderItemIds.add((Id)s);
                } catch(Exception e802){
                    // ignore invalid id
                }
                effectiveProduct2IdsByIndex.add(null);
            } else{
                // Treat as Product2 Id
                try{
                    Id p2=(Id)s;
                    product2Ids.add(p2);
                    effectiveProduct2IdsByIndex.add(p2);
                } catch(Exception eP2){
                    effectiveProduct2IdsByIndex.add(null);
                }
            }
        }
        if(orderItemIds.isEmpty() && effectiveProduct2IdsByIndex.isEmpty()){
        
            throw new AuraHandledException('Your cart is empty. Please add items first.');
        }
        /******************* ACCOUNT RESOLUTION *******************/
        // Pehla attempt: params se direct
        Id accountId=params.accountId;
        // Doosra attempt: agar 802* ids hai to OrderItem → Order.AccountId se nikaal lo
        if(accountId==null && !orderItemIds.isEmpty()){
            try{
                OrderItem sampleOi=[
                    SELECT 
                        Id,Order.AccountId
                    FROM 
                        OrderItem
                    WHERE 
                        Id IN :orderItemIds
                    LIMIT 1
                ];
                if(sampleOi.Order!=null){
                    accountId=sampleOi.Order.AccountId;
                }
            } catch(Exception eOiAcc){
            }
        }
        // Teesra attempt: agar Contract दिया हुआ hai to usse AccountId le lo
        if(accountId==null && params.contractId!=null){
            try{
                Contract cAcc=[
                    SELECT 
                        Id,AccountId
                    FROM 
                        Contract
                    WHERE 
                        Id=:params.contractId
                    LIMIT 1
                ];
                accountId=cAcc.AccountId;
            
            } catch(Exception eConAcc){
            
            }
        }
        if(accountId==null){
            throw new AuraHandledException('Account is required to place an order.');
        }
        /******************* ACCOUNT LOAD *******************/
        Account acc;
        try{
            acc=[
                SELECT 
                    Id
                FROM 
                    Account
                WHERE 
                    Id=:accountId
                LIMIT 1
            ];
        } catch(Exception eAcc){
        
            throw new AuraHandledException('Selected account not found or invalid.');
        }
        /******************* SNAPSHOT FROM ORDERITEM(802*) *******************/
        List<OrderItem> cartItems=new List<OrderItem>();
        if(!orderItemIds.isEmpty()){
            cartItems=[
                SELECT 
                    Id,Quantity,UnitPrice,PricebookEntryId
                FROM 
                    OrderItem
                WHERE 
                    Id IN :orderItemIds
            ];
        }
        // Agar na 802 wale mile,na Product2Ids aaye,tabhi cart truly empty hai
        if(cartItems.isEmpty() && product2Ids.isEmpty()){
            throw new AuraHandledException('Your cart is empty. Please add items.');
        }
        Map<Id,OrderItem> cartMap=new Map<Id,OrderItem>(cartItems);
        // Pricebook2Id nikalne ki primary try: existing OIs se
        Id pb2Id=null;
        for(OrderItem oi : cartItems){
            if(oi.PricebookEntryId!=null && pb2Id==null){
                PricebookEntry pbe=[
                    SELECT 
                        Pricebook2Id
                    FROM 
                        PricebookEntry
                    WHERE 
                        Id=:oi.PricebookEntryId
                    LIMIT 1
                ];
                pb2Id=pbe.Pricebook2Id;
            }
        }
        /******************* CONTRACT RESOLUTION *******************/
        Contract con=null;
        // Step A: client se aaya contractId – par Account match hona chahiye
        if(params.contractId!=null){
            List<Contract> tryCon=[
                SELECT 
                    Id,AccountId,Pricebook2Id,Status
                FROM 
                    Contract
                WHERE 
                    Id=:params.contractId
                LIMIT 1
            ];
            if(!tryCon.isEmpty() && tryCon[0].AccountId==acc.Id){
                con=tryCon[0];
            
            } else if(!tryCon.isEmpty()){
            }
        }
        // Step B: agar abhi bhi null – isi Account ka latest Contract utha lo
        if(con==null){
            List<Contract> accCon=[
                SELECT 
                    Id,AccountId,Pricebook2Id,Status
                FROM 
                    Contract
                WHERE 
                    AccountId=:acc.Id
                ORDER BY 
                    CreatedDate DESC
                LIMIT 1
            ];
            if(!accCon.isEmpty()){
                con=accCon[0];
            
            }
        }
        // Step C: agar phir bhi null – naya Contract DRAFT me bana rahe
        if(con==null){
            // agar pb2Id abhi null hai(sirf Product2Ids ka case) to yaha handle karna hoga
            if(pb2Id==null){
                try{
                    Pricebook2 stdPb=[SELECT 
                                            Id 
                                        FROM 
                                            Pricebook2 
                                        WHERE 
                                            IsStandard=true LIMIT 1];
                    pb2Id=stdPb.Id;
                } catch(Exception ePb){
                
                }
            }   
            con=new Contract(
                AccountId  =acc.Id,
                Status     ='Draft',  // new contract must start Draft
                StartDate  =Date.today(),
                Pricebook2Id=pb2Id
            );
            insert con; 
        } else{
            // Contract ka Pricebook agar missing hai to OI/cart waala set kar dete
            if(con.Pricebook2Id==null && pb2Id!=null){
                con.Pricebook2Id=pb2Id;
                update con;
            
            }
        }
        // Final PB choose karte – Contract se,warna OI/cart/standard se
        Id finalPB2=(con.Pricebook2Id!=null)?con.Pricebook2Id : pb2Id;
        if(finalPB2==null && !product2Ids.isEmpty()){
        
            throw new AuraHandledException('No pricebook is configured to price the selected products.');
        }
        /******************* ORDER AS DRAFT *******************/
        List<Order> drafts=[
            SELECT 
                Id,Status
            FROM 
                Order
            WHERE 
                AccountId=:acc.Id
            AND 
                Status='Draft'
            LIMIT 1
        ];
        Order ord;
        if(!drafts.isEmpty()){
            ord=drafts[0];
            // Purane line items delete – cart snapshot refresh karne ke liye
            List<OrderItem> existing=[
                SELECT Id
                FROM OrderItem
                WHERE OrderId=:ord.Id
            ];
            if(!existing.isEmpty()){
                delete existing;
            }

            ord.Pricebook2Id=finalPB2;
            ord.ContractId  =con.Id;
            ord.EffectiveDate=Date.today();

            if(params.billingAddress!=null){
                ord.BillingStreet   =params.billingAddress.street;
                ord.BillingCity     =params.billingAddress.city;
                ord.BillingState    =params.billingAddress.state;
                ord.BillingPostalCode=params.billingAddress.postalCode;
                ord.BillingCountry  =params.billingAddress.country;
            }
            if(params.shippingAddress!=null){
                ord.ShippingStreet   =params.shippingAddress.street;
                ord.ShippingCity     =params.shippingAddress.city;
                ord.ShippingState    =params.shippingAddress.state;
                ord.ShippingPostalCode=params.shippingAddress.postalCode;
                ord.ShippingCountry  =params.shippingAddress.country;
            }

            update ord;
        } else{
            ord=new Order(
                AccountId   =acc.Id,
                Pricebook2Id=finalPB2,
                ContractId  =con.Id,
                EffectiveDate=Date.today(),
                Status='Draft'
            );
            if(params.billingAddress!=null){
                ord.BillingStreet   =params.billingAddress.street;
                ord.BillingCity     =params.billingAddress.city;
                ord.BillingState    =params.billingAddress.state;
                ord.BillingPostalCode=params.billingAddress.postalCode;
                ord.BillingCountry  =params.billingAddress.country;
            }
            if(params.shippingAddress!=null){
                ord.ShippingStreet   =params.shippingAddress.street;
                ord.ShippingCity     =params.shippingAddress.city;
                ord.ShippingState    =params.shippingAddress.state;
                ord.ShippingPostalCode=params.shippingAddress.postalCode;
                ord.ShippingCountry  =params.shippingAddress.country;
            }
            insert ord;
        }
        /******************* PREP PBE FOR Product2Ids *******************/
        Map<Id,PricebookEntry> pbeByProduct=new Map<Id,PricebookEntry>();
        if(!product2Ids.isEmpty()){
            List<PricebookEntry> pbes=[
                SELECT 
                    Id,Product2Id
                FROM 
                    PricebookEntry
                WHERE 
                    Product2Id IN :product2Ids
                AND 
                    Pricebook2Id=:finalPB2
                AND 
                    IsActive=true
            ];
            for(PricebookEntry pe : pbes){
                pbeByProduct.put(pe.Product2Id,pe);
            }
        
        }
        /******************* CREATE ORDER ITEMS *******************/
        List<OrderItem> newItems=new List<OrderItem>();
        Decimal total=0;
        // 1) Clone existing 802* OrderItems(cartItems)
        for(OrderItem baseOi : cartItems){
            if(baseOi==null) continue;
            OrderItem newOi=new OrderItem(
                OrderId =ord.Id,
                PricebookEntryId=baseOi.PricebookEntryId,
                Quantity=baseOi.Quantity,
                UnitPrice=baseOi.UnitPrice
            );
            newItems.add(newOi);
            if(baseOi.UnitPrice!=null){
                total += baseOi.UnitPrice * baseOi.Quantity;
            }
        }
        // 2) New lines from Product2Ids using qtys/prices from params(index-based mapping,supports temp_ ids)
        for(Integer i=0; i < rawIdsStr.size(); i++){
            String s=rawIdsStr[i];
            if(String.isBlank(s)) continue;
            // Skip existing OrderItem ids(802*)
            if(s.length() >= 3 && s.substring(0,3)=='802'){
                continue;
            }
            // Resolve effective Product2Id for this index:
            Id productId=(i < effectiveProduct2IdsByIndex.size())?effectiveProduct2IdsByIndex[i] : null;
            if(productId==null){
                // Try parsing from raw when not temp_ and not 802
                try{
                    productId=(Id)s;
                } catch(Exception eId){
                
                    continue;
                }
            }
            PricebookEntry pe=pbeByProduct.get(productId);
            if(pe==null){
                continue; // agar pricebook-entry hi nahi hai to skip kar rahe
            }
            Integer qty =(params.qtys  !=null && i < params.qtys.size())?params.qtys[i]   : 1;
            Decimal price=(params.prices!=null && i < params.prices.size())?params.prices[i] : null;
            // Ensure UnitPrice is set - either from params or from PricebookEntry
            Decimal finalPrice=price;
            if(finalPrice==null && pe!=null){
                // Try to get price from PricebookEntry if not provided in params
                try{
                    PricebookEntry pbe=[
                        SELECT 
                            UnitPrice
                        FROM 
                            PricebookEntry
                        WHERE 
                            Id=:pe.Id
                        LIMIT 1
                    ];
                    finalPrice=pbe.UnitPrice;
                } catch(Exception e){
                    // If we can't get price from PBE,we'll let it fail naturally
                }
            }
            OrderItem newOiFromProd=new OrderItem(
                OrderId=ord.Id,
                PricebookEntryId=pe.Id,
                Quantity=qty,
                UnitPrice=finalPrice
            );
            newItems.add(newOiFromProd);
            if(price!=null){
                total += price * qty;
            }
        }
        if(newItems.isEmpty()){
           throw new AuraHandledException('No order lines could be created from the cart.');
        }
        insert newItems;
/******************* ACTIVATE ORDER(IF CONTRACT ACTIVATED) *******************/
// Update the contract status to Activated before activating the order
        try{
            if(con.Status!='Activated'){
                con.Status='Activated';
                update con;
            }
        } catch(Exception e){
        }
        if(con.Status=='Activated'){
            ord.Status='Activated';
            update ord;
        }
        /******************* BUILD RESULT *******************/
        CreateOrderResult res=new CreateOrderResult();
        res.orderId     =ord.Id;
        res.lineItemCount=newItems.size();
        res.totalAmount =total;
        return res;
    }
    catch(AuraHandledException ahe){
        throw ahe;
    }
    catch(Exception e){
        throw e;
    }
}
/************************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    saveInvoicePdfToAccount
 * @Description:   Isolated method. Query the most recent Activated Order (post-commit),
 *                 render its invoice as PDF, save to Files, link to Account and Order,
 *                 and send the same PDF to the external FileService. Takes no parameters.
 **************************************************************************************************/
 @AuraEnabled   
 public static Map<String,Id> saveInvoicePdfToAccount(){
        // 1) Find the most recent Activated Order
        List<Order> latestOrders = [
            SELECT Id, Name, EffectiveDate, AccountId
            FROM Order
            WHERE Status = 'Activated'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if(latestOrders.isEmpty()){
            return null;
        }
        Order ord = latestOrders[0];
        // 2) Load Account Name if available (for external FileService)
        Account accName = null;
        if(ord.AccountId != null){
            List<Account> accs = [
                SELECT Id, Name
                FROM Account
                WHERE Id = :ord.AccountId
                LIMIT 1
            ];
            if(!accs.isEmpty()){
                accName = accs[0];
            }
        }
        // 3) Build filename and render the VF as PDF for the specific Order Id
        String invoiceFileName = (ord.Name != null ? ord.Name : 'Invoice') + '_' +
                                 (ord.EffectiveDate != null ? String.valueOf(ord.EffectiveDate) : '') + '.pdf';
        PageReference pr = Page.InvoicePdf;
        pr.getParameters().put('id', String.valueOf(ord.Id));
        Blob pdfBlob;
        try{
            pdfBlob = pr.getContentAsPDF();
        }catch(VisualforceException vfEx){
            throw new AuraHandledException('Failed to render PDF: ' + vfEx.getMessage());
        }
        // 4) Save to Files: publish to Account when available; else to current user
        ContentVersion cv = new ContentVersion();
        cv.Title = invoiceFileName.replace('.pdf','');
        cv.PathOnClient = '/' + invoiceFileName;
        cv.VersionData = pdfBlob;
        if (ord.AccountId != null) {
            cv.FirstPublishLocationId = ord.AccountId;
        } else {
            cv.FirstPublishLocationId = UserInfo.getUserId();
        }
        insert cv;
        // 5) Retrieve ContentDocumentId and ensure explicit link to the Order
        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        if (insertedCv.ContentDocumentId != null && ord.Id != null) {
            List<ContentDocumentLink> existingLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :insertedCv.ContentDocumentId
                AND LinkedEntityId = :ord.Id
                LIMIT 1
            ];
            if (existingLinks.isEmpty()) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = insertedCv.ContentDocumentId;
                cdl.LinkedEntityId = ord.Id;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                insert cdl;
            }
        }
        // 6) Send to external FileService
        sendPdfToFileService(invoiceFileName, accName != null ? accName.Name : null, pdfBlob);
        Map<String,Id> out = new Map<String,Id>();
        out.put('contentVersionId', insertedCv.Id);
        out.put('contentDocumentId', insertedCv.ContentDocumentId);
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
        if(accountId==null){
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
        if(acc!=null){
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
        if(accountId==null){
            return new List<Contract>();
        }
        return [SELECT 
                    Id,ContractNumber,Status,StartDate,EndDate,Contract_Name__c 
                FROM 
                    Contract 
                WHERE 
                    AccountId=:accountId 
                AND 
                    Status='Activated' 
                ORDER BY 
                    ContractNumber];
    }
    /***************************************************************************** 
     * @methodName:     deletOrderItem
     * @Param orderItemId The Id of the OrderItem to delete
     * @description:    Deletes an OrderItem from the database.
     *********************************************************************************/
    @AuraEnabled
    public static void deleteOrderItem(Id orderItemId){
        if(orderItemId==null){
            throw new AuraHandledException('OrderItem Id is required');
        }
        // Query the OrderItem to verify it exists
        List<OrderItem> orderItems=[SELECT 
                                        Id 
                                    FROM 
                                        OrderItem 
                                    WHERE 
                                        Id=:orderItemId 
                                    LIMIT 1];
        if(orderItems.isEmpty()){
            throw new AuraHandledException('OrderItem not found');
        }
        // Delete the OrderItem
        delete orderItems[0];
    }
    /***************************************************************************** 
     * @methodName:     sendPdfToFileService
     * @Param           orderId,fileName
     * @description:    this method is used to send the invoice pdf to the file service.
     *********************************************************************************/
    @future(callout=true)
    public static void sendPdfToFileService(String fileName,String accountName,Blob pdfBlob){
        try{
            Http http=new Http();
            HttpRequest req=new HttpRequest();
            String endpointUrl='callout:ServerOrg/services/apexrest/fileservice/';
            List<String> qParams=new List<String>();
            if(!String.isBlank(accountName)){
                qParams.add('accountName='+EncodingUtil.urlEncode(accountName,'UTF-8'));
            }
            if(!String.isBlank(fileName)){
                qParams.add('fileName='+EncodingUtil.urlEncode(fileName,'UTF-8'));
            }
            if(!qParams.isEmpty()){
                endpointUrl += '?'+String.join(qParams,'&');
            }
            req.setEndpoint(endpointUrl);
            req.setMethod('POST');
            req.setHeader('Content-Type','application/octet-stream');
            req.setBodyAsBlob(pdfBlob);
            HttpResponse res=http.send(req);
        }catch(Exception e){
        }
    }
}

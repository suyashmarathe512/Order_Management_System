public with sharing class OrderService {
    public class CartItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String sku;
        @AuraEnabled public Integer qty;
        @AuraEnabled public Decimal unitPrice;
    }
    public class CreateOrderResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Integer lineItemCount;
        @AuraEnabled public Decimal totalAmount;
    }
    @AuraEnabled
    public static CreateOrderResult createOrderFromCart(List<CartItem> cartItems, Id accountId, Id pricebookId) {
        if (cartItems == null || cartItems.isEmpty()) {
            throw new AuraHandledException('Cart is empty');
        }
        if (accountId == null) {
            throw new AuraHandledException('Account is required');
        }
        Map<String, CartItem> skuToCart = new Map<String, CartItem>();
        for (CartItem ci : cartItems) {
            if (ci == null || String.isBlank(ci.sku)) continue;
            skuToCart.put(ci.sku.trim(), ci);
        }
        if (skuToCart.isEmpty()) throw new AuraHandledException('No valid SKUs in cart');

        Set<String> skus = skuToCart.keySet();
        Map<String, Id> skuToProductId = new Map<String, Id>();
        for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :skus]) {
            if (!String.isBlank(p.StockKeepingUnit)) skuToProductId.put(p.StockKeepingUnit.trim(), p.Id);
        }
        Set<Id> prodIds = new Set<Id>(skuToProductId.values());
        if (prodIds.isEmpty()) {
            throw new AuraHandledException('No products found for provided SKUs.');
        }
        List<PricebookEntry> pbeList = [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :prodIds AND IsActive = true
            ORDER BY UnitPrice ASC
        ];
        Map<Id, PricebookEntry> chosenPbeByProd = new Map<Id, PricebookEntry>();
        Map<Id, List<PricebookEntry>> pbesByProd = new Map<Id, List<PricebookEntry>>();
        for (PricebookEntry pbe : pbeList) {
            if (!pbesByProd.containsKey(pbe.Product2Id)) pbesByProd.put(pbe.Product2Id, new List<PricebookEntry>());
            pbesByProd.get(pbe.Product2Id).add(pbe);
        }
        for (Id pid : pbesByProd.keySet()) {
            PricebookEntry chosen = null;
            List<PricebookEntry> listForProd = pbesByProd.get(pid);
            if (pricebookId != null) {
                for (PricebookEntry pb : listForProd) {
                    if (pb.Pricebook2Id == pricebookId) { chosen = pb; break; }
                }
            }
            if (chosen == null && !listForProd.isEmpty()) chosen = listForProd[0];
            if (chosen != null) chosenPbeByProd.put(pid, chosen);
        }
        Map<String, PricebookEntry> chosenPbeBySku = new Map<String, PricebookEntry>();
        List<String> missingSkus = new List<String>();
        for (String sku : skus) {
            Id pid = skuToProductId.get(sku);
            if (pid == null) {
                missingSkus.add(sku);
                continue;
            }
            if (chosenPbeByProd.containsKey(pid)) {
                chosenPbeBySku.put(sku, chosenPbeByProd.get(pid));
            } else {
                missingSkus.add(sku);
            }
        }
        if (!missingSkus.isEmpty()) {
            throw new AuraHandledException('Missing PricebookEntry for SKUs: ' + String.join(missingSkus, ', '));
        }
        Order ord = new Order();
        ord.AccountId = accountId;
        ord.Status = 'Draft';
        ord.EffectiveDate = Date.today();
        if (pricebookId != null) ord.Pricebook2Id = pricebookId;
        insert ord;
        List<OrderItem> itemsToInsert = new List<OrderItem>();
        Decimal total = 0;
        Integer lineCount = 0;
        for (String sku : chosenPbeBySku.keySet()) {
            CartItem ci = skuToCart.get(sku);
            PricebookEntry pbe = chosenPbeBySku.get(sku);
            if (ci == null || pbe == null) continue;

            Integer qty = (ci.qty == null || ci.qty < 1) ? 1 : ci.qty;
            OrderItem oi = new OrderItem();
            oi.OrderId = ord.Id;
            oi.PricebookEntryId = pbe.Id;
            oi.Quantity = qty;
            oi.UnitPrice = pbe.UnitPrice;
            itemsToInsert.add(oi);

            total += (oi.UnitPrice == null ? 0 : oi.UnitPrice) * qty;
            lineCount++;
        }
        if (!itemsToInsert.isEmpty()) insert itemsToInsert;
        CreateOrderResult result = new CreateOrderResult();
        result.orderId = ord.Id;
        result.lineItemCount = lineCount;
        result.totalAmount = total;
        return result;
    }

    public class GenerateInvoiceResult {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String fileDownloadUrl;
    }
    @AuraEnabled
    public static GenerateInvoiceResult generateInvoiceForOrder(Id orderId) {
        if (orderId == null) throw new AuraHandledException('orderId required');
        Order ord = [SELECT Id, AccountId, EffectiveDate, Status, OrderNumber FROM Order WHERE Id = :orderId LIMIT 1];
        PageReference pr = Page.InvoicePdf;
        if (pr == null) throw new AuraHandledException('Invoice PDF Visualforce page not found');
        pr.getParameters().put('id', String.valueOf(orderId));
        Blob pdfBlob;
        try {
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('PDF_CONTENT_TEST');
            } else {
                pdfBlob = pr.getContentAsPDF();
            }
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to render PDF: ' + ex.getMessage());
        }

        String fileName = 'Invoice_' + (ord.OrderNumber != null ? ord.OrderNumber : ord.Id) + '.pdf';

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        Id contentDocId = cv.ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocId;
        cdl.LinkedEntityId = UserInfo.getUserId();
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
        GenerateInvoiceResult res = new GenerateInvoiceResult();
        res.contentDocumentId = contentDocId;
        res.contentVersionId = cv.Id;
        res.fileDownloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        return res;
    }
}

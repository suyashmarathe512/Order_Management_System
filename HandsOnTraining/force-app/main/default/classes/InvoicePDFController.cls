/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      InvoicePDFController
 * @Description:     This class is used to generate the invoice pdf for the order.
 ***********************************************************************************/
public with sharing class InvoicePDFController{
    public Order order{get;private set;}
    public List<OrderItem> orderItems{get;private set;}
    public Decimal total{get;private set;}
    // Property to hold the target currency based on billing country
    public String targetCurrency{get;private set;}
    // Property to hold the timezone-converted invoice date for display in PDF
    public String invoiceDateForDisplay{get;private set;}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      InvoicePDFController
 * @Description:     This class is used to generate the invoice pdf for the order.
 ***********************************************************************************/
    public InvoicePDFController(){
        // Try to get the Order Id from the page parameter to always render the intended order
        Id orderIdParam;
        try{
            String idStr=ApexPages.currentPage()!=null ? ApexPages.currentPage().getParameters().get('id') : null;
            if(!String.isBlank(idStr)){
                orderIdParam=(Id) idStr;
            }
        }catch(Exception eCast){
            orderIdParam=null;
        }
        if(orderIdParam != null){
            // Load the specific Order passed in, ensuring it's accessible
            List<Order> ords=[
                SELECT 
                    Id,Name,CreatedDate,AccountId,
                    BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                    ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry,
                    Account.Name
                FROM 
                    Order
                WHERE 
                    Id=:orderIdParam
                LIMIT 1
            ];
            if(!ords.isEmpty()){
                order=ords[0];
            }
        }
        // Fallback: previous behavior - latest Activated Order
        if(order == null){
            List<Order> latest=[
                SELECT 
                    Id,Name,CreatedDate,AccountId,
                    BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                    ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry,
                    Account.Name
                FROM 
                    Order
                WHERE 
                    Status='Activated'
                ORDER BY
                    CreatedDate DESC
                LIMIT 1
            ];
            if(!latest.isEmpty()){
                order=latest[0];
            }else{
                initEmpty();
                return;
            }
        }
        // Load items for the resolved order
        Id orderId=order.Id;
        orderItems=[
            SELECT 
                Id,Quantity,UnitPrice,PricebookEntry.Product2.Name
            FROM 
                OrderItem
            WHERE 
                OrderId=:orderId
            ORDER BY 
                Id
        ];
        computeTotals();
        // Convert CreatedDate to local timezone for display in PDF
        convertInvoiceDateForDisplay();
}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      convertInvoiceDateForDisplay
 * @Description:     Converts the order's CreatedDate to the customer's local timezone for PDF display
 ***********************************************************************************/
    private void convertInvoiceDateForDisplay(){
        if(order != null && order.CreatedDate != null){
            String billingCountry = order.BillingCountry;
            invoiceDateForDisplay = TimezoneConverterService.convertToLocalTimeString(order.CreatedDate, billingCountry);
        }else {
            invoiceDateForDisplay = '';
        }
    }
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      initEmpty
 * @Description:     This method is used to initialize the empty order and order items.
 ***********************************************************************************/
    private void initEmpty(){
        order=new Order(Name='Unknown',EffectiveDate=Date.today());
        orderItems=new List<OrderItem>();
        total=0;
}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      computeTotals
 * @Description:     This method is used to compute the totals for the order.
 ***********************************************************************************/
   private void computeTotals(){
        total=0;
        if(orderItems == null){
            orderItems=new List<OrderItem>();
        }
        // Determine target currency based on billing country
        targetCurrency = CurrencyConverterService.COUNTRY_TO_CURRENCY.get(order.BillingCountry.trim().toUpperCase());
        if (targetCurrency == null) {
            targetCurrency = 'INR'; 
        }
        for (OrderItem oi : orderItems){
            Decimal unit=(oi.UnitPrice == null) ? 0 : oi.UnitPrice;
            Decimal qtyDecimal=(oi.Quantity == null) ? 1 : Decimal.valueOf(String.valueOf(oi.Quantity));
            Decimal ConvertedPrice = CurrencyConverterService.convertByCountry(unit * qtyDecimal, 'INR', order.BillingCountry);
            total += ConvertedPrice;
        }
}
}

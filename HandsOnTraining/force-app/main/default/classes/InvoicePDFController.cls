/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      InvoicePDFController
 * @Description:     This class is used to generate the invoice pdf for the order.
 ***********************************************************************************/
public with sharing class InvoicePDFController{
    public class OrderItemWrapper {
        public OrderItem item { get; private set; }
        public Decimal convertedUnitPrice { get; private set; }
        public Decimal convertedTotal { get; private set; }
        public Decimal originalTotal { get; private set; }

        public OrderItemWrapper(OrderItem oi, Decimal convUnitPrice, Decimal convTotal, Decimal origTotal) {
            this.item = oi;
            this.convertedUnitPrice = convUnitPrice;
            this.convertedTotal = convTotal;
            this.originalTotal = origTotal;
        }
    }
    public Order order{get;private set;}
    public List<OrderItemWrapper> orderItemWrappers{get;private set;}
    public Decimal total{get;private set;}
    public String targetCurrency{get;private set;}
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
            String idStr=ApexPages.currentPage().getParameters().get('id');
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
        List<OrderItem> orderItems=[
            SELECT
                Id,Quantity,UnitPrice,PricebookEntry.Product2.Name
            FROM
                OrderItem
            WHERE
                OrderId=:orderId
            ORDER BY
                Id
        ];
        computeTotals(orderItems);
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
        orderItemWrappers=new List<OrderItemWrapper>();
        total=0;
}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      computeTotals
 * @Description:     This method is used to compute the totals for the order.
 ***********************************************************************************/
   private void computeTotals(List<OrderItem> orderItems){
        total=0;
        orderItemWrappers = new List<OrderItemWrapper>();
        if(orderItems == null){
            orderItems=new List<OrderItem>();
        }
        targetCurrency = CurrencyConverterService.COUNTRY_TO_CURRENCY.get(order.BillingCountry.trim().toUpperCase());
        if (targetCurrency == null) {
            targetCurrency = 'INR';
        }
        for (OrderItem oi : orderItems){
            Decimal unit=oi.UnitPrice;
            Decimal qtyDecimal=Decimal.valueOf(String.valueOf(oi.Quantity));
            Decimal convertedUnitPrice = CurrencyConverterService.convertByCountry(unit, 'INR', order.BillingCountry);
            Decimal convertedTotal = convertedUnitPrice * qtyDecimal;
            Decimal originalTotal = unit * qtyDecimal;
            orderItemWrappers.add(new OrderItemWrapper(oi, convertedUnitPrice, convertedTotal, originalTotal));
            total += convertedTotal;
        }
}
}

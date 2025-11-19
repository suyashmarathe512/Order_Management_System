/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @ClassName:      InvoicePDFController
 * @Description:     This class is used to generate the invoice pdf for the order.
 ***********************************************************************************/
public with sharing class InvoicePDFController{
    public Order order{get;private set;}
    public List<OrderItem> orderItems{get;private set;}
    public Decimal subtotal{get;private set;}
    public Decimal tax{get;private set;}
    public Decimal total{get;private set;}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      InvoicePDFController
 * @Description:     This class is used to generate the invoice pdf for the order.
 ***********************************************************************************/
    public InvoicePDFController(){
        order=[
            SELECT 
                Id,Name,CreatedDate,AccountId,
                BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry,
                Account.Name
            FROM 
                Order
            ORDER BY
                CreatedDate DESC
            LIMIT 1
        ];
       Id  orderId=order.Id;
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
}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      initEmpty
 * @Description:     This method is used to initialize the empty order and order items.
 ***********************************************************************************/
    private void initEmpty(){
        order=new Order(Name='Unknown',EffectiveDate=Date.today());
        orderItems=new List<OrderItem>();
        subtotal=0;
        tax=0;
        total=0;
}
/*****************************************************************************
 * @AuthorName:     CRM Team Innovation
 * @MethodName:      computeTotals
 * @Description:     This method is used to compute the totals for the order.
 ***********************************************************************************/
   private void computeTotals(){
        subtotal=0;
        for (OrderItem oi:orderItems){
            Decimal unit=(oi.UnitPrice == null) ? 0:oi.UnitPrice;
            Decimal qtyDecimal;
            if (oi.Quantity == null){
                qtyDecimal=1;
        }else{
            qtyDecimal=Decimal.valueOf(String.valueOf(oi.Quantity));
        }subtotal += unit * qtyDecimal;
    }
        tax=0;
        total=subtotal + tax;
}
}
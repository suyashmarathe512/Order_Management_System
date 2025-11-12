public with sharing class InvoicePdfExtension {
    private final Order order;
    
    public InvoicePdfExtension(ApexPages.StandardController controller) {
        this.order = (Order) controller.getRecord();
    }
    
    public Decimal getSubtotal() {
        Decimal subtotal = 0;
        if (order.OrderItems != null) {
            for (OrderItem item : order.OrderItems) {
                if (item.UnitPrice != null && item.Quantity != null) {
                    subtotal += item.UnitPrice * item.Quantity;
                }
            }
        }
        return subtotal;
    }
    
    public Decimal getTotal() {
        // For now, assuming tax is 0
        return getSubtotal();
    }
}

import { LightningElement, track } from 'lwc';
import createOrderFromCart from '@salesforce/apex/OrderService.createOrderFromCart';
import generateInvoiceForOrder from '@salesforce/apex/OrderService.generateInvoiceForOrder';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CheckoutPage extends NavigationMixin(LightningElement) {
  @track cart = [];
  @track isLoading = false;
  @track orderResult = null;
  @track accountId = '';

  connectedCallback() {
    const raw = sessionStorage.getItem('cart');
    if (raw) {
      try {
        const parsedCart = JSON.parse(raw);
        // Ensure cart items have required properties
        this.cart = parsedCart.map(item => ({
          id: item.id,
          name: item.name,
          sku: item.sku,
          price: item.price,
          qty: item.qty || 1
        }));
      } catch (e) {
        console.error('Failed to parse cart data:', e);
        this.cart = [];
      }
    } else {
      this.cart = [];
    }
  }

  get total() {
    return this.cart.reduce((sum, it) => sum + ((it.price || 0) * (it.qty || 1)), 0);
  }

  handleQtyChange(evt) {
    const id = evt.target.dataset.id;
    const qty = parseInt(evt.target.value, 10) || 1;
    this.cart = this.cart.map(i => i.id === id ? { ...i, qty } : i);
    sessionStorage.setItem('cart', JSON.stringify(this.cart));
  }

  removeLine(evt) {
    const id = evt.target.dataset.id;
    this.cart = this.cart.filter(i => i.id !== id);
    sessionStorage.setItem('cart', JSON.stringify(this.cart));
  }

  async placeOrder() {
    if (!this.cart.length) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Empty cart', message: 'Add products first', variant: 'warning' }));
      return;
    }
    if (!this.accountId) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Account required', message: 'Enter Account Id', variant: 'warning' }));
      return;
    }

    this.isLoading = true;
    try {
      // Create properly formatted cart items for the OrderService
      const cartDto = this.cart.map(i => {
        // Ensure all required fields are present and properly formatted
        const item = {
          id: i.id,
          sku: i.sku,
          qty: i.qty || 1,
          unitPrice: i.price
        };
        // Validate that required fields are not null/empty
        if (!item.sku || item.sku.trim() === '') {
          throw new Error('Invalid SKU in cart item');
        }
        return item;
      });
      
      const res = await createOrderFromCart({ cartItems: cartDto, accountId: this.accountId, pricebookId: null });
      this.orderResult = res;
      this.dispatchEvent(new ShowToastEvent({ title: 'Order Created', message: `Order ${res.orderId} created (${res.lineItemCount} lines)`, variant: 'success' }));
      // clear cart in session
      sessionStorage.removeItem('cart');
      this.cart = [];
      // navigate to order view
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: res.orderId, objectApiName: 'Order', actionName: 'view' }
      });
    } catch (err) {
      console.error('Order creation error:', err);
      this.dispatchEvent(new ShowToastEvent({ title: 'Order failed', message: err?.body?.message || err?.message || 'Unknown error', variant: 'error' }));
    } finally {
      this.isLoading = false;
    }
  }

  async generateInvoice() {
    if (!this.orderResult || !this.orderResult.orderId) {
      this.dispatchEvent(new ShowToastEvent({ title: 'No Order', message: 'Create an order first', variant: 'warning' }));
      return;
    }
    this.isLoading = true;
    try {
      const res = await generateInvoiceForOrder({ orderId: this.orderResult.orderId });
      this.dispatchEvent(new ShowToastEvent({ title: 'Invoice generated', message: 'Invoice saved to Files', variant: 'success' }));
      if (res && res.fileDownloadUrl) window.open(res.fileDownloadUrl, '_blank');
    } catch (err) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Invoice failed', message: err?.body?.message || err?.message || 'Unknown error', variant: 'error' }));
    } finally {
      this.isLoading = false;
    }
  }

  handleAccountChange(evt) {
    this.accountId = evt.target.value;
  }
}

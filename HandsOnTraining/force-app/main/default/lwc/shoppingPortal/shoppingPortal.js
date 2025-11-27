import { LightningElement, track } from 'lwc';

export default class ShoppingPortal extends LightningElement {
    @track showCheckoutPage = false;
    @track cartItems = [];
    @track accountId;

    connectedCallback() {
        // pick cart from session if present, so checkout can render immediately if needed
        try {
            const raw = sessionStorage.getItem('cart');
            if (raw) {
                const parsed = JSON.parse(raw);
                if (Array.isArray(parsed)) {
                    this.cartItems = parsed;
                    if (parsed.length && parsed[0].accountId) {
                        this.accountId = parsed[0].accountId;
                    }
                }
            }
        } catch (e) {
            // ignore
        }
    }

    // Handle cart updates from product information display (if used)
    handleCartUpdate(event) {
        if (event?.detail?.cart) {
            this.cartItems = event.detail.cart;
            if (event.detail.accountId) {
                this.accountId = event.detail.accountId;
            } else if (this.cartItems.length && this.cartItems[0].accountId) {
                this.accountId = this.cartItems[0].accountId;
            }
            // persist for checkout page to read as well
            try {
                sessionStorage.setItem('cart', JSON.stringify(this.cartItems));
            } catch (e) {}
        }
    }

    // Handle checkout event bubbled from productInformationDisplay
    handleCheckout(event) {
        console.log('ShoppingPortal: handleCheckout called with event:', event);
        console.log('ShoppingPortal: event detail:', event?.detail);
        // accept payload from child and store
        if (event?.detail?.cart) {
            this.cartItems = event.detail.cart;
        } else {
            // as a fallback, read from session
            try {
                const raw = sessionStorage.getItem('cart');
                if (raw) {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) this.cartItems = parsed;
                }
            } catch (e) {}
        }
        if (event?.detail?.accountId) {
            this.accountId = event.detail.accountId;
        } else if (this.cartItems.length && this.cartItems[0].accountId) {
            this.accountId = this.cartItems[0].accountId;
        }
        this.showCheckoutPage = true;
        console.log('ShoppingPortal: showCheckoutPage set to true, cartItems length:', this.cartItems.length);
    }

    // Handle going back to portal from checkout page
    handleBackToPortal() {
        console.log('ShoppingPortal: handleBackToPortal called');
        this.showCheckoutPage = false;
    }
}

import { LightningElement, api } from 'lwc';

export default class ProductCard extends LightningElement {
  @api product;

  get ariaLabel() {
    const name = this.product?.name || this.product?.Name || 'Product';
    return `Product: ${name}`;
  }
  get productImage() {
    return this.product?.ProductImage__c || this.product?.productImage || null;
  }

  get imageHidden() {
    return !this.productImage;
  }

  get formattedPrice() {
    const price = this.product?.price;
    if (price === null || price === undefined) return '—';
    try {
      return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(price);
    } catch (e) {
      return `₹${price}`;
    }
  }
  get isFetchedFromOrg() {
    return !!(this.product && (this.product.isFetchedFromOrg === true || this.product.isPriceFromOrg === true));
  }

  onAdd() {
    const cartItem = {
      id: this.product.id,
      name: this.product.name,
      sku: this.product.sku,
      price: this.product.price,
      qty: 1
    };
    if (!cartItem.sku) {
      console.error('Product has no SKU:', this.product);
      return;
    }
    this.dispatchEvent(new CustomEvent('addtocart', { detail: cartItem }));
  }

  onView() {
    this.dispatchEvent(new CustomEvent('viewdetails', { detail: this.product }));
  }
}

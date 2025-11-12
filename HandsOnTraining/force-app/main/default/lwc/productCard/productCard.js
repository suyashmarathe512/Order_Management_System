import { LightningElement, api } from 'lwc';

export default class ProductCard extends LightningElement {
  @api product;

  get ariaLabel() {
    const name = this.product?.name || this.product?.Name || 'Product';
    return `Product: ${name}`;
  }

  get productImage() {
    // Accept both API-name and camelCase DTO property
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

  // NEW: boolean flag to indicate if PBE info used fallback from org
  get isFetchedFromOrg() {
    // support different casing and ensure boolean
    return !!(this.product && (this.product.isFetchedFromOrg === true || this.product.isPriceFromOrg === true));
  }

  onAdd() {
    this.dispatchEvent(new CustomEvent('addtocart', { detail: this.product }));
  }

  onView() {
    this.dispatchEvent(new CustomEvent('viewdetails', { detail: this.product }));
  }
}

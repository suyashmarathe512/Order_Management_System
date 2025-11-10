import { LightningElement, api } from 'lwc';

export default class ProductCard extends LightningElement {
  @api product;

  onAdd() {
    this.dispatchEvent(new CustomEvent('addtocart', { detail: this.product }));
  }

  onView() {
    this.dispatchEvent(new CustomEvent('viewdetails', { detail: this.product }));
  }
}

import { LightningElement, track } from 'lwc';
import fetchProducts from '@salesforce/apex/ProductController.fetchProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class productInformationDisplay extends LightningElement {
  @track products = [];
  @track pageNumber = 1;
  pageSize = 12;
  @track isLoading = true;
  @track isLoadingMore = false;
  @track totalSize = 0;
  @track searchKey = '';
  @track noResults = false;
  @track showModal = false;
  @track modalProduct = {};
  skeletons = new Array(6);

  connectedCallback() {
    this.loadProducts(true);
  }

  async loadProducts(reset = true) {
    try {
      if (reset) {
        this.pageNumber = 1;
        this.products = [];
        this.noResults = false;
        this.isLoading = true;
      } else {
        this.isLoadingMore = true;
      }

      const resp = await fetchProducts({
        pageNumber: this.pageNumber,
        pageSize: this.pageSize,
        searchQuery: this.searchKey,
        sortField: 'Name',
        sortDir: 'ASC'
      });

      if (resp && resp.records) {
        this.totalSize = resp.totalSize;
        this.products = this.products.concat(resp.records);
        this.noResults = this.products.length === 0;
      }
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Error loading products',
          message: err?.body?.message || err?.message || 'Unknown error',
          variant: 'error'
        })
      );
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  onSearchChange(event) {
    this.searchKey = event.target.value;
    // Debounce handled by lightning-input's debounce attribute
    this.loadProducts(true);
  }

  onGridScroll(e) {
    const grid = e.currentTarget;
    if (grid.scrollTop + grid.clientHeight >= grid.scrollHeight - 200 && !this.isLoadingMore && this.products.length < this.totalSize) {
      this.pageNumber += 1;
      this.loadProducts(false);
    }
  }

  handleAddToCart(e) {
    const prod = e.detail;
    this.dispatchEvent(new ShowToastEvent({ title: 'Added to cart', message: prod.name || 'Product added', variant: 'success' }));
    // TODO: call Apex to persist cart / raise LMS message for cross-component sync
  }

  handleViewDetails(e) {
    this.modalProduct = e.detail;
    this.showModal = true;
  }

  closeModal() {
    this.showModal = false;
    this.modalProduct = {};
  }

  modalAddToCart() {
    this.handleAddToCart({ detail: this.modalProduct });
    this.closeModal();
  }

  openFilterPanel() {
    // placeholder for off-canvas filters
  }

  onCreateOrder() {
    // navigate to new order or open order creation modal
  }
}

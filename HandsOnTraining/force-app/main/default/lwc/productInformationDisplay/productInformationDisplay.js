import { LightningElement, track } from 'lwc';
import fetchProducts from '@salesforce/apex/ProductController.fetchProducts';
import fetchProductFamilies from '@salesforce/apex/ProductController.fetchProductFamilies';
import fetchPBEsRealtimeBySKUs from '@salesforce/apex/ProductController.fetchPBEsRealtimeBySKUs';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ProductInformationDisplay extends LightningElement {
  @track products = [];
  @track pageNumber = 1;
  pageSize = 12;
  @track isLoading = true;
  @track isLoadingMore = false;
  @track totalSize = 0;
  @track searchKey = '';
  @track noResults = false;

  // cart state
  @track cartItems = [];

  // modal & drawer
  @track showModal = false;
  @track modalProduct = {};
  @track showCart = false;

  // filter modal
  @track showFilterModal = false;
  @track selectedFamilies = [];
  @track availableFamilies = [];

  // skeleton placeholders (array of objects with stable ids)
  skeletons = Array.from({ length: 6 }, (_, i) => ({ id: `sk-${i}` }));

  connectedCallback() {
    this.loadProducts(true);
  }

  // computed getters used in template (no inline expressions)
  get cartCount() {
    return this.cartItems.length;
  }
  get hasCartItems() {
    return this.cartItems.length > 0;
  }
  get isCheckoutDisabled() {
    return this.cartCount === 0;
  }

  // load products from Apex with server-side paging
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
        selectedFamilies: this.selectedFamilies,
        sortField: 'Name',
        sortDir: 'ASC'
      });

      if (resp && resp.records) {
        this.totalSize = resp.totalSize || 0;

        // append new unique records (avoid duplicates)
        const newRecords = resp.records.filter(r => !this.products.some(p => p.id === r.id));
        this.products = this.products.concat(newRecords);
        this.noResults = this.products.length === 0;
      }
    } catch (err) {
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error loading products',
        message: err?.body?.message || err?.message || 'Unknown error',
        variant: 'error'
      }));
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  onSearchChange(event) {
    this.searchKey = event.target.value;
    // debounce respected by lightning-input; reload
    this.loadProducts(true);
  }

  onGridScroll(e) {
    const grid = e.currentTarget;
    if (grid.scrollTop + grid.clientHeight >= grid.scrollHeight - 200 && !this.isLoadingMore && this.products.length < this.totalSize) {
      this.pageNumber += 1;
      this.loadProducts(false);
    }
  }

  // cart behaviors
  handleAddToCart(e) {
    const prod = e.detail;
    if (!prod || !prod.id) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Invalid item', message: 'Cannot add item to cart', variant: 'error' }));
      return;
    }

    // add if not present — simple qty=1 semantics
    if (!this.cartItems.some(i => i.id === prod.id)) {
      this.cartItems = [...this.cartItems, { ...prod, qty: 1 }];
      this.dispatchEvent(new ShowToastEvent({ title: 'Added to cart', message: prod.name || 'Product added', variant: 'success' }));
    } else {
      this.dispatchEvent(new ShowToastEvent({ title: 'Already in cart', message: prod.name || 'Item already in cart', variant: 'info' }));
    }
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

  // drawer handlers
  openCart() {
    this.showCart = true;
  }
  onCartKeydown(evt) {
    if (evt.key === 'Enter' || evt.key === ' ') {
      this.openCart();
    }
  }
  closeCart() {
    this.showCart = false;
  }

  removeFromCart(evt) {
    const idToRemove = evt.currentTarget.dataset.id;
    if (!idToRemove) return;
    this.cartItems = this.cartItems.filter(i => i.id !== idToRemove);
  }

  onCheckout() {
    // Place-holder — integrate with Order creation flow or Apex
    this.dispatchEvent(new ShowToastEvent({ title: 'Checkout', message: `Proceeding with ${this.cartCount} items`, variant: 'success' }));
    this.closeCart();
  }

  // filter panel methods
  async openFilterPanel() {
    try {
      const families = await fetchProductFamilies();
      this.availableFamilies = families.map(family => ({
        name: family,
        selected: this.selectedFamilies.includes(family)
      }));
      this.showFilterModal = true;
    } catch (err) {
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error loading families',
        message: err?.body?.message || err?.message || 'Unknown error',
        variant: 'error'
      }));
    }
  }

  closeFilterPanel() {
    this.showFilterModal = false;
  }

  handleFamilyChange(event) {
    const family = event.target.value;
    const isChecked = event.target.checked;
    if (isChecked) {
      this.selectedFamilies = [...this.selectedFamilies, family];
    } else {
      this.selectedFamilies = this.selectedFamilies.filter(f => f !== family);
    }
    // Update the availableFamilies array to reflect the change
    this.availableFamilies = this.availableFamilies.map(f => ({
      ...f,
      selected: this.selectedFamilies.includes(f.name)
    }));
  }

  isFamilySelected(family) {
    return this.selectedFamilies.includes(family);
  }

  applyFilters() {
    this.loadProducts(true);
    this.closeFilterPanel();
  }

  onCreateOrder() {
    // navigate to order creation or open order modal
  }
}

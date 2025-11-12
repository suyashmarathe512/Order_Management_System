import { LightningElement, track } from 'lwc';
import fetchProducts from '@salesforce/apex/ProductController.fetchProducts';
import fetchProductFamilies from '@salesforce/apex/ProductController.fetchProductFamilies';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
export default class ProductInformationDisplay extends NavigationMixin(LightningElement) {
  @track products = [];
  @track pageNumber = 1;
  pageSize = 12;
  @track isLoading = true;
  @track isLoadingMore = false;
  @track totalSize = 0;
  @track searchKey = '';
  @track noResults = false;
  @track cartItems = [];
  @track showModal = false;
  @track modalProduct = {};
  @track showCart = false;

  @track showFilterModal = false;
  @track selectedFamilies = [];
  @track availableFamilies = [];
  skeletons = Array.from({ length: 6 }, (_, i) => ({ id: `sk-${i}` }));
  connectedCallback() {
    this.loadProducts(true);
  }
  get cartCount() {
    return this.cartItems.length;
  }
  get hasCartItems() {
    return this.cartItems.length > 0;
  }
  get isCheckoutDisabled() {
    return this.cartCount === 0;
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
        selectedFamilies: this.selectedFamilies,
        sortField: 'Name',
        sortDir: 'ASC'
      });

      if (resp && resp.records) {
        this.totalSize = resp.totalSize || 0;
        const mapped = resp.records.map(r => {
          const pbes = Array.isArray(r.pbes) ? r.pbes : [];
          const displayPrice = (pbes.length > 0 && pbes[0].unitPrice != null) ? pbes[0].unitPrice : r.price != null ? r.price : null;

          return {
            id: r.id,
            name: r.name,
            productCode: r.productCode,
            description: r.description,
            family: r.family,
            isActive: r.isActive,
            sku: r.sku,
            uom: r.uom,
            productImage: r.productImage,
            price: displayPrice,
            pricebookId: r.pricebookId || null,
            pbes: pbes.map(p => ({
              pricebookEntryId: p.pricebookEntryId,
              pricebookId: p.pricebookId,
              pricebookName: p.pricebookName,
              unitPrice: p.unitPrice,
              isActive: p.isActive,
              productId: p.productId,
              productName: p.productName,
              sku: p.sku,
              isFetchedFromOrg: !!p.isFetchedFromOrg
            }))
          };
        });
        const newRecords = mapped.filter(r => !this.products.some(p => p.id === r.id));
        this.products = this.products.concat(newRecords);
        this.noResults = this.products.length === 0;
      } else {
        this.noResults = true;
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
    if (!prod || !prod.id) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Invalid item', message: 'Cannot add item to cart', variant: 'error' }));
      return;
    }
    this.cartItems = [...this.cartItems, { ...prod, qty: 1 }];
    this.dispatchEvent(new ShowToastEvent({ title: 'Added to cart', message: prod.name || 'Product added', variant: 'success' }));
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
    this.dispatchEvent(new ShowToastEvent({ title: 'Checkout', message: `Proceeding with ${this.cartCount} items`, variant: 'success' }));
    this.closeCart();
    const cartData = this.cartItems || [];
    const validatedCart = cartData.filter(item => item && item.id && item.sku);
    sessionStorage.setItem('cart', JSON.stringify(validatedCart));
    this[NavigationMixin.Navigate]({
      type: 'standard__webPage',
      attributes: { url: '/lightning/n/Checkout_Page' }
    });
  }
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
  }
  goToCheckout() {
    sessionStorage.setItem('cart', JSON.stringify(this.cartItems || []));
    this[NavigationMixin.Navigate]({
      type: 'standard__component',
      attributes: {
        componentName: 'c__checkoutPage'
      }
    });
  }
}

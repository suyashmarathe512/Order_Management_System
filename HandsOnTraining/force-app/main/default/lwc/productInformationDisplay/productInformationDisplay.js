import{LightningElement, track, api}from 'lwc';
import fetchProducts from '@salesforce/apex/ProductController.fetchProducts';
import fetchProductFamilies from '@salesforce/apex/ProductController.fetchProductFamilies';
import{ShowToastEvent}from 'lightning/platformShowToastEvent';
import{NavigationMixin}from 'lightning/navigation';
export default class ProductInformationDisplay extends NavigationMixin(LightningElement){
  @track products=[];
  @track pageNumber=1;
  pageSize=12;
  @track isLoading=true;
  @track isLoadingMore=false;
  @track totalSize=0;
  @track searchKey='';
  @track noResults=false;
  @track cartItems=[];
  @api
  get selectedCartItems(){
    return(this.cartItems || []).filter(item => item && item.id && item.sku);
  }
  @track showModal=false;
  @track modalProduct ={};
  @track showCart=false;
  @track showPbeModal=false;
  @track pbeInfo=[];
  @track pbeForProductId;
  @track showFilterModal=false;
  @track selectedFamilies=[];
  @track availableFamilies=[];
  skeletons=Array.from({length: 6 },(_, i) =>({id: `sk-${i}` }));
  connectedCallback(){
    this.loadProducts(true);
    this.template?.addEventListener?.('pbeinfo', this.handlePbeInfo.bind(this));
    this.template?.addEventListener?.('pbeerror', this.handlePbeError.bind(this));
    this.template?.addEventListener?.('loading', this.handleChildLoading.bind(this));
  }
  get cartCount(){
    return this.cartItems.length;
  }
  get hasCartItems(){
    return this.cartItems.length > 0;
  }

  get isCheckoutDisabled(){
    return this.cartCount === 0;
  }
  get formattedModalPrice(){
    return this.formatCurrency(this.modalProduct?.price);
  }
  async loadProducts(reset=true){
    try{
      if(reset){
        this.pageNumber=1;
        this.products=[];
        this.noResults=false;
        this.isLoading=true;
    }else{
        this.isLoadingMore=true;
      }
      const resp=await fetchProducts({
        pageNumber: this.pageNumber,
        pageSize: this.pageSize,
        searchQuery: this.searchKey,
        selectedFamilies: this.selectedFamilies,
        sortField: 'Name',
        sortDir: 'ASC'
      });
      if(resp && resp.records){
        this.totalSize=resp.totalSize || 0;
        const mapped=resp.records.map(r =>{
          const pbes=Array.isArray(r.pbes) ? r.pbes : [];
          const endpointPbes=pbes.filter(p => p && p.isFetchedFromOrg === true);
          const localPbes=pbes.filter(p => p && !p.isFetchedFromOrg);
          const chosenPbes=(endpointPbes.length > 0) ? endpointPbes : localPbes;
          let displayPrice=null;
          if(chosenPbes.length > 0){
            const firstWithPrice=chosenPbes.find(p => p && p.unitPrice != null);
            if(firstWithPrice) displayPrice=firstWithPrice.unitPrice;
          }
          if(displayPrice == null && r.price != null) displayPrice=r.price;
          return{
            id: r.id,
            name: r.name,
            productCode: r.productCode,
            description: r.description,
            family: r.family,
            isActive: r.isActive,
            sku: r.sku,
            uom: r.uom,
            productImage: r.productImage,
            isFetchedFromOrg: r.isFetchedFromOrg || endpointPbes.length > 0,
            price: displayPrice,
            pricebookId:(chosenPbes.length > 0 && chosenPbes[0].pricebookId) ? chosenPbes[0].pricebookId :(r.pricebookId || null),
            pbes: chosenPbes.map(p =>({
              pricebookEntryId: p.pricebookEntryId || null,
              pricebookId: p.pricebookId || null,
              pricebookName: p.pricebookName || null,
              unitPrice: p.unitPrice != null ? p.unitPrice : null,
              formattedUnitPrice: this.formatCurrency(p.unitPrice != null ? p.unitPrice : null),
              isActive: typeof p.isActive === 'boolean' ? p.isActive : !!p.isActive,
              productId: p.productId || null,
              productName: p.productName || null,
              sku: p.sku || null,
              isFetchedFromOrg: !!p.isFetchedFromOrg
            }))
          };
        });
        const newRecords=mapped.filter(r => !this.products.some(p => p.id === r.id));
        this.products=this.products.concat(newRecords);
        this.noResults=this.products.length === 0;
    }else{
        this.noResults=true;
      }
  }catch(err){
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error loading products',
        message: err?.body?.message || err?.message || 'Unknown error',
        variant: 'error'
      }));
  }finally{
      this.isLoading=false;
      this.isLoadingMore=false;
    }
  }
  onSearchChange(event){
    this.searchKey=event.target.value;
    this.loadProducts(true);
  }
  onGridScroll(e){
    const grid=e.currentTarget;
    if(grid.scrollTop + grid.clientHeight >= grid.scrollHeight - 200 && !this.isLoadingMore && this.products.length < this.totalSize){
      this.pageNumber += 1;
      this.loadProducts(false);
    }
  }
  handleAddToCart(e){
    const prod=e.detail;
    if(!prod || !prod.id){
      this.dispatchEvent(new ShowToastEvent({title: 'Invalid item', message: 'Cannot add item to cart', variant: 'error' }));
      return;
    }
    const cartItem ={
      id: prod.id,
      name: prod.name,
      sku: prod.sku || prod.productCode,
      price: prod.price,
      qty: 1,
      formattedPrice: this.formatCurrency(prod.price)
    };
    this.cartItems=[...this.cartItems, cartItem];
    this.dispatchEvent(new ShowToastEvent({title: 'Added to cart', message: prod.name || 'Product added', variant: 'success' }));
  }
  handleViewDetails(e){
    this.modalProduct=e.detail;
    this.showModal=true;
  }
  handlePbeInfo(evt){
    const{productId, data}= evt.detail ||{};
    this.pbeForProductId=productId;
    let rows=[];
    if(!data){
      rows=[];
  }else if(Array.isArray(data)){
      rows=data;
  }else if(data && typeof data === 'object'){
      const looksLikeRow=data.unitPrice !== undefined || data.UnitPrice !== undefined ||
                           data.pricebookEntryId !== undefined || data.Id !== undefined ||
                           data.price !== undefined;
      if(looksLikeRow){
        rows=[data];
    }else{
        const arrValue=Object.values(data).find(v => Array.isArray(v));
        rows=Array.isArray(arrValue) ? arrValue : [];
      }
    }
    const mappedRows=rows.map(p =>{
      const unitPriceVal=p.unitPrice != null ? p.unitPrice :(p.UnitPrice != null ? p.UnitPrice :(p.unit_price != null ? p.unit_price : null));
      return{
        pricebookEntryId: p.pricebookEntryId || p.PricebookEntryId || p.Id || null,
        pricebookId: p.pricebookId || p.Pricebook2Id || null,
        pricebookName: p.pricebookName || p.PricebookName ||(p.Pricebook2 ? p.Pricebook2.Name : null) || null,
        unitPrice: unitPriceVal,
        formattedUnitPrice: this.formatCurrency(unitPriceVal),
        isActive: typeof p.isActive === 'boolean' ? p.isActive : !!p.IsActive,
        productId: p.productId || p.Product2Id || null,
        productName: p.productName || p.ProductName || null,
        sku: p.sku || p.SKU || null,
        isFetchedFromOrg: !!(p.isFetchedFromOrg === true || p.isPriceFromOrg === true)
      };
    });
    this.pbeInfo=mappedRows;
    if(this.products && mappedRows.length > 0){
      const productIndex=this.products.findIndex(pr =>(pr.id || pr.Id) === productId);
      if(productIndex !== -1){
        const firstPbe=mappedRows[0];
        this.products[productIndex] ={
          ...this.products[productIndex],
          price: firstPbe.unitPrice != null ? firstPbe.unitPrice : this.products[productIndex].price,
          isFetchedFromOrg: firstPbe.isFetchedFromOrg,
          pbes: mappedRows
        };
      }
    }
    const productObj=this.products ? this.products.find(pr =>(pr.id || pr.Id) === productId) : null;
    this.modalProduct=productObj ?{...productObj}:{id: productId, name: mappedRows[0]?.productName || '', price: mappedRows[0]?.unitPrice ?? null, pbes: mappedRows };
    this.showPbeModal=true;
  }
  handlePbeError(evt){
    const{error}= evt.detail ||{};
    this.dispatchEvent(new ShowToastEvent({
      title: 'Error',
      message: error?.body?.message || error?.message || 'Failed to load Pricebook info',
      variant: 'error'
    }));
  }
  handleChildLoading(evt){
    const{isLoading}= evt.detail ||{};
    this.isLoading=!!isLoading;
  }
  closePbeModal(){
    this.showPbeModal=false;
    this.pbeInfo=[];
    this.pbeForProductId=null;
  }
  closeModal(){
    this.showModal=false;
    this.modalProduct ={};
  }
  pbeAddToCart(){
    if(!this.modalProduct || !this.modalProduct.id){
      console.error('Cannot add to cart: Invalid product data');
      return;
    }
    const item ={
      id: this.modalProduct.id,
      name: this.modalProduct.name,
      sku: this.modalProduct.sku || this.modalProduct.productCode,
      price: this.modalProduct.price,
      qty: 1,
      formattedPrice: this.formatCurrency(this.modalProduct.price)
    };
    this.cartItems=[...this.cartItems, item];
    this.closePbeModal();
    this.dispatchEvent(new ShowToastEvent({
      title: 'Added to cart',
      message: this.modalProduct.name || 'Product added',
      variant: 'success'
    }));
  }
  modalAddToCart(){
    const item ={
      id: this.modalProduct.id,
      name: this.modalProduct.name,
      sku: this.modalProduct.sku || this.modalProduct.productCode,
      price: this.modalProduct.price,
      qty: 1,
      formattedPrice: this.formatCurrency(this.modalProduct.price)
    };
    this.cartItems=[...this.cartItems, item];
    this.closeModal();
  }
  openCart(){
    this.showCart=true;
  }
  onCartKeydown(evt){
    if(evt.key === 'Enter' || evt.key === ' '){
      this.openCart();
    }
  }
  closeCart(){
    this.showCart=false;
  }
  removeFromCart(evt){
    const idToRemove=evt.currentTarget.dataset.id;
    if(!idToRemove) return;
    this.cartItems=this.cartItems.filter(i => i.id !== idToRemove);
  }
  onCheckout(){
    this.dispatchEvent(new ShowToastEvent({title: 'Checkout', message: `Proceeding with ${this.cartCount} items`, variant: 'success' }));
    this.closeCart();
    const validatedCart=this.selectedCartItems;
    try{
      sessionStorage.setItem('cart', JSON.stringify(validatedCart));
  }catch(e){
    }
    this.dispatchEvent(new CustomEvent('cartupdate',{detail:{cart: validatedCart}}));
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes:{
        apiName: 'Checkout_Page'
      },
      state:{
        fromPid: '1'
      }
    });
  }
  async openFilterPanel(){
    try{
      const families=await fetchProductFamilies();
      this.availableFamilies=families.map(family =>({
        name: family,
        selected: this.selectedFamilies.includes(family)
      }));
      this.showFilterModal=true;
  }catch(err){
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error loading families',
        message: err?.body?.message || err?.message || 'Unknown error',
        variant: 'error'
      }));
    }
  }
  closeFilterPanel(){
    this.showFilterModal=false;
  }
  handleFamilyChange(event){
    const family=event.target.value;
    const isChecked=event.target.checked;
    if(isChecked){
      this.selectedFamilies=[...this.selectedFamilies, family];
  }else{
      this.selectedFamilies=this.selectedFamilies.filter(f => f !== family);
    }
    this.availableFamilies=this.availableFamilies.map(f =>({
      ...f,
      selected: this.selectedFamilies.includes(f.name)
    }));
  }
  isFamilySelected(family){
    return this.selectedFamilies.includes(family);
  }
  applyFilters(){
    this.loadProducts(true);
    this.closeFilterPanel();
  }
  goToCheckout(){
    sessionStorage.setItem('cart', JSON.stringify(this.cartItems || []));
    this[NavigationMixin.Navigate]({
      type: 'standard__component',
      attributes:{
        componentName: 'c__checkoutPage'
      }
    });
  }
  formatCurrency(value){
    if(value === null || value === undefined) return '—';
    try{
      return new Intl.NumberFormat('en-IN',{style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(value));
  }catch(e){
      return `₹${value}`;
    }
  }
}
import{LightningElement,track,api,wire}from 'lwc';
import fetchProducts from '@salesforce/apex/ProductController.fetchProducts';
import fetchProductFamilies from '@salesforce/apex/ProductController.fetchProductFamilies';
import{ShowToastEvent}from 'lightning/platformShowToastEvent';
import{NavigationMixin}from 'lightning/navigation';
import CartIcon from '@salesforce/resourceUrl/CartIcon';
import getAccountName from '@salesforce/apex/ProductController.getAccountName';
import getOrdersForAccount from '@salesforce/apex/ProductController.getOrdersForAccount';
import deleteOrderItem from '@salesforce/apex/ProductController.removeOrderItem';
import addToOrder from '@salesforce/apex/ProductController.addToOrder';
import{CurrentPageReference}from 'lightning/navigation';
export default class ProductInformationDisplay extends NavigationMixin(LightningElement){
  // reactive state / inputs
  // -----------------------
  @api recordId;
  @track products=[];
  @track pageNumber=1;
  pageSize=12;
  @track isLoading=true;
  @track isLoadingMore=false;
  @track totalSize=0;
  @track searchKey='';
  @track noResults=false;
  @track cartItems=[];
  @track showModal=false;
  @track modalProduct ={};
  @track showCart=false;
  @track showPbeModal=false;
  @track pbeInfo=[];
  @track pbeForProductId;
  @track showFilterModal=false;
  @track selectedFamilies=[];
  @track availableFamilies=[];
  @track accountName='';
  @track orderItems=[]; // flattened draft order items shown in the cart drawer
  @track orders=[]; // raw order wrappers
  skeletons=Array.from({length:6},(_,i) => ({id:`sk-${i}`}));
  isSavingDraft=false;
  connectedCallback(){
    // Session se cart ko wapas la rahe hain — user ne page band kiya ho toh bhi list na ude
    try{
      const raw=sessionStorage.getItem('cart');
      if (raw){
        const parsed=JSON.parse(raw);
        if (Array.isArray(parsed)){
          this.cartItems=parsed;
      }
    }
  }catch (e){
      // Parsing fail ho gaya toh tension nahi — silently skip kar denge
  }
    this.loadProducts(true);
    this.template?.addEventListener?.('pbeinfo',this.handlePbeInfo.bind(this));
    this.template?.addEventListener?.('pbeerror',this.handlePbeError.bind(this));
    this.template?.addEventListener?.('loading',this.handleChildLoading.bind(this));

    window.addEventListener('beforeunload', this.handleBeforeUnload.bind(this));

    this.dispatchEvent(new CustomEvent('close'));
    // Yaha navigate nahi kar rahe — record context ko disturb nahi karna
  }
  handleBeforeUnload(event){
    if(this.allCartItems && this.allCartItems.length > 0){
      event.preventDefault();
      event.returnValue="You have items in your cart. Do you want to save them as draft before leaving?";
      this.dispatchEvent(new ShowToastEvent({
        title:'Cart has items',
        message:'Save the items as draft?',
        variant:'warning',
        mode:'sticky'
      }));
    }
  }
  // Current cart ko Draft order me save karte hain — taaki banda page se nikle toh bhi data safe rahe
  async saveCartToDraft(){
    if(this.isSavingDraft){
      this.dispatchEvent(new ShowToastEvent({
        title:'Please wait',
        message:'Cart is already being saved as draft.',
        variant:'info'
      }));
      return;
    }
    if(!this.allCartItems||this.allCartItems.length===0){
      this.dispatchEvent(new ShowToastEvent({
        title:'Empty Cart',
        message:'There are no items in the cart to save as draft.',
        variant:'info'
      }));
      return;
    }
    this.isSavingDraft=true;
    try{
      // Sirf live items save karenge — draft wale already server pe padhe hain
      const liveItemsToSave=(this.cartItems||[]).filter(item => item && item.id && item.sku);
      if(liveItemsToSave.length===0){
          this.dispatchEvent(new ShowToastEvent({
              title:'Info',
              message:'Draft order items already present, no new items to save.',
              variant:'info'
          }));
      } else {
        for(let item of liveItemsToSave){
          await addToOrder({
            accountId:this.recordId,
            productId:item.id,
            price:item.price,
            quantity:item.qty||1
          });
        }
        this.dispatchEvent(new ShowToastEvent({
          title:'Success',
          message:'Cart items have been saved as draft order.',
          variant:'success'
        }));
      }
    }catch(error){
      const msg=(error && error.body && error.body.message) ? error.body.message:'Failed to save cart as draft.';
      this.dispatchEvent(new ShowToastEvent({
        title:'Error',
        message:msg,
        variant:'error'
      }));
    }finally{
      this.isSavingDraft=false;
    }
  }
  // Sirf valid cart items return karo (checkout/session ke liye) — half-baked data se bachna hai
  @api
  get selectedCartItems(){
    return (this.cartItems||[]).filter(item => item && item.id && item.sku);
}// lifecycle
  connectedCallback(){
    // Session se cart ko wapas la rahe hain — user ne page band kiya ho toh bhi list na ude
    try{
      const raw=sessionStorage.getItem('cart');
      if (raw){
        const parsed=JSON.parse(raw);
        if (Array.isArray(parsed)){
          this.cartItems=parsed;
      }
    }
  }catch (e){
      // Parsing fail ho gaya toh koi baat nahi — quietly ignore
  }
    this.loadProducts(true);
    this.template?.addEventListener?.('pbeinfo',this.handlePbeInfo.bind(this));
    this.template?.addEventListener?.('pbeerror',this.handlePbeError.bind(this));
    this.template?.addEventListener?.('loading',this.handleChildLoading.bind(this));
    this.dispatchEvent(new CustomEvent('close'));
    // Navigation nahi karna — current record ka context maintain rehna chahiye
}
// Product loading — same logic, bas safai se handle kar rahe
  async loadProducts(reset=true){
    try{
      if (reset){
        this.pageNumber=1;
        this.products=[];
        this.noResults=false;
        this.isLoading=true;
    }else{
        this.isLoadingMore=true;
    }
      const resp=await fetchProducts({
        pageNumber:this.pageNumber,
        pageSize:this.pageSize,
        searchQuery:this.searchKey,
        selectedFamilies:this.selectedFamilies,
        sortField:'Name',
        sortDir:'ASC'
    });
      if (resp && resp.records){
        this.totalSize=resp.totalSize||0;
        // PBE me se best price pick karte hain — warna base price pe fallback
        const mapped=resp.records.map(r =>{
          const pbes=Array.isArray(r.pbes) ? r.pbes:[];
          const endpointPbes=pbes.filter(p => p && p.isFetchedFromOrg===true);
          const localPbes=pbes.filter(p => p && !p.isFetchedFromOrg);
          const chosenPbes=(endpointPbes.length > 0) ? endpointPbes:localPbes;
          let displayPrice=null;
          if (chosenPbes.length > 0){
            const firstWithPrice=chosenPbes.find(p => p && p.unitPrice != null);
            if (firstWithPrice) displayPrice=firstWithPrice.unitPrice;
        }
          if (displayPrice == null && r.price != null) displayPrice=r.price;
          return{
            id:r.id,
            name:r.name,
            productCode:r.productCode,
            description:r.description,
            family:r.family,
            isActive:r.isActive,
            sku:r.sku,
            uom:r.uom,
            productImage:r.productImage,
            isFetchedFromOrg:r.isFetchedFromOrg||endpointPbes.length > 0,
            price:displayPrice,
            pricebookId:(chosenPbes.length > 0 && chosenPbes[0].pricebookId) ? chosenPbes[0].pricebookId:(r.pricebookId||null),
            pbes:chosenPbes.map(p => ({
              pricebookEntryId:p.pricebookEntryId||null,
              pricebookId:p.pricebookId||null,
              pricebookName:p.pricebookName||null,
              unitPrice:p.unitPrice != null ? p.unitPrice:null,
              formattedUnitPrice:this.formatCurrency(p.unitPrice != null ? p.unitPrice:null),
              isActive:typeof p.isActive==='boolean' ? p.isActive:!!p.isActive,
              productId:p.productId||null,
              productName:p.productName||null,
              sku:p.sku||null,
              isFetchedFromOrg:!!p.isFetchedFromOrg
          }))
        };
      });
        const newRecords=mapped.filter(r => !this.products.some(p => p.id===r.id));
        this.products=this.products.concat(newRecords);
        this.noResults=this.products.length===0;
    }else{
        this.noResults=true;
    }
  }catch (err){
      this.dispatchEvent(new ShowToastEvent({
        title:'Error loading products',
        message:err?.body?.message||err?.message||'Unknown error',
        variant:'error'
    }));
  }finally{
      this.isLoading=false;
      this.isLoadingMore=false;
  }
}
// URL/button se recordId aaya ho toh page state se pakad lo — handy when deep-linking
  @wire(CurrentPageReference)
  wiredPageRef(pageRef){
    if (pageRef && pageRef.state){
      const state=pageRef.state;
      this.recordId=state.c__recordId||state.recordId||this.recordId||null;
      const encodedAccountName=state.c__accountName||null;
      if (encodedAccountName){
        this.accountName=decodeURIComponent(encodedAccountName.replace(/\+/g,' '));
    }else{
        if (this.recordId && !this.accountName){
          this.getAccountName().then(accountName =>{
            this.accountName=accountName||'';
        });
      }
    }
  }
}
  // -----------------------
  // Orders wire — Draft order items ko hamesha sync me rakho
  // -----------------------
  @wire(getOrdersForAccount,{accountId:'$recordId'})
  wiredOrders({error,data}){
    if(data){
      try{
        // Always map to a safe structure
        let filtered=(data||[]).filter(w => w && w.order && w.order.Status==='Draft')
          .map(w => ({
            order:w.order,
            orderItems:Array.isArray(w.orderItems) ? w.orderItems.slice():[]
          }));

        // Apply optimistic deletion filter only if we actually deleted something
        if (this._deletedDraftItemIds && this._deletedDraftItemIds.size > 0) {
          const deletedSet=this._deletedDraftItemIds;
          filtered=filtered.map(w => ({
            ...w,
            orderItems:(w.orderItems||[]).filter(oi => oi && !deletedSet.has(oi.Id))
          }));
        }
        // If we have optimistic adds, append them but DO NOT override existing server items
        if (this._optimisticAdds && this._optimisticAdds.length) {
          if (filtered.length===0) {
            filtered=[{ order:{ Status:'Draft' }, orderItems:[] }];
          }
          filtered[0]={
            ...filtered[0],
            orderItems:(filtered[0].orderItems||[]).concat(this._optimisticAdds)
          };
        }

        this.orders=filtered;
      }catch(e){
        console.error('wiredOrders mapping error', e);
        this.orders=[];
      }
    }else if(error){
      console.error('Error loading orders for account',error);
      this.orders=[];
    }else{
      this.orders=[];
    }
  }
  // -----------------------
  // Chhote getters — UI ko saaf data dene ke liye
  // -----------------------
  get allCartItems(){
    // Show ONLY Draft Order Items from backend
    if (!Array.isArray(this.orders)||this.orders.length===0) return [];
    return this.orders.flatMap(wrapper => {
      if (!wrapper||!wrapper.orderItems) return [];
      return wrapper.orderItems.map(oi => ({
        id:oi.Id,
        name:oi.Product2 ? oi.Product2.Name:'',
        qty:oi.Quantity,
        productCode:oi.Product2 ? oi.Product2.ProductCode:'',
        price:oi.UnitPrice,
        unitPrice:oi.UnitPrice,
        formattedPrice:this.formatCurrency(oi.UnitPrice),
        source:'draft'
      }));
    });
  }
  get cartCount(){
    if (!this.allCartItems) return 0;
    return this.allCartItems.reduce((total, item) => total + (item.qty||1), 0);
}
  get hasCartItems(){
    return (this.allCartItems||[]).length > 0;
}
  get isCheckoutDisabled(){
    return this.cartCount===0;
}
  get hasActiveFilters(){
    return this.selectedFamilies.length > 0;
}
  get filterBtnClass(){
    return this.hasActiveFilters ? 'filter-btn-active':'';
}
  get formattedModalPrice(){
    return this.formatCurrency(this.modalProduct?.price);
}
  get cartIconUrl(){
    return CartIcon + '/CartIcon.png';
}
  // -----------------------
  // Session persistence helper — browser storage me thoda state hold karke rakhte hain
  // -----------------------
  saveCartToSession(){
    try{
      const cartWithAccountId=(this.allCartItems||[]).map(item => ({
        ...item,
        accountId:this.recordId
      }));
      sessionStorage.setItem('cart',JSON.stringify(cartWithAccountId));
  }catch (e){
      console.error('saveCartToSession failed',e); // Local storage kabhi block ho sakta — error log karke aage badh jao
  }
  }// Product loading — idempotent aur paginated
  async loadProducts(reset=true){
    try{
      if (reset){
        this.pageNumber=1;
        this.products=[];
        this.noResults=false;
        this.isLoading=true;
    }else{
        this.isLoadingMore=true;
    }
      const resp=await fetchProducts({
        pageNumber:this.pageNumber,
        pageSize:this.pageSize,
        searchQuery:this.searchKey,
        selectedFamilies:this.selectedFamilies,
        sortField:'Name',
        sortDir:'ASC'
    });
      if (resp && resp.records){
        this.totalSize=resp.totalSize||0;
        const mapped=resp.records.map(r =>{
          const pbes=Array.isArray(r.pbes) ? r.pbes:[];
          const endpointPbes=pbes.filter(p => p && p.isFetchedFromOrg===true);
          const localPbes=pbes.filter(p => p && !p.isFetchedFromOrg);
          const chosenPbes=(endpointPbes.length > 0) ? endpointPbes:localPbes;
          let displayPrice=null;
          if (chosenPbes.length > 0){
            const firstWithPrice=chosenPbes.find(p => p && p.unitPrice != null);
            if (firstWithPrice) displayPrice=firstWithPrice.unitPrice;
        }
          if (displayPrice == null && r.price != null) displayPrice=r.price;
          return{
            id:r.id,
            name:r.name,
            productCode:r.productCode,
            description:r.description,
            family:r.family,
            isActive:r.isActive,
            sku:r.sku,
            uom:r.uom,
            productImage:r.productImage,
            isFetchedFromOrg:r.isFetchedFromOrg||endpointPbes.length > 0,
            price:displayPrice,
            pricebookId:(chosenPbes.length > 0 && chosenPbes[0].pricebookId) ? chosenPbes[0].pricebookId:(r.pricebookId||null),
            pbes:chosenPbes.map(p => ({
              pricebookEntryId:p.pricebookEntryId||null,
              pricebookId:p.pricebookId||null,
              pricebookName:p.pricebookName||null,
              unitPrice:p.unitPrice != null ? p.unitPrice:null,
              formattedUnitPrice:this.formatCurrency(p.unitPrice != null ? p.unitPrice:null),
              isActive:typeof p.isActive==='boolean' ? p.isActive:!!p.isActive,
              productId:p.productId||null,
              productName:p.productName||null,
              sku:p.sku||null,
              isFetchedFromOrg:!!p.isFetchedFromOrg
          }))
        };
      });
        const newRecords=mapped.filter(r => !this.products.some(p => p.id===r.id));
        this.products=this.products.concat(newRecords);
        this.noResults=this.products.length===0;
    }else{
        this.noResults=true;
    }
  }catch (err){
      this.dispatchEvent(new ShowToastEvent({
        title:'Error loading products',
        message:err?.body?.message||err?.message||'Unknown error',
        variant:'error'
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
    // Infinite scroll ka jugaad — neeche pahunchte hi next page lao
    const grid=e.currentTarget;
    if (grid.scrollTop + grid.clientHeight >= grid.scrollHeight - 200 && !this.isLoadingMore && this.products.length < this.totalSize){
      this.pageNumber += 1;
      this.loadProducts(false);
  }
}
  // Cart handlers — UI-only, yaha server-side DML nahi chalega
  @track isAddingToCart=false;
  async handleAddToCart(e){
    const prod=e.detail;
    if (!prod||!prod.id){
      this.dispatchEvent(new ShowToastEvent({title:'Invalid item',message:'Cannot add item to cart',variant:'error'}));
      return;
    }
    if(this.isAddingToCart){
      this.dispatchEvent(new ShowToastEvent({title:'Please wait',message:'Item is being added to cart, please wait...',variant:'info'}));
      return;
    }
 // Optimistic UI add
    const tempId=`temp_${prod.id}_${Date.now()}`;
    this._optimisticallyAddDraftItem(tempId, prod);
    this.isAddingToCart=true;
    try {
      await addToOrder({accountId:this.recordId, productId:prod.id, price:prod.price, quantity:prod.qty || 1});
      // Important:don't clear optimistic adds until wire brings back server items
      // Just trigger refresh; optimistic items will coexist until server echoes the new item
      this._forceOrdersRefresh();
      this.dispatchEvent(new ShowToastEvent({title:'Added to cart',message:prod.name||'Product added',variant:'success'}));
    } catch (error) {
      // Roll back optimistic row
      this._removeOptimisticItem(tempId);
      this.dispatchEvent(new ShowToastEvent({title:'Info',message:'Item is already in cart.',variant:'Info'}));
    } finally {
      this.isAddingToCart=false;
    }
  }
  handleViewDetails(e){
    this.modalProduct=e.detail;
    this.showModal=true;
    if (this.recordId){
      this.getAccountName().then(accountName =>{
        this.accountName=accountName||'';
    });
  }
}
  handlePbeInfo(evt){
    // PBE data ko normalize karke readable format me convert kar rahe — UI ko clean rows milen
    const{productId,data}= evt.detail ||{};
    this.pbeForProductId=productId;
    let rows=[];
    if (!data){
      rows=[];
  }else if (Array.isArray(data)){
      rows=data;
  }else if (data && typeof data==='object'){
      const looksLikeRow=data.unitPrice !== undefined||data.UnitPrice !== undefined ||
        data.pricebookEntryId !== undefined||data.Id !== undefined ||
        data.price !== undefined;
      if (looksLikeRow){
        rows=[data];
    }else{
        const arrValue=Object.values(data).find(v => Array.isArray(v));
        rows=Array.isArray(arrValue) ? arrValue:[];
    }
  }
    const mappedRows=rows.map(p =>{
      const unitPriceVal=p.unitPrice != null ? p.unitPrice:(p.UnitPrice != null ? p.UnitPrice:(p.unit_price != null ? p.unit_price:null));
      return{
        pricebookEntryId:p.pricebookEntryId||p.PricebookEntryId||p.Id||null,
        pricebookId:p.pricebookId||p.Pricebook2Id||null,
        pricebookName:p.pricebookName||p.PricebookName||(p.Pricebook2 ? p.Pricebook2.Name:null)||null,
        unitPrice:unitPriceVal,
        formattedUnitPrice:this.formatCurrency(unitPriceVal),
        isActive:typeof p.isActive==='boolean' ? p.isActive:!!p.IsActive,
        productId:p.productId||p.Product2Id||null,
        productName:p.productName||p.ProductName||null,
        sku:p.sku||p.SKU||null,
        isFetchedFromOrg:!!(p.isFetchedFromOrg===true||p.isPriceFromOrg===true)
    };
  });
    this.pbeInfo=mappedRows;
    if (this.products && mappedRows.length > 0){
      const productIndex=this.products.findIndex(pr => (pr.id||pr.Id)===productId);
      if (productIndex !== -1){
        const firstPbe=mappedRows[0];
        this.products[productIndex] ={
          ...this.products[productIndex],
          price:firstPbe.unitPrice != null ? firstPbe.unitPrice:this.products[productIndex].price,
          isFetchedFromOrg:firstPbe.isFetchedFromOrg,
          pbes:mappedRows
      };
    }
  }
    const productObj=this.products ? this.products.find(pr => (pr.id||pr.Id)===productId):null;
    this.modalProduct=productObj ?{...productObj}:{id:productId,name:mappedRows[0]?.productName||'',price:mappedRows[0]?.unitPrice ?? null,pbes:mappedRows};
    this.showPbeModal=true;
}
  handlePbeError(evt){
    // Agar PBE fetch me kuch gadbad — user ko simple error dikhado
    const{error}= evt.detail ||{};
    this.dispatchEvent(new ShowToastEvent({
      title:'Error',
      message:error?.body?.message||error?.message||'Failed to load Pricebook info',
      variant:'error'
  }));
}
  handleChildLoading(evt){
    // Child component se loading state bubble karwa rahe — ek hi spinner ka source
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
  // PBE modal se direct cart me daalna — sirf UI level par
  pbeAddToCart(){
    if (!this.modalProduct||!this.modalProduct.id){
      console.error('Cannot add to cart:Invalid product data');
      return;
  }
    const existing=this.cartItems.find(i => i.id===this.modalProduct.id);
    if (existing){
      this.dispatchEvent(new ShowToastEvent({title:'Already in cart',message:`${this.modalProduct.name}is already in the cart.`,variant:'info'}));
      return;
  }
    const item ={
      id:this.modalProduct.id,
      name:this.modalProduct.name,
      sku:this.modalProduct.sku||this.modalProduct.productCode||null,
      price:this.modalProduct.price,
      qty:this.modalProduct.qty || 1,
      formattedPrice:this.formatCurrency(this.modalProduct.price)
  };
    this.cartItems=[...this.cartItems,item];
    this.saveCartToSession();
    this.closePbeModal();
    this.dispatchEvent(new ShowToastEvent({
      title:'Added to cart',
      message:this.modalProduct.name||'Product added',
      variant:'success'
  }));
}
  // Generic modal add-to-cart — UI-only flow
  modalAddToCart(){
    const existing=this.cartItems.find(i => i.id===this.modalProduct.id);
    if (existing){
      this.dispatchEvent(new ShowToastEvent({title:'Already in cart',message:`${this.modalProduct.name}is already in the cart.`,variant:'info'}));
      return;
  }
    const item ={
      id:this.modalProduct.id,
      name:this.modalProduct.name,
      sku:this.modalProduct.sku||this.modalProduct.productCode||null,
      price:this.modalProduct.price,
      qty:this.modalProduct.qty || 1,
      formattedPrice:this.formatCurrency(this.modalProduct.price)
  };
    this.cartItems=[...this.cartItems,item];
    this.saveCartToSession();
    this.closeModal();
}

  async openCart(){
    this.showCart=true;
}
  onCartKeydown(evt){
    if (evt.key==='Enter'||evt.key===' '){
      this.openCart();
  }
}
  closeCart(){
    this.showCart=false;
}
  // Client cart se item hatao — sirf UI side pe
  async removeFromCart(evt){
    const idToRemove=evt.currentTarget.dataset.id;
    if (!idToRemove) return;
    this.cartItems=this.cartItems.filter(i => i.id !== idToRemove);
    this.saveCartToSession();
    this.dispatchEvent(new ShowToastEvent({title:'Removed',message:'Item removed from cart',variant:'success'}));
  }
  async removeItem(evt){
    const idToRemove=evt.currentTarget.dataset.id;
    const source=evt.currentTarget.dataset.source;
    if (!idToRemove) return;
    // Optimistic UI delete:remove immediately and mark as deleted to suppress reappearance until refresh completes
    this._optimisticDelete(idToRemove);
    try{
      if(source==='draft'){
        await deleteOrderItem({orderItemId:idToRemove});
        this.dispatchEvent(new ShowToastEvent({title:'Draft item removed',message:'Draft item removed permanently',variant:'success'}));
      }else{
        this.removeFromCart(evt);
      }
      // Re-fetch authoritative data
      this._forceOrdersRefresh();
    }catch(error){
      // Roll back optimistic delete on failure
      this._rollbackOptimisticDelete(idToRemove);
      this.dispatchEvent(new ShowToastEvent({title:'Error',message:'Failed to remove item. Please try again.',variant:'error'}));
    }
  }
  // -----------------------
  // Checkout / Navigation — clean hand-off to next screen
  // -----------------------
  onCheckout(){
    this.dispatchEvent(new ShowToastEvent({title:'Checkout',message:`Proceeding with ${this.cartCount}items`,variant:'success'}));
    this.closeCart();
    // Send all cart items (both live and draft) to checkout page
    const allCartItems=this.allCartItems||[];
    // Session me daalne se pehle har item ko account context de dete — baad me kaam aayega
    const cartWithAccountId=allCartItems.map(item => ({
      ...item,
      accountId:this.recordId,
      // Ensure UnitPrice is included for consistency
      unitPrice:item.price||item.unitPrice||null
    }));
    try{
      sessionStorage.setItem('cart',JSON.stringify(cartWithAccountId));
  }catch (e){
      console.error('sessionStorage set failed',e); // Kuch browsers me storage tight ho sakti — log karke nikal lo
  }
    this.dispatchEvent(new CustomEvent('cartupdate',{detail:{cart:cartWithAccountId}}));
    this[NavigationMixin.Navigate]({
      type:'standard__navItemPage',
      attributes:{
        apiName:'Checkout_Page'
    },
      state:{
        accountId:this.recordId,
        fromPid:'1'
    }
  });
}
  // Filters + utils — yaha UX polish baithti hai
  async openFilterPanel(){
    try{
      const families=await fetchProductFamilies();
      this.availableFamilies=families.map(family => ({
        name:family,
        selected:this.selectedFamilies.includes(family)
    }));
      this.showFilterModal=true;
  }catch (err){
      this.dispatchEvent(new ShowToastEvent({
        title:'Error loading families',
        message:err?.body?.message||err?.message||'Unknown error',
        variant:'error'
    })); // Family fetch fail — user ko context de do
  }
}
  closeFilterPanel(){
    this.showFilterModal=false;
}
  handleFamilyChange(event){
    const family=event.target.value;
    const isChecked=event.target.checked;
    if (isChecked){
      this.selectedFamilies=[...this.selectedFamilies,family];
  }else{
      this.selectedFamilies=this.selectedFamilies.filter(f => f !== family);
  }
    this.availableFamilies=this.availableFamilies.map(f => ({
      ...f,
      selected:this.selectedFamilies.includes(f.name)
  }));
}
  isFamilySelected(family){
    return this.selectedFamilies.includes(family);
}
  applyFilters(){
    // Selected filters apply karke product list refresh kar lo
    this.loadProducts(true);
    this.closeFilterPanel();
}
  goToCheckout(){
    this.saveCartToSession();
    this[NavigationMixin.Navigate]({
      type:'standard__component',
      attributes:{
        componentName:'c__checkoutPage'
    }
  });
}
  formatCurrency(value){
    // Price ko human-friendly INR me dikhate — fallback bhi rakha
    if (value===null||value===undefined) return '—';
    try{
      return new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(Number(value));
  }catch (e){
      return `₹${value}`; // Worst-case — raw value ko rupee prefix ke sath dikha do
  }
}
  async getAccountName(){
    // Account ka naam lazily fetch karte — UI me friendly text ke liye
    if (this.recordId){
      try{
        const result=await getAccountName({recordId:this.recordId});
        return result;
      }catch (error){
        console.error('Error fetching account name:',error); // Fetch fail hua toh null dekar gracefully degrade karo
        return null;
      }
    }
    return null;
  }
  // Optimistic UI helpers and refresh utilities
  _ordersRefreshKey=0;
  _optimisticAdds=[];
  _deletedDraftItemIds=new Set();
  _forceOrdersRefresh(){
    // Reassign recordId to retrigger wire; schedule microtask to avoid sync glitches
    this._ordersRefreshKey++;
    const prev=this.recordId;
    this.recordId=null;
    Promise.resolve().then(() => { this.recordId=prev; });
  }
  _optimisticallyAddDraftItem(tempId, prod){
    const optimisticRow={
      Id:tempId,
      Quantity:prod.qty || 1,
      UnitPrice:prod.price,
      Product2:{ Name:prod.name, ProductCode:prod.sku||prod.productCode||'' }
    };
    this._optimisticAdds=[...this._optimisticAdds, optimisticRow];
    // Proactively update UI without waiting for wire — append to existing first wrapper instead of replacing
    if (Array.isArray(this.orders) && this.orders.length > 0) {
      const first=this.orders[0];
      const currentItems=Array.isArray(first.orderItems) ? first.orderItems.slice():[];
      const next=[{ ...first, orderItems:currentItems.concat([optimisticRow]) }].concat(this.orders.slice(1));
      this.orders=next;
    } else {
      this.orders=[{ order:{ Status:'Draft' }, orderItems:[optimisticRow] }];
    }
  }
  _removeOptimisticItem(tempId){
    this._optimisticAdds=this._optimisticAdds.filter(r => r.Id !== tempId);
    // Remove from visible list too
    if (this.orders && this.orders[0] && Array.isArray(this.orders[0].orderItems)) {
      this.orders=[{
        ...this.orders[0],
        orderItems:this.orders[0].orderItems.filter(r => r.Id !== tempId)
      }];
    }
  }
  _clearOptimisticAdds(){
    // Keep optimistic adds until we see a server item with same Product2 or a new orderItem echo, to avoid vanishing
    // This function is no longer used after add; retained for possible future explicit clears.
  }
  _optimisticDelete(orderItemId){
    // Remove item from current orders view immediately
    if (Array.isArray(this.orders)) {
      this.orders=this.orders.map(w => ({
        ...w,
        orderItems:(w.orderItems||[]).filter(oi => oi.Id !== orderItemId)
      }));
    }
    // Track as deleted so wired refresh doesn't re-add it transiently
    this._deletedDraftItemIds.add(orderItemId);
  }
  _rollbackOptimisticDelete(orderItemId){
    // Simply remove the deletion mark; next refresh will bring it back
    this._deletedDraftItemIds.delete(orderItemId);
    this._forceOrdersRefresh();
  }
}

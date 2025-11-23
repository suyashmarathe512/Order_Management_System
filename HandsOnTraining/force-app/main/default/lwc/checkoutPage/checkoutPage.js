import { LightningElement, track, api, wire } from 'lwc';
import createOrderFromCart from '@salesforce/apex/CheckOutController.createOrderFromCart';
import saveOrderAsDraft from '@salesforce/apex/CheckOutController.saveOrderAsDraft';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getAccountInfo from '@salesforce/apex/CheckOutController.getAccountInfo';
import getContractsForAccount from '@salesforce/apex/CheckOutController.getContractsForAccount';
export default class CheckoutPage extends NavigationMixin(LightningElement){
  @track _cart=[];
  @track isLoading=false;
  @track orderResult=null;
  @track selectedAccountId=null;
  @track accountName=null;
  @track selectedContractId=null;
  @track contracts = [];
  @track billingAddress={
    street:'',
    city:'',
    state:'',
    postalCode:'',
    country:''
};
  @track shippingAddress={
    street:'',
    city:'',
    state:'',
    postalCode:'',
    country:''
};
  @api
  get cart(){
    return this._cart;
}
  set cart(value){
    this._cart=(value || []).map(i=>{
      const price=Number(i.price || 0);
      const qty=Number(i.qty || 1);
      const lineTotal=price * qty;
      return{
        ...i,
        price,
        qty,
        lineTotal,
        formattedPrice:this.currencyFormatter(price),
        formattedLineTotal:this.currencyFormatter(lineTotal)
    };
  });
}
  connectedCallback(){
    try{
      const raw=sessionStorage.getItem('cart');
      if(raw){
        const parsed=JSON.parse(raw);
        if(Array.isArray(parsed)){
          // Extract account info from first item (all items should have same account)
          if(parsed.length > 0 && parsed[0].accountId){
            this.selectedAccountId = parsed[0].accountId;
            // Get account info when component loads
            this.getAccountDetails(this.selectedAccountId);
          }
          this.cart=parsed.map(item=>({
            id:item.id,
            name:item.name,
            sku:item.sku,
            price:Number(item.price ?? item.unitPrice ?? item.UnitPrice ?? 0),
            qty:Number(item.qty || 1),
            accountId: item.accountId || null
        }));
      }
    }
  }catch(e){
  }
    const handleCartUpdate=(event)=>{
      if(event.detail && event.detail.cart){
        this.cart=event.detail.cart.map(item=>({
          id:item.id,
          name:item.name,
          sku:item.sku,
          price:Number(item.price ?? item.unitPrice ?? item.UnitPrice ?? 0),
          qty:Number(item.qty || 1),
          accountId: item.accountId || null
      }));
        try{
          sessionStorage.setItem('cart',JSON.stringify(this.cart));
      }catch(e){
      }
    }
  };
    console.log('cart:',this.cart);
    this.addEventListener('cartupdate',handleCartUpdate);
    
    // Empty the cart from sessionStorage when arriving at checkout page
    // This ensures the cart is cleared when user gets redirected to checkout
    try {
      sessionStorage.removeItem('cart');
    } catch(e) {
      // Ignore errors when clearing sessionStorage
    }

    // Add beforeunload event listener for refresh warning
    window.addEventListener('beforeunload', this.handleBeforeUnload);
}
  get total(){
    return this.cart.reduce((sum,it)=> sum +((it.price || 0) *(it.qty || 1)),0);
}

  get formattedTotal(){
    return this.currencyFormatter(this.total);
}

  get currencyFormatter(){
    return(val)=>{
      const num=Number(val || 0);
      try{
        return new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(num);
    }catch(e){
        return `₹${num}`;
    }
  };
}
  get lineTotalCalculator(){
    return(item)=>{
      const qty=Number(item?.qty || 1);
      const price=Number(item?.price || 0);
      return qty * price;
  };
}
  handleQtyButton(evt){
    const id=evt.currentTarget.dataset.id;
    const dir=evt.currentTarget.dataset.dir;
    this.cart=this.cart.map(i=>{
      if(i.id !==id) return i;
      let next=Number(i.qty || 1);
      next=dir==='inc'?next+1 :next - 1;
      if(!next || next < 1) next=1;
      if(next > 9999) next=9999;
      const price=Number(i.price || 0);
      const lineTotal=price * next;
      return{
        ...i,
        qty:next,
        lineTotal,
        formattedPrice:this.currencyFormatter(price),
        formattedLineTotal:this.currencyFormatter(lineTotal)
    };
  });
    try{
      sessionStorage.setItem('cart',JSON.stringify(this.cart));
  }catch(e){
  }
}
  handleQtyChange(evt){
    const id=evt.target.dataset.id;
    let qty=parseInt(evt.target.value,10);
    if(!qty || qty < 1) qty=1;
    if(qty > 9999) qty=9999;
    this.cart=this.cart.map(i=> i.id===id ?{...i,qty}:i);
    try{
      sessionStorage.setItem('cart',JSON.stringify(this.cart));
  }catch(e){
  }
}
  removeLine(evt){
    const id=evt.target.dataset.id;
    this._cart=this._cart.filter(i=> i.id !==id);
    try{
      sessionStorage.setItem('cart',JSON.stringify(this._cart));
  }catch(e){
  }
}
  placeOrder(){
  const cartArray=Array.from(this.cart || []);
  if(!cartArray.length){
    this.dispatchEvent(new ShowToastEvent({
      title:'Empty cart',
      message:'Add products first',
      variant:'warning'
  }));
    return;
}
  if(!this.selectedAccountId){
    this.dispatchEvent(new ShowToastEvent({
      title:'Account required',
      message:'Select an Account',
      variant:'warning'
  }));
    return;
}
  if(!this.selectedContractId){
    this.dispatchEvent(new ShowToastEvent({
      title:'Contract required',
      message:'Select a Contract',
      variant:'warning'
  }));
    return;
}
  this.isLoading=true;
  const productIds=cartArray.map(item=> item.id);
  const names=cartArray.map(item=> item.name);
  const skus=cartArray.map(item=> item.sku);
  const qtys=cartArray.map(item=> item.qty);
  const prices=cartArray.map(item=> item.price);
  
  // Create address objects
  const billingAddress = {
    street: this.billingAddress.street,
    city: this.billingAddress.city,
    state: this.billingAddress.state,
    postalCode: this.billingAddress.postalCode,
    country: this.billingAddress.country
  };
  
  const shippingAddress = {
    street: this.shippingAddress.street,
    city: this.shippingAddress.city,
    state: this.shippingAddress.state,
    postalCode: this.shippingAddress.postalCode,
    country: this.shippingAddress.country
  };
  
  // Create order parameters object
  const orderParams = {
    productIds: productIds,
    names: names,
    skus: skus,
    qtys: qtys,
    prices: prices,
    accountId: this.selectedAccountId,
    contractId: this.selectedContractId,
    billingAddress: billingAddress,
    shippingAddress: shippingAddress
  };
  
  createOrderFromCart(orderParams)
    .then(res=>{
      this.orderResult=res;
      this.dispatchEvent(new ShowToastEvent({
        title:'Order Created',
        message:`Order ${res.orderId}created(${res.lineItemCount}lines)`,
        variant:'success'
    }));
      sessionStorage.removeItem('cart');
      this.cart=[];
      if(res.contentVersionId){
        const cvId=res.contentVersionId;
        const url=window.location.origin+'/sfc/servlet.shepherd/version/download/'+cvId;
        window.open(url,'_blank');
    }else if(res.contentDocumentId){
        const docId=res.contentDocumentId;
        const url=window.location.origin+'/sfc/servlet.shepherd/document/download?docId='+docId;
        window.open(url,'_blank');
    }else{
        const vfUrl=window.location.origin+'/apex/InvoicePdf?id='+res.orderId;
        this[NavigationMixin.Navigate]({
          type:'standard__webPage',
          attributes:{
            url:vfUrl
        }
      });
    }
  })
    .catch(err=>{
      console.error('Order creation error:',JSON.stringify(err));
      this.dispatchEvent(new ShowToastEvent({
        title:'Order failed',
        message:(err && err.body && err.body.message)?err.body.message :(err && err.message)?err.message :'Unknown error',
        variant:'error'
    }));
  })
    .finally(()=>{
      this.isLoading=false;
  });
}

  getAccountDetails(accountId) {
    if (accountId) {
      getAccountInfo({accountId: accountId})
        .then(result => {
          if (result) {
            this.accountName = result.name;
            // Auto-populate shipping and billing addresses from account fields
            this.billingAddress = {
              street: result.billingStreet || '',
              city: result.billingCity || '',
              state: result.billingState || '',
              postalCode: result.billingPostalCode || '',
              country: result.billingCountry || ''
            };
            this.shippingAddress = {
              street: result.shippingStreet || '',
              city: result.shippingCity || '',
              state: result.shippingState || '',
              postalCode: result.shippingPostalCode || '',
              country: result.shippingCountry || ''
            };
          }
        })
        .catch(error => {
          console.error('Error fetching account details:', error);
        });
      // Fetch contracts for the account
      getContractsForAccount({accountId: accountId})
        .then(result => {
          this.contracts = result || [];
        })
        .catch(error => {
          console.error('Error fetching contracts:', error);
          this.contracts = [];
        });
    }
  }
  handleBillingChange(evt){
    this.billingAddress={...evt.detail};
}
  handleShippingChange(evt){
    this.shippingAddress={...evt.detail};
}
  handleContractChange(evt) {
    this.selectedContractId = evt.target.value;
  }

  @wire(CurrentPageReference)
  wiredPageRef(pageRef) {
    if (pageRef && pageRef.state) {
      const accountId = pageRef.state.accountId;
      if (accountId && accountId !== this.selectedAccountId) {
        this.selectedAccountId = accountId;
        this.getAccountDetails(accountId);
      }
    }
  }

  disconnectedCallback() {
    // Remove beforeunload event listener
    window.removeEventListener('beforeunload', this.handleBeforeUnload);
  }

  handleBeforeUnload(event) {
    // Show warning message on refresh/close
    event.preventDefault();
    event.returnValue = 'Are you sure you want to refresh? Your cart and entered information will be lost.';
    return event.returnValue;
  }
}

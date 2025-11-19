import{LightningElement,track,api}from 'lwc';
import createOrderFromCart from '@salesforce/apex/CheckOutController.createOrderFromCart';
import{ShowToastEvent}from 'lightning/platformShowToastEvent';
import{NavigationMixin}from 'lightning/navigation';
export default class CheckoutPage extends NavigationMixin(LightningElement){
  @track _cart=[];
  @track isLoading=false;
  @track orderResult=null;
  @track accountName='';
  @track showAccountModal=false;
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
          this.cart=parsed.map(item=>({
            id:item.id,
            name:item.name,
            sku:item.sku,
            price:Number(item.price ?? item.unitPrice ?? item.UnitPrice ?? 0),
            qty:Number(item.qty || 1)
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
          qty:Number(item.qty || 1)
      }));
        try{
          sessionStorage.setItem('cart',JSON.stringify(this.cart));
      }catch(e){
      }
    }
  };
    console.log('cart:',this.cart);
    this.addEventListener('cartupdate',handleCartUpdate);
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
  if(!this.accountName){
    this.dispatchEvent(new ShowToastEvent({
      title:'Account required',
      message:'Enter Account Name',
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
  createOrderFromCart({
    productIds,
    names,
    skus,
    qtys,
    prices,
    accountName:this.accountName,
    billingStreet:this.billingAddress.street,
    billingCity:this.billingAddress.city,
    billingState:this.billingAddress.state,
    billingPostalCode:this.billingAddress.postalCode,
    billingCountry:this.billingAddress.country,
    shippingStreet:this.shippingAddress.street,
    shippingCity:this.shippingAddress.city,
    shippingState:this.shippingAddress.state,
    shippingPostalCode:this.shippingAddress.postalCode,
    shippingCountry:this.shippingAddress.country
})
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
  handleAccountChange(evt){
    this.accountName=evt.target.value;
}
  openNewAccountModal(){
    this.showAccountModal=true;
}

  closeAccountModal(){
    this.showAccountModal=false;
}
  handleAccountSuccess(event){
    const accountId=event.detail.id;
    const accountName=event.detail.fields.Name.value;
    this.accountName=accountName;
    this.showAccountModal=false;
    this.dispatchEvent(new ShowToastEvent({
      title:'Account Created',
      message:`Account "${accountName}" created successfully`,
      variant:'success'
  }));
}
  handleBillingChange(evt){
    this.billingAddress={...evt.detail};
}
  handleShippingChange(evt){
    this.shippingAddress={...evt.detail};
}
}
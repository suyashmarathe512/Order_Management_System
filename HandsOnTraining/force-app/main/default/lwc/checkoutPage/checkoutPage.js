import { LightningElement, track, api, wire } from 'lwc';
import createOrderFromCart from '@salesforce/apex/CheckOutController.createOrderFromCart';
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
          if(parsed.length > 0){
            // Check if first item has accountId, if not, check if we have a page reference with accountId
            if(parsed[0].accountId){
              this.selectedAccountId = parsed[0].accountId;
              // Get account info when component loads
              this.getAccountDetails(this.selectedAccountId);
            } else if (this.selectedAccountId) {
              // If we already have selectedAccountId from page reference, use it
              this.getAccountDetails(this.selectedAccountId);
            }
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
    console.error('Error processing cart from session storage:', e);
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
                    console.error('Error saving cart to session storage:', e);
                }
            }
        };

        console.log('cart:',this.cart);
        this.addEventListener('cartupdate',handleCartUpdate);

        // Ensure contracts are loaded when component loads with account info
        if (this.selectedAccountId) {
            this.getAccountDetails(this.selectedAccountId);
        }

        // Empty the cart from sessionStorage when arriving at checkout page
        // This ensures the cart is cleared when user gets redirected to checkout
        // Commented out to fix issue where accountId vanishes on redirect due to cart clearing
        // try {
        //   sessionStorage.removeItem('cart');
        // } catch(e) {
        //   // Ignore errors when clearing sessionStorage
        // }

        // Add beforeunload event listener for refresh warning
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
            console.error('Error saving cart to session storage:', e);
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
            console.error('Error saving cart to session storage:', e);
        }
    }

    removeLine(evt){
        const id=evt.target.dataset.id;
        this._cart=this._cart.filter(i=> i.id !==id);
        try{
            sessionStorage.setItem('cart',JSON.stringify(this._cart));
        }catch(e){
            console.error('Error saving cart to session storage:', e);
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
        // Hardcoded contractId as requested
        const orderParams = {
            orderProductIds: productIds,
            names: names,
            skus: skus,
            qtys: qtys,
            prices: prices,
            accountId: this.selectedAccountId,
            contractId: '800d200001Zp7h7AAB', // Hardcoded contractId as requested
            billingStreet: billingAddress.street,
            billingCity: billingAddress.city,
            billingState: billingAddress.state,
            billingPostalCode: billingAddress.postalCode,
            billingCountry: billingAddress.country,
            shippingStreet: shippingAddress.street,
            shippingCity: shippingAddress.city,
            shippingState: shippingAddress.state,
            shippingPostalCode: shippingAddress.postalCode,
            shippingCountry: shippingAddress.country
        };
        console.log('Order parameters being sent to Apex:', JSON.stringify(orderParams));
        createOrderFromCart(orderParams)
            .then(res=>{
                this.orderResult=res;
                this.dispatchEvent(new ShowToastEvent({
                    title:'Order Created',
                    message:`Order ${res.orderId} created (${res.lineItemCount} lines)`,
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
                this.dispatchEvent(new ShowToastEvent({
                    title:'Order failed',
                    message: errorMessage,
                    variant:'error'
                }));
            })
            .finally(()=>{
                this.isLoading=false;
            });
    }

    getAccountDetails(accountId) {
        if (accountId) {
            // Fetch account info first
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
                    // Add debugging to see what's actually returned
                    console.log('Contracts received:', result);
                    // Ensure contracts are properly assigned
                    if (result && Array.isArray(result)) {
                        this.contracts = result;
                        console.log('Contracts assigned to component:', this.contracts);
                    } else {
                        this.contracts = [];
                        console.log('No contracts returned, setting empty array');
                    }
                })
                .catch(error => {
                    console.error('Error fetching contracts:', error);
                    this.contracts = [];
                    console.log('Error occurred, setting empty contracts array');
                });
        }
    }

    handleBillingChange(evt){
        const field = evt.target.dataset.field;
        this.billingAddress = {
            ...this.billingAddress,
            [field]: evt.target.value
        };
    }

    handleShippingChange(evt){
        const field = evt.target.dataset.field;
        this.shippingAddress = {
            ...this.shippingAddress,
            [field]: evt.target.value
        };
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

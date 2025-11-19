import{LightningElement,api,track}from 'lwc';
import caller from '@salesforce/apex/ProductController.caller';
export default class ProductCard extends LightningElement{
  @track _product={};
  @api
  get product(){
    return this._product;
}
  set product(value){
    if(value){
      this._product={
        id: value.id||value.Id||null,
        name: value.name||value.Name||'',
        description: value.description||value.Description||'',
        family: value.family||value.Family||'',
        sku: value.sku||value.StockKeepingUnit||value.SKU||'',
        price: value.price !== undefined ? value.price :(value.unitPrice !== undefined ? value.unitPrice : null),
        isFetchedFromOrg: value.isFetchedFromOrg=== true||value.isPriceFromOrg=== true||false,
        ...value
    };
  }else{
      this._product={};
  }
}
  get ariaLabel(){
    const name=this._product?.name||'Product';
    return `Product: ${name}`;
}
  get displayName(){
    return this._product?.name||this._product?.Name||'Product';
}
  get displayFamily(){
    return this._product?.family||this._product?.Family||'';
}
  get displayDescription(){
    return this._product?.description||this._product?.Description||'';
}
  get productImage(){
    return this._product?.ProductImage__c||this._product?.productImage||null;
}
  get imageHidden(){
    return !this.productImage;
}
  get hasPrice(){
    return this._product && this._product.price !== null && this._product.price !== undefined;
}
  get formattedPrice(){
    const price=this._product?.price;
    if(price=== null||price=== undefined) return '';
    try{
      return new Intl.NumberFormat('en-IN',{style: 'currency',currency: 'INR',maximumFractionDigits: 0}).format(price);
  }catch(e){
      return `₹${price}`;
  }
}
  get isFetchedFromOrg(){
    return !!(this._product &&(this._product.isFetchedFromOrg=== true||this._product.isPriceFromOrg=== true));
}
  async onView(){
    const viewBtn=this.template.querySelector('.btn-view');
    if(viewBtn) viewBtn.disabled=true;
    const productId=this._product?.id||this._product?.Id;
    if(!productId){
      this.dispatchEvent(new CustomEvent('showtoast',{
        detail:{variant: 'error',title: 'Missing Product Id',message: 'Unable to fetch pricebook info. No Product Id found.'},
        bubbles: true,composed: true
    }));
      if(viewBtn) viewBtn.disabled=false;
      return;
  }
    this.dispatchEvent(new CustomEvent('loading',{detail:{isLoading: true},bubbles: true,composed: true}));
    try{
      const apexResult=await caller({recordId: productId});
      let pbeInfo=apexResult;
      if(typeof apexResult=== 'string'){
        try{pbeInfo=JSON.parse(apexResult);}catch(e){}
    }
      if(pbeInfo && typeof pbeInfo=== 'object'){
        if(!Array.isArray(pbeInfo)){
          if(Array.isArray(pbeInfo.rows)) pbeInfo=pbeInfo.rows;
          else if(Array.isArray(pbeInfo.data)) pbeInfo=pbeInfo.data;
          else pbeInfo=[pbeInfo];
      }
    }
      const rows=Array.isArray(pbeInfo) ? pbeInfo : [];
      let foundRow=null;
      for(const r of rows){
        if(!r) continue;
        const candidates=[
          r.unitPrice,r.UnitPrice,r.unit_price,r.unitprice,r.price,
          r.pricebookEntry?.UnitPrice,(r.data &&(r.data.unitPrice||r.data.UnitPrice||r.data.unit_price))
        ];
        if(candidates.some(c=> c !== undefined && c !== null && c !== '')){
          foundRow=r;
          break;
      }
    }
      if(!foundRow){
        this._product={...this._product,pbes: []};
        this.dispatchEvent(new CustomEvent('pbeinfo',{detail:{productId,data: []},bubbles: true,composed: true}));
    }else{
        const extractPrice=(obj)=>{
          if(!obj) return null;
          const maybe=obj.unitPrice ?? obj.UnitPrice ?? obj.unit_price ?? obj.unitprice ?? obj.price;
          if(maybe !== undefined && maybe !== null && maybe !== ''){
            const num=Number(maybe);
            return Number.isFinite(num) ? num : null;
        }
          if(obj.data){
            const m=obj.data.unitPrice ?? obj.data.UnitPrice ?? obj.data.unit_price ?? obj.data.price;
            const num2=m !== undefined && m !== null && m !== '' ? Number(m) : null;
            return Number.isFinite(num2) ? num2 : null;
        }
          return null;
      };
        const numericPrice=extractPrice(foundRow);
        const normalizedPbe={
          pricebookEntryId: foundRow.pricebookEntryId ?? foundRow.Id ?? null,
          pricebookId: foundRow.pricebookId ?? foundRow.Pricebook2Id ?? null,
          pricebookName: foundRow.pricebookName ?? foundRow.PricebookName ??(foundRow.Pricebook2 ? foundRow.Pricebook2.Name : null),
          unitPrice: numericPrice,
          isActive: !!(foundRow.isActive ?? foundRow.IsActive),
          productId: foundRow.productId ?? foundRow.Product2Id ?? this._product.id,
          productName: foundRow.productName ?? foundRow.ProductName ?? this._product.name,
          sku: foundRow.sku ?? foundRow.SKU ?? this._product.sku,
          isFetchedFromOrg: !!(foundRow.isFetchedFromOrg=== true||foundRow.isFetchedFromOrg=== 'true'||foundRow.isPriceFromOrg=== true)
      };
        this._product={
          ...this._product,
          price: numericPrice !== null ? numericPrice : this._product.price,
          isFetchedFromOrg: normalizedPbe.isFetchedFromOrg,
          pbes: [normalizedPbe]
      };
        this.dispatchEvent(new CustomEvent('pbeinfo',{detail:{productId,data: normalizedPbe},bubbles: true,composed: true}));
    }
  }catch(error){
      const message=error?.body?.message||error?.message||'Failed to fetch Pricebook Entry information. Please try again.';
      this.dispatchEvent(new CustomEvent('showtoast',{detail:{variant: 'error',title: 'PBE Fetch Failed',message},bubbles: true,composed: true}));
      this.dispatchEvent(new CustomEvent('pbeerror',{detail:{productId,error},bubbles: true,composed: true}));
  }finally{
      this.dispatchEvent(new CustomEvent('loading',{detail:{isLoading: false},bubbles: true,composed: true}));
      if(viewBtn) viewBtn.disabled=false;
  }
}
}
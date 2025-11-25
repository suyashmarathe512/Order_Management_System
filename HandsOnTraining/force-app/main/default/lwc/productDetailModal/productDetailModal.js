import{ LightningElement, api }from 'lwc';
export default class ProductDetailModal extends LightningElement{
    @api product;
    get formattedPrice(){
        if (!this.product || this.product.price === null || this.product.price === undefined){
            return '';
        }
        try{
            return new Intl.NumberFormat('en-IN',{
                style:'currency',
                currency:'INR',
                maximumFractionDigits:0
            }).format(this.product.price);
        }catch (e){
            return `₹${this.product.price}`;
        }
    }
    get productStatus(){
        if (this.product && this.product.isActive !== undefined && this.product.isActive !== null){
            return this.product.isActive ? 'Active' :'Inactive';
        }
        return 'Unknown';
    }
    handleClose(){
        const closeModalEvent=new CustomEvent('closemodal');
        this.dispatchEvent(closeModalEvent);
    }
}

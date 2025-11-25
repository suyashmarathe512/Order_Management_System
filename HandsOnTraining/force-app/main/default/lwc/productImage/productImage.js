// file: productImageViewer.js
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
// Field on Product2
import PRODUCT_IMAGE_ID from '@salesforce/schema/Product2.ProductImage_Id__c';
const FIELDS = [PRODUCT_IMAGE_ID];
export default class ProductImageViewer extends LightningElement {
    @api recordId; // Product2 Id from the record page

    productImageId;
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProduct({ data, error }) {
        if (data) {
            this.productImageId = data.fields.ProductImage_Id__c.value;
        } else if (error) {
            // optional: handle error / show message
            console.error('Error loading product image field', error);
        }
    }
    // Build the same image URL used in the formula, but relative path is enough in LWC
    get imageUrl() {
        return this.productImageId
            ? `/sfc/servlet.shepherd/document/download/${this.productImageId}`
            : null;
    }

    get hasImage() {
        return !!this.imageUrl;
    }
}

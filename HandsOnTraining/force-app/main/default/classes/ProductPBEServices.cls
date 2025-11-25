/***************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    ProductPBEServices
 * @Description:   This class allowed the POST method to accept the product Id 
 *                 and return the PBE for the product.
 ******************************************************************************************/
@RestResource(urlMapping='/product/pbeinfo')
global with sharing class ProductPBEServices{
/***************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    getPBEInfo
 * @Description:   This method allowed the POST method to accept the product Id 
 *                 and return the PBE for the product.
 ******************************************************************************************/
    @HttpPost
    global static void getPBEInfo(){
        RestResponse response=RestContext.response;
        response.addHeader('Content-Type','application/json;');
        String key=RestContext.request.requestBody != null?RestContext.request.requestBody.toString() : null;
        if(String.isBlank(key)){
            response.statusCode=400;
            response.responseBody=Blob.valueOf(
                JSON.serialize(
                    new Map<String,String>{ 'error' => 'Request body must be a product Id.'}));
            return;
        }
        key=key.trim();
        if(key.startsWith('"') && key.endsWith('"')){
            key=key.substring(1,key.length() - 1);
        }
        Product2 prod;
        try{
            prod=[
                SELECT 
                    Id 
                FROM 
                    Product2 
                WHERE 
                    Id=:key 
                LIMIT 1
            ];
        }catch(Exception e){
            prod=null;
        }
        if(prod==null){
            response.statusCode=200;
            response.responseBody=Blob.valueOf('null');
            return;
        }
        Decimal unitPrice;
        try{
            PricebookEntry pbe=[
                SELECT 
                    UnitPrice
                FROM 
                    PricebookEntry
                WHERE 
                    Product2Id=:prod.Id 
                AND 
                    IsActive=true
                ORDER BY 
                    UnitPrice ASC
                LIMIT 1
            ];
            unitPrice=(pbe != null)?pbe.UnitPrice : null;
        }catch(Exception e){
            unitPrice=null;
        }
        response.statusCode=200;
        response.responseBody=Blob.valueOf(
            unitPrice==null?'null' : String.valueOf(unitPrice)
        );
    }
}
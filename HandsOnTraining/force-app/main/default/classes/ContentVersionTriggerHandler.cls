public class ContentVersionTriggerHandler{
    public static void linkProductImages(List<ContentVersion> newVersions){
        if (newVersions==null || newVersions.isEmpty()){
            return;
        }
        // Collect all unique titles (used as Product2.Name)
        Set<String> titles=new Set<String>();
        for (ContentVersion cv:newVersions){
            if (String.isNotBlank(cv.Title)){
                titles.add(cv.Title.trim());
            }
        }
        if (titles.isEmpty()){
            return;
        }
        // Get all products whose Name matches any of the file titles
        Map<String,Product2> nameToProduct=new Map<String,Product2>();
        for (Product2 p:[
            SELECT 
                Id,Name,ProductImage_Id__c
            FROM 
                Product2
            WHERE 
                Name 
            IN :titles
        ]){
            nameToProduct.put(p.Name,p);
        }
        if (nameToProduct.isEmpty()){
            return;
        }
        // Prepare updates: set ProductImage_Id__c=ContentDocumentId
        List<Product2> productsToUpdate=new List<Product2>();
        for (ContentVersion cv:newVersions){
            if (String.isBlank(cv.Title) || cv.ContentDocumentId==null){
                continue;
            }
            String key=cv.Title.trim();
            Product2 prod=nameToProduct.get(key);
            if (prod==null) continue;
            // Only update if value is actually different
            String newImageId=String.valueOf(cv.ContentDocumentId);
            if (prod.ProductImage_Id__c != newImageId){
                prod.ProductImage_Id__c=newImageId;
                productsToUpdate.add(prod);
            }
        }
        if (!productsToUpdate.isEmpty()){
            update productsToUpdate;
        }
    }
}

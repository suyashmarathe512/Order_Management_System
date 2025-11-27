/***************************************************************************************
 * @Author:     CRM Team Innovation
 * @ClassName:   FileService
 * @Description:  This class allowed the POST method to accept the file 
                     from the external sysstem and insert it in the Org.
 ******************************************************************************************/
@RestResource(urlMapping='/fileservice/*')
global class FileService{
/***************************************************************************************
 * @Author:     CRM Team Innovation
 * @MethodName:   recieveFile
 * @Description:  This method allowed the POST method to accept the file 
                     from the external sysstem and insert it in the Org.
 ******************************************************************************************/
    @HttpPost
    global static void receiveFile(){
        RestRequest req=RestContext.request;
        Blob fileBlob=req.requestBody;
        String accountNameParam='';
        String fileNameParam='';
        Map<String, String> queryParams=req.params;
        if(queryParams != null && !queryParams.isEmpty()){
            accountNameParam=queryParams.containsKey('accountName')?queryParams.get('accountName'):'';
            fileNameParam   =queryParams.containsKey('fileName')?queryParams.get('fileName'):'';
        }
        Id firstPublishLocationId=UserInfo.getUserId(); // Default to current user
        if(accountNameParam != null && accountNameParam.trim() != ''){
            List<Account> accs=[SELECT 
                                    Id 
                                FROM 
                                    Account 
                                WHERE 
                                    Name=:accountNameParam 
                                LIMIT 1];
            if(!accs.isEmpty()){
                firstPublishLocationId=accs[0].Id;
            }else{
                try{
                    Account newAcc=new Account(Name=accountNameParam);
                    insert newAcc;
                    firstPublishLocationId=newAcc.Id;
                }catch(DmlException e){
                    // On failure, keep as user
                }
            }
        }
        if(fileBlob != null && fileBlob.size() > 0){
            ContentVersion contentVersion=new ContentVersion();
            String titleName='Invoice_'+DateTime.now().format('yyyy-MM-dd_HH-mm-ss');
            String pathName='/Invoice_'+DateTime.now().format('yyyy-MM-dd_HH-mm-ss')+'.pdf';
            if(fileNameParam != null && fileNameParam != ''){
                if(fileNameParam.endsWith('.pdf')){
                    titleName=fileNameParam.substring(0, fileNameParam.length()-4);
                }else{
                    titleName=fileNameParam;
                }
                if(!fileNameParam.startsWith('/')){
                    pathName='/'+fileNameParam;
                }else{
                    pathName=fileNameParam;
                }
            }           contentVersion.Title=titleName;
            contentVersion.PathOnClient=pathName;
            contentVersion.VersionData=fileBlob;
            contentVersion.ContentLocation='S';
            contentVersion.FirstPublishLocationId=firstPublishLocationId;
            try{
                insert contentVersion;
                RestContext.response.responseBody=Blob.valueOf('{"status":"success", "contentVersionId":"'+contentVersion.Id+'"}');
                RestContext.response.statusCode=200;
            }catch(DmlException dmlEx){
                RestContext.response.responseBody=Blob.valueOf('{"status":"error", "message":"Failed to save file"}');
                RestContext.response.statusCode=500;
            }
        }else{
            RestContext.response.responseBody=Blob.valueOf('{"status":"error", "message":"No file received"}');
            RestContext.response.statusCode=400;
        }
    }
}
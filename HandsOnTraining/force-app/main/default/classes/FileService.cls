/***************************************************************************************
 * @Author :      CRM Team Innovation
 * @ClassName:    FileService
 * @Description:   This class allowed the POST method to accept the file 
                     from the external sysstem and insert it in the Org.
 ******************************************************************************************/
@RestResource(urlMapping='/fileservice/*')
global class FileService{
/***************************************************************************************
 * @Author :      CRM Team Innovation
 * @MethodName:    recieveFile
 * @Description:   This method allowed the POST method to accept the file 
                     from the external sysstem and insert it in the Org.
 ******************************************************************************************/
    @HttpPost
    global static void receiveFile(){
        RestRequest req=RestContext.request;
        Blob fileBlob=req.requestBody;
        if (fileBlob != null && fileBlob.size() > 0){
            String timestamp=DateTime.now().format('yyyy-MM-dd_HH-mm-ss');
            ContentVersion cv=new ContentVersion();
            cv.Title='Invoice_' + timestamp;
            cv.PathOnClient='/Invoice_' + timestamp + '.pdf';
            cv.VersionData=fileBlob;
            cv.ContentLocation='S';
            insert cv;
            RestContext.response.responseBody=Blob.valueOf('{"status": "success", "contentVersionId": "' + cv.Id + '"}');
            RestContext.response.statusCode=200;
        }else{
            RestContext.response.responseBody=Blob.valueOf('{"status": "error", "message": "No file received"}');
            RestContext.response.statusCode=400;
        }
    }
}
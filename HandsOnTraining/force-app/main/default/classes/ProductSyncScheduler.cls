public class ProductSyncScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ProductSyncBatch(), 200);
        Datetime now = Datetime.now();
        Datetime nextRun = now.addMinutes(15);
        String seconds = '0';
        String minutes = String.valueOf(nextRun.minute());
        String hours = String.valueOf(nextRun.hour());
        String cronExp = seconds + ' ' + minutes + ' ' + hours + ' * * ?';
        System.abortJob(sc.getTriggerId());
        System.schedule('Product Sync Scheduler', cronExp, new ProductSyncScheduler());
    }
}

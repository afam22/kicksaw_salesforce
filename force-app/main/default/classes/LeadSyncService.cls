public with sharing class LeadSyncService {
    // 50-100 is the safe zone for callout batch sizes to avoid the 100-callout limit per transaction
    public static final Integer BATCH_SIZE = 50;

    public static void enqueue(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        
        // Execute the Batch natively. Salesforce will automatically chunk it by BATCH_SIZE
        Database.executeBatch(new LeadSyncBatch(leadIds), BATCH_SIZE);
    }
}
public with sharing class LeadSyncService {
    // Chunking keeps governors limit safe if a batch update inserts thousands of leads
    public static final Integer CHUNK_SIZE = 50;

    public static void enqueue(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        // Enqueue only ONE job from the trigger context
        System.enqueueJob(new LeadSyncQueueable(new List<Id>(leadIds)));
    }
}
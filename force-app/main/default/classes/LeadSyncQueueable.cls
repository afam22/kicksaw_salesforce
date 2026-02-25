public with sharing class LeadSyncQueueable 
    implements Queueable, Database.AllowsCallouts {

    private List<Id> leadIds;

    public LeadSyncQueueable(List<Id> leadIds) {
        this.leadIds = (leadIds == null) ? new List<Id>() : leadIds;
    }

    public void execute(QueueableContext qc) {
        if (leadIds.isEmpty()) {
            return;
        }

        ChunkResult chunk = splitChunk();

        List<Lead> leads = queryLeads(chunk.currentChunk);

        ProcessingResult result = processLeads(leads);

        updateLeads(result.updates, result.logs);

        IntegrationLogger.flush(result.logs);

        chainIfNeeded(chunk.remaining);
    }

    // ---------------- PRIVATE HELPERS ----------------

    private ChunkResult splitChunk() {

        List<Id> currentChunk = new List<Id>();
        List<Id> remaining = new List<Id>();

        Integer sizeLimit = Math.min(LeadSyncService.CHUNK_SIZE, leadIds.size());

        //build current chunk(first chunkSize records) 
        for (Integer i = 0; i < sizeLimit; i++) {
            currentChunk.add(leadIds[i]);
        }

        //build remaining chunk(records after first chunkSize records)
        for (Integer i = sizeLimit; i < leadIds.size(); i++) {
            remaining.add(leadIds[i]);
        }
        return new ChunkResult(currentChunk, remaining);
    }

    private List<Lead> queryLeads(List<Id> ids) {
        return [
            SELECT Id, FirstName, LastName, Company, Email,
                   LeadSource, Status, External_Reference_Id__c
            FROM Lead
            WHERE Id IN :ids
        ];
    }

    private ProcessingResult processLeads(List<Lead> leads) {
        List<Lead> updates = new List<Lead>();
        List<IntegrationLogger.LogEntry> logs = new List<IntegrationLogger.LogEntry>();

        for (Lead lead : leads) {
            try {
                LeadApiClient.Response resp = LeadApiClient.sendLead(lead);

                if (resp.success && !String.isBlank(resp.externalId)) {
                    updates.add(new Lead(
                        Id = lead.Id,
                        External_Reference_Id__c = resp.externalId
                    ));
                } else if (!resp.success) {
                    logs.add(IntegrationLogger.error(
                        'LeadSync',
                        lead.Id,
                        resp.errorMessage,
                        resp.statusCode,
                        resp.rawResponse
                    ));
                }

            } catch (Exception ex) {
                logs.add(IntegrationLogger.error(
                    'LeadSync',
                    lead.Id,
                    ex.getMessage(),
                    null,
                    null
                ));
            }
        }

        return new ProcessingResult(updates, logs);
    }

    private void updateLeads(List<Lead> updates, List<IntegrationLogger.LogEntry> logs) {
        if (updates.isEmpty()) {
            return;
        }

        Database.SaveResult[] sr = Database.update(updates, false);

        for (Integer i = 0; i < sr.size(); i++) {
            if (!sr[i].isSuccess()) {
                logs.add(IntegrationLogger.error(
                    'LeadSync',
                    updates[i].Id,
                    sr[i].getErrors()[0].getMessage(),
                    null,
                    null
                ));
            }
        }
    }

    private void chainIfNeeded(List<Id> remaining) {
        if (!remaining.isEmpty()) {
            System.enqueueJob(new LeadSyncQueueable(remaining));
        }
    }

    // ---------------- HELPER CLASSES ----------------

    private class ChunkResult {
        List<Id> currentChunk;
        List<Id> remaining;

        ChunkResult(List<Id> currentChunk, List<Id> remaining) {
            this.currentChunk = currentChunk;
            this.remaining = remaining;
        }
    }

    private class ProcessingResult {
        List<Lead> updates;
        List<IntegrationLogger.LogEntry> logs;

        ProcessingResult(List<Lead> updates, List<IntegrationLogger.LogEntry> logs) {
            this.updates = updates;
            this.logs = logs;
        }
    }
}
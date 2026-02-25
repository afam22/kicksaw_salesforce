public with sharing class LeadSyncBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    
    private Set<Id> leadIds;

    // Accept the specific IDs from the Trigger
    public LeadSyncBatch(Set<Id> leadIds) {
        this.leadIds = (leadIds == null) ? new Set<Id>() : leadIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Guard: if no IDs, return an "empty" query locator safely
        if (leadIds == null || leadIds.isEmpty()) {
            return Database.getQueryLocator('SELECT Id FROM Lead WHERE Id = null');
        }
        // Query only the leads passed from the trigger
        return Database.getQueryLocator([
            SELECT Id, FirstName, LastName, Company, Email, LeadSource, Status, External_Reference_Id__c FROM Lead
            WHERE Id IN :leadIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead> scope) {

        if (scope == null || scope.isEmpty()) {
            return;
        }
        List<Lead> updates = new List<Lead>();
        List<IntegrationLogger.LogEntry> logs = new List<IntegrationLogger.LogEntry>();

        for (Lead lead : scope) {
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

        // DML Update
        if (!updates.isEmpty()) {
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

        // Flush Logs
        IntegrationLogger.flush(logs);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('LeadSyncBatch finished. JobId=' + bc.getJobId());
        // Optional: Send an email alert to the admin if the batch fails, 
        // but for this assignment, leaving it empty for now.
    }
}
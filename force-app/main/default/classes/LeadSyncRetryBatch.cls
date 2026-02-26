/**
 * LeadSyncRetryBatch
 *
 * Scheduled sweeper that retries Lead sync for records where External_Reference_Id__c
 * is still blank after the initial trigger-driven batch. Designed to recover from
 * transient API failures (e.g., 429 rate limits, timeouts) without manual intervention.
 *
 * Why this class performs callouts directly (not via LeadSyncService):
 *   Salesforce does not allow Database.executeBatch() to be called from within
 *   a batch execute() method. Delegating to LeadSyncService would violate this
 *   platform restriction. Instead, this class implements Database.AllowsCallouts
 *   and replicates the callout + DML writeback pattern from LeadSyncBatch directly.
 *
 * Constructor:
 *   new LeadSyncRetryBatch()    — production/scheduler use, applies 5-minute delay
 *   new LeadSyncRetryBatch(0)   — manual/testing use, retries all unsynced leads immediately
 */
public with sharing class LeadSyncRetryBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {

    private static final Integer DEFAULT_DELAY_MINUTES = 5;

    // Instance variable serialised with the batch job — survives all transaction boundaries.
    private Integer retryDelayMinutes;

    public LeadSyncRetryBatch() {
        this.retryDelayMinutes = DEFAULT_DELAY_MINUTES;
    }

    public LeadSyncRetryBatch(Integer delayMinutes) {
        this.retryDelayMinutes = (delayMinutes != null && delayMinutes >= 0)
            ? delayMinutes
            : DEFAULT_DELAY_MINUTES;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = System.now().addMinutes(-retryDelayMinutes);

        return Database.getQueryLocator([
            SELECT Id, FirstName, LastName, Company, Email, LeadSource, Status, External_Reference_Id__c
            FROM Lead
            WHERE External_Reference_Id__c = null
            AND   CreatedDate <= :cutoff
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
                        Id                       = lead.Id,
                        External_Reference_Id__c = resp.externalId
                    ));
                } else if (!resp.success) {
                    logs.add(IntegrationLogger.error(
                        'LeadSyncRetry',
                        lead.Id,
                        resp.errorMessage,
                        resp.statusCode,
                        resp.rawResponse
                    ));
                }

            } catch (Exception ex) {
                logs.add(IntegrationLogger.error(
                    'LeadSyncRetry',
                    lead.Id,
                    ex.getMessage(),
                    null,
                    null
                ));
            }
        }

        // Partial success DML — one bad record never blocks the rest
        if (!updates.isEmpty()) {
            Database.SaveResult[] sr = Database.update(updates, false);
            for (Integer i = 0; i < sr.size(); i++) {
                if (!sr[i].isSuccess()) {
                    logs.add(IntegrationLogger.error(
                        'LeadSyncRetry',
                        updates[i].Id,
                        sr[i].getErrors()[0].getMessage(),
                        null,
                        null
                    ));
                }
            }
        }

        IntegrationLogger.flush(logs);

        System.debug('LeadSyncRetryBatch: processed ' + scope.size() +
                     ' leads, updated ' + updates.size() + ', errors ' + logs.size());
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('LeadSyncRetryBatch finished. JobId=' + bc.getJobId());
    }
}
public with sharing class IntegrationLogger {
    public class LogEntry {
        public String integrationName;
        public Id recordId;
        public String message;
        public Integer statusCode;
        public String rawResponse;
        public Datetime occurredAt;
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static LogEntry error(String name, Id recordId, String message, Integer statusCode, String rawResponse) {
        LogEntry logEntry = new LogEntry();
        logEntry.integrationName = name;
        logEntry.recordId = recordId;
        logEntry.message = message;
        logEntry.statusCode = statusCode;
        logEntry.rawResponse = rawResponse;
        logEntry.occurredAt = System.now();
        return logEntry;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void flush(List<LogEntry> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }

        // CRUD: object create permission
        if (!Schema.sObjectType.Integration_Log__c.isCreateable()) {
            debugFallback(entries);
            return;
        }

        List<Integration_Log__c> logsToInsert = new List<Integration_Log__c>();
        for (LogEntry e : entries) {
            Integration_Log__c log = new Integration_Log__c();

            // Assign values (FLS will be enforced via stripInaccessible below)
            log.Integration_Name__c = e.integrationName;
            log.Record_Id__c        = String.valueOf(e.recordId);
            log.Message__c          = e.message;
            log.Status_Code__c      = e.statusCode;
            log.Raw_Response__c     = e.rawResponse;
            log.Occurred_At__c      = e.occurredAt;

            logsToInsert.add(log);
        }

        // FLS: remove fields user can’t create
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.CREATABLE, logsToInsert);

        List<SObject> sanitized = decision.getRecords();
        if (sanitized.isEmpty()) {
            debugFallback(entries);
            return;
        }

        try {
            Database.insert(sanitized, false);
        } catch (Exception ex) {
            // never fail
            System.debug('Logging insert failed: ' + ex.getMessage());
            debugFallback(entries);
        }
    }

    private static void debugFallback(List<LogEntry> entries) {
        for (LogEntry e : entries) {
            System.debug('LOG(' + e.integrationName + '): ' + e.message);
        }
    }
}
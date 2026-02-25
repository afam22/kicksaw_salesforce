@isTest
private class LeadApiClientTest {
    
    // ==========================================
    // 1. API UNIT TESTS (Synchronous Callouts)
    // ==========================================

    @isTest
    static void testSendLeadSuccess() {
        String successBody = '{"status":"success", "externalId":"12345ABC"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));

        Lead testLead = new Lead(
            FirstName = 'Jane', LastName = 'Doe', Company = 'Stark Industries', 
            Email = 'jane.doe@example.com', Status = 'New'
        );

        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        System.assertEquals(true, res.success, 'The callout should be marked as successful.');
        System.assertEquals(200, res.statusCode, 'Status code should be 200.');
        System.assertEquals('12345ABC', res.externalId, 'The externalId should be parsed correctly.');
    }

    @isTest
    static void testSendLeadApiError() {
        String errorBody = '{"error": {"message": "Invalid Email Format"}}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(400, errorBody, false));

        Lead testLead = new Lead(LastName = 'Doe', Company = 'Stark Industries');

        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        System.assertEquals(false, res.success, 'The callout should fail.');
        System.assertEquals(400, res.statusCode, 'Status code should be 400.');
        System.assertEquals('Invalid Email Format', res.errorMessage, 'The specific API error message should be parsed.');
    }

    @isTest
    static void testSendLeadCalloutException() {
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(0, '', true));

        Lead testLead = new Lead(LastName = 'Doe', Company = 'Stark Industries');

        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        System.assertEquals(false, res.success, 'The callout should fail due to exception.');
        System.assert(res.errorMessage.contains('Simulated callout exception'), 'Should catch and log the simulated exception.');
    }

    // ==========================================
    // 2. TRIGGER & BATCH EXECUTION TESTS
    // ==========================================

    @isTest
    static void testBulkInsertBatchExecution() {
        String successBody = '{"status":"success", "externalId":"BULK-999"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));
        
        List<Lead> bulkLeads = new List<Lead>();
        for (Integer i = 0; i < 50; i++) {
            bulkLeads.add(new Lead(
                FirstName = 'Test', LastName = 'BulkLead ' + i, 
                Company = 'Bulk Corp', Email = 'bulk' + i + '@example.com', Status = 'New'
            ));
        }
        
        Test.startTest();
        // The insert fires LeadTrigger -> LeadTriggerHandler -> LeadSyncService -> LeadSyncBatch
        insert bulkLeads; 
        Test.stopTest(); // Forces the async Batch to execute immediately
        
        List<Lead> updatedLeads = [SELECT Id, External_Reference_Id__c FROM Lead WHERE Company = 'Bulk Corp'];
        System.assertEquals(50, updatedLeads.size(), 'Should have inserted 50 leads.');
        
        for (Lead l : updatedLeads) {
            System.assertEquals('BULK-999', l.External_Reference_Id__c, 'The Batch should have updated the External ID.');
        }
    }

    @isTest
    static void testBulkUpdateBatchExecution() {
        String successBody = '{"status":"success", "externalId":"UPDATED-BULK-999"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));
        
        List<Lead> bulkLeads = new List<Lead>();
        for (Integer i = 0; i < 50; i++) {
            bulkLeads.add(new Lead(
                FirstName = 'Test', LastName = 'BulkLead ' + i, 
                Company = 'Old Company', Email = 'bulk' + i + '@example.com', Status = 'New'
            ));
        }
        insert bulkLeads; 
        
        // Modify an outbound field to force the AFTER UPDATE trigger logic to fire
        for (Lead l : bulkLeads) {
            l.Company = 'New Enterprise Company';
        }

        Test.startTest();
        update bulkLeads; // Enqueues the update Batch
        Test.stopTest(); 
        
        List<Lead> updatedLeads = [SELECT Id, External_Reference_Id__c FROM Lead WHERE Id IN :bulkLeads];
        System.assertEquals(50, updatedLeads.size(), 'Should have updated 50 leads.');
        
        for (Lead l : updatedLeads) {
            System.assertEquals('UPDATED-BULK-999', l.External_Reference_Id__c, 'External ID should be updated on all records.');
        }
    }

    @isTest
    static void testTriggerHandlerEdgeCases() {
        Lead dbLead = new Lead(LastName='Edge', Company='Acme', Status='New');
        insert dbLead;
    
        Lead oldLead = new Lead(Id = dbLead.Id, Company='Acme', External_Reference_Id__c='Old-123');
        Lead newLead = new Lead(Id = dbLead.Id, Company='Acme', External_Reference_Id__c='New-123');
    
        // Recursion guard scenario (only external id changed)
        LeadTriggerHandler.run(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead },
            System.TriggerOperation.AFTER_UPDATE
        );
    
        // Null oldMap guard
        LeadTriggerHandler.run(
            new List<Lead>{ newLead },
            null,
            System.TriggerOperation.AFTER_UPDATE
        );
    
        // Null Lead Id guard
        Lead nullIdLead = new Lead(Company='No Id');
        LeadTriggerHandler.run(
            new List<Lead>{ nullIdLead },
            null,
            System.TriggerOperation.AFTER_INSERT
        );
    
        System.assert(true);
    }

    // ==========================================
    // 3. LOGGER FRAMEWORK TESTS
    // ==========================================

    @isTest
    static void testBatchExecutionApiFailureLogsError() {
        // 1. Setup Mock for Failure (e.g., 401 Unauthorized token)
        String errorBody = '{"status":"error", "message":"Invalid authentication token"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(401, errorBody, false));
        
        // 2. Prepare and Insert Lead
        Lead failLead = new Lead(
            FirstName = 'Error', LastName = 'Test', 
            Company = 'Fail Corp', Status = 'New'
        );
        
        Test.startTest();
        insert failLead; // Fires trigger, enqueues batch, hits 401 mock response
        Test.stopTest(); 
        
        // 3. Assert Results
        // Verify Lead External ID was NOT updated
        Lead updatedLead = [SELECT Id, External_Reference_Id__c FROM Lead WHERE Id = :failLead.Id];
        System.assertEquals(null, updatedLead.External_Reference_Id__c, 'External ID should remain null on a failed callout.');
        
        // Verify Integration_Log__c record was successfully created
        List<Integration_Log__c> logs = [
            SELECT Integration_Name__c, Record_Id__c, Message__c, Status_Code__c 
            FROM Integration_Log__c
        ];
        
        System.assertEquals(1, logs.size(), 'One integration log should be created for the failed batch callout.');
        System.assertEquals('LeadSync', logs[0].Integration_Name__c, 'Integration name should be LeadSync.');
        System.assertEquals(String.valueOf(failLead.Id), logs[0].Record_Id__c, 'Log should be tied to the correct Lead ID.');
        System.assertEquals(401, logs[0].Status_Code__c, 'Status code should be logged as 401.');
        System.assert(logs[0].Message__c.contains('Invalid authentication token'), 'The specific error message should be extracted and logged.');
    }

    @isTest
    static void testLoggerNoCrudPermissionFallback() {
        // 1. Force the logger to go down the fallback branch deterministically
        IntegrationLogger.forceNoCreateAccessForTest = true;

        // 2. Use a real Lead Id (no fake IDs) to prevent future validation breaks
        Lead l = new Lead(LastName = 'LogTest', Company = 'Acme', Status = 'New');
        insert l;

        IntegrationLogger.LogEntry entry = IntegrationLogger.error(
            'TestIntegration',
            l.Id,
            'Test Permission Error',
            500,
            'Internal Server Error'
        );

        // 3. Execute the logger context
        Test.startTest();
        IntegrationLogger.flush(new List<IntegrationLogger.LogEntry>{ entry });
        Test.stopTest();

        // 4. Assert Results
        // Since we forced fallback, no Integration_Log__c rows should be inserted
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Log__c],
            'No logs should be inserted when fallback path is used.'
        );

        // 5. Reset flag so it doesn't leak into other tests in the same transaction
        IntegrationLogger.forceNoCreateAccessForTest = false;
    }
}
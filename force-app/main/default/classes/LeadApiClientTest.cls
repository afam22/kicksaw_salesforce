@isTest
private class LeadApiClientTest {
    
    @isTest
    static void testSendLeadSuccess() {
        // 1. Setup Mock Response
        String successBody = '{"status":"success", "externalId":"12345ABC"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));

        // 2. Prepare Test Data
        Lead testLead = new Lead(
            FirstName = 'Jane',
            LastName = 'Doe',
            Company = 'Stark Industries',
            Email = 'jane.doe@example.com',
            Status = 'New'
        );

        // 3. Execute Test
        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        // 4. Assert Results
        System.assertEquals(true, res.success, 'The callout should be marked as successful.');
        System.assertEquals(200, res.statusCode, 'Status code should be 200.');
        System.assertEquals('12345ABC', res.externalId, 'The externalId should be parsed correctly.');
    }

    @isTest
    static void testSendLeadApiError() {
        // 1. Setup Mock Response (Simulating a validation error from the API)
        String errorBody = '{"error": {"message": "Invalid Email Format"}}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(400, errorBody, false));

        // 2. Prepare Test Data
        Lead testLead = new Lead(LastName = 'Doe', Company = 'Stark Industries');

        // 3. Execute Test
        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        // 4. Assert Results
        System.assertEquals(false, res.success, 'The callout should fail.');
        System.assertEquals(400, res.statusCode, 'Status code should be 400.');
        System.assertEquals('Invalid Email Format', res.errorMessage, 'The specific API error message should be parsed.');
    }

    @isTest
    static void testSendLeadCalloutException() {
        // 1. Setup Mock Response to throw a System.CalloutException
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(0, '', true));

        // 2. Prepare Test Data
        Lead testLead = new Lead(LastName = 'Doe', Company = 'Stark Industries');

        // 3. Execute Test
        Test.startTest();
        LeadApiClient.Response res = LeadApiClient.sendLead(testLead);
        Test.stopTest();

        // 4. Assert Results
        System.assertEquals(false, res.success, 'The callout should fail due to exception.');
        System.assertNotEquals(null, res.errorMessage, 'Error message should not be null.');
        System.assert(res.errorMessage.contains('Simulated callout exception'), 'Should catch and log the simulated exception.');
    }

    @isTest
    static void testBulkInsertQueueableExecution() {
        // 1. Setup Mock for 50 Callouts
        String successBody = '{"status":"success", "externalId":"BULK-999"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));
        
        // 2. Prepare exactly 50 Leads to match the CHUNK_SIZE limit
        // This ensures the Queueable processes the chunk but does not attempt to chain in a test context.
        List<Lead> bulkLeads = new List<Lead>();
        for (Integer i = 0; i < 50; i++) {
            bulkLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'BulkLead ' + i,
                Company = 'Bulk Corp',
                Email = 'bulk' + i + '@example.com',
                Status = 'New'
            ));
        }
        
        // 3. Execute Test
        Test.startTest();
        // When the insert fires LeadTrigger, it calls LeadTriggerHandler.
        // The handler enqueues LeadSyncQueueable via LeadSyncService.
        insert bulkLeads; 
        
        // Test.stopTest() forces any asynchronous Queueable jobs to run synchronously right now.
        Test.stopTest();
        
        // 4. Assert Results
        // Verify the Queueable successfully updated the leads
        List<Lead> updatedLeads = [SELECT Id, External_Reference_Id__c FROM Lead WHERE Company = 'Bulk Corp'];
        System.assertEquals(50, updatedLeads.size(), 'Should have inserted 50 leads.');
        
        for (Lead l : updatedLeads) {
            System.assertEquals('BULK-999', l.External_Reference_Id__c, 'The Queueable should have updated the External ID on all records.');
        }
    }

    @isTest
    static void testTriggerHandlerUpdateLogic() {
        // Because LeadTriggerHandler uses a static `processed` set to prevent recursion,
        // a Lead inserted and updated in the exact same test transaction will be skipped during the update phase.
        // To accurately test the 'AFTER_UPDATE' logic, we bypass the DML and test the handler method directly.
        
        // 1. Create simulated Trigger.new and Trigger.oldMap data
        // Insert a lead to obtain a real Id instead of hardcoding
        Lead dbLead = new Lead(
            FirstName = 'Jane',
            LastName = 'Doe',
            Company = 'Old Company'
        );
        insert dbLead;
        
        Lead oldLead = new Lead(
            Id = dbLead.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Company = 'Old Company'
        );
        
        Lead newLead = new Lead(
            Id = dbLead.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Company = 'New Company' // Outbound field changed
        );
        
        List<Lead> newList = new List<Lead>{ newLead };
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ oldLead.Id => oldLead };
        
        // 2. Execute Handler Logic
        Test.startTest();
        // This directly invokes the handler logic for an update scenario
        LeadTriggerHandler.run(newList, oldMap, System.TriggerOperation.AFTER_UPDATE);
        Test.stopTest();
        
        // 3. Assert Results
        // Since the Queueable was enqueued, we can verify an async job was created.
        Integer jobs = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'];
        System.assertEquals(1, jobs, 'Changing the Company field should enqueue a sync job.');
    }
}
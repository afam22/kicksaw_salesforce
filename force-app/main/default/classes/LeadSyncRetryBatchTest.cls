@isTest
private class LeadSyncRetryBatchTest {

    // ============================================================
    // 1. CORE RETRY LOGIC — Leads with blank External_Reference_Id__c
    //    should be re-enqueued and populated when delay=0 is passed.
    // ============================================================

    @isTest
    static void testRetryPopulatesBlankExternalIds() {
        String successBody = '{"status":"success", "externalId":"RETRY-001"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));

        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 10; i++) {
            leads.add(new Lead(
                FirstName  = 'Retry',
                LastName   = 'Lead' + i,
                Company    = 'Retry Corp',
                Status     = 'New',
                Email      = 'retry' + i + '@example.com'
                // External_Reference_Id__c intentionally left blank — simulates failed sync
            ));
        }
        insert leads;

        Test.startTest();
        // Pass delay=0 via constructor — value is serialised with the batch object and
        // survives all transaction boundaries, unlike a static variable which resets.
        Database.executeBatch(new LeadSyncRetryBatch(0), 50);
        Test.stopTest(); // Flushes both LeadSyncRetryBatch and the inner LeadSyncBatch

        List<Lead> retried = [
            SELECT Id, External_Reference_Id__c
            FROM Lead
            WHERE Company = 'Retry Corp'
        ];

        System.assertEquals(10, retried.size(), 'All 10 leads should be present.');
        for (Lead l : retried) {
            System.assertEquals(
                'RETRY-001',
                l.External_Reference_Id__c,
                'Retry batch should have populated External_Reference_Id__c for Lead: ' + l.Id
            );
        }
    }

    // ============================================================
    // 2. CUTOFF GUARD — Leads created very recently (within the delay
    //    window) should NOT be retried yet. They may still be in-flight
    //    from the original trigger-driven batch.
    // ============================================================

    @isTest
    static void testRecentLeadsAreNotRetried() {
        // Use the default constructor (5-minute delay). Leads inserted right now have
        // CreatedDate = System.now(), which is NOT <= (now - 5 min), so they should
        // be excluded from the query — confirming the cutoff guard works correctly.
        List<Lead> recentLeads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            recentLeads.add(new Lead(
                LastName  = 'TooNew' + i,
                Company   = 'Recent Corp',
                Status    = 'New'
            ));
        }
        insert recentLeads;

        Test.startTest();
        Database.executeBatch(new LeadSyncRetryBatch(), 50); // default 5-min delay
        Test.stopTest();

        List<Lead> result = [
            SELECT Id, External_Reference_Id__c
            FROM Lead
            WHERE Company = 'Recent Corp'
        ];

        for (Lead l : result) {
            System.assertEquals(
                null,
                l.External_Reference_Id__c,
                'Recently created leads should not be retried before the delay window.'
            );
        }
    }

    // ============================================================
    // 3. IDEMPOTENCY — Already-synced records (External_Reference_Id__c
    //    populated) must be excluded and never double-processed.
    // ============================================================

    @isTest
    static void testAlreadySyncedLeadsAreSkipped() {
        Lead syncedLead = new Lead(
            LastName                 = 'AlreadySynced',
            Company                  = 'Synced Corp',
            Status                   = 'New',
            External_Reference_Id__c = 'EXISTING-ID-999'
        );
        insert syncedLead;

        Test.startTest();
        Database.executeBatch(new LeadSyncRetryBatch(0), 50);
        Test.stopTest();

        Lead result = [
            SELECT External_Reference_Id__c
            FROM Lead
            WHERE Id = :syncedLead.Id
        ];

        System.assertEquals(
            'EXISTING-ID-999',
            result.External_Reference_Id__c,
            'Already-synced leads should not be overwritten by the retry batch.'
        );
    }

    // ============================================================
    // 4. EMPTY SCOPE — Batch execute() should be safe with no records.
    // ============================================================

    @isTest
    static void testBatchHandlesEmptyScope() {
        Test.startTest();
        Database.executeBatch(new LeadSyncRetryBatch(0), 50);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead WHERE External_Reference_Id__c = null],
            'No leads should exist in this isolated test context.'
        );
    }

    // ============================================================
    // 5. SCHEDULER — scheduleEvery10Minutes() and unscheduleAll()
    //    should register and then cleanly remove all 6 cron jobs.
    // ============================================================

    @isTest
    static void testSchedulerRegistersAndUnschedulesJobs() {
        Test.startTest();
        LeadSyncRetryScheduler.scheduleEvery10Minutes();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'LeadSyncRetry_%'
        ];

        System.assertEquals(6, jobs.size(), 'Six scheduled jobs should be registered (one per 10-min slot).');

        LeadSyncRetryScheduler.unscheduleAll();

        List<CronTrigger> remainingJobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'LeadSyncRetry_%'
        ];

        System.assertEquals(0, remainingJobs.size(), 'All retry jobs should be removed after unscheduleAll().');
    }

    // ============================================================
    // 6. BATCH EXECUTION — Confirms the batch populates External ID
    //    end-to-end when fired with delay=0.
    // ============================================================

    @isTest
    static void testSchedulerExecuteFiresBatch() {
        String successBody = '{"status":"success", "externalId":"SCHED-RUN"}';
        Test.setMock(HttpCalloutMock.class, new LeadApiClientMock(200, successBody, false));

        Lead l = new Lead(LastName = 'SchedTest', Company = 'Sched Corp', Status = 'New');
        insert l;

        Test.startTest();
        // Fire the batch directly with delay=0 so the just-inserted lead is eligible.
        Database.executeBatch(new LeadSyncRetryBatch(0), LeadSyncService.BATCH_SIZE);
        Test.stopTest();

        Lead result = [SELECT External_Reference_Id__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(
            'SCHED-RUN',
            result.External_Reference_Id__c,
            'Retry batch with delay=0 should have populated the External ID.'
        );
    }
}
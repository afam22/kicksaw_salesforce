List<CronTrigger> jobs = [
    SELECT CronJobDetail.Name, NextFireTime, State
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'LeadSyncRetry_%'
    ORDER BY NextFireTime ASC
];
System.debug(jobs);
System.debug('Remaining jobs: ' + jobs.size()); // Should be 0
/**
 * LeadSyncRetryScheduler
 *
 * Schedulable wrapper that fires LeadSyncRetryBatch on a cron schedule.
 *
 * To activate, run this one-time setup script in Anonymous Apex:
 *   LeadSyncRetryScheduler.scheduleEvery10Minutes();
 *
 * To unschedule all retry jobs cleanly:
 *   LeadSyncRetryScheduler.unscheduleAll();
 *
 * To manually trigger a one-off retry (e.g., after an outage):
 *   Database.executeBatch(new LeadSyncRetryBatch(), LeadSyncService.BATCH_SIZE);
 */
public with sharing class LeadSyncRetryScheduler implements Schedulable {

    private static final String JOB_NAME_PREFIX = 'LeadSyncRetry_';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LeadSyncRetryBatch(), LeadSyncService.BATCH_SIZE);
    }

    /**
     * Schedules 6 named jobs offset by 10 minutes each to simulate a 10-minute
     * polling interval. Salesforce's UI only allows hourly scheduling, but
     * Anonymous Apex allows minute-level granularity via multiple named jobs.
     *
     * Cron format: Seconds Minutes Hours Day-of-month Month Day-of-week Year
     */
    public static void scheduleEvery10Minutes() {
        Map<String, String> jobs = new Map<String, String>{
            JOB_NAME_PREFIX + '00' => '0 0  * * * ?',
            JOB_NAME_PREFIX + '10' => '0 10 * * * ?',
            JOB_NAME_PREFIX + '20' => '0 20 * * * ?',
            JOB_NAME_PREFIX + '30' => '0 30 * * * ?',
            JOB_NAME_PREFIX + '40' => '0 40 * * * ?',
            JOB_NAME_PREFIX + '50' => '0 50 * * * ?'
        };

        for (String jobName : jobs.keySet()) {
            try {
                System.schedule(jobName, jobs.get(jobName), new LeadSyncRetryScheduler());
                System.debug('Scheduled: ' + jobName);
            } catch (Exception ex) {
                // Job may already exist — safe to ignore on re-runs
                System.debug('Could not schedule ' + jobName + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * Aborts all scheduled retry jobs.
     * Call this before re-scheduling to avoid duplicate job errors.
     */
    public static void unscheduleAll() {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
        ];

        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
            System.debug('Aborted: ' + job.CronJobDetail.Name);
        }

        System.debug('LeadSyncRetryScheduler: unscheduled ' + jobs.size() + ' jobs.');
    }
}
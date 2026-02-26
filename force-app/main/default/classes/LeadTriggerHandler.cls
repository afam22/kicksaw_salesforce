public with sharing class LeadTriggerHandler {
    // Recursion guard (in case other automation causes re-entry)
    private static Set<Id> processed = new Set<Id>();

    public static void run(List<Lead> newList, Map<Id, Lead> oldMap, System.TriggerOperation triggerOp) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> toSync = collectIdsToSync(newList, oldMap, triggerOp);

        if (!toSync.isEmpty()) {
            processed.addAll(toSync);
            LeadSyncService.enqueue(toSync);
        }
    }

    // ---------------- PRIVATE HELPERS ----------------

    private static Set<Id> collectIdsToSync(List<Lead> newList, Map<Id, Lead> oldMap, System.TriggerOperation triggerOp) {
        Set<Id> toSync = new Set<Id>();

        for (Lead lead : newList) {
            if (shouldSkip(lead)) {
                continue;
            }

            if (triggerOp == System.TriggerOperation.AFTER_INSERT) {
                toSync.add(lead.Id);
            } else if (triggerOp == System.TriggerOperation.AFTER_UPDATE) {
                if (shouldSyncAfterUpdate(lead, oldMap)) {
                    toSync.add(lead.Id);
                }
            }
        }

        return toSync;
    }

    private static Boolean shouldSkip(Lead lead) {
        if (lead == null || lead.Id == null) {
            return true;
        }
        return processed.contains(lead.Id);
    }

    private static Boolean shouldSyncAfterUpdate(Lead lead, Map<Id, Lead> oldMap) {
        Lead oldLead = (oldMap == null) ? null : oldMap.get(lead.Id);

        // If we can't compare, be safe and sync
        if (oldLead == null) {
            return true;
        }

        // Avoid re-sync purely because we wrote External_Reference_Id__c
        if (isOnlyExternalIdChanged(lead, oldLead)) {
            return false;
        }
        

        // Sync when outbound fields changed OR external id blank - retry mechanism but manual
        return outboundFieldsChanged(lead, oldLead) || String.isBlank(lead.External_Reference_Id__c);
    }

    private static Boolean isOnlyExternalIdChanged(Lead nowLead, Lead oldLead) {
        return nowLead.External_Reference_Id__c != oldLead.External_Reference_Id__c
            && outboundFieldsEqual(nowLead, oldLead);
    }

    private static Boolean outboundFieldsChanged(Lead leadA, Lead leadB) {
        return leadA.FirstName   != leadB.FirstName
            || leadA.LastName    != leadB.LastName
            || leadA.Company     != leadB.Company
            || leadA.Email       != leadB.Email
            || leadA.LeadSource  != leadB.LeadSource
            || leadA.Status      != leadB.Status;
    }

    private static Boolean outboundFieldsEqual(Lead leadA, Lead leadB) {
        return !outboundFieldsChanged(leadA, leadB);
    }
}
trigger LeadTrigger on Lead (after insert, after update) {
    LeadTriggerHandler.run(Trigger.new, Trigger.oldMap, Trigger.operationType);
}
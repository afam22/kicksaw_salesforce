// How many succeeded vs failed?
Integer synced = [SELECT COUNT() FROM Lead WHERE External_Reference_Id__c != null];
Integer failed = [SELECT COUNT() FROM Lead WHERE External_Reference_Id__c = null];
System.debug('Synced: ' + synced + ' | Failed (blank): ' + failed);

List<Lead> leadsToDelete = [
    SELECT Id 
    FROM Lead 
    WHERE FirstName = 'Automated'
    AND Email LIKE 'test%@testcompany.com'
];

System.debug('Leads Found For Deletion: ' + leadsToDelete.size());

if (!leadsToDelete.isEmpty()) {
    delete leadsToDelete;
    System.debug('Deleted Leads: ' + leadsToDelete.size());
} else {
    System.debug('No matching leads found.');
}
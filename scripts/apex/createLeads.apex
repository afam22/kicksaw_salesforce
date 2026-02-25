List<Lead> leadsToInsert = new List<Lead>();

for (Integer i = 1; i <= 200; i++) {
    Lead l = new Lead(
        FirstName = 'Automated',
        LastName  = 'Lead' + i,
        Company   = 'Test Company' + i,
        Email     = 'test' + i + '@testcompany.com',
        Status    = 'Open - Not Contacted',
        LeadSource = 'Web'
    );
    leadsToInsert.add(l);
}

insert leadsToInsert;

System.debug('Inserted Leads: ' + leadsToInsert.size());
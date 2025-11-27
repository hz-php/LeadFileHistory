trigger LeadFileHistoryTrigger on Lead (after update) {

    List<File_History__c> histories = new List<File_History__c>();
    List<Id> leadIds = new List<Id>();

    for (Lead newL : Trigger.new) {

        Lead oldL = Trigger.oldMap.get(newL.Id);

        String oldUrl = oldL.FILE__c;
        String newUrl = newL.FILE__c;

        if (oldUrl != newUrl) {

            histories.add(new File_History__c(
                Lead__c = newL.Id,
                Old_File_URL__c = oldUrl,
                New_File_URL__c = newUrl,
                Change_Datetime__c = System.now(),
                Statements_Handler__c = newL.Statments_Handler__c
            ));

            leadIds.add(newL.Id);
        }
    }

    if (!histories.isEmpty()) insert histories;
    if (!leadIds.isEmpty()) System.enqueueJob(new LeadFileHistoryQueue(leadIds));
}

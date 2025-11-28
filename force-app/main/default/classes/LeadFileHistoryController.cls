public with sharing class LeadFileHistoryController {
    
    @AuraEnabled(cacheable=true)
    public static List<File_History__c> getHistory(Id leadId) {
        return [
            SELECT Id,
                   Old_File_URL__c,
                   New_File_URL__c,
                   Change_Datetime__c,
                   Log_Button__c,
                   Log_Files__c,
                   Log_Prescoring__c,
                   Log_Created_At__c,

                   /* UUID тянем напрямую из лида */
                   Lead__r.uuid__c

            FROM File_History__c
            WHERE Lead__c = :leadId
            ORDER BY Change_Datetime__c DESC
        ];
    }
}

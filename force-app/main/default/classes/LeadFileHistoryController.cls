public with sharing class LeadFileHistoryController {

    @AuraEnabled(cacheable=true)
    public static List<File_History__c> getHistory(Id leadId) {

        return [
            SELECT Id,
                   Change_Datetime__c,
                   Old_File_URL__c,
                   New_File_URL__c,
                   Statements_Handler__c,
                   Log_Content__c
            FROM File_History__c
            WHERE Lead__c = :leadId
            ORDER BY Change_Datetime__c DESC
        ];
    }
}

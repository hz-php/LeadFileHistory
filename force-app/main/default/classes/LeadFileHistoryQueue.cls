public class LeadFileHistoryQueue implements Queueable, Database.AllowsCallouts {

    private List<Id> leadIds;
    public LeadFileHistoryQueue(List<Id> leadIds) { this.leadIds = leadIds; }

    public void execute(QueueableContext context) {

        List<File_History__c> histories = [
            SELECT Id, Lead__c, Old_File_URL__c, New_File_URL__c,
                   Change_Datetime__c, Statements_Handler__c,
                   Log_Content__c
            FROM File_History__c
            WHERE Lead__c IN :leadIds
            ORDER BY Change_Datetime__c DESC
        ];

        Map<Id, File_History__c> last = new Map<Id, File_History__c>();
        for (File_History__c h : histories)
            if (!last.containsKey(h.Lead__c))
                last.put(h.Lead__c, h);

        List<File_History__c> upd = new List<File_History__c>();

        for (Id leadId : leadIds) {
            File_History__c fh = last.get(leadId);
            if (fh == null) continue;

            try {
                fetchLogs(fh);
            } catch (Exception e) {
                fh.Log_Content__c = 'ERROR: ' + e.getMessage();
            }

            upd.add(fh);
        }

        update upd;
    }

    private static void fetchLogs(File_History__c fh) {

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://lenderpro.ai/api/v1/leads/' + fh.Lead__c + '/logs');
        req.setMethod('GET');

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() >= 300)
            throw new CalloutException(res.getBody());

        Map<String, Object> root = (Map<String, Object>)
            JSON.deserializeUntyped(res.getBody());

        List<Object> logs = (List<Object>) root.get('logs');

        if (logs == null) logs = new List<Object>();

        // СОХРАНЯЕМ ВСЕ ЛОГИ!
        fh.Log_Content__c = JSON.serialize(logs);
    }
}

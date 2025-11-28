trigger LeadFileHistoryTrigger on Lead (after update) {
    if (!Trigger.isAfter || !Trigger.isUpdate) {
        return;
    }

    List<File_History__c> historiesToInsert = new List<File_History__c>();

    for (Lead newLead : Trigger.new) {
        Lead oldLead = Trigger.oldMap.get(newLead.Id);

        String oldUrl = oldLead.FILE__c;
        String newUrl = newLead.FILE__c;

        // 1) Если старое значение было NULL – НИЧЕГО не пишем (первая загрузка файла)
        // 2) Пишем запись только при реальном изменении значения
        if (oldUrl != null && oldUrl != newUrl) {
            historiesToInsert.add(new File_History__c(
                Lead__c             = newLead.Id,
                Old_File_URL__c     = oldUrl,
                New_File_URL__c     = newUrl,
                Change_Datetime__c  = System.now(),
                // Снапшот поля лида Statements_Handler__c
                Statements_Handler__c = newLead.Statments_Handler__c
            ));
        }
    }

    if (!historiesToInsert.isEmpty()) {
        insert historiesToInsert;
    }
}

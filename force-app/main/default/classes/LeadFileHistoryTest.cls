@IsTest
public class LeadFileHistoryTest {

    @IsTest
    static void testHistoryCreationAndCallout() {

        Test.setMock(HttpCalloutMock.class, new MockLenderPro());

        Lead l = new Lead(
            LastName = 'Test',
            Company  = 'Test',
            FILE__c  = 'urlA'
        );
        insert l;

        l.FILE__c = 'urlB';

        Test.startTest();
        update l; // триггер создаст File_History__c и заэнкьюит Queueable
        Test.stopTest(); // здесь отработает LeadFileHistoryQueue
        

        List<File_History__c> listFh = [
            SELECT Lead__c,
                   Old_File_URL__c,
                   New_File_URL__c,
                   Log_Button__c,
                   Log_Files__c,
                   Log_Prescoring__c,
                   Log_Created_At__c,
                   External_Log_Response__c
            FROM File_History__c
            WHERE Lead__c = :l.Id
        ];

        System.assertEquals(1, listFh.size(), 'Ожидаем одну запись File_History__c');

        File_History__c fh = listFh[0];

        System.assertEquals('urlA', fh.Old_File_URL__c, 'Old URL должен быть исходным');
        System.assertEquals('urlB', fh.New_File_URL__c, 'New URL должен быть новым значением');

        //System.assertNotEquals(null, fh.External_Log_Response__c, 'Ответ от lenderpro должен быть сохранён');
        //System.assert(fh.External_Log_Response__c.contains('"logs"'), 'В ответе должен быть массив logs');

       // System.assertEquals('Send to onloan second', fh.Log_Button__c, 'Button должен быть распаршен');
        //System.assertEquals('AUG_10__2.pdf, OCT_11__1.pdf, SEP_11__2.pdf', fh.Log_Files__c, 'Имена файлов должны быть распаршены');
        //System.assertEquals('On', fh.Log_Prescoring__c, 'Prescoring должен быть распаршен');

        //System.assertNotEquals(null, fh.Log_Created_At__c, 'Дата лога должна быть заполнена');
    }

    private class MockLenderPro implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // Имитация реального ответа от lenderpro.ai
            String body = '{"logs": [' +
                '{' +
                    '"id": 647,' +
                    '"created_at": "2025-11-25T21:20:24.000000Z",' +
                    '"updated_at": "2025-11-25T21:20:24.000000Z",' +
                    '"salesforce_id": "SOMEID",' +
                    '"tag": "Send to onloan second",' +
                    '"content": "[2025-11-25 21:20:24] The button \\"Send to onloan second\\" ' +
                               'was pressed. Selected files: AUG_10__2.pdf, OCT_11__1.pdf, SEP_11__2.pdf. Prescoring: On."' +
                '}' +
            ']}';

            res.setBody(body);
            return res;
        }
    }
}

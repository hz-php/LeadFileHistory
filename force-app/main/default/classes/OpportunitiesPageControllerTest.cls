@IsTest
private class OpportunitiesPageControllerTest {

    // ---------- Mock для успешного внешнего API (поддерживает 2 формата) ----------
    private class AggregatesSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('POST', req.getMethod(), 'Method must be POST');
            System.assertEquals('application/json', req.getHeader('Content-Type'), 'Content-Type must be JSON');

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            System.assertNotEquals(null, body, 'Body must be valid JSON object');

            // Ветвление по форме payload
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // Вариант А: массив записей { opportunityId, leadId, lender } -> отвечаем records[]
            if (body.containsKey('records')) {
                List<Object> recordsIn = (List<Object>) body.get('records');
                System.assert(recordsIn != null && !recordsIn.isEmpty(), 'Payload.records must be non-empty');

                List<Map<String, Object>> recordsOut = new List<Map<String, Object>>();
                for (Object o : recordsIn) {
                    Map<String, Object> pair = (Map<String, Object>) o;
                    String opportunityId = (String) pair.get('opportunityId');

                    // leadId может быть null, но ключ должен быть
                    System.assert(pair.containsKey('leadId'), 'Each record must contain leadId key');
                    // проверяем, что уходит lender (может быть пустым, но ключ обязателен)
                    System.assert(pair.containsKey('lender'), 'Each record must contain lender key');
                    System.assert(pair.containsKey('lenderProId'), 'Each record must contain lenderProId key');

                    Map<String, Object> row = new Map<String, Object>();
                    row.put('id', opportunityId);
                    row.put('remainingAmount', 100.50);
                    row.put('totalDebt', 2500);
                    row.put('repaymentAmount', 400);
                    row.put('repaymentStartDate', '2025-09-01');
                    row.put('repaymentEndDate', '2025-09-30');
                    // В ответе тоже есть decisionLogicBalance, но контроллер теперь его не использует
                    row.put('decisionLogicBalance', 999.99);
                    recordsOut.add(row);
                }

                Map<String, Object> payload = new Map<String, Object>{ 'records' => recordsOut };
                res.setBody(JSON.serialize(payload));
                return res;
            }

            // Вариант Б: одиночный объект для сервиса отправки лендеров { opportunityId, lender, ... }
            if (body.containsKey('opportunityId') && body.containsKey('lender')) {
                Map<String, Object> ok = new Map<String, Object>{
                    'ok' => true,
                    'echo' => new Map<String, Object>{
                        'opportunityId' => body.get('opportunityId'),
                        'lender' => body.get('lender')
                    }
                };
                res.setBody(JSON.serialize(ok));
                return res;
            }

            // На всякий случай — неизвестный формат
            res.setBody('{"ok":true}');
            return res;
        }
    }

    // ---------- Mock для неуспешного внешнего API (проверяем, что страница не падает) ----------
    private class AggregatesErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"fail"}');
            return res;
        }
    }

    // Утилита: находим максимально нейтральный профиль и создаём пользователя
    private static User createUser() {
        Profile p;
        List<Profile> std = [SELECT Id FROM Profile WHERE Name LIKE 'Standard%' LIMIT 1];
        if (!std.isEmpty()) {
            p = std[0];
        } else {
            p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        }

        User u = new User(
            Alias = 'tuser',
            Email = 'testuser@onloan.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testuser' + System.currentTimeMillis() + '@onloan.com',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    // Утилита: создаём ContentNote (SNOTE) и линкуем к оппортуне
    private static Id attachNoteToOpportunity(Opportunity opp, String title, String bodyText) {
        ContentNote note = new ContentNote(
            Title   = title,
            Content = Blob.valueOf(bodyText)
        );
        insert note;

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId   = opp.Id,
            ContentDocumentId= note.Id, // Для Notes Id = ContentDocumentId
            ShareType        = 'V',
            Visibility       = 'AllUsers'
        );
        insert cdl;

        return note.Id; // этот же Id используется в URL как ContentDocumentId
    }

    // ---------- Основной позитивный тест ----------
    @IsTest
    static void testGetPage_Success() {
        User u = createUser();

        // Создадим лида(ов), чтобы заполнить SlaesForceLeadId__c
        Lead l1 = new Lead(LastName = 'L1', Company = 'C1', Status = 'DENIED');
        Lead l2 = new Lead(LastName = 'L2', Company = 'C2', Status = 'DENIED');
        insert new List<Lead>{ l1, l2 };

        // Создаём данные и назначаем владельцем u
        Opportunity o1 = new Opportunity(
            StageName = 'Close',
            CloseDate = Date.today().addDays(30),
            Name = 'Company A',
            Lender_type__c = 'Boostra',
            LenderPro_Dashboard__c = 'https://example.com/dashA',
            LenderPro_Id__c = '123',
            OwnerId = u.Id,
            SlaesForceLeadId__c = l1.Id,
            Decision_Logic_Balance__c = '123.45', // теперь баланс храним здесь
            Communication_with_the_client__c = 'In touch',
            Way_of_settlement__c = 'Collectors'
        );
        Opportunity o2 = new Opportunity(
            StageName = 'Close',
            CloseDate = Date.today().addDays(40),
            Name = 'Company B',
            Lender_type__c = 'Boostra',
            LenderPro_Dashboard__c = 'https://example.com/dashB',
            OwnerId = u.Id,
            SlaesForceLeadId__c = l2.Id,
            Decision_Logic_Balance__c = '999.99', // и здесь
            Communication_with_the_client__c = 'Not in touch',
            Way_of_settlement__c = 'Collectors'
        );
        insert new List<Opportunity>{ o1, o2 };

        // Доп. оппортуна другого владельца — чтобы убедиться, что фильтр по ownerId работает
        User other = createUser();
        Opportunity oOther = new Opportunity(
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(50),
            Name = 'Other Company',
            OwnerId = other.Id
        );
        insert oOther;

        // Прикрепим ContentNote к o2 (он должен подтянуться как последняя заметка)
        Id noteId = attachNoteToOpportunity(o2, 'Latest Title For O2', 'note body');

        // Мок внешнего API
        Test.setMock(HttpCalloutMock.class, new AggregatesSuccessMock());

        System.runAs(u) {
            Test.startTest();
            OpportunitiesPageController.PageResult pr =
                OpportunitiesPageController.getPage(1, 25, new List<Id>{ u.Id }, null, '', '', '', '');
            Test.stopTest();

            System.assertNotEquals(null, pr, 'PageResult must not be null');
            System.assertEquals(2, pr.totalCount, 'Total count must match number of user opportunities');
            System.assertEquals(1, pr.pageNumber, 'Page number must be 1');
            System.assertEquals(25, pr.pageSize, 'Page size must be 25');
            System.assertEquals(2, pr.rows.size(), 'Should return two rows (filtered by owner)');

            // Сопоставим строки по Id (порядок сортировки нам не важен)
            Map<Id, OpportunitiesPageController.RowDto> byId = new Map<Id, OpportunitiesPageController.RowDto>();
            for (OpportunitiesPageController.RowDto r : pr.rows) byId.put(r.id, r);

            OpportunitiesPageController.RowDto r1 = byId.get(o1.Id);
            OpportunitiesPageController.RowDto r2 = byId.get(o2.Id);

            // --- Проверки по первой оппе ---
            System.assertEquals('Company A', r1.companyName);
            System.assertEquals('Close', r1.opportunityStage);
            System.assertEquals('Boostra', r1.lender);
            System.assertEquals('/lightning/r/Opportunity/' + o1.Id + '/view', r1.recordUrl);
            System.assertEquals(u.Id, r1.ownerId, 'ownerId must be set');
            System.assertNotEquals(null, r1.ownerName, 'ownerName must be present');

            // Значения из мока (остались прежними)
            System.assertEquals(Decimal.valueOf('100.50'),  r1.remainingAmount);
            System.assertEquals(Decimal.valueOf('2500'),    r1.totalDebt);
            System.assertEquals(Decimal.valueOf('400'),     r1.repaymentAmount);
            System.assertEquals(Date.newInstance(2025, 9, 1),  r1.repaymentStartDate);
            System.assertEquals(Date.newInstance(2025, 9, 30), r1.repaymentEndDate);

            // Баланс теперь должен браться из Request_Code_decisionlogic__c
            System.assertEquals(Decimal.valueOf('123.45'),  r1.decisionLogicBalance);
            System.assertEquals(
                'In touch',
                r1.communicationWithClient,
                'communicationWithClient для o1 должно тянуться из Communication_with_the_client__c'
            );

            // Для первой оппы заметок нет
            System.assertEquals(null, r1.latestNoteTitle);
            System.assertEquals(null, r1.latestNoteUrl);

            // --- Проверки по второй оппе ---
            System.assertEquals('Company B', r2.companyName);
            System.assertEquals('Close', r2.opportunityStage);
            System.assertEquals('Boostra', r2.lender);
            System.assertEquals('/lightning/r/Opportunity/' + o2.Id + '/view', r2.recordUrl);
            System.assertEquals(u.Id, r2.ownerId, 'ownerId must be set');
            System.assertNotEquals(null, r2.ownerName, 'ownerName must be present');

            // Есть ContentNote -> должен подтянуться Title и URL
            System.assertEquals('Latest Title For O2', r2.latestNoteTitle);
            System.assertEquals('/lightning/r/ContentNote/' + noteId + '/view', r2.latestNoteUrl);

            // Агрегаты из API (кроме баланса)
            System.assertEquals(Decimal.valueOf('100.50'),  r2.remainingAmount);
            System.assertEquals(Decimal.valueOf('2500'),    r2.totalDebt);
            System.assertEquals(Decimal.valueOf('400'),     r2.repaymentAmount);
            System.assertEquals(Date.newInstance(2025, 9, 1),  r2.repaymentStartDate);
            System.assertEquals(Date.newInstance(2025, 9, 30), r2.repaymentEndDate);

            // Баланс снова берём из поля
            System.assertEquals(Decimal.valueOf('999.99'),  r2.decisionLogicBalance);
            System.assertEquals(
                'Not in touch',
                r2.communicationWithClient,
                'communicationWithClient для o2 должно тянуться из Communication_with_the_client__c'
            );
        }
    }

    // ---------- Негативный сценарий: внешний API вернул 500, страница не падает ----------
    @IsTest
    static void testGetPage_ApiErrorGraceful() {
        User u = createUser();

        Lead l = new Lead(LastName = 'L', Company = 'C', Status = 'DENIED');
        insert l;

        Opportunity o1 = new Opportunity(
            StageName = 'Close',
            CloseDate = Date.today().addDays(10),
            Name = 'Company C',
            OwnerId = u.Id,
            SlaesForceLeadId__c = l.Id,
            Decision_Logic_Balance__c = '77.7', // задаём баланс в поле
            Communication_with_the_client__c = 'In touch',
            Way_of_settlement__c = 'Collectors'
            
        );
        insert o1;

        // Для надёжности создадим ещё одну оппорту на другого владельца
        User other = createUser();
        Opportunity oOther = new Opportunity(
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Name = 'Other C',
            OwnerId = other.Id
        );
        insert oOther;

        Test.setMock(HttpCalloutMock.class, new AggregatesErrorMock());

        System.runAs(u) {
            Test.startTest();
            OpportunitiesPageController.PageResult pr =
                OpportunitiesPageController.getPage(1, 25, new List<Id>{ u.Id }, null, '', '', '', '');
            Test.stopTest();

            System.assertEquals(1, pr.rows.size(), 'Should still return rows even if API failed (filtered by owner)');
            System.assertEquals(1, pr.totalCount, 'Total count must reflect filter by owner');

            OpportunitiesPageController.RowDto r = pr.rows[0];
            // поля, приходящие только из API, пустые
            System.assertEquals('/lightning/r/Opportunity/' + o1.Id + '/view', r.recordUrl);
            System.assertEquals('Company C', r.companyName);
            System.assertEquals(null, r.remainingAmount);
            System.assertEquals(null, r.totalDebt);
            System.assertEquals(null, r.repaymentAmount);
            System.assertEquals(null, r.repaymentStartDate);
            System.assertEquals(null, r.repaymentEndDate);

            // А вот баланс берётся из поля, несмотря на ошибку API
            System.assertEquals(Decimal.valueOf('77.7'), r.decisionLogicBalance);

            // и заметки отсутствуют
            System.assertEquals(null, r.latestNoteTitle);
            System.assertEquals(null, r.latestNoteUrl);

            // Проверим владельца в DTO
            System.assertEquals(u.Id, r.ownerId);
            System.assertNotEquals(null, r.ownerName);
            System.assertEquals(
                'In touch',
                r.communicationWithClient,
                'communicationWithClient должно тянуться из Communication_with_the_client__c даже при ошибке API'
            );
        }
    }

    @IsTest
    static void testUpdateRows_UpdatesOpportunityAndReturnsDebug() {
        // создаём юзера и оппортьюнити под ним
        User u = createUser();

        Opportunity opp = new Opportunity(
            Name = 'UpdateRows Test Opp',
            StageName = '0 days',
            CloseDate = Date.today().addDays(10),
            Category__c = 'GM',
            B2B_B2C__c = 'B2C',
            Automatic_Payments__c = 'Manual',
            Possibility_of_Collection__c = 0.10, // 10%
            Brokers__c = 'Old Brokers',
            Statements__c = 'Old Statements',
            UCC__c = 'Old UCC',
            Collectors__c = 'Old Collectors',
            Advocate_Lawyers__c = 'David',
            Communication_with_the_client__c = 'In touch',
            OwnerId = u.Id
        );
        insert opp;

        System.runAs(u) {
            // готовим payload так же, как это делает LWC (Map<String, Object>)
            Map<String, Object> updateMap = new Map<String, Object>{
                'id' => (String)opp.Id,            // важно как String, как в LWC
                'category' => 'GA',
                'b2bB2c' => 'B2B',
                'automaticPayments' => 'Automatic',
                'possibilityOfCollection' => 75,   // в UI %, должно сохраниться как 0.75
                'brokers' => 'New Brokers',
                'statements' => 'New Statements',
                'ucc' => 'New UCC',
                'collectors' => 'New Collectors',
                'advocateLawyers' => 'Lewis',
                'communicationWithClient' => 'Not in touch'
            };

            List<Map<String, Object>> updates = new List<Map<String, Object>>{ updateMap };

            Test.startTest();
            OpportunitiesPageController.UpdateRowsResult res =
                OpportunitiesPageController.updateRows(updates);
            Test.stopTest();

            // --- проверяем результирующий объект ---
            System.assertNotEquals(null, res, 'Result must not be null');
            System.assertEquals(1, res.receivedUpdatesCount, 'Should receive exactly one update');
            System.assertEquals(1, res.nonNullIdCount, 'There must be exactly one non-null Id');
            System.assertEquals(1, res.foundOpportunitiesCount, 'One Opportunity must be found');
            System.assertEquals(1, res.updatedCount, 'Exactly one record must be updated');

            System.assertEquals(1, res.receivedIds.size(), 'receivedIds must contain one Id');
            System.assertEquals(1, res.foundIds.size(), 'foundIds must contain one Id');
            System.assertEquals(0, res.missingIds.size(), 'missingIds must be empty');
            System.assertEquals(1, res.updatedIds.size(), 'updatedIds must contain one Id');

            System.assertEquals(opp.Id, res.receivedIds[0], 'receivedIds[0] must equal opp.Id');
            System.assertEquals(opp.Id, res.foundIds[0], 'foundIds[0] must equal opp.Id');
            System.assertEquals(opp.Id, res.updatedIds[0], 'updatedIds[0] must equal opp.Id');

            System.assertNotEquals(null, res.debugJson, 'debugJson must be filled');

            // --- проверяем, что запись реально обновилась в БД ---
            Opportunity oppAfter = [
                SELECT Category__c, B2B_B2C__c, Automatic_Payments__c,
                    Possibility_of_Collection__c,
                    Brokers__c, Statements__c, UCC__c, Collectors__c,
                    Advocate_Lawyers__c, Communication_with_the_client__c 
                FROM Opportunity
                WHERE Id = :opp.Id
                LIMIT 1
            ];

            System.assertEquals('GA', oppAfter.Category__c, 'Category__c must be updated');
            System.assertEquals('B2B', oppAfter.B2B_B2C__c, 'B2B_B2C__c must be updated');
            System.assertEquals('Automatic', oppAfter.Automatic_Payments__c, 'Automatic_Payments__c must be updated');
            System.assertEquals(
                0.75,
                oppAfter.Possibility_of_Collection__c,
                'Possibility_of_Collection__c must be stored as 0.75 (75%)'
            );
            System.assertEquals('New Brokers', oppAfter.Brokers__c, 'Brokers__c must be updated');
            System.assertEquals('New Statements', oppAfter.Statements__c, 'Statements__c must be updated');
            System.assertEquals('New UCC', oppAfter.UCC__c, 'UCC__c must be updated');
            System.assertEquals('New Collectors', oppAfter.Collectors__c, 'Collectors__c must be updated');
            System.assertEquals('Lewis', oppAfter.Advocate_Lawyers__c, 'Advocate_Lawyers__c must be updated');
            System.assertEquals(
                'Not in touch',
                oppAfter.Communication_with_the_client__c,
                'Communication_with_the_client__c must be updated'
            );
        }
    }
}
import { LightningElement, api, wire, track } from 'lwc';
import getHistory from '@salesforce/apex/LeadFileHistoryController.getHistory';

export default class LeadFileHistory extends LightningElement {
    @api recordId;
    @track history = [];
    logs = [];

    // -------------------- LOAD HISTORY --------------------
    @wire(getHistory, { leadId: '$recordId' })
    wiredHistory({ data, error }) {
        if (data) {
            console.log('HISTORY RAW:', data);

            let clean = JSON.parse(JSON.stringify(data));

            clean.sort((a, b) =>
                new Date(b.Change_Datetime__c) - new Date(a.Change_Datetime__c)
            );

            const n = clean.length;

            this.history = clean.map((item, index) => ({
                ...item,
                index: n - index,
                uuid: item.Lead__r ? item.Lead__r.uuid__c : null,
                logs: []  // ВАЖНО: пустой массив — чтобы потом заполнить
            }));

            // загружаем логи отдельно
            this.loadLogs();
        }

        if (error) {
            console.error('HISTORY ERROR:', error);
        }
    }

    // -------------------- LOAD LOGS --------------------
    async loadLogs() {
        if (!this.recordId) return;

        try {
            const url = `https://lenderpro.ai/api/v1/leads/${this.recordId}/logs`;

            const response = await fetch(url);
            const json = await response.json();

            console.log('LOGS RAW:', json);

            if (!json.logs) return;

            this.logs = json.logs.map((l, i) => ({
                key: i,
                createdAt: l.created_at,
                content: l.content
            }));

            this.attachLogsToHistory();
        } catch (e) {
            console.error('LOGS LOAD ERROR:', e);
        }
    }

    // -------------------- ATTACH LOGS TO HISTORY --------------------
    attachLogsToHistory() {
        if (this.history.length === 0 || this.logs.length === 0) return;

        let hist = JSON.parse(JSON.stringify(this.history));

        // ASC — самая старая первая
        hist.sort((a, b) =>
            new Date(a.Change_Datetime__c) - new Date(b.Change_Datetime__c)
        );

        for (let lg of this.logs) {
            const logTime = new Date(lg.createdAt);
            let targetIndex = 0;

            for (let i = 0; i < hist.length; i++) {
                if (new Date(hist[i].Change_Datetime__c) <= logTime) {
                    targetIndex = i;
                }
            }

            hist[targetIndex].logs.push(lg);
        }

        // Возвращаем обратно в DESC
        hist.sort((a, b) =>
            new Date(b.Change_Datetime__c) - new Date(a.Change_Datetime__c)
        );

        this.history = hist;

        console.log('FINAL HISTORY WITH LOGS:', this.history);
    }
}

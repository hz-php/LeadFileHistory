import { LightningElement, api, wire, track } from 'lwc';
import getHistory from '@salesforce/apex/LeadFileHistoryController.getHistory';

export default class LeadFileHistory extends LightningElement {
    @api recordId;
    @track history = [];

    @wire(getHistory, { leadId: '$recordId' })
    wiredHistory({ data, error }) {

        if (data) {
            this.history = data.map((item, index) => {
                let logs = [];

                try {
                    logs = item.Log_Content__c
                        ? JSON.parse(item.Log_Content__c)
                        : [];
                } catch (e) {
                    logs = [{ content: 'PARSE ERROR: ' + e }];
                }

                // форматируем каждый лог
                logs = logs.map((l, i) => ({
                    key: `log-${index}-${i}`,
                    created: l.created_at,
                    text: l.content
                }));

                return {
                    ...item,
                    index: index + 1,
                    logs
                };
            });
        } else {
            console.error(error);
        }
    }
}

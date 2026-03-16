/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : QuoteApprovedEventPublisher
 * Author          : Prakashraj Kodimunja
 * Created Date    : Mar 6, 2026
 * Last Modified By: Prakashraj Kodimunja
 * Last Modified On: Mar 6, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 6, 2026  │ Prakashraj Kodimunja   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class QuoteApprovedEventPublisher {

	public class Request {
        @InvocableVariable(required=true)
        public Id quoteId;
    }

    @InvocableMethod(label='Publish Quote Approved Event')
    public static void publishQuoteApprovedEvent(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.quoteId != null) {
                quoteIds.add(req.quoteId);
            }
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        List<Quote> quotes = [
            SELECT Id, QuoteNumber, AccountId, Status, GrandTotal,
                   Integration_Correlation_Id__c,
                   ERP_Sync_Status__c,
                   ERP_Attempt_Count__c,
                   ERP_Order_Id__c,
                   QuoteAccount.Name
            FROM Quote
            WHERE Id IN :quoteIds
        ];

        Map<Id, List<QuoteLineItem>> quoteLineMap = new Map<Id, List<QuoteLineItem>>();
        for (QuoteLineItem ql : [
            SELECT Id, QuoteId, Quantity,NetTotalPrice ,
                   PricebookEntry.Product2.ProductCode,
                   PricebookEntry.Product2.Name
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
        ]) {
            if (!quoteLineMap.containsKey(ql.QuoteId)) {
                quoteLineMap.put(ql.QuoteId, new List<QuoteLineItem>());
            }
            quoteLineMap.get(ql.QuoteId).add(ql);
        }

        List<Quote> quotesToUpdate = new List<Quote>();
        List<RCA_QuoteApproved__e> eventsToPublish = new List<RCA_QuoteApproved__e>();
        List<Integration_Log__c> logsToInsert = new List<Integration_Log__c>();

        for (Quote q : quotes) {
            String correlationId = q.Integration_Correlation_Id__c;

            if (String.isBlank(correlationId)) {
                correlationId = 'Q-' + String.valueOf(q.Id) + '-' + String.valueOf(Datetime.now().getTime());
                q.Integration_Correlation_Id__c = correlationId;
            }

            Integer attemptCount = (q.ERP_Attempt_Count__c == null) ? 1 : Integer.valueOf(q.ERP_Attempt_Count__c) + 1;
            q.ERP_Attempt_Count__c = attemptCount;
            q.ERP_Sync_Status__c = 'Sent';
            quotesToUpdate.add(q);

            List<Object> linePayload = new List<Object>();
            if (quoteLineMap.containsKey(q.Id)) {
                for (QuoteLineItem ql : quoteLineMap.get(q.Id)) {
                    Map<String, Object> lineMap = new Map<String, Object>();
                    lineMap.put('sku', ql.PricebookEntry != null && ql.PricebookEntry.Product2 != null ? ql.PricebookEntry.Product2.ProductCode : null);
                    lineMap.put('name', ql.PricebookEntry != null && ql.PricebookEntry.Product2 != null ? ql.PricebookEntry.Product2.Name : null);
                    lineMap.put('qty', ql.Quantity);
                    lineMap.put('netTotalPrice', ql.NetTotalPrice);
                    linePayload.add(lineMap);
                }
            }

            String linesJson = JSON.serialize(linePayload);

            RCA_QuoteApproved__e evt = new RCA_QuoteApproved__e(
                CorrelationId__c = correlationId,
                QuoteId__c = (String) q.Id,
                QuoteNumber__c = q.QuoteNumber,
                AccountId__c = (String) q.AccountId,
                CurrencyIsoCode__c = UserInfo.getDefaultCurrency(),
                GrandTotal__c = q.GrandTotal,
                LinesJson__c = linesJson,
                ERP_Order_Id__c = q.ERP_Order_Id__c,
                ERP_Attempt_Count__c = q.ERP_Attempt_Count__c,
                Customer_Name__c = q.QuoteAccount.Name
            );
            eventsToPublish.add(evt);

            Integration_Log__c logRec = new Integration_Log__c();
            logRec.CorrelationId__c = correlationId;
            logRec.Status__c = 'Sent';
            logRec.Direction__c = 'Salesforce to Mule';
            logRec.Target_System__c = 'MuleSoft';
            logRec.Request__c = linesJson;
            logRec.Attempt__c = attemptCount;
			logRec.Related_Quote__c = q.Id;
            logsToInsert.add(logRec);
        }

        if (!quotesToUpdate.isEmpty()) {
            update quotesToUpdate;
        }

        if (!eventsToPublish.isEmpty()) {
            List<Database.SaveResult> eventResults = EventBus.publish(eventsToPublish);

            for (Integer i = 0; i < eventResults.size(); i++) {
                if (!eventResults[i].isSuccess()) {
                    Database.Error err = eventResults[i].getErrors()[0];
                    logsToInsert[i].Status__c = 'Failed';
                    logsToInsert[i].Error_Message__c = err.getMessage();
                }
            }
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }
}
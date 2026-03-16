/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ERPOrderResultCallback
 * Author          : Prakashraj Kodimunja
 * Created Date    : Mar 6, 2026
 * Last Modified By: Prakashraj Kodimunja
 * Last Modified On: Mar 6, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 6, 2026  │ Prakashraj Kodimunja  │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/erp/order-result/*')
global with sharing class ERPOrderResultCallback {

    global class CallbackRequest {
        public String correlationId;
        public String quoteId;
        public String erpOrderId;
        public String erpOrderNumber;
        public String status;
        public String message;
        public String requestPayload;
        public String responsePayload;
        public Integer httpStatus;
        public Integer attempt;
    }

    global class CallbackResponse {
        public Boolean success;
        public String message;
        public String quoteId;
        public String correlationId;
    }

    @HttpPost
    global static CallbackResponse handleCallback() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        CallbackResponse responseBody = new CallbackResponse();

        try {
            String requestBody = req.requestBody == null ? null : req.requestBody.toString();

            if (String.isBlank(requestBody)) {
                res.statusCode = 400;
                responseBody.success = false;
                responseBody.message = 'Request body is empty.';
                return responseBody;
            }

            CallbackRequest payload = (CallbackRequest) JSON.deserialize(requestBody, CallbackRequest.class);

            if (payload == null) {
                res.statusCode = 400;
                responseBody.success = false;
                responseBody.message = 'Invalid request payload.';
                return responseBody;
            }

            if (String.isBlank(payload.correlationId) && String.isBlank(payload.quoteId)) {
                res.statusCode = 400;
                responseBody.success = false;
                responseBody.message = 'Either correlationId or quoteId is required.';
                return responseBody;
            }

            Quote targetQuote;

            if (!String.isBlank(payload.correlationId)) {
                List<Quote> quotesByCorrelation = [
                    SELECT Id,
                           QuoteNumber,
                           Integration_Correlation_Id__c,
                           ERP_Order_Id__c,
                           ERP_Order_Number__c,
                           ERP_Sync_Status__c,
                           ERP_Sync_Message__c,
                           ERP_Last_Attempt_At__c,
                           ERP_Attempt_Count__c,
                           ERP_Last_Request__c,
                           ERP_Last_Response__c
                    FROM Quote
                    WHERE Integration_Correlation_Id__c = :payload.correlationId
                    LIMIT 1
                ];

                if (!quotesByCorrelation.isEmpty()) {
                    targetQuote = quotesByCorrelation[0];
                }
            }

            if (targetQuote == null && !String.isBlank(payload.quoteId)) {
                List<Quote> quotesById = [
                    SELECT Id,
                           QuoteNumber,
                           Integration_Correlation_Id__c,
                           ERP_Order_Id__c,
                           ERP_Order_Number__c,
                           ERP_Sync_Status__c,
                           ERP_Sync_Message__c,
                           ERP_Last_Attempt_At__c,
                           ERP_Attempt_Count__c,
                           ERP_Last_Request__c,
                           ERP_Last_Response__c
                    FROM Quote
                    WHERE Id = :payload.quoteId
                    LIMIT 1
                ];

                if (!quotesById.isEmpty()) {
                    targetQuote = quotesById[0];
                }
            }

            if (targetQuote == null) {
                res.statusCode = 404;
                responseBody.success = false;
                responseBody.message = 'Quote not found for provided correlationId/quoteId.';
                responseBody.correlationId = payload.correlationId;
                return responseBody;
            }

            String normalizedStatus = String.isBlank(payload.status) ? 'FAILED' : payload.status.trim().toUpperCase();

            if (normalizedStatus == 'SUCCESS') {
                targetQuote.ERP_Sync_Status__c = 'Success';
            } else if (normalizedStatus == 'FAILED') {
                targetQuote.ERP_Sync_Status__c = 'Failed';
            } else if (normalizedStatus == 'SENT') {
                targetQuote.ERP_Sync_Status__c = 'Sent';
            } else if (normalizedStatus == 'PENDING') {
                targetQuote.ERP_Sync_Status__c = 'Pending';
            } else {
                targetQuote.ERP_Sync_Status__c = 'Failed';
            }

            if (!String.isBlank(payload.erpOrderId)) {
                targetQuote.ERP_Order_Id__c = payload.erpOrderId;
            }

            if (!String.isBlank(payload.erpOrderNumber)) {
                targetQuote.ERP_Order_Number__c = payload.erpOrderNumber;
            }

            targetQuote.ERP_Sync_Message__c = payload.message;
            targetQuote.ERP_Last_Attempt_At__c = System.now();

            if (payload.attempt != null) {
                targetQuote.ERP_Attempt_Count__c = payload.attempt;
            }

            if (payload.requestPayload != null) {
                targetQuote.ERP_Last_Request__c = payload.requestPayload;
            }

            if (payload.responsePayload != null) {
                targetQuote.ERP_Last_Response__c = payload.responsePayload;
            }

            update targetQuote;

            Integration_Log__c logRec = new Integration_Log__c();
            logRec.CorrelationId__c = !String.isBlank(payload.correlationId)
                ? payload.correlationId
                : targetQuote.Integration_Correlation_Id__c;
            logRec.Status__c = targetQuote.ERP_Sync_Status__c;
            logRec.Direction__c = 'Mule to Salesforce';
            logRec.Target_System__c = 'Salesforce';
            logRec.Request__c = payload.requestPayload;
            logRec.Response__c = payload.responsePayload;
            logRec.Error_Message__c = normalizedStatus == 'SUCCESS' ? null : payload.message;
            logRec.Http_Status__c = payload.httpStatus;
			logRec.Related_Quote__c = targetQuote.Id;
            logRec.Attempt__c = payload.attempt;
            insert logRec;

            res.statusCode = 200;
            responseBody.success = true;
            responseBody.message = 'Quote updated successfully.';
            responseBody.quoteId = targetQuote.Id;
            responseBody.correlationId = targetQuote.Integration_Correlation_Id__c;
            return responseBody;

        } catch (Exception e) {
            RestContext.response.statusCode = 500;

            CallbackResponse errorResponse = new CallbackResponse();
            errorResponse.success = false;
            errorResponse.message = 'Unexpected error: ' + e.getMessage();
            return errorResponse;
        }
    }
}
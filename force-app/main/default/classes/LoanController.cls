@RestResource(urlMapping='/loan')
global with sharing class LoanController {

    @HttpPost
    global static ResponseWrapper createLoan(String loanData) {
        ResponseWrapper response = new ResponseWrapper();
        
        try {
            System.debug('Received loanData: ' + loanData);
            
            // Deserialize the JSON data from the request
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);

            // Validate required fields
            String loanType = (String) data.get('Loan_Type__c');
            if (loanType == null || data.get('Loan_Amount__c') == null || data.get('Loan_Term__c') == null ||
                data.get('Interest_Rate__c') == null || data.get('Loan_Status__c') == null || data.get('Account__c') == null) {
                response.isSuccess = false;
                response.errorMessage = 'Missing required fields.';
                return response;
            }

            // Enqueue LoanQueueable job
            LoanQueueable loanQueueableJob = new LoanQueueable(data);
            ID jobId = System.enqueueJob(loanQueueableJob);

            // Return a response indicating that the job has been enqueued
            response.isSuccess = true;
            response.loanId = jobId; // Return Job ID (tracking for async process)

        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
            System.debug('Error: ' + e.getMessage());
        }

        return response;
    }

    global class ResponseWrapper {
        public Boolean isSuccess;
        public String errorMessage;
        public String loanId;  // Returning Job ID instead of Loan ID
    }
}
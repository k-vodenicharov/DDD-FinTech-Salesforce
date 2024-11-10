@RestResource(urlMapping='/loan')
global with sharing class LoanController {

    /**
     * HTTP PATCH method to adjust loan term
     * Accepts loan ID and new loan term to update the loan
     */
    @HttpPatch
    global static ResponseWrapper adjustLoanTerm(String loanId, Integer newLoanTerm) {
        LoanService service = new LoanService();
        return service.adjustLoanTerm(loanId, newLoanTerm);
    }

    /**
     * HTTP POST method to create a loan
     * Accepts loan data as JSON-formatted string and returns response wrapper with status
     */
    @AuraEnabled
    @HttpPost
    global static ResponseWrapper createLoanApex(String loanData) {
        LoanService service = new LoanService();
        return service.createLoan(loanData);
    }

    // Wrapper class for responses
    global class ResponseWrapper {
        @AuraEnabled
        public Boolean isSuccess;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public String loanId;
    }
}
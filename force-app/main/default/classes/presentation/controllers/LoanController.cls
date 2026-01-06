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

    /**
     * Aura-exposed method to prepay a Loan.
     * Delegates to PrepayLoanService and returns its result for UI toast handling.
     */
    @AuraEnabled
    public static Object prepayLoanApex(Id loanId) {
        PrepayLoanService.PrepayResult res = PrepayLoanService.prepayLoan(loanId);
        return res;
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

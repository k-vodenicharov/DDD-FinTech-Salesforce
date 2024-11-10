public class LoanFormController {
    
    /**
     * Exposed to Aura Components to create a loan record using loan data.
     * @param loanData JSON-formatted string containing loan details.
     * @return ResponseWrapper with success status or error details.
     */
    @AuraEnabled
    public static LoanController.ResponseWrapper createLoanApex(String loanData) {
        LoanService service = new LoanService();
        return service.createLoan(loanData);
    }
}

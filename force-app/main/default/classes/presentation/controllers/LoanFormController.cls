public class LoanFormController {
    
    /**
     * Method exposed to Aura Components to create a loan record
     * Call LoanService to create the Loan using the loan data
   	*/
    
    @AuraEnabled
    public static LoanController.ResponseWrapper createLoanApex(String loanData) {
        LoanService service = new LoanService();
        return service.createLoan(loanData);
    }
}
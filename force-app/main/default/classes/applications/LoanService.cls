public class LoanService {
    
    // Dependencies for loan operations and data storage
    private LoanDomain loanDomain;
    private LoanRepository loanRepository;

    public LoanService() {
        this.loanDomain = new LoanDomain();
        this.loanRepository = new LoanRepository();
    }

    /**
     * Creates a new loan based on provided loan data.
     * - Validates the loan term based on loan type (Secured or Unsecured).
     * - If valid, creates the loan, saves it, and enqueues a payment plan job.
     * @param loanData JSON-formatted string containing loan details.
     * @return ResponseWrapper with success status, loan ID (if created), or error message.
     */

    public LoanController.ResponseWrapper createLoan(String loanData) {
        LoanController.ResponseWrapper response = new LoanController.ResponseWrapper();
        
        try {
            // Deserialize JSON loanData to a Map for easy access to fields
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);
            String loanType = (String)data.get('Loan_Type__c');
            Integer loanTerm = (Integer)data.get('Loan_Term__c');

            // Validate loan term based on loan type
            if ((loanType == 'Secured' && loanTerm > 6) || (loanType == 'Unsecured' && loanTerm > 12)) {
                response.isSuccess = false;
                response.errorMessage = 'Loan term exceeds maximum allowed for ' + loanType + ' loans.';
                return response;
            }

            // Create and save loan using domain logic and repository
            Loan__c newLoan = loanDomain.createLoan(data);
            loanRepository.save(newLoan);

            // Enqueue Payment Plan 
            System.enqueueJob(new PaymentPlanQueueable(newLoan.Id));

            response.isSuccess = true;
            response.loanId = newLoan.Id;
        } catch (Exception e) {
            // Catch and log any errors, updating response with failure status and error message
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        
        return response;
    }
    
    /**
     * Invokes adjustment of payment plans for a list of loan IDs.
     * Used to batch process loan adjustments that may affect payment plans.
     * @param loanIds List of loan IDs to adjust payment plans for.
     */
    public static void invokeAdjustPaymentPlans(List<Id> loanIds) {
        LoanDomain.adjustPaymentPlans(loanIds);
    }
    
    /**
     * Adjusts the term of an existing loan.
     * - Finds the loan by ID and updates the loan term.
     * - Adjusts related payment plans based on the new loan term.
     * @param loanId ID of the loan to adjust.
     * @param newLoanTerm New loan term value to be set.
     * @return ResponseWrapper with success status or error message.
     */
    public LoanController.ResponseWrapper adjustLoanTerm(String loanId, Integer newLoanTerm) {
        LoanController.ResponseWrapper response = new LoanController.ResponseWrapper();
        
        try {
            Loan__c loan = loanRepository.findById(loanId);
            
            if (loan != null) {
                loanDomain.adjustLoanTerm(loan, newLoanTerm);

                // Adjust related payment plans to reflect the new loan term
                LoanService.invokeAdjustPaymentPlans(new List<Id>{loan.Id});
                response.isSuccess = true;

            } else {
                response.isSuccess = false;
                response.errorMessage = 'Loan not found.';
            }
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        
        return response;
    }
}
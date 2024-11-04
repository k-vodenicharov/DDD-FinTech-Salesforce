public class LoanService {
    private LoanRepository loanRepository;

    public LoanService() {
        this.loanRepository = new LoanRepository();
    }
    
    /**
     * Method to create a Loan record using provided loanData
     * @param loanData JSON string containing loan information
     * @return ResponeWrapper with success status and loan ID or error message
     */

    public LoanController.ResponseWrapper createLoan(String loanData) {
        LoanController.ResponseWrapper response = new LoanController.ResponseWrapper();
        try {
            System.debug('Received loanData: ' + loanData);
            
            // Deserialize JSON loanData to a Map for easy access to fields
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);
            
            // Create and save loan using domain logic and repository
            Loan__c newLoan = LoanDomain.createLoan(data);
            loanRepository.save(newLoan);
            System.debug('Loan created with ID: ' + newLoan.Id);
            
            // Enqueue Payment Plan 
            System.enqueueJob(new PaymentPlanQueueable(newLoan.Id));

            response.isSuccess = true;
            response.loanId = newLoan.Id;

        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
            System.debug('Error: ' + e.getMessage());
        }
        return response;
    }
}
public class LoanFormController {
    @AuraEnabled
    public static LoanController.ResponseWrapper createLoanApex(String loanData) {
        LoanController.ResponseWrapper response = LoanController.createLoan(loanData);

        if (response != null && response.isSuccess) {
            System.debug('Loan created successfully. ID: ' + response.loanId);
            
            // Call the method to create Payment Plan records
            System.enqueueJob(new PaymentPlanQueueable(response.loanId));
        } else {
            System.debug('Error: Loan creation failed');
        }

        return response;
    }
}
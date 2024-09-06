public class LoanFormController {
    @AuraEnabled
    public static LoanController.ResponseWrapper createLoanApex(String loanData) {
        // Call the LoanController.createLoan method
        LoanController.ResponseWrapper response = LoanController.createLoan(loanData);
        
        // Ensure that the response has the expected fields populated
        if (response != null && response.isSuccess) {
            // Call the method to create Payment Plan records
            createPaymentPlans(response.loanId);
        }
        
        return response;
    }

    // Method to create Payment Plans
    @AuraEnabled
    public static void createPaymentPlans(Id loanId) {
        // Retrieve the loan record
        Loan__c loan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate 
                        FROM Loan__c 
                        WHERE Id = :loanId];

        // Calculate the Payment Amount for each Payment Plan
        Decimal totalAmount = loan.Principal_Plus_Interest__c;
        
        // Casting Loan_Term__c to Integer to avoid the decimal assignment issue
        Integer loanTerm = Integer.valueOf(loan.Loan_Term__c);
        
        Decimal paymentAmount = totalAmount / loanTerm;

        // Prepare to create Payment Plan records
        List<Payment_Plan__c> paymentPlans = new List<Payment_Plan__c>();

        // Convert loan.CreatedDate (Datetime) to a Date and get the first day of the next month
        Date loanCreationDate = loan.CreatedDate.date(); // Convert Datetime to Date
        Date firstPaymentDeadline = loanCreationDate.toStartOfMonth().addMonths(1);

        for (Integer i = 0; i < loanTerm; i++) {
            // Create a Payment Plan record for each month
            Payment_Plan__c paymentPlan = new Payment_Plan__c();
            paymentPlan.Loan__c = loanId;
            paymentPlan.Payment_Amount__c = paymentAmount;
            paymentPlan.Payment_Status__c = 'Pending';  // Ensure the field exists on the Payment_Plan__c object
            paymentPlan.Payment_Deadline__c = firstPaymentDeadline.addMonths(i);

            // Add to the list of Payment Plan records to insert
            paymentPlans.add(paymentPlan);
        }

        // Insert all Payment Plan records
        insert paymentPlans;
    }
}
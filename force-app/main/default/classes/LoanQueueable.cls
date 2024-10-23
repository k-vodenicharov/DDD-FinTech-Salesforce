public class LoanQueueable implements Queueable {
    private Map<String, Object> loanData;

    public LoanQueueable(Map<String, Object> loanData) {
        this.loanData = loanData;
    }

    public void execute(QueueableContext context) {
        try {
            // Extract loan data fields
            String loanType = (String) loanData.get('Loan_Type__c');
            Decimal loanAmount = (Decimal) loanData.get('Loan_Amount__c');
            Integer loanTerm = (Integer) loanData.get('Loan_Term__c');
            Decimal interestRate = (Decimal) loanData.get('Interest_Rate__c');
            String loanStatus = (String) loanData.get('Loan_Status__c');
            String accountId = (String) loanData.get('Account__c');

            // Validate required fields
            if (loanType == null || loanAmount == null || loanTerm == null || interestRate == null || loanStatus == null || accountId == null) {
                System.debug('Error: Missing required fields.');
                return;
            }

            // Validate loan term
            if (loanType == 'Secured' && loanTerm > 6) {
                System.debug('Error: Loan term exceeds maximum allowed value for Secured loans (6 months).');
                return;
            } else if (loanType == 'Unsecured' && loanTerm > 12) {
                System.debug('Error: Loan term exceeds maximum allowed value for Unsecured loans (12 months).');
                return;
            }

            // Calculate Principal Plus Interest
            Decimal interestAmount = (loanAmount * interestRate) / 100;
            Decimal principalPlusInterest = loanAmount + interestAmount;

            // Create Loan__c record
            Loan__c newLoan = new Loan__c();
            newLoan.Loan_Type__c = loanType;
            newLoan.Loan_Amount__c = loanAmount;
            newLoan.Loan_Term__c = loanTerm;
            newLoan.Interest_Rate__c = interestRate;
            newLoan.Loan_Status__c = loanStatus;
            newLoan.Account__c = accountId;
            newLoan.Principal_Plus_Interest__c = principalPlusInterest;

            insert newLoan;

            // Add debug to ensure loan is created
            System.debug('Loan created with ID: ' + newLoan.Id);

            // Enqueue PaymentPlanQueueable to create payment plans
            System.enqueueJob(new PaymentPlanQueueable(newLoan.Id));

        } catch (Exception e) {
            System.debug('Error in LoanQueueable: ' + e.getMessage());
        }
    }
}
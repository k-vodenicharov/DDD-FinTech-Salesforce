public class LoanDomain {
    
    /**
     * Creates a new Loan__c record with values from loanData and calculates Principal_Plus_Interest__c.
     * @param loanData Map containing fields like Loan_Type__c, Loan_Amount__c, Loan_Term__c, etc.
     * @return The Loan__c instance with populated fields.
     */
    public Loan__c createLoan(Map<String, Object> loanData) {
        // Initialize a new Loan__c record and populate its fields from loanData map
        Loan__c newLoan = new Loan__c();
        newLoan.Loan_Type__c = (String) loanData.get('Loan_Type__c');
        newLoan.Loan_Amount__c = (Decimal) loanData.get('Loan_Amount__c');
        newLoan.Loan_Term__c = (Integer) loanData.get('Loan_Term__c');
        newLoan.Interest_Rate__c = (Decimal) loanData.get('Interest_Rate__c');
        newLoan.Loan_Status__c = (String) loanData.get('Loan_Status__c');
        newLoan.Account__c = (Id) loanData.get('Account__c');
        
        // Calculate interest and Principal_Plus_Interest__c
        Decimal interest = newLoan.Loan_Amount__c * newLoan.Interest_Rate__c / 100;
        newLoan.Principal_Plus_Interest__c = newLoan.Loan_Amount__c + interest;

        return newLoan;
    }
    
    /**
     * Adjusts the loan term of an existing Loan__c record and updates it.
     * @param loan The Loan__c record to be updated.
     * @param newLoanTerm The new loan term value.
     */
    public void adjustLoanTerm(Loan__c loan, Integer newLoanTerm) {
        loan.Loan_Term__c = newLoanTerm;
        update loan;
    }
    
    /**
     * Adjusts payment plans for loans by their IDs. Validates loan term and updates or deletes 
     * payment plans based on the new term.
     * @param loanIds List of Loan__c IDs to process.
     */
    @InvocableMethod(label='Adjust Payment Plans' description='Adjusts payment plans based on new loan term')
    public static void adjustPaymentPlans(List<Id> loanIds) {
        for (Id loanId : loanIds) {
            Loan__c loan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate, Loan_Type__c, Loan_Status__c FROM Loan__c WHERE Id = :loanId LIMIT 1];
            
            // Check if Loan Type changed from Secured to Unsecured
            String oldLoanType = loan.Loan_Type__c;
            String newLoanType = loan.Loan_Type__c;
            
            // Check if the Loan Term is more than 6 months
            Integer maxLoanTerm = 6;
            Integer newTerm = Integer.valueOf(loan.Loan_Term__c);
            
            // If Loan Type is changed from 'Secured' to 'Unsecured' and Loan Term is more than 6 months
            if (oldLoanType == 'Secured' && newLoanType == 'Unsecured' && newTerm > maxLoanTerm) {
                // Create Payment Plans with Payment Status as Pending
                List<Payment_Plan__c> newPlans = new List<Payment_Plan__c>();
                Decimal newPaymentAmount = loan.Principal_Plus_Interest__c / newTerm;
                Date firstPaymentDeadline = loan.CreatedDate.date().toStartOfMonth().addMonths(1);
                
                for (Integer i = 0; i < newTerm; i++) {
                    Payment_Plan__c newPlan = new Payment_Plan__c(
                        Loan__c = loanId,
                        Payment_Amount__c = newPaymentAmount,
                        Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                        Payment_Status__c = 'Pending'  // Set Payment Status to Pending
                    );
                    newPlans.add(newPlan);
                }
                
                // Insert new payment plans
                insert newPlans;
                
                // Set Loan Status to Under Review
                loan.Loan_Status__c = 'Under Review';
                update loan; // Update loan with new status
            }

            // Retrieve existing payment plans and adjust if needed
            List<Payment_Plan__c> existingPlans = [SELECT Id, Payment_Amount__c, Payment_Deadline__c FROM Payment_Plan__c WHERE Loan__c = :loanId];
            
            // Validate loan term for "Secured" loans
            if (loan.Loan_Type__c == 'Secured' && newTerm > maxLoanTerm) {
                throw new LoanTermExceededException('Loan term exceeds maximum allowed value for Secured loans (6 months).');
            }

            // Shorten loan term: delete excess payment plans
            if (newTerm < existingPlans.size()) {
                Integer plansToDeleteCount = existingPlans.size() - newTerm;
                List<Payment_Plan__c> plansToDelete = new List<Payment_Plan__c>();
                for (Integer i = 0; i < plansToDeleteCount; i++) {
                    plansToDelete.add(existingPlans.remove(existingPlans.size() - 1));
                }
                delete plansToDelete;
            }

            // Extend loan term: create additional payment plans
            if (newTerm > existingPlans.size()) {
                Date firstPaymentDeadline = loan.CreatedDate.date().toStartOfMonth().addMonths(1);
                List<Payment_Plan__c> newPlans = new List<Payment_Plan__c>();
                for (Integer i = existingPlans.size(); i < newTerm; i++) {
                    Payment_Plan__c newPlan = new Payment_Plan__c(
                        Loan__c = loanId,
                        Payment_Amount__c = loan.Principal_Plus_Interest__c / newTerm,
                        Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                        Payment_Status__c = 'Pending'  // Set Payment Status to Pending
                    );
                    newPlans.add(newPlan);
                }
                insert newPlans;
                existingPlans.addAll(newPlans);
            }

            // Adjust payment amounts across all plans
            Decimal adjustedPaymentAmount = loan.Principal_Plus_Interest__c / newTerm;
            for (Payment_Plan__c plan : existingPlans) {
                plan.Payment_Amount__c = adjustedPaymentAmount;
            }

            // If any payment plan fails, set loan status to "Under Review"
            try {
                upsert existingPlans;
            } catch (DmlException e) {
                loan.Loan_Status__c = 'Under Review';
                update loan; // Set the loan status to "Under Review" if there is a failure
                continue; // Skip to the next loan if this one fails
            }

            // Ensure total payment matches Principal_Plus_Interest__c
            Decimal totalPaymentAmount = 0;
            for (Payment_Plan__c plan : existingPlans) {
                totalPaymentAmount += plan.Payment_Amount__c;
            }

            if (totalPaymentAmount != loan.Principal_Plus_Interest__c) {
                Decimal adjustmentAmount = loan.Principal_Plus_Interest__c - totalPaymentAmount;
                Decimal perPlanAdjustment = adjustmentAmount / existingPlans.size();
                for (Payment_Plan__c plan : existingPlans) {
                    plan.Payment_Amount__c += perPlanAdjustment;
                }
                upsert existingPlans;
            }
        }
    }
    
    public static void addPaymentPlansAndSetStatus(List<Loan__c> loansToProcess) {
        List<Payment_Plan__c> newPaymentPlans = new List<Payment_Plan__c>();
        
        for (Loan__c loan : loansToProcess) {
            Integer loanTerm = (Integer) loan.Loan_Term__c;
            Decimal paymentAmount = loan.Principal_Plus_Interest__c / loanTerm;
            Date firstPaymentDeadline = loan.CreatedDate.date().addMonths(1);

            for (Integer i = 0; i < loanTerm; i++) {
                newPaymentPlans.add(new Payment_Plan__c(
                    Loan__c = loan.Id,
                    Payment_Amount__c = paymentAmount,
                    Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                    Payment_Status__c = 'Pending'
                ));
            }

            // Update Loan Status to "Under Review"
            loan.Loan_Status__c = 'Under Review';
        }

        // Insert new payment plans and update loan statuses
        if (!newPaymentPlans.isEmpty()) {
            insert newPaymentPlans;
        }
        update loansToProcess;
    }

    // Custom exception to handle loan term validation errors
    public class LoanTermExceededException extends Exception {}
}
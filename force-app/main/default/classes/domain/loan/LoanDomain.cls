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
        // Set Loan Status to "Pending" automatically, regardless of user input
        newLoan.Loan_Status__c = 'Pending';
        newLoan.Account__c = (Id) loanData.get('Account__c');
        
        // Set a meaningful name for the loan record
        newLoan.Name = 'Loan ' + newLoan.Loan_Type__c + ' - ' + newLoan.Loan_Amount__c;
        
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
        loan.Loan_Term__c = (Decimal)newLoanTerm;
        update loan;
    }
    
    /**
     * Calculates adjusted interest based on actual loan term for prepayment scenarios.
     * @param loan The Loan__c record with original loan details
     * @param prepaymentDate The date when prepayment occurred
     * @return The adjusted principal plus interest amount
     */
    public static Decimal calculateAdjustedInterest(Loan__c loan, Date prepaymentDate) {
        // Calculate actual loan term in months based on prepayment date vs loan creation date
        Integer actualLoanTermMonths = (prepaymentDate.year() * 12 + prepaymentDate.month()) - (loan.CreatedDate.year() * 12 + loan.CreatedDate.month());
        
        if (actualLoanTermMonths < 1) {
            actualLoanTermMonths = 1;
        }

        Decimal adjustedInterest = loan.Loan_Amount__c * loan.Interest_Rate__c / 100 * (actualLoanTermMonths / loan.Loan_Term__c);
        return loan.Loan_Amount__c + adjustedInterest;
    }
    
    /**
     * Adjusts payment plans for loans by their IDs. Validates loan term and updates or deletes 
     * payment plans based on the new term.
     * @param loanIds List of Loan__c IDs to process.
     */
    @InvocableMethod(label='Adjust Payment Plans' description='Adjusts payment plans based on new loan term')
    public static void adjustPaymentPlans(List<Id> loanIds) {
        for (Id loanId : loanIds) {
            Loan__c loan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate, Loan_Type__c, Loan_Status__c, Interest_Rate__c, Loan_Amount__c FROM Loan__c WHERE Id = :loanId LIMIT 1];
            
            // Check if the Loan Term is more than 6 months for Secured loans
            Integer maxLoanTerm = 6;
            Decimal loanTermDecimal = loan.Loan_Term__c;
            Integer newTerm = loanTermDecimal.intValue();
            
            // Validate loan term for "Secured" loans
            if (loan.Loan_Type__c == 'Secured' && newTerm > maxLoanTerm) {
                throw new LoanTermExceededException('Loan term exceeds maximum allowed value for Secured loans (6 months).');
            }
            
            // Validate loan term for "Unsecured" loans (max 12 months)
            if (loan.Loan_Type__c == 'Unsecured' && newTerm > 12) {
                throw new LoanTermExceededException('Loan term exceeds maximum allowed value for Unsecured loans (12 months).');
            }

            // Retrieve existing payment plans and adjust if needed
            List<Payment_Plan__c> existingPlans = [SELECT Id, Payment_Amount__c, Payment_Deadline__c FROM Payment_Plan__c WHERE Loan__c = :loanId];
            
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
                        Payment_Amount__c = 0, // Will be calculated below
                        Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                        Payment_Status__c = 'Pending'  // Set Payment Status to Pending
                    );
                    // Set a meaningful name for the payment plan using counter-based naming
                    newPlan.Name = 'Payment ' + (i+1) + ' of ' + newTerm + ' for ' + loan.Loan_Type__c;
                    newPlans.add(newPlan);
                }
                insert newPlans;
                existingPlans.addAll(newPlans);
            }

            // Calculate payment amounts to ensure they sum to Principal_Plus_Interest__c
            // Distribute the amount as evenly as possible, with any remainder going to the first plan
            Decimal totalAmount = loan.Principal_Plus_Interest__c;
            Decimal paymentAmount = totalAmount / newTerm;
            Decimal remainder = totalAmount - (paymentAmount * newTerm);
            
            // Adjust payment amounts across all plans
            for (Integer i = 0; i < existingPlans.size(); i++) {
                Payment_Plan__c plan = existingPlans[i];
                plan.Payment_Amount__c = paymentAmount;
                // Add any remainder to the first plan to ensure perfect match
                if (i == 0) {
                    plan.Payment_Amount__c += remainder;
                }
            }

            // Update all payment plans in bulk
            if (!existingPlans.isEmpty()) {
                try {
                    upsert existingPlans;
                } catch (DmlException e) {
                    // If upsert fails, we don't update the loan status here to avoid inconsistent state
                    // The error should be logged and handled at a higher level if needed
                    System.debug('Error updating payment plans: ' + e.getMessage());
                }
            }
        }
    }
    
    /**
     * Recalculates Principal_Plus_Interest__c based on updated interest rate and current loan term
     * @param loan The Loan__c record to recalculate interest for
     * @return The recalculated Principal_Plus_Interest__c amount
     */
    public static Decimal recalculatePrincipalPlusInterest(Loan__c loan) {
        // Recalculate interest based on updated interest rate and current loan term
        Decimal interest = loan.Loan_Amount__c * loan.Interest_Rate__c / 100;
        return loan.Loan_Amount__c + interest;
    }
    
    /**
     * Handles loan restructuring operations including term extension and interest rate modification
     * NOW delegates to a single authoritative orchestration that:
     * - Determines final state (term, rate)
     * - Recalculates totals exactly once
     * - Rebuilds ALL payment plans from scratch from final state
     */
    public static void restructureLoan(Id loanId, Integer newLoanTerm, Decimal newInterestRate) {
        Loan__c loan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, Interest_Rate__c, Loan_Amount__c, CreatedDate, Loan_Type__c FROM Loan__c WHERE Id = :loanId LIMIT 1];
        orchestrateRestructure(loan, newLoanTerm, newInterestRate);
    }

    /**
     * Authoritative restructuring orchestration.
     * - Detects any change to term/rate
     * - Computes final values first
     * - Recalculates Principal_Plus_Interest__c exactly once
     * - Recreates ALL payment plans from final state
     */
    public static void orchestrateRestructure(Loan__c existingLoan, Integer newLoanTerm, Decimal newInterestRate) {
        Boolean termChanged = false;
        Boolean rateChanged = false;
        
        if (newLoanTerm != null) {
            if (existingLoan.Loan_Term__c == null) {
                termChanged = true; // Term was null, now it's set
            } else {
                termChanged = existingLoan.Loan_Term__c.intValue() != newLoanTerm;
            }
        } else if (existingLoan.Loan_Term__c != null) {
            // Term was previously set but now is null (though this shouldn't happen in practice)
            termChanged = true;
        }
        
        if (newInterestRate != null) {
            rateChanged = existingLoan.Interest_Rate__c != newInterestRate;
        } else if (existingLoan.Interest_Rate__c != null) {
            rateChanged = true;
        }

        if (!termChanged && !rateChanged) {
            return;
        }

        Integer finalTerm = newLoanTerm != null ? newLoanTerm : existingLoan.Loan_Term__c.intValue();
        Decimal finalRate = newInterestRate != null ? newInterestRate : existingLoan.Interest_Rate__c;

        if (finalTerm != null) {
            existingLoan.Loan_Term__c = (Decimal) finalTerm;
        }
        existingLoan.Interest_Rate__c = finalRate;
        // Recalculate totals exactly once from final state
        existingLoan.Principal_Plus_Interest__c = recalculatePrincipalPlusInterest(existingLoan);
        // Persist loan first so all dependent calcs/plans reference updated values
        update existingLoan;

        List<Payment_Plan__c> existingPlans = [
            SELECT Id FROM Payment_Plan__c WHERE Loan__c = :existingLoan.Id
        ];
        if (!existingPlans.isEmpty()) {
            delete existingPlans;
        }

        // Recreate plans from final state
        Integer termForPlans = finalTerm != null ? finalTerm : 0;
        if (termForPlans > 0) {
            List<Payment_Plan__c> newPlans = new List<Payment_Plan__c>();
            Date firstPaymentDeadline = existingLoan.CreatedDate.date().toStartOfMonth().addMonths(1);

            Decimal totalAmount = existingLoan.Principal_Plus_Interest__c;
            Decimal paymentAmount = totalAmount / termForPlans;
            Decimal remainder = totalAmount - (paymentAmount * termForPlans);

            for (Integer i = 0; i < termForPlans; i++) {
                Payment_Plan__c plan = new Payment_Plan__c(
                    Loan__c = existingLoan.Id,
                    Payment_Amount__c = paymentAmount + (i == 0 ? remainder : 0),
                    Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                    Payment_Status__c = 'Pending',
                    Name = 'Payment ' + (i+1) + ' of ' + termForPlans + ' for ' + existingLoan.Loan_Type__c
                );
                newPlans.add(plan);
            }
            insert newPlans;
        }
    }
    
    public static void addPaymentPlansAndSetStatus(List<Loan__c> loansToProcess) {
        List<Payment_Plan__c> newPaymentPlans = new List<Payment_Plan__c>();
        
        for (Loan__c loan : loansToProcess) {
            Decimal loanTermDecimal = loan.Loan_Term__c;
            Integer loanTerm = loanTermDecimal.intValue();
            Decimal paymentAmount = loan.Principal_Plus_Interest__c / loanTerm;
            Date firstPaymentDeadline = loan.CreatedDate.date().toStartOfMonth().addMonths(1);

            for (Integer i = 0; i < loanTerm; i++) {
                Payment_Plan__c newPlan = new Payment_Plan__c(
                    Loan__c = loan.Id,
                    Payment_Amount__c = paymentAmount,
                    Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                    Payment_Status__c = 'Pending'
                );
                // Set a meaningful name for the payment plan using counter-based naming
                newPlan.Name = 'Payment ' + (i+1) + ' of ' + loanTerm + ' for ' + loan.Loan_Type__c;
                newPaymentPlans.add(newPlan);
            }
            
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

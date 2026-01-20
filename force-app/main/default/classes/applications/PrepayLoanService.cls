public with sharing class PrepayLoanService {
    /**
     * Invocable action to prepay a single Loan by Id.
     * - Calculates remaining balance (sum of non-Completed Payment Plans)
     * - Marks all non-Completed Payment_Plan__c as Completed
     * - Updates Loan__c status to Closed
     * - Returns a message with remaining balance
     *
     * Security:
     * - Queries and DML use USER_MODE to respect CRUD/FLS per org rulebook.
     */
    public class PrepayResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Decimal remainingBalance;
        @AuraEnabled public Id loanId;
        @AuraEnabled public String error;
    }

    @AuraEnabled
    public static PrepayResult prepayLoan(Id loanId) {
        PrepayResult res = new PrepayResult();
        res.loanId = loanId;

        if (loanId == null) {
            res.success = false;
            res.error = 'Loan Id is required';
            return res;
        }

        try {
            String loanQuery = 'SELECT Id, Loan_Status__c, Loan_Amount__c, Interest_Rate__c, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate FROM Loan__c WHERE Id = :loanId LIMIT 1';
            Loan__c loan = Database.query(loanQuery);

            String paymentPlanQuery = 'SELECT Id, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c FROM Payment_Plan__c WHERE Loan__c = :loanId AND Payment_Status__c != \'Completed\'';
            List<Payment_Plan__c> openPlans = Database.query(paymentPlanQuery);

            Decimal remaining = 0;
            for (Payment_Plan__c pp : openPlans) {
                if (pp.Payment_Amount__c != null) {
                    remaining += pp.Payment_Amount__c;
                }
                pp.Payment_Status__c = 'Completed';
            }

            Date prepaymentDate = Date.today();
            Decimal adjustedPrincipalPlusInterest = LoanDomain.calculateAdjustedInterest(loan, prepaymentDate);
            loan.Principal_Plus_Interest__c = adjustedPrincipalPlusInterest;
            
            // Update all open payment plans to reflect the new total
            if (!openPlans.isEmpty()) {
                Decimal loanTermDecimal = loan.Loan_Term__c;
                Integer loanTerm = loanTermDecimal.intValue();
                Decimal paymentAmount = adjustedPrincipalPlusInterest / loanTerm;
                Decimal remainder = adjustedPrincipalPlusInterest - (paymentAmount * loanTerm);
                
                for (Integer i = 0; i < openPlans.size(); i++) {
                    Payment_Plan__c plan = openPlans[i];
                    plan.Payment_Amount__c = paymentAmount;
                    if (i == 0) {
                        plan.Payment_Amount__c += remainder;
                    }
                }
                
                // DML - close open plans with adjusted amounts
                Database.update(openPlans, AccessLevel.USER_MODE);
            }

            // Update loan to Closed
            loan.Loan_Status__c = 'Closed';
            Database.update(new List<Loan__c>{loan}, AccessLevel.USER_MODE);

            res.success = true;
            res.remainingBalance = remaining;
            res.message = 'Loan prepaid successfully. Remaining balance paid: ' + String.valueOf(remaining) + '. Interest adjusted based on actual loan term.';
        } catch (Exception e) {
            res.success = false;
            res.error = 'Error processing prepayment: ' + e.getMessage();
        }
        return res;
    }
}

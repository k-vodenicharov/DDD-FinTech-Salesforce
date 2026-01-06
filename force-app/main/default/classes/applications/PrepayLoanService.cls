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
            String loanQuery = 'SELECT Id, Loan_Status__c FROM Loan__c WHERE Id = :loanId LIMIT 1';
            Loan__c loan = Database.query(loanQuery);

            String paymentPlanQuery = 'SELECT Id, Payment_Amount__c, Payment_Status__c FROM Payment_Plan__c WHERE Loan__c = :loanId AND Payment_Status__c != \'Completed\'';
            List<Payment_Plan__c> openPlans = Database.query(paymentPlanQuery);

            Decimal remaining = 0;
            for (Payment_Plan__c pp : openPlans) {
                if (pp.Payment_Amount__c != null) {
                    remaining += pp.Payment_Amount__c;
                }
                pp.Payment_Status__c = 'Completed';
            }

            // DML - close open plans
            if (!openPlans.isEmpty()) {
                Database.update(openPlans, AccessLevel.USER_MODE);
            }

            // Update loan to Closed
            loan.Loan_Status__c = 'Closed';
            Database.update(new List<Loan__c>{loan}, AccessLevel.USER_MODE);

            res.success = true;
            res.remainingBalance = remaining;
            res.message = 'Loan prepaid successfully. Remaining balance paid: ' + String.valueOf(remaining);
        } catch (Exception e) {
            res.success = false;
            res.error = 'Error processing prepayment: ' + e.getMessage();
        }
        return res;
    }
}

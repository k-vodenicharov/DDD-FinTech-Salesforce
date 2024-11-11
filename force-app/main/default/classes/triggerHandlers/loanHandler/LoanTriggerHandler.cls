public class LoanTriggerHandler extends TriggerHandler {
    private List<Loan__c> newLoans;
    private List<Loan__c> oldLoans;

    public LoanTriggerHandler(List<Loan__c> newLoans, List<Loan__c> oldLoans) {
        this.newLoans = newLoans;
        this.oldLoans = oldLoans;
    }

    /**
     * Handles logic that occurs after a Loan__c record is updated.
     * - Updates Loan_Status__c to 'Under Review' if the loan type changes from 'Secured' to 'Unsecured'
     *   and the term exceeds 6 months.
     * - Generates a new Payment_Plan__c for each month in the loan term if criteria are met.
     */
    public override void afterUpdate() {
        List<Loan__c> loansToUpdate = new List<Loan__c>(); // Collects Loan records to be updated
        List<Payment_Plan__c> newPaymentPlans = new List<Payment_Plan__c>(); // Collects new Payment_Plan__c records

        for (Integer i = 0; i < newLoans.size(); i++) {
            Loan__c newLoan = newLoans[i];
            Loan__c oldLoan = oldLoans[i];

            if (oldLoan.Loan_Type__c == 'Secured' && newLoan.Loan_Type__c == 'Unsecured' && newLoan.Loan_Term__c > 6) {
                Loan__c loanToUpdate = new Loan__c(Id = newLoan.Id);
                loanToUpdate.Loan_Status__c = 'Under Review';
                loansToUpdate.add(loanToUpdate);

                Integer term = (Integer) newLoan.Loan_Term__c;
                Decimal paymentAmount = newLoan.Principal_Plus_Interest__c / term;
                Date firstPaymentDeadline = newLoan.CreatedDate.date().toStartOfMonth().addMonths(1);

                for (Integer j = 0; j < term; j++) {
                    Payment_Plan__c paymentPlan = new Payment_Plan__c(
                        Loan__c = newLoan.Id,
                        Payment_Amount__c = paymentAmount,
                        Payment_Deadline__c = firstPaymentDeadline.addMonths(j),
                        Payment_Status__c = 'Pending'
                    );
                    newPaymentPlans.add(paymentPlan);
                }
            }
        }

        // Inserts new Payment_Plan__c records if any were created
        if (!newPaymentPlans.isEmpty()) {
            insert newPaymentPlans;
        }

        // Updates loans with modified status if any were added to the loansToUpdate list
        if (!loansToUpdate.isEmpty()) {
            update loansToUpdate;
        }
    }
}

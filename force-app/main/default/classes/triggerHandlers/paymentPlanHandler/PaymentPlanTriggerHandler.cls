public class PaymentPlanTriggerHandler extends TriggerHandler {
    private List<Payment_Plan__c> newPaymentPlans;
    private List<Payment_Plan__c> oldPaymentPlans;

    public PaymentPlanTriggerHandler(List<Payment_Plan__c> newPaymentPlans, List<Payment_Plan__c> oldPaymentPlans) {
        this.newPaymentPlans = newPaymentPlans;
        this.oldPaymentPlans = oldPaymentPlans;
    }

/**
     * Handles logic that occurs after a Payment_Plan__c record is updated.
     * - If all Payment_Plan__c records for a loan are 'Completed', sets the Loan__c status to 'Closed'.
     * - If any Payment_Plan__c record is 'Failed', sets the Loan__c status to 'Failed'.
     * - If some payment plans are 'Completed' and others are 'Pending', sets loan status to 'Pending' (reflecting partial completion)
     * - If all payment plans are 'Pending', sets loan status to 'Pending' (initial state)
     */
public override void afterUpdate() {
        Set<Id> loanIds = new Set<Id>();

        // Step 1: Identify if Payment_Status__c has changed for any Payment_Plan__c records
        for (Integer i = 0; i < newPaymentPlans.size(); i++) {
            Payment_Plan__c newPlan = newPaymentPlans[i];
            Payment_Plan__c oldPlan = oldPaymentPlans[i];

            if (newPlan.Payment_Status__c != oldPlan.Payment_Status__c) {
                loanIds.add(newPlan.Loan__c);
            }
        }

        // Skip if no relevant payment status change is detected
        if (loanIds.isEmpty()) return;

        // Step 2: Retrieve all related payment plans to check for status
        Map<Id, List<Payment_Plan__c>> loanPaymentPlansMap = new Map<Id, List<Payment_Plan__c>>();

        for (Payment_Plan__c plan : [
            SELECT Id, Loan__c, Payment_Status__c FROM Payment_Plan__c WHERE Loan__c IN :loanIds
        ]) {
            if (!loanPaymentPlansMap.containsKey(plan.Loan__c)) {
                loanPaymentPlansMap.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            loanPaymentPlansMap.get(plan.Loan__c).add(plan);
        }

        // Step 3: Determine proper loan status for each loan based on all payment plans
        Map<Id, Loan__c> loansToUpdateMap = new Map<Id, Loan__c>();

        for (Id loanId : loanPaymentPlansMap.keySet()) {
            List<Payment_Plan__c> plans = loanPaymentPlansMap.get(loanId);
            Boolean allCompleted = true;
            Boolean anyFailed = false;
            Boolean anyCompleted = false;

            // Reset flags for proper evaluation
            allCompleted = true;
            anyFailed = false;
            anyCompleted = false;

            // Properly evaluate all payment plans to determine their statuses
            for (Payment_Plan__c plan : plans) {
                if (plan.Payment_Status__c == 'Failed') {
                    anyFailed = true;
                    allCompleted = false; // If any failed, not all completed
                    break;
                } else if (plan.Payment_Status__c == 'Completed') {
                    anyCompleted = true;
                } else if (plan.Payment_Status__c != 'Pending') {
                    // Any status other than Pending or Completed or Failed - treat as pending for now
                    allCompleted = false;
                } else {
                    // plan.Payment_Status__c == 'Pending'
                    allCompleted = false; // If any are pending, not all completed
                }
            }

            // If any payment plan failed, set loan status to Failed
            if (anyFailed) {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Failed'));
            }
// If all payment plans are completed, set loan status to Closed
            else if (allCompleted && plans.size() > 0) {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Closed'));
            }
// If some payment plans are completed and others are pending, set to Under Review (partial completion)
            else if (anyCompleted) {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Under Review'));
            }
            // If all payment plans are pending, set to Pending (initial state)
            else {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Pending'));
            }
        }

        // Step 4: Update loan statuses in bulk if any changes were determined
        if (!loansToUpdateMap.isEmpty()) {
            update loansToUpdateMap.values();
        }
    }
    
    public void handleMissedPayments(List<Payment_Plan__c> newPayments, List<Payment_Plan__c> oldPayments) {

        List<Payment_Plan__c> missedPayments = PaymentPlanDomain.identifyMissedPayments(newPayments, oldPayments);

        if (missedPayments.isEmpty()) {
            return;
        }

        for (Payment_Plan__c payment : missedPayments) {
            Id accountId = payment.Loan__r.Account__r.Id;

            List<Contact> accountContacts = [
                SELECT Id, Email, FirstName, LastName
                FROM Contact
                WHERE AccountId = :accountId
            ];

            if (!accountContacts.isEmpty()) {
                Contact borrower = accountContacts[0];
                String borrowerEmail = borrower.Email;
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;

                if (String.isNotBlank(borrowerEmail)) {
                    EmailService.sendMissedPaymentReminder(borrowerEmail, borrowerName, payment);
                }
            }
        }
    }
}
public class PaymentPlanTriggerHandler extends TriggerHandler {
    private List<Payment_Plan__c> newPaymentPlans;
    private List<Payment_Plan__c> oldPaymentPlans;

    public PaymentPlanTriggerHandler(List<Payment_Plan__c> newPaymentPlans, List<Payment_Plan__c> oldPaymentPlans) {
        this.newPaymentPlans = newPaymentPlans;
        this.oldPaymentPlans = oldPaymentPlans;
    }

    /**
     * Handles logic that occurs after a Payment_Plan__c record is updated.
     * - Sets Loan_Status__c on the associated Loan__c to 'Under Review' if any payment status changes.
     * - If all Payment_Plan__c records for a loan are 'Approved', sets the Loan__c status to 'Disbursed'.
     */
    public override void afterUpdate() {
        Set<Id> loanIds = new Set<Id>();
        Boolean paymentStatusChanged = false;

        // Step 1: Identify if Payment_Status__c has changed for any Payment_Plan__c records
        for (Integer i = 0; i < newPaymentPlans.size(); i++) {
            Payment_Plan__c newPlan = newPaymentPlans[i];
            Payment_Plan__c oldPlan = oldPaymentPlans[i];

            if (newPlan.Payment_Status__c != oldPlan.Payment_Status__c) {
                loanIds.add(newPlan.Loan__c);
                paymentStatusChanged = true;
            }
        }

        // Skip if no relevant payment status change is detected
        if (!paymentStatusChanged) return;

        // Step 2: Use a Map to ensure unique Loan__c records for updates
        Map<Id, Loan__c> loansToUpdateMap = new Map<Id, Loan__c>();

        if (!loanIds.isEmpty()) {
            for (Id loanId : loanIds) {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Under Review'));
            }

            // Step 3: Retrieve all related payment plans to check for "Approved" status
            Map<Id, List<Payment_Plan__c>> loanPaymentPlansMap = new Map<Id, List<Payment_Plan__c>>();

            for (Payment_Plan__c plan : [
                SELECT Id, Loan__c, Payment_Status__c FROM Payment_Plan__c WHERE Loan__c IN :loanIds
            ]) {
                if (!loanPaymentPlansMap.containsKey(plan.Loan__c)) {
                    loanPaymentPlansMap.put(plan.Loan__c, new List<Payment_Plan__c>());
                }
                loanPaymentPlansMap.get(plan.Loan__c).add(plan);
            }

            // Step 4: Check if all Payment_Plan__c records for each loan are "Approved"
            for (Id loanId : loanPaymentPlansMap.keySet()) {
                List<Payment_Plan__c> plans = loanPaymentPlansMap.get(loanId);
                Boolean allApproved = true;

                for (Payment_Plan__c plan : plans) {
                    if (plan.Payment_Status__c != 'Approved') {
                        allApproved = false;
                        break;
                    }
                }

                // Adds the loan with 'Disbursed' status to the update map if all plans are approved
                if (allApproved) {
                    loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Disbursed'));
                }
            }

            // Step 5: Update loan statuses in bulk if any changes were determined
            if (!loansToUpdateMap.isEmpty()) {
                update loansToUpdateMap.values();
            }
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
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

        // Step 2: Use a Map to ensure unique Loan__c records for updates
        Map<Id, Loan__c> loansToUpdateMap = new Map<Id, Loan__c>();

        if (!loanIds.isEmpty() && paymentStatusChanged) {
            for (Id loanId : loanIds) {
                loansToUpdateMap.put(loanId, new Loan__c(Id = loanId, Loan_Status__c = 'Under Review'));
            }
        }

        // Step 3: Check if all Payment_Plan__c records for each loan are "Approved"
        Map<Id, List<Payment_Plan__c>> loanPaymentPlansMap = new Map<Id, List<Payment_Plan__c>>();

        // Retrieves all related payment plans for the affected loans
        for (Payment_Plan__c plan : [SELECT Id, Loan__c, Payment_Status__c FROM Payment_Plan__c WHERE Loan__c IN :loanIds]) {
            if (!loanPaymentPlansMap.containsKey(plan.Loan__c)) {
                loanPaymentPlansMap.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            loanPaymentPlansMap.get(plan.Loan__c).add(plan);
        }

        // Checks if all payment plans for each loan are approved; if so, set Loan_Status__c to 'Disbursed'
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

        // Step 4: Update loan statuses in bulk if any changes were determined
        if (!loansToUpdateMap.isEmpty()) {
            update loansToUpdateMap.values();
        }
    }
}

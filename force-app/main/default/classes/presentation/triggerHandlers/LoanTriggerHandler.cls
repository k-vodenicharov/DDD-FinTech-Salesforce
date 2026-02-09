/**
 * Trigger handler for Loan__c lifecycle events.
 */
public class LoanTriggerHandler {
    private static Boolean isRunning = false;

    /** Applies validations before insert. */
    public static void beforeInsert(List<Loan__c> newLoans) {
        LoanCommandService svc = new LoanCommandService();
        svc.beforeInsert(newLoans);
    }

    /** Applies validations before update. */
    public static void beforeUpdate(List<Loan__c> newLoans, Map<Id, Loan__c> oldMap) {
        LoanCommandService svc = new LoanCommandService();
        svc.beforeUpdate(newLoans, oldMap);
    }

    /** Enqueues initial plan creation after insert. */
    public static void afterInsert(List<Loan__c> newLoans) {
        if (isRunning) return;
        isRunning = true;
        try {
            Set<Id> loanIds = new Set<Id>();
            for (Loan__c loan : newLoans) {
                if (loan != null && loan.Id != null) loanIds.add(loan.Id);
            }
            // Queueable handles bulk plan creation.
            if (!loanIds.isEmpty()) {
                System.enqueueJob(new PaymentPlanQueueable(loanIds, 'CREATE'));
            }
        } finally {
            isRunning = false;
        }
    }

    /** Enqueues plan adjustment after update. */
    public static void afterUpdate(List<Loan__c> newLoans, Map<Id, Loan__c> oldMap) {
        if (isRunning) return;
        isRunning = true;
        try {
            // Avoid double-queueing when Flow invokes adjustments directly.
            if (AdjustmentContext.skipQueueable) return;
            Set<Id> changedLoanIds = new Set<Id>();
            for (Loan__c loan : newLoans) {
                Loan__c oldLoan = oldMap.get(loan.Id);
                if (oldLoan == null) continue;
                Boolean termChanged = loan.Loan_Term__c != oldLoan.Loan_Term__c;
                Boolean rateChanged = loan.Interest_Rate__c != oldLoan.Interest_Rate__c;
                Boolean amountChanged = loan.Loan_Amount__c != oldLoan.Loan_Amount__c;
                if (!termChanged && (rateChanged || amountChanged)) {
                    changedLoanIds.add(loan.Id);
                }
            }
            if (!changedLoanIds.isEmpty()) {
                System.enqueueJob(new PaymentPlanQueueable(changedLoanIds, 'ADJUST'));
            }
        } finally {
            isRunning = false;
        }
    }
}

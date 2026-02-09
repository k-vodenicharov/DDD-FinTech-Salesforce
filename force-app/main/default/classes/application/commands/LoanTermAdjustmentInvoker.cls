/**
 * Flow invocable entry point for loan term adjustments.
 */
public with sharing class LoanTermAdjustmentInvoker {
    /**
     * Adjusts payment plans for the provided loan Ids.
     */
    @InvocableMethod(label='Adjust Loan Term')
    public static void adjustLoanTerms(List<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return;
        // Prevent double-queueing when Flow invokes adjustment directly.
        AdjustmentContext.skipQueueable = true;
        try {
            PaymentPlanCommandService svc = new PaymentPlanCommandService();
            svc.adjustPlansForLoanIds(new Set<Id>(loanIds));
        } finally {
            AdjustmentContext.skipQueueable = false;
        }
    }
}

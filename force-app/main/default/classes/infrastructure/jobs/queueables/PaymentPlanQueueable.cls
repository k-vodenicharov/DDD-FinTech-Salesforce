/**
 * Queueable job for async payment plan creation/adjustment.
 */
public class PaymentPlanQueueable implements Queueable {
    private Set<Id> loanIds;
    private String action;

    /** Creates a queueable for the given loan Ids and action. */
    public PaymentPlanQueueable(Set<Id> loanIds, String action) {
        this.loanIds = loanIds == null ? new Set<Id>() : loanIds;
        this.action = action;
    }

    /** Executes the requested action. */
    public void execute(QueueableContext context) {
        PaymentPlanCommandService svc = new PaymentPlanCommandService();
        if (action == 'CREATE') {
            svc.rebuildInitialPlans(loanIds);
        } else if (action == 'ADJUST') {
            svc.adjustPlansForLoanIds(loanIds);
        }
    }
}

/**
 * Queueable job for async loan creation.
 */
public class LoanQueueable implements Queueable {
    private Map<String, Object> loanData;

    /** Creates a queueable with serialized loan input. */
    public LoanQueueable(Map<String, Object> loanData) {
        this.loanData = loanData;
    }

    /** Executes loan creation asynchronously. */
    public void execute(QueueableContext context) {
        LoanCommandService svc = new LoanCommandService();
        svc.createLoan(JSON.serialize(loanData));
    }
}

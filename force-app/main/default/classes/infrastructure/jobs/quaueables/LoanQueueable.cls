public class LoanQueueable implements Queueable {
    
    // Stores loan data and handles loan repository actions
    private Map<String, Object> loanData;
    private LoanRepository loanRepository;
    private LoanDomain loanDomain;

    public LoanQueueable(Map<String, Object> loanData) {
        this.loanData = loanData;
        this.loanRepository = new LoanRepository();
        this.loanDomain = new LoanDomain();
    }

    /**
     * Asynchronously creates a loan and saves it using LoanDomain.
     * @param context QueueableContext for job execution.
     */
    public void execute(QueueableContext context) {
        try {
            Loan__c newLoan = loanDomain.createLoan(loanData);
            loanRepository.save(newLoan);
        } catch (Exception e) {
            System.debug('Queueable job failed: ' + e.getMessage());
        }
    }
}
public class LoanQueueable implements Queueable {
    
    /**
     * Stores loanData required to create the Loan
     * Repo for loan database operations
    */
    
    private Map<String, Object> loanData;
    private LoanRepository loanRepository;

    // Constructor to initialize LoanQueueable with loanData
    public LoanQueueable(Map<String, Object> loanData) {
        this.loanData = loanData;
        this.loanRepository = new LoanRepository();
    }

    // Executes asynchronously to create a loan
    public void execute(QueueableContext context) {
        try {
            Loan__c newLoan = LoanDomain.createLoan(loanData);
            loanRepository.save(newLoan);
            System.debug('Loan created with ID: ' + newLoan.Id);
            
            // and enqueue a new Payment Plan job for the loan
            System.enqueueJob(new PaymentPlanQueueable(newLoan.Id));

        } catch (Exception e) {
            System.debug('Error in LoanQueueable: ' + e.getMessage());
        }
    }
}
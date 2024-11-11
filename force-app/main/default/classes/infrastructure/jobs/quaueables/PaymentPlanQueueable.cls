public class PaymentPlanQueueable implements Queueable {
    private Id loanId;
    private LoanRepository loanRepository;

    public PaymentPlanQueueable(Id loanId) {
        this.loanId = loanId;
        this.loanRepository = new LoanRepository();
    }

    /**
     * Creates and inserts payment plans for a loan based on loan term and amount.
     * @param context QueueableContext for job execution.
     */
    public void execute(QueueableContext context) {
        Loan__c loan = loanRepository.findById(loanId);
        if (loan == null) {
            System.debug('Loan not found');
            return;
        }

        Decimal totalAmount = loan.Principal_Plus_Interest__c;
        Integer loanTerm = (Integer) loan.Loan_Term__c;
        Decimal paymentAmount = totalAmount / loanTerm;

        List<Payment_Plan__c> paymentPlans = new List<Payment_Plan__c>();
        Date firstPaymentDeadline = loan.CreatedDate.date().toStartOfMonth().addMonths(1);

        String paymentStatus = 'Pending';

        for (Integer i = 0; i < loanTerm; i++) {
            Payment_Plan__c payment = new Payment_Plan__c(
                Loan__c = loanId,
                Payment_Deadline__c = firstPaymentDeadline.addMonths(i),
                Payment_Amount__c = paymentAmount,
                Payment_Status__c = paymentStatus
            );
            paymentPlans.add(payment);
        }

        insert paymentPlans;
    }
}
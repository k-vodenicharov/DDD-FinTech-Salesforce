public class PaymentPlanQueueable implements Queueable {
    private Id loanId;
    private LoanRepository loanRepository;

    public PaymentPlanQueueable(Id loanId) {
        this.loanId = loanId;
        this.loanRepository = new LoanRepository();
    }

    public void execute(QueueableContext context) {
        try {
            System.debug('Loan ID passed to PaymentPlanQueueable: ' + loanId);
			            
            // Retrieve loan record by ID
            Loan__c loan = loanRepository.findById(loanId);
			            
            // Check if loan record exists
            if (loan == null) {
                System.debug('Error: No loan found with ID: ' + loanId);
                return;
            }

            Decimal totalAmount = loan.Principal_Plus_Interest__c;
            Integer loanTerm = Integer.valueOf(loan.Loan_Term__c);
            Decimal paymentAmount = totalAmount / loanTerm;

            List<Payment_Plan__c> paymentPlans = new List<Payment_Plan__c>();
            Date loanCreationDate = loan.CreatedDate.date();
            Date firstPaymentDeadline = loanCreationDate.toStartOfMonth().addMonths(1);
			
            // Loop to create a Payment Plan record for each month of the Loan Term
            for (Integer i = 0; i < loanTerm; i++) {
                Payment_Plan__c paymentPlan = new Payment_Plan__c();
                paymentPlan.Loan__c = loanId;
                paymentPlan.Payment_Amount__c = paymentAmount;
                paymentPlan.Payment_Status__c = 'Pending';
                paymentPlan.Payment_Deadline__c = firstPaymentDeadline.addMonths(i);
                paymentPlans.add(paymentPlan);
            }

            insert paymentPlans;

            System.debug('Payment plans created for Loan ID: ' + loanId);

        } catch (Exception e) {
            System.debug('Error in PaymentPlanQueueable: ' + e.getMessage());
        }
    }
}
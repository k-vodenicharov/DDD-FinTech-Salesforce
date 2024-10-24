public class PaymentPlanQueueable implements Queueable {
    private Id loanId;

    public PaymentPlanQueueable(Id loanId) {
        this.loanId = loanId;
    }

    public void execute(QueueableContext context) {
        try {
            System.debug('Loan ID passed to PaymentPlanQueueable: ' + loanId);

            // Retrieve the loan record
            List<Loan__c> loans = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate 
                            FROM Loan__c 
                            WHERE Id = :loanId];

            // Check if loan exists
            if (loans.isEmpty()) {
                System.debug('Error: No loan found with ID: ' + loanId);
                return;
            }

            Loan__c loan = loans[0];

            // Calculate payment plan details
            Decimal totalAmount = loan.Principal_Plus_Interest__c;
            Integer loanTerm = Integer.valueOf(loan.Loan_Term__c);
            Decimal paymentAmount = totalAmount / loanTerm;

            // Create payment plans
            List<Payment_Plan__c> paymentPlans = new List<Payment_Plan__c>();
            Date loanCreationDate = loan.CreatedDate.date();
            Date firstPaymentDeadline = loanCreationDate.toStartOfMonth().addMonths(1);

            for (Integer i = 0; i < loanTerm; i++) {
                Payment_Plan__c paymentPlan = new Payment_Plan__c();
                paymentPlan.Loan__c = loanId;
                paymentPlan.Payment_Amount__c = paymentAmount;
                paymentPlan.Payment_Status__c = 'Pending';
                paymentPlan.Payment_Deadline__c = firstPaymentDeadline.addMonths(i);

                paymentPlans.add(paymentPlan);
            }

            // Insert payment plans
            insert paymentPlans;

            System.debug('Payment plans created for Loan ID: ' + loanId);

        } catch (Exception e) {
            System.debug('Error in PaymentPlanQueueable: ' + e.getMessage());
        }
    }
}
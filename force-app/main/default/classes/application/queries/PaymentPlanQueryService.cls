/**
 * Query-side service for read-only payment plan access.
 */
public with sharing class PaymentPlanQueryService {
    /**
     * Returns payment plans for a loan.
     */
    public List<Payment_Plan__c> getPaymentPlansByLoanId(Id loanId) {
        return PaymentPlanSelector.getPaymentPlansByLoanId(loanId);
    }

    /**
     * Returns payment plans by status.
     */
    public List<Payment_Plan__c> getPaymentPlansByStatus(String status) {
        return PaymentPlanSelector.getPaymentPlansByStatus(status);
    }
}

/**
 * Simple validation for negative payment amounts.
 */
public class BeforePaymentPlanUpdateHandler {
    /** Adds an error when a payment amount is negative. */
    public static void handleBeforeUpdate(List<Payment_Plan__c> newPlans) {
        if (newPlans == null) return;
        for (Payment_Plan__c plan : newPlans) {
            if (plan.Payment_Amount__c != null && plan.Payment_Amount__c < 0) {
                plan.addError('Payment amount cannot be negative.');
            }
        }
    }
}

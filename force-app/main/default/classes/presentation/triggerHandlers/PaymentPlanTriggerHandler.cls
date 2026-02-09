/**
 * Trigger handler for Payment_Plan__c lifecycle events.
 */
public class PaymentPlanTriggerHandler {
    private static Boolean isRunning = false;
    private static Boolean isRunningBefore = false;

    /** Validates edits before update. */
    public static void beforeUpdate(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        if (isRunningBefore) return;
        isRunningBefore = true;
        try {
            PaymentPlanCommandService svc = new PaymentPlanCommandService();
            svc.beforeUpdate(newPlans, oldMap);
        } finally {
            isRunningBefore = false;
        }
    }

    /** Applies post-update orchestration. */
    public static void afterUpdate(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        if (isRunning) return;
        isRunning = true;
        try {
            PaymentPlanCommandService svc = new PaymentPlanCommandService();
            svc.handleAfterUpdate(newPlans, oldMap);
        } finally {
            isRunning = false;
        }
    }
}

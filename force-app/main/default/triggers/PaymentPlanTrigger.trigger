trigger PaymentPlanTrigger on Payment_Plan__c (before insert, before update, after insert, after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        PaymentPlanTriggerHandler handler = new PaymentPlanTriggerHandler(Trigger.new, Trigger.old);
        handler.handleMissedPayments(Trigger.new, Trigger.old);
        handler.afterUpdate();
    }
}
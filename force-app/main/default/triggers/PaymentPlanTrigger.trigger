// Entry point for Payment_Plan__c trigger events.
trigger PaymentPlanTrigger on Payment_Plan__c (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        BeforePaymentPlanUpdateHandler.handleBeforeUpdate(Trigger.new);
        PaymentPlanTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        PaymentPlanTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}

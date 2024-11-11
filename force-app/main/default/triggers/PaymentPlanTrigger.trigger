trigger PaymentPlanTrigger on Payment_Plan__c (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    PaymentPlanTriggerHandler handler = new PaymentPlanTriggerHandler(Trigger.new, Trigger.old);
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        handler.afterUpdate();
    }
}
trigger LoanTrigger on Loan__c (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    LoanTriggerHandler handler = new LoanTriggerHandler(Trigger.new, Trigger.old);

    if (Trigger.isAfter && Trigger.isUpdate) {
        handler.afterUpdate();
    }
}
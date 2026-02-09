trigger LoanEventTrigger on Loan_Event__e (after insert) {
    LoanEventConsumer.handle(Trigger.new);
}

/**
 * Publishes platform events for loan state changes.
 */
public with sharing class LoanEventPublisher {
    /**
     * Publishes status change events and returns publish results.
     */
    public static List<Database.SaveResult> publishStatusChanges(List<Loan__c> loans) {
        if (loans == null || loans.isEmpty()) return new List<Database.SaveResult>();
        List<Loan_Event__e> events = new List<Loan_Event__e>();
        for (Loan__c loan : loans) {
            if (loan == null) continue;
            // Minimal payload for downstream consumers.
            Loan_Event__e evt = new Loan_Event__e(
                Loan_Id__c = String.valueOf(loan.Id),
                Event_Type__c = 'StatusChanged',
                Payload__c = 'Loan_Status__c=' + loan.Loan_Status__c
            );
            events.add(evt);
        }
        if (!events.isEmpty()) {
            return EventBus.publish(events);
        }
        return new List<Database.SaveResult>();
    }
}

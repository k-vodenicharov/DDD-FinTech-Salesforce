/**
 * Test-only platform event consumer stub.
 */
public with sharing class LoanEventConsumer {
    /** Logs received events during tests. */
    public static void handle(List<Loan_Event__e> events) {
        if (events == null || events.isEmpty()) return;
        // Only active in tests to avoid runtime side effects.
        if (!Test.isRunningTest()) {
            return;
        }
        for (Loan_Event__e evt : events) {
            if (evt == null) continue;
            System.debug(LoggingLevel.INFO,
                'Loan event received. Type=' + evt.Event_Type__c + ', LoanId=' + evt.Loan_Id__c);
        }
    }
}

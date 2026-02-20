/**
 * Backward-compatible wrapper around the v2 escalation job.
 */
global class LoanMissingDocumentAlertJob implements Schedulable {
    global void execute(SchedulableContext ctx) {
        new LoanDocumentEscalationJob().execute(ctx);
    }
}

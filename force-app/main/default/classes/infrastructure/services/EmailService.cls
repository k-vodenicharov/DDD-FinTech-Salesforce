/**
 * Email composition helpers for loan payment reminders.
 */
public class EmailService {
    /**
     * Sends an email to the borrower reminding them of an upcoming payment.
     */
    public static void sendUpcomingPaymentReminder(String email, String name, Payment_Plan__c payment) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { email });
        mail.setSubject('Upcoming Payment Reminder');
        mail.setPlainTextBody('Dear ' + name + ',\n\nThis is a reminder that your payment of ' +
                              payment.Payment_Amount__c + ' is due on ' + payment.Payment_Deadline__c +
                              '. Please make the payment to avoid penalties.\n\nThank you.');
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    /**
     * Sends an email to the borrower reminding them of a missed payment.
     */
    public static void sendMissedPaymentReminder(String email, String name, Payment_Plan__c payment) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { email });
        mail.setSubject('Missed Payment Reminder');
        mail.setPlainTextBody('Dear ' + name + ',\n\nYou have missed a payment due on ' +
                              payment.Payment_Deadline__c + '. Please make the payment at the earliest to avoid penalties.\n\nThank you.');
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    /**
     * Sends missing-document alert to operations/admin recipients.
     */
    public static void sendMissingDocumentAlert(List<String> emails, Loan__c loan, List<String> missingTypes) {
        if (emails == null || emails.isEmpty() || loan == null || missingTypes == null || missingTypes.isEmpty()) {
            return;
        }
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(emails);
        mail.setSubject('Missing Loan Documents: ' + loan.Name);
        String accountName = (loan.Account__r == null || String.isBlank(loan.Account__r.Name)) ? 'N/A' : loan.Account__r.Name;
        String body = 'Loan ' + loan.Name + ' (' + loan.Id + ') has missing required documents.\n' +
                      'Account: ' + accountName + '\n' +
                      'Missing: ' + String.join(missingTypes, ', ') + '\n\n' +
                      'Please review the loan record and request uploads from the borrower.';
        mail.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}

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
}
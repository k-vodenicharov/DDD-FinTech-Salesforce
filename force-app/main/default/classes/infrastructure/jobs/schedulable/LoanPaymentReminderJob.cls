global class LoanPaymentReminderJob implements Schedulable {

    global void execute(SchedulableContext ctx) {

        List<Payment_Plan__c> payments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Payment_Amount__c, Loan__r.Account__r.Id
            FROM Payment_Plan__c
            WHERE Payment_Status__c != 'Approved'
            AND Payment_Deadline__c = :System.today().addDays(5) // 5 days before deadline
        ];

        Map<Id, List<Contact>> accountContactsMap = new Map<Id, List<Contact>>();
        for (Contact contact : [
            SELECT Id, Email, FirstName, LastName, AccountId
            FROM Contact
        ]) {
            if (!accountContactsMap.containsKey(contact.AccountId)) {
                accountContactsMap.put(contact.AccountId, new List<Contact>());
            }
            accountContactsMap.get(contact.AccountId).add(contact);
        }

        // Process payments and send reminders
        for (Payment_Plan__c payment : payments) {
            Id accountId = payment.Loan__r.Account__r.Id;
            List<Contact> accountContacts = accountContactsMap.get(accountId);

            if (accountContacts != null && !accountContacts.isEmpty()) {
                // Pick the first contact for simplicity
                Contact borrower = accountContacts[0];
                String borrowerEmail = borrower.Email;
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;

                if (String.isNotBlank(borrowerEmail)) {
                    EmailService.sendUpcomingPaymentReminder(borrowerEmail, borrowerName, payment);
                }
            }
        }

        // Send follow-up emails for missed payments
        List<Payment_Plan__c> missedPayments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Loan__r.Account__r.Id
            FROM Payment_Plan__c
            WHERE Payment_Status__c != 'Approved'
            AND Payment_Deadline__c < :System.today().addDays(-7) // Deadline passed more than 7 days ago
        ];

        for (Payment_Plan__c missedPayment : missedPayments) {
            Id accountId = missedPayment.Loan__r.Account__r.Id;
            List<Contact> accountContacts = accountContactsMap.get(accountId);

            if (accountContacts != null && !accountContacts.isEmpty()) {
                // Pick the first contact for simplicity
                Contact borrower = accountContacts[0];
                String borrowerEmail = borrower.Email;
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;

                if (String.isNotBlank(borrowerEmail)) {
                    EmailService.sendMissedPaymentReminder(borrowerEmail, borrowerName, missedPayment);
                }
            }
        }
    }
}
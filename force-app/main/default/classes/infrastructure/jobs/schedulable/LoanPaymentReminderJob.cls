global class LoanPaymentReminderJob implements Schedulable {

    global void execute(SchedulableContext ctx) {
        System.debug('=== START LoanPaymentReminderJob ===');
        System.debug('System.today(): ' + System.today());
        System.debug('Looking for payments due on: ' + System.today().addDays(5));
        
        // Send reminders for payments due 5 days from now
        List<Payment_Plan__c> payments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Payment_Amount__c, Loan__r.Account__r.Id, Loan__r.Principal_Plus_Interest__c
            FROM Payment_Plan__c
            WHERE Payment_Status__c != 'Completed'
            AND Payment_Deadline__c = :System.today().addDays(5) // 5 days before deadline
        ];
        
        System.debug('Found ' + payments.size() + ' payments due 5 days from now');
        
        // Add more debug info
        for(Payment_Plan__c p : payments) {
            System.debug('Payment ID: ' + p.Id + ', Deadline: ' + p.Payment_Deadline__c);
        }

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
            System.debug('Processing payment: ' + payment.Id);
            Id accountId = payment.Loan__r.Account__r.Id;
            List<Contact> accountContacts = accountContactsMap.get(accountId);

            System.debug('Account ID: ' + accountId);
            System.debug('Account contacts found: ' + (accountContacts != null ? accountContacts.size() : 0));

            if (accountContacts != null && !accountContacts.isEmpty()) {
                // Pick the first contact for simplicity
                Contact borrower = accountContacts[0];
                String borrowerEmail = borrower.Email;
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;

                System.debug('Borrower email: ' + borrowerEmail);
                System.debug('Borrower name: ' + borrowerName);

                if (String.isNotBlank(borrowerEmail)) {
                    System.debug('Sending email reminder...');
                    EmailService.sendUpcomingPaymentReminder(borrowerEmail, borrowerName, payment);
                    System.debug('Email sent successfully');
                } else {
                    System.debug('Email is blank, skipping');
                }
            } else {
                System.debug('No contacts found for account');
            }
        }
        
        // Send follow-up emails for missed payments (due more than 7 days ago)
        List<Payment_Plan__c> missedPayments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Loan__r.Account__r.Id, Loan__r.Principal_Plus_Interest__c
            FROM Payment_Plan__c
            WHERE Payment_Status__c != 'Completed'
            AND Payment_Deadline__c < :System.today().addDays(-7) // Deadline passed more than 7 days ago
        ];

        System.debug('Found ' + missedPayments.size() + ' missed payments');
        for(Payment_Plan__c p : missedPayments) {
            System.debug('Missed Payment ID: ' + p.Id + ', Deadline: ' + p.Payment_Deadline__c);
        }

        for (Payment_Plan__c missedPayment : missedPayments) {
            Id accountId = missedPayment.Loan__r.Account__r.Id;
            List<Contact> accountContacts = accountContactsMap.get(accountId);

            if (accountContacts != null && !accountContacts.isEmpty()) {
                // Pick the first contact for simplicity
                Contact borrower = accountContacts[0];
                String borrowerEmail = borrower.Email;
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;

                if (String.isNotBlank(borrowerEmail)) {
                    System.debug('Sending missed payment reminder...');
                    EmailService.sendMissedPaymentReminder(borrowerEmail, borrowerName, missedPayment);
                    System.debug('Missed payment email sent successfully');
                }
            }
        }
        System.debug('=== END LoanPaymentReminderJob ===');
    }
}
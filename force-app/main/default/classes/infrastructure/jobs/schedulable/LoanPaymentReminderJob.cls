/**
 * Scheduled job to send upcoming and missed payment reminders.
 */
global class LoanPaymentReminderJob implements Schedulable {
    private static final Integer FOLLOW_UP_DAYS_AFTER_DEADLINE = 3;

    /** Executes reminder logic on schedule. */
    global void execute(SchedulableContext ctx) {
        // Send reminders for payments due exactly 5 days from today.
        List<Payment_Plan__c> upcomingPayments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Payment_Amount__c, Loan__r.Account__r.Id, Loan__r.Principal_Plus_Interest__c
            FROM Payment_Plan__c
            WHERE Payment_Status__c = 'Pending'
            AND Payment_Deadline__c = :System.today().addDays(5)
            WITH SECURITY_ENFORCED
        ];
        upcomingPayments = sanitizePayments(upcomingPayments);
        
        Set<Id> accountIds = new Set<Id>();
        for (Payment_Plan__c payment : upcomingPayments) {
            if (payment.Loan__r != null && payment.Loan__r.Account__r != null) {
                accountIds.add(payment.Loan__r.Account__r.Id);
            }
        }
        
        // Send follow-up emails for missed payments (overdue by a fixed grace period).
        Date followUpDate = System.today().addDays(-FOLLOW_UP_DAYS_AFTER_DEADLINE);
        List<Payment_Plan__c> missedPayments = [
            SELECT Id, Payment_Deadline__c, Payment_Status__c, Loan__r.Account__r.Id, Loan__r.Principal_Plus_Interest__c
            FROM Payment_Plan__c
            WHERE Payment_Status__c = 'Pending'
            AND Payment_Deadline__c = :followUpDate
            WITH SECURITY_ENFORCED
        ];
        missedPayments = sanitizePayments(missedPayments);

        for (Payment_Plan__c missedPayment : missedPayments) {
            if (missedPayment.Loan__r != null && missedPayment.Loan__r.Account__r != null) {
                accountIds.add(missedPayment.Loan__r.Account__r.Id);
            }
        }

        Map<Id, Contact> contactByAccount = new Map<Id, Contact>();
        if (!accountIds.isEmpty()) {
            List<Contact> contacts = [
                SELECT Id, Email, FirstName, LastName, AccountId
                FROM Contact
                WHERE AccountId IN :accountIds
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ];
            contacts = sanitizeContacts(contacts);
            for (Contact contact : contacts) {
                if (contactByAccount.containsKey(contact.AccountId)) continue;
                if (String.isBlank(contact.Email)) continue;
                contactByAccount.put(contact.AccountId, contact);
            }
        }

        for (Payment_Plan__c payment : upcomingPayments) {
            Id accountId = payment.Loan__r.Account__r.Id;
            Contact borrower = contactByAccount.get(accountId);
            if (borrower != null && String.isNotBlank(borrower.Email)) {
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;
                EmailService.sendUpcomingPaymentReminder(borrower.Email, borrowerName, payment);
            }
        }

        for (Payment_Plan__c missedPayment : missedPayments) {
            Id accountId = missedPayment.Loan__r.Account__r.Id;
            Contact borrower = contactByAccount.get(accountId);
            if (borrower != null && String.isNotBlank(borrower.Email)) {
                String borrowerName = borrower.FirstName + ' ' + borrower.LastName;
                EmailService.sendMissedPaymentReminder(borrower.Email, borrowerName, missedPayment);
            }
        }
    }

    /** Applies FLS read filtering to payment plans. */
    private static List<Payment_Plan__c> sanitizePayments(List<Payment_Plan__c> plans) {
        if (plans == null || plans.isEmpty()) return new List<Payment_Plan__c>();
        List<SObject> sobs = new List<SObject>();
        sobs.addAll(plans);
        List<SObject> sanitized = SecurityUtil.stripRead(sobs);
        List<Payment_Plan__c> result = new List<Payment_Plan__c>();
        for (SObject s : sanitized) {
            result.add((Payment_Plan__c) s);
        }
        return result;
    }

    /** Applies FLS read filtering to contacts. */
    private static List<Contact> sanitizeContacts(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) return new List<Contact>();
        List<SObject> sobs = new List<SObject>();
        sobs.addAll(contacts);
        List<SObject> sanitized = SecurityUtil.stripRead(sobs);
        List<Contact> result = new List<Contact>();
        for (SObject s : sanitized) {
            result.add((Contact) s);
        }
        return result;
    }
}

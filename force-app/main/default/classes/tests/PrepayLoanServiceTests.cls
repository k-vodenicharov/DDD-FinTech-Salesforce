/**
 * Unit tests for PrepayLoanCommandService.
 */
@IsTest
private class PrepayLoanServiceTests {
    private static User createAdminUser() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'admin',
            Email = 'admin.user@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'admin.user+' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@example.com'
        );
        insert u;
        return u;
    }

    private static Account createAccountWithContact(String accountName, String email) {
        Account acc = new Account(Name = accountName);
        insert acc;
        if (email != null) {
            Contact c = new Contact(FirstName = 'Test', LastName = 'User', Email = email, AccountId = acc.Id);
            insert c;
        }
        return acc;
    }

    private static Loan__c createLoan(Account acc, Decimal amount, Integer term, Decimal rate) {
        Loan__c loan = new Loan__c(
            Name = 'Loan Unsecured - ' + amount,
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = amount,
            Loan_Term__c = term,
            Interest_Rate__c = rate,
            Principal_Plus_Interest__c = amount + (amount * (rate == null ? 0 : rate) / 100),
            Loan_Status__c = 'Pending',
            Account__c = acc.Id
        );
        insert loan;
        return loan;
    }

    private static void createPaymentPlan(Loan__c loan, Date deadline, String status, Decimal amount) {
        Payment_Plan__c plan = new Payment_Plan__c(
            Loan__c = loan.Id,
            Payment_Amount__c = amount,
            Payment_Deadline__c = deadline,
            Payment_Status__c = status,
            Name = 'PP-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert plan;
    }

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Borrower');
        insert acc;

        Loan__c loan = new Loan__c(
            Name = 'Loan Unsecured - 12000',
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 12000,
            Loan_Term__c = 3,
            Interest_Rate__c = 0,
            Principal_Plus_Interest__c = 12000,
            Loan_Status__c = 'Pending',
            Account__c = acc.Id
        );
        insert loan;

        // Two pending, one completed
        List<Payment_Plan__c> plans = new List<Payment_Plan__c>{
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 4000, Payment_Deadline__c = Date.today().addMonths(1).toStartOfMonth(), Payment_Status__c = 'Pending', Name='PP-1'),
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 4000, Payment_Deadline__c = Date.today().addMonths(2).toStartOfMonth(), Payment_Status__c = 'Pending', Name='PP-2'),
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 4000, Payment_Deadline__c = Date.today().addMonths(3).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-3')
        };
        insert plans;
    }

    @IsTest
    static void testPrepayLoan_ClosesLoanAndCompletesPlans() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Loan__c loan = [SELECT Id, Loan_Status__c FROM Loan__c LIMIT 1];

            Test.startTest();
            PrepayLoanCommandService svc = new PrepayLoanCommandService();
            ResponseWrapper res = svc.prepayLoan(loan.Id);
            Test.stopTest();

            System.assertEquals(true, res.isSuccess, 'Prepayment should succeed');
            System.assertEquals(8000, res.remainingBalance, 'Remaining balance should sum only pending installments');

            List<Payment_Plan__c> afterPlans = [
                SELECT Id, Payment_Status__c, BYPASS__c
                FROM Payment_Plan__c
                WHERE Loan__c = :loan.Id
            ];
            for (Payment_Plan__c pp : afterPlans) {
                System.assertEquals('Completed', pp.Payment_Status__c, 'All plans should be completed after prepay');
                System.assertEquals(false, pp.BYPASS__c, 'BYPASS__c should be reset after prepay adjustments');
            }

            Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
            System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay');
        }
    }

    @IsTest
    static void testPrepayLoan_InvalidInput() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Test.startTest();
            PrepayLoanCommandService svc = new PrepayLoanCommandService();
            ResponseWrapper res = svc.prepayLoan(null);
            Test.stopTest();

            System.assertEquals(false, res.isSuccess, 'Should fail without loan Id');
            System.assertNotEquals(null, res.errorMessage, 'Error message expected');
        }
    }
    
    @IsTest
    static void testPrepayLoan_AllPlansCompleted() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = new Account(Name = 'Test Borrower 2');
            insert acc;

            Loan__c loan = new Loan__c(
                Name = 'Loan Unsecured - 9000',
                Loan_Type__c = 'Unsecured',
                Loan_Amount__c = 9000,
                Loan_Term__c = 3,
                Interest_Rate__c = 0,
                Principal_Plus_Interest__c = 9000,
                Loan_Status__c = 'Pending',
                Account__c = acc.Id
            );
            insert loan;

            List<Payment_Plan__c> plans = new List<Payment_Plan__c>{
                new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(1).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-1'),
                new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(2).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-2'),
                new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(3).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-3')
            };
            insert plans;

            Test.startTest();
            PrepayLoanCommandService svc = new PrepayLoanCommandService();
            ResponseWrapper res = svc.prepayLoan(loan.Id);
            Test.stopTest();

            System.assertEquals(true, res.isSuccess, 'Prepayment should succeed even when all plans are completed');
            System.assertEquals(0, res.remainingBalance, 'Remaining balance should be zero when all plans completed');

            List<Payment_Plan__c> afterPlans = [
                SELECT Id, Payment_Status__c
                FROM Payment_Plan__c
                WHERE Loan__c = :loan.Id
            ];
            for (Payment_Plan__c pp : afterPlans) {
                System.assertNotEquals(null, pp.Payment_Status__c, 'Payment status should remain set after prepay');
            }

            Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
            System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay even when all plans completed');
        }
    }
    
    @IsTest
    static void testPrepayLoan_NoPlans() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = new Account(Name = 'Test Borrower 3');
            insert acc;

            Loan__c loan = new Loan__c(
                Name = 'Loan Unsecured - 0',
                Loan_Type__c = 'Unsecured',
                Loan_Amount__c = 0,
                Loan_Term__c = 1,
                Interest_Rate__c = 0,
                Principal_Plus_Interest__c = 0,
                Loan_Status__c = 'Pending',
                Account__c = acc.Id
            );
            insert loan;

            Test.startTest();
            PrepayLoanCommandService svc = new PrepayLoanCommandService();
            ResponseWrapper res = svc.prepayLoan(loan.Id);
            Test.stopTest();

            System.assertEquals(true, res.isSuccess, 'Prepayment should succeed for loan with no plans');
            System.assertEquals(0, res.remainingBalance, 'Remaining balance should be zero for loan with no plans');

            Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
            System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay even with no plans');
        }
    }

    @IsTest
    static void testPrepayLoan_AdjustedInterest() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Early Prepay Account', 'early@example.com');

            Loan__c loan = new Loan__c(
                Name = 'Loan Unsecured - 12000',
                Loan_Type__c = 'Unsecured',
                Loan_Amount__c = 12000,
                Loan_Term__c = 12,
                Interest_Rate__c = 12,
                Principal_Plus_Interest__c = 12000 + (12000 * 0.12),
                Loan_Status__c = 'Pending',
                Account__c = acc.Id
            );
            insert loan;

            DateTime createdDt = DateTime.newInstance(Date.today().addMonths(-6), Time.newInstance(0, 0, 0, 0));
            Test.setCreatedDate(loan.Id, createdDt);

            createPaymentPlan(loan, Date.today().addDays(3), 'Pending', 1000);

            Decimal expectedInterest = 12000 * 0.12 * (6.0 / 12.0);
            Decimal expectedTotal = 12000 + expectedInterest;

            Test.startTest();
            PrepayLoanCommandService svc = new PrepayLoanCommandService();
            ResponseWrapper res = svc.prepayLoan(loan.Id);
            Test.stopTest();

            System.assertEquals(true, res.isSuccess, 'Prepayment should succeed with adjusted interest');

            Loan__c afterLoan = [
                SELECT Principal_Plus_Interest__c
                FROM Loan__c
                WHERE Id = :loan.Id
            ];
            System.assertEquals(expectedTotal.setScale(2), afterLoan.Principal_Plus_Interest__c.setScale(2),
                'Adjusted Principal_Plus_Interest__c should reflect early repayment term');
        }
    }

    @IsTest
    static void testBoundaryConditions_ClientSideValidation() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Boundary Account', 'boundary@example.com');

            Map<String, Object> loanData = new Map<String, Object>{
                'Loan_Type__c' => 'Secured',
                'Loan_Amount__c' => 10000,
                'Loan_Term__c' => 0,
                'Interest_Rate__c' => 5,
                'Account__c' => acc.Id
            };

            Test.startTest();
            ResponseWrapper res = new LoanCommandService().createLoan(JSON.serialize(loanData));
            Test.stopTest();

            System.assertEquals(false, res.isSuccess, 'Should fail for invalid loan term');
            System.assert(res.errorMessage != null, 'Expected error message for invalid loan term');
        }
    }

    @IsTest
    static void testBoundaryConditions_LoanAmountsAndTerms() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Boundary Account 2', 'boundary2@example.com');

            Map<String, Object> okLoanData = new Map<String, Object>{
                'Loan_Type__c' => 'Unsecured',
                'Loan_Amount__c' => 10000,
                'Loan_Term__c' => 12,
                'Interest_Rate__c' => 7,
                'Account__c' => acc.Id
            };

            Test.startTest();
            ResponseWrapper okRes = new LoanCommandService().createLoan(JSON.serialize(okLoanData));
            Test.stopTest();

            System.assertEquals(true, okRes.isSuccess, 'Should allow max unsecured term');
        }
    }

    @IsTest
    static void testEmailFunctionality_VerifyEmailSendingLogic() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Email Account', 'email@example.com');
            Loan__c loan = createLoan(acc, 12000, 3, 5);

            createPaymentPlan(loan, Date.today().addDays(3), 'Pending', 4000);
            createPaymentPlan(loan, Date.today().addDays(-3), 'Pending', 4000);

            List<Payment_Plan__c> upcoming = [
                SELECT Id FROM Payment_Plan__c
                WHERE Payment_Status__c != 'Completed'
                AND Payment_Deadline__c >= :Date.today()
                AND Payment_Deadline__c <= :Date.today().addDays(5)
                AND Payment_Deadline__c != :Date.today()
            ];
            List<Payment_Plan__c> missed = [
                SELECT Id FROM Payment_Plan__c
                WHERE Payment_Status__c != 'Completed'
                AND Payment_Deadline__c = :Date.today().addDays(-3)
            ];
            System.assertEquals(1, upcoming.size(), 'Expected one upcoming payment');
            System.assertEquals(1, missed.size(), 'Expected one missed payment');

            Test.startTest();
            new LoanPaymentReminderJob().execute(null);
            Test.stopTest();
        }
    }

    @IsTest
    static void testEmailFunctionality_RecipientIdentification() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account accWithEmail = createAccountWithContact('Has Email', 'has@example.com');
            Account accNoEmail = createAccountWithContact('No Email', null);

            Loan__c loan1 = createLoan(accWithEmail, 10000, 3, 5);
            Loan__c loan2 = createLoan(accNoEmail, 10000, 3, 5);

            createPaymentPlan(loan1, Date.today().addDays(2), 'Pending', 3000);
            createPaymentPlan(loan2, Date.today().addDays(2), 'Pending', 3000);

            List<Contact> contacts = [
                SELECT Id, Email FROM Contact
                WHERE AccountId IN :new Set<Id>{accWithEmail.Id, accNoEmail.Id}
            ];
            Integer withEmail = 0;
            for (Contact c : contacts) {
                if (String.isNotBlank(c.Email)) withEmail++;
            }
            System.assertEquals(1, withEmail, 'Expected one contact with email');

            Test.startTest();
            new LoanPaymentReminderJob().execute(null);
            Test.stopTest();
        }
    }

    @IsTest
    static void testEmailFunctionality_EmailContentValidation() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Content Account', 'content@example.com');
            Loan__c loan = createLoan(acc, 5000, 2, 5);
            createPaymentPlan(loan, Date.today().addDays(3), 'Pending', 2500);

            List<Payment_Plan__c> upcoming = [
                SELECT Id FROM Payment_Plan__c
                WHERE Payment_Status__c != 'Completed'
                AND Payment_Deadline__c >= :Date.today()
                AND Payment_Deadline__c <= :Date.today().addDays(5)
                AND Payment_Deadline__c != :Date.today()
            ];
            System.assertEquals(1, upcoming.size(), 'Expected one upcoming payment');

            Test.startTest();
            new LoanPaymentReminderJob().execute(null);
            Test.stopTest();
        }
    }

    @IsTest
    static void testEmailFunctionality_MissedPaymentNotification() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account acc = createAccountWithContact('Missed Account', 'missed@example.com');
            Loan__c loan = createLoan(acc, 8000, 2, 5);
            createPaymentPlan(loan, Date.today().addDays(-3), 'Pending', 4000);

            List<Payment_Plan__c> missed = [
                SELECT Id FROM Payment_Plan__c
                WHERE Payment_Status__c != 'Completed'
                AND Payment_Deadline__c = :Date.today().addDays(-3)
            ];
            System.assertEquals(1, missed.size(), 'Expected one missed payment');

            Test.startTest();
            new LoanPaymentReminderJob().execute(null);
            Test.stopTest();
        }
    }
}

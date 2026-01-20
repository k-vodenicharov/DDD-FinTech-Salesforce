@IsTest
private class PrepayLoanServiceTests {
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
        Loan__c loan = [SELECT Id, Loan_Status__c FROM Loan__c LIMIT 1];

        Test.startTest();
        PrepayLoanService.PrepayResult res = PrepayLoanService.prepayLoan(loan.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Prepayment should succeed');
        System.assertEquals(8000, res.remainingBalance, 'Remaining balance should sum only pending installments');

        // Verify all plans completed
        List<Payment_Plan__c> afterPlans = [
            SELECT Id, Payment_Status__c
            FROM Payment_Plan__c
            WHERE Loan__c = :loan.Id
        ];
        for (Payment_Plan__c pp : afterPlans) {
            System.assertEquals('Completed', pp.Payment_Status__c, 'All plans should be completed after prepay');
        }

        // Verify Loan status Closed
        Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
        System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay');
    }

    @IsTest
    static void testPrepayLoan_InvalidInput() {
        Test.startTest();
        PrepayLoanService.PrepayResult res = PrepayLoanService.prepayLoan(null);
        Test.stopTest();

        System.assertEquals(false, res.success, 'Should fail without loan Id');
        System.assertNotEquals(null, res.error, 'Error message expected');
    }
    
    @IsTest
    static void testPrepayLoan_AllPlansCompleted() {
        // Setup: Create a loan with all plans already completed
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

        // All plans already completed
        List<Payment_Plan__c> plans = new List<Payment_Plan__c>{
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(1).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-1'),
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(2).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-2'),
            new Payment_Plan__c(Loan__c = loan.Id, Payment_Amount__c = 3000, Payment_Deadline__c = Date.today().addMonths(3).toStartOfMonth(), Payment_Status__c = 'Completed', Name='PP-3')
        };
        insert plans;

        Test.startTest();
        PrepayLoanService.PrepayResult res = PrepayLoanService.prepayLoan(loan.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Prepayment should succeed even when all plans are completed');
        System.assertEquals(0, res.remainingBalance, 'Remaining balance should be zero when all plans completed');

        // Verify all plans still completed
        List<Payment_Plan__c> afterPlans = [
            SELECT Id, Payment_Status__c
            FROM Payment_Plan__c
            WHERE Loan__c = :loan.Id
        ];
        for (Payment_Plan__c pp : afterPlans) {
            System.assertEquals('Completed', pp.Payment_Status__c, 'All plans should remain completed after prepay');
        }

        // Verify Loan status Closed
        Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
        System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay even when all plans completed');
    }
    
    @IsTest
    static void testPrepayLoan_NoPlans() {
        // Setup: Create a loan with no payment plans (edge case)
        Account acc = new Account(Name = 'Test Borrower 3');
        insert acc;

        Loan__c loan = new Loan__c(
            Name = 'Loan Unsecured - 0',
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 0,
            Loan_Term__c = 0,
            Interest_Rate__c = 0,
            Principal_Plus_Interest__c = 0,
            Loan_Status__c = 'Pending',
            Account__c = acc.Id
        );
        insert loan;

        Test.startTest();
        PrepayLoanService.PrepayResult res = PrepayLoanService.prepayLoan(loan.Id);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Prepayment should succeed for loan with no plans');
        System.assertEquals(0, res.remainingBalance, 'Remaining balance should be zero for loan with no plans');

        // Verify Loan status Closed
        Loan__c afterLoan = [SELECT Loan_Status__c FROM Loan__c WHERE Id = :loan.Id];
        System.assertEquals('Closed', afterLoan.Loan_Status__c, 'Loan should be Closed after prepay even with no plans');
    }

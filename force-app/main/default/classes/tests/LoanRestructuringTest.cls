/**
 * Unit tests for loan restructuring adjustments.
 */
@isTest
public class LoanRestructuringTest {
    private static Loan__c insertLoanWithPlans(Loan__c loan) {
        Test.startTest();
        insert loan;
        Test.stopTest();
        return [
            SELECT Id, CreatedDate, Loan_Term__c, Loan_Type__c, Loan_Amount__c, Principal_Plus_Interest__c, Interest_Rate__c
            FROM Loan__c
            WHERE Id = :loan.Id
        ];
    }
    
    @isTest
    static void testInterestOnlyChange() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );

        Loan__c insertedLoan = insertLoanWithPlans(testLoan);
        System.assertEquals(31500, insertedLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');

        List<Payment_Plan__c> initialPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');

        testLoan.Interest_Rate__c = 7;

        update testLoan;
        new PaymentPlanCommandService().adjustPlansForLoanIds(new Set<Id>{testLoan.Id});

        Loan__c updatedLoan = [
            SELECT Id, Principal_Plus_Interest__c, Interest_Rate__c FROM Loan__c WHERE Id = :testLoan.Id
        ];
        System.assertEquals(7, updatedLoan.Interest_Rate__c, 'Interest rate should be updated');
        System.assertEquals(32100, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should be recalculated correctly (30000 + 30000*0.07)');

        List<Payment_Plan__c> updatedPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(3, updatedPlans.size(), 'Should still have 3 payment plans');

        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(32100, totalAmount, 'Payment plan amounts should sum to new Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testTermOnlyChange() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );

        Loan__c insertedLoan = insertLoanWithPlans(testLoan);
        System.assertEquals(31500, insertedLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');

        List<Payment_Plan__c> initialPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');

        testLoan.Loan_Term__c = 5;

        update testLoan;
        new PaymentPlanCommandService().adjustPlansForLoanIds(new Set<Id>{testLoan.Id});

        Loan__c updatedLoan = [
            SELECT Id, Loan_Term__c, Principal_Plus_Interest__c FROM Loan__c WHERE Id = :testLoan.Id
        ];
        System.assertEquals(5, updatedLoan.Loan_Term__c, 'Loan term should be updated');
        System.assertEquals(31500, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should remain the same');

        List<Payment_Plan__c> updatedPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(5, updatedPlans.size(), 'Should now have 5 payment plans');

        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(31500, totalAmount, 'Payment plan amounts should sum to Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testCombinedChange() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );

        Loan__c insertedLoan = insertLoanWithPlans(testLoan);
        System.assertEquals(31500, insertedLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');

        List<Payment_Plan__c> initialPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');

        testLoan.Loan_Term__c = 4;
        testLoan.Interest_Rate__c = 6;

        update testLoan;
        new PaymentPlanCommandService().adjustPlansForLoanIds(new Set<Id>{testLoan.Id});

        Loan__c updatedLoan = [
            SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, Interest_Rate__c FROM Loan__c WHERE Id = :testLoan.Id
        ];
        System.assertEquals(4, updatedLoan.Loan_Term__c, 'Loan term should be updated');
        System.assertEquals(6, updatedLoan.Interest_Rate__c, 'Interest rate should be updated');
        System.assertEquals(31800, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should be recalculated correctly (30000 + 30000*0.06)');

        List<Payment_Plan__c> updatedPlans = [
            SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(4, updatedPlans.size(), 'Should now have 4 payment plans');

        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(31800, totalAmount, 'Payment plan amounts should sum to new Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testNoChange() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );

        Loan__c insertedLoan = insertLoanWithPlans(testLoan);
        Decimal initialPI = insertedLoan.Principal_Plus_Interest__c;
        Integer initialTerm = insertedLoan.Loan_Term__c.intValue();
        
        testLoan.Loan_Term__c = 3;
        testLoan.Interest_Rate__c = 5;
        
        update testLoan;
        new PaymentPlanCommandService().adjustPlansForLoanIds(new Set<Id>{testLoan.Id});
        
        Loan__c updatedLoan = [
            SELECT Id, Loan_Term__c, Principal_Plus_Interest__c FROM Loan__c WHERE Id = :testLoan.Id
        ];
        System.assertEquals(initialTerm, updatedLoan.Loan_Term__c.intValue(), 'Loan term should remain unchanged');
        System.assertEquals(initialPI, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should remain unchanged');
    }

    @isTest
    static void testTermReductionBelowCompletedPlansBlocked() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 12000,
            Loan_Term__c = 3,
            Interest_Rate__c = 0,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );

        Loan__c insertedLoan = insertLoanWithPlans(testLoan);

        List<Payment_Plan__c> plans = [
            SELECT Id, Payment_Status__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id
            ORDER BY Payment_Deadline__c
        ];
        System.assertEquals(3, plans.size(), 'Expected 3 payment plans after insert');

        plans[0].Payment_Status__c = 'Completed';
        plans[1].Payment_Status__c = 'Completed';
        update new List<Payment_Plan__c>{ plans[0], plans[1] };

        testLoan.Loan_Term__c = 1;

        try {
            update testLoan;
            System.assert(false, 'Expected validation error when reducing term below completed plans');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Loan term cannot be less than completed payment plans'),
                'Expected completed plan count validation error');
        }
    }

    @isTest
    static void testScheduleAnchoringPreservesEarliestOpenDeadline() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c loan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );
        Loan__c insertedLoan = insertLoanWithPlans(loan);

        List<Payment_Plan__c> plans = [
            SELECT Id, Payment_Status__c, Payment_Deadline__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id
            ORDER BY Payment_Deadline__c
        ];
        System.assertEquals(3, plans.size(), 'Expected 3 payment plans after insert');

        // Mark the first plan completed and keep the next open deadline as anchor.
        plans[0].Payment_Status__c = 'Completed';
        update plans[0];

        Date expectedFirstOpen = plans[1].Payment_Deadline__c;

        insertedLoan.Loan_Term__c = 5;
        update insertedLoan;
        new PaymentPlanCommandService().adjustPlansForLoanIds(new Set<Id>{insertedLoan.Id});

        List<Payment_Plan__c> updatedPlans = [
            SELECT Id, Payment_Status__c, Payment_Deadline__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id AND Payment_Status__c != 'Completed'
            ORDER BY Payment_Deadline__c
        ];
        System.assert(!updatedPlans.isEmpty(), 'Expected open plans after term increase');
        System.assertEquals(expectedFirstOpen, updatedPlans[0].Payment_Deadline__c,
            'Earliest open deadline should be preserved after restructuring');
    }

    @isTest
    static void testDeleteLoan() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c loan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 5000,
            Loan_Term__c = 2,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Pending',
            Account__c = testAccount.Id
        );
        insert loan;

        ResponseWrapper res = new LoanCommandService().deleteLoan(loan.Id);
        System.assertEquals(true, res.isSuccess, 'Delete should succeed');

        Integer countRemaining = [SELECT COUNT() FROM Loan__c WHERE Id = :loan.Id];
        System.assertEquals(0, countRemaining, 'Loan should be deleted');
    }
}

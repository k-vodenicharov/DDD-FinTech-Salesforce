/**
 * Unit tests for payment plan validation and redistribution.
 */
@isTest
public class PaymentPlanValidationTests {
    /** Inserts a loan and waits for async plan creation. */
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
    static void testEditAllOpenPlansBlocked() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Loan__c loan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 3000,
            Loan_Term__c = 3,
            Interest_Rate__c = 0,
            Loan_Status__c = 'Pending',
            Account__c = acct.Id
        );
        Loan__c insertedLoan = insertLoanWithPlans(loan);

        List<Payment_Plan__c> plans = [
            SELECT Id, Payment_Amount__c, Payment_Status__c, BYPASS__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id
            ORDER BY Payment_Deadline__c
        ];
        System.assertEquals(3, plans.size(), 'Expected 3 payment plans');

        for (Payment_Plan__c plan : plans) {
            plan.Payment_Amount__c = 1;
            plan.BYPASS__c = true;
        }

        try {
            update plans;
            System.assert(false, 'Expected validation error when all open plans are edited off total');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Payment amounts must total the remaining balance'),
                'Expected remaining balance validation error'
            );
        }
    }

    @isTest
    static void testEditOnePlanAdjustsRemaining() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Loan__c loan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 3000,
            Loan_Term__c = 3,
            Interest_Rate__c = 0,
            Loan_Status__c = 'Pending',
            Account__c = acct.Id
        );
        Loan__c insertedLoan = insertLoanWithPlans(loan);

        List<Payment_Plan__c> plans = [
            SELECT Id, Payment_Amount__c, Payment_Status__c, BYPASS__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id
            ORDER BY Payment_Deadline__c
        ];
        System.assertEquals(3, plans.size(), 'Expected 3 payment plans');

        Decimal originalFirst = plans[0].Payment_Amount__c;
        plans[0].Payment_Amount__c = originalFirst + 100;
        plans[0].BYPASS__c = true;

        update plans[0];

        List<Payment_Plan__c> updatedPlans = [
            SELECT Id, Payment_Amount__c, Payment_Status__c
            FROM Payment_Plan__c
            WHERE Loan__c = :insertedLoan.Id
        ];

        Decimal total = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            if (plan.Payment_Amount__c != null) total += plan.Payment_Amount__c;
        }
        System.assertEquals(
            insertedLoan.Principal_Plus_Interest__c,
            total,
            'Updated payment plan amounts should sum to Principal_Plus_Interest__c'
        );
    }
}

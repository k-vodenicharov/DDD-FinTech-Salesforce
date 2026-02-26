/**
 * Unit tests for repository implementations.
 */
@isTest
public class RepositoryTests {
    
    @isTest
    static void testLoanRepositoryInterfaces() {
        // Setup test data
        Account testAccount = new Account(
            Name = 'Test Account',
            Account_Type__c = 'Loan'
        );
        insert testAccount;
        
        Loan__c testLoan = new Loan__c(
            Account__c = testAccount.Id,
            Loan_Type__c = 'Secured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 6,
            Interest_Rate__c = 5.0
        );
        
        // Test save and findById
        LoanRepository loanRepo = new LoanRepository();
        loanRepo.save(testLoan);
        
        // Verify the loan was saved
        Loan__c retrievedLoan = loanRepo.findById(testLoan.Id);
        System.assertEquals(testLoan.Id, retrievedLoan.Id);
        System.assertEquals(testLoan.Loan_Type__c, retrievedLoan.Loan_Type__c);

        // Test update path via save
        retrievedLoan.Interest_Rate__c = 6.5;
        loanRepo.save(retrievedLoan);
        Loan__c updatedLoan = loanRepo.findById(testLoan.Id);
        System.assertEquals(6.5, updatedLoan.Interest_Rate__c);
        
        // Test saveAll
        List<Loan__c> loansToSave = new List<Loan__c>();
        Loan__c loan1 = new Loan__c(
            Account__c = testAccount.Id,
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 15000,
            Loan_Term__c = 12,
            Interest_Rate__c = 7.0
        );
        Loan__c loan2 = new Loan__c(
            Account__c = testAccount.Id,
            Loan_Type__c = 'Secured',
            Loan_Amount__c = 20000,
            Loan_Term__c = 6,
            Interest_Rate__c = 6.0
        );
        loansToSave.add(loan1);
        loansToSave.add(loan2);
        
        loanRepo.saveAll(loansToSave);
        
        // Test findAllById
        Set<Id> loanIds = new Set<Id>{loan1.Id, loan2.Id};
        List<Loan__c> retrievedLoans = loanRepo.findAllById(loanIds);
        System.assertEquals(2, retrievedLoans.size());

        // Test bulk update path via saveAll
        for (Loan__c row : retrievedLoans) {
            row.Interest_Rate__c = 8.0;
        }
        loanRepo.saveAll(retrievedLoans);
        List<Loan__c> updatedLoans = loanRepo.findAllById(loanIds);
        for (Loan__c row : updatedLoans) {
            System.assertEquals(8.0, row.Interest_Rate__c);
        }
        
        // Test findByAccountId
        List<Loan__c> loansByAccount = loanRepo.findByAccountId(testAccount.Id);
        System.assert(loansByAccount.size() >= 3); // Should include our 3 test loans
        
        // Test delete
        loanRepo.deleteRecord(testLoan);
        Loan__c deletedLoan = loanRepo.findById(testLoan.Id);
        System.assertEquals(null, deletedLoan);

        // Test bulk delete path
        loanRepo.deleteAll(updatedLoans);
        List<Loan__c> deletedLoans = loanRepo.findAllById(loanIds);
        System.assertEquals(0, deletedLoans.size());
    }
    
    @isTest
    static void testPaymentPlanRepositoryInterfaces() {
        // Setup test data
        Account testAccount = new Account(
            Name = 'Test Account',
            Account_Type__c = 'Loan'
        );
        insert testAccount;
        
        Loan__c testLoan = new Loan__c(
            Account__c = testAccount.Id,
            Loan_Type__c = 'Secured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 6,
            Interest_Rate__c = 5.0
        );
        insert testLoan;
        
        Payment_Plan__c testPaymentPlan = new Payment_Plan__c(
            Loan__c = testLoan.Id,
            Payment_Amount__c = 1000,
            Payment_Status__c = 'Pending',
            Payment_Deadline__c = Date.today().addDays(30)
        );
        
        // Test save and findById
        PaymentPlanRepository paymentPlanRepo = new PaymentPlanRepository();
        paymentPlanRepo.save(testPaymentPlan);
        
        // Verify the payment plan was saved
        Payment_Plan__c retrievedPlan = paymentPlanRepo.findById(testPaymentPlan.Id);
        System.assertEquals(testPaymentPlan.Id, retrievedPlan.Id);
        System.assertEquals(testPaymentPlan.Payment_Status__c, retrievedPlan.Payment_Status__c);

        // Test update path via save
        retrievedPlan.Payment_Status__c = 'Completed';
        paymentPlanRepo.save(retrievedPlan);
        Payment_Plan__c updatedPlan = paymentPlanRepo.findById(testPaymentPlan.Id);
        System.assertEquals('Completed', updatedPlan.Payment_Status__c);
        
        // Test saveAll
        List<Payment_Plan__c> plansToSave = new List<Payment_Plan__c>();
        Payment_Plan__c plan1 = new Payment_Plan__c(
            Loan__c = testLoan.Id,
            Payment_Amount__c = 1500,
            Payment_Status__c = 'Pending',
            Payment_Deadline__c = Date.today().addDays(60)
        );
        Payment_Plan__c plan2 = new Payment_Plan__c(
            Loan__c = testLoan.Id,
            Payment_Amount__c = 2000,
            Payment_Status__c = 'Pending',
            Payment_Deadline__c = Date.today().addDays(90)
        );
        plansToSave.add(plan1);
        plansToSave.add(plan2);
        
        paymentPlanRepo.saveAll(plansToSave);
        
        // Test findAllById
        Set<Id> planIds = new Set<Id>{plan1.Id, plan2.Id};
        List<Payment_Plan__c> retrievedPlans = paymentPlanRepo.findAllById(planIds);
        System.assertEquals(2, retrievedPlans.size());

        // Test bulk update path via saveAll
        for (Payment_Plan__c row : retrievedPlans) {
            row.Payment_Status__c = 'Completed';
        }
        paymentPlanRepo.saveAll(retrievedPlans);
        List<Payment_Plan__c> updatedPlans = paymentPlanRepo.findAllById(planIds);
        for (Payment_Plan__c row : updatedPlans) {
            System.assertEquals('Completed', row.Payment_Status__c);
        }
        
        // Test findByLoanId
        List<Payment_Plan__c> plansByLoan = paymentPlanRepo.findByLoanId(testLoan.Id);
        System.assert(plansByLoan.size() >= 3); // Should include our 3 test payment plans
        
        // Test findByStatus
        List<Payment_Plan__c> pendingPlans = paymentPlanRepo.findByStatus('Pending');
        System.assert(pendingPlans.size() >= 3); // Should include our 3 test payment plans
        
        // Test delete
        paymentPlanRepo.deleteRecord(testPaymentPlan);
        Payment_Plan__c deletedPlan = paymentPlanRepo.findById(testPaymentPlan.Id);
        System.assertEquals(null, deletedPlan);

        // Test bulk delete path
        paymentPlanRepo.deleteAll(updatedPlans);
        List<Payment_Plan__c> deletedPlans = paymentPlanRepo.findAllById(planIds);
        System.assertEquals(0, deletedPlans.size());
    }
    
    // LoanService tests removed as service has been refactored into command/query services.
}

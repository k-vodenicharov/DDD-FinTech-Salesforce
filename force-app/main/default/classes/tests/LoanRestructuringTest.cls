@isTest
public class LoanRestructuringTest {
    
    @isTest
    static void testInterestOnlyChange() {
        // Create a test loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        // Verify initial calculation
        System.assertEquals(31500, testLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');
        
        // Get initial payment plans count
        List<Payment_Plan__c> initialPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');
        
        // Update interest rate only (5% -> 7%)
        testLoan.Interest_Rate__c = 7;
        
        // This should trigger the restructuring logic
        update testLoan;
        
        // Verify the Principal_Plus_Interest__c was recalculated correctly
        Loan__c updatedLoan = [SELECT Id, Principal_Plus_Interest__c, Interest_Rate__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(7, updatedLoan.Interest_Rate__c, 'Interest rate should be updated');
        System.assertEquals(32100, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should be recalculated correctly (30000 + 30000*0.07)');
        
        // Verify payment plans were recreated
        List<Payment_Plan__c> updatedPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(3, updatedPlans.size(), 'Should still have 3 payment plans');
        
        // Verify payment amounts sum to the new total
        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(32100, totalAmount, 'Payment plan amounts should sum to new Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testTermOnlyChange() {
        // Create a test loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        // Verify initial calculation
        System.assertEquals(31500, testLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');
        
        // Get initial payment plans count
        List<Payment_Plan__c> initialPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');
        
        // Update loan term only (3 months -> 5 months)
        testLoan.Loan_Term__c = 5;
        
        // This should trigger the restructuring logic
        update testLoan;
        
        // Verify the loan term was updated
        Loan__c updatedLoan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(5, updatedLoan.Loan_Term__c, 'Loan term should be updated');
        System.assertEquals(31500, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should remain the same');
        
        // Verify payment plans were recreated
        List<Payment_Plan__c> updatedPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(5, updatedPlans.size(), 'Should now have 5 payment plans');
        
        // Verify payment amounts sum to the total
        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(31500, totalAmount, 'Payment plan amounts should sum to Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testCombinedChange() {
        // Create a test loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        // Verify initial calculation
        System.assertEquals(31500, testLoan.Principal_Plus_Interest__c, 'Initial calculation should be correct');
        
        // Get initial payment plans count
        List<Payment_Plan__c> initialPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(3, initialPlans.size(), 'Should have 3 payment plans initially');
        
        // Update both loan term and interest rate (3 months -> 4 months, 5% -> 6%)
        testLoan.Loan_Term__c = 4;
        testLoan.Interest_Rate__c = 6;
        
        // This should trigger the restructuring logic
        update testLoan;
        
        // Verify both values were updated
        Loan__c updatedLoan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, Interest_Rate__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(4, updatedLoan.Loan_Term__c, 'Loan term should be updated');
        System.assertEquals(6, updatedLoan.Interest_Rate__c, 'Interest rate should be updated');
        System.assertEquals(31800, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should be recalculated correctly (30000 + 30000*0.06)');
        
        // Verify payment plans were recreated
        List<Payment_Plan__c> updatedPlans = [SELECT Id, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(4, updatedPlans.size(), 'Should now have 4 payment plans');
        
        // Verify payment amounts sum to the new total
        Decimal totalAmount = 0;
        for (Payment_Plan__c plan : updatedPlans) {
            totalAmount += plan.Payment_Amount__c;
        }
        System.assertEquals(31800, totalAmount, 'Payment plan amounts should sum to new Principal_Plus_Interest__c');
    }
    
    @isTest
    static void testNoChange() {
        // Create a test loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 30000,
            Loan_Term__c = 3,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        // Store initial values
        Decimal initialPI = testLoan.Principal_Plus_Interest__c;
        Integer initialTerm = testLoan.Loan_Term__c.intValue();
        
        // Update with same values (no actual change)
        testLoan.Loan_Term__c = 3;
        testLoan.Interest_Rate__c = 5;
        
        // This should NOT trigger restructuring logic
        update testLoan;
        
        // Verify no changes occurred
        Loan__c updatedLoan = [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(initialTerm, updatedLoan.Loan_Term__c.intValue(), 'Loan term should remain unchanged');
        System.assertEquals(initialPI, updatedLoan.Principal_Plus_Interest__c, 'Principal plus interest should remain unchanged');
    }
}

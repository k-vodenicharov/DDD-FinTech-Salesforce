@isTest
public class LoanTests {

    // Helper method to create test loan data as JSON
    private static String generateLoanData(String loanType, Decimal loanAmount, Integer loanTerm, Decimal interestRate, String loanStatus, Id accountId) {
        Map<String, Object> loanData = new Map<String, Object>{
            'Loan_Type__c' => loanType,
            'Loan_Amount__c' => loanAmount,
            'Loan_Term__c' => loanTerm,
            'Interest_Rate__c' => interestRate,
            'Loan_Status__c' => loanStatus,
            'Account__c' => accountId
        };
        return JSON.serialize(loanData);
    }

    @IsTest
    static void testCreateLoan_Success() {
        // Setup test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        String loanData = generateLoanData('Unsecured', 10000, 12, 5, 'Pending', testAccount.Id);

        // Test the loan creation method
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoanApex(loanData);
        Test.stopTest();

        // Assert that the response indicates success
        System.assert(response.isSuccess, 'Loan creation should be successful');
        System.assertNotEquals(response.loanId, null, 'Loan ID should be populated on success');
        System.assertEquals(response.errorMessage, null, 'Error message should be null on success');
    }

    @IsTest
    static void testCreateLoan_Failure_InvalidTerm() {
        // Setup test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Test invalid term for a secured loan (term > 6 for 'Secured' loans)
        String loanData = generateLoanData('Secured', 10000, 12, 5, 'Pending', testAccount.Id);

        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoanApex(loanData);
        Test.stopTest();

        // Assert that the response indicates failure
        System.assert(!response.isSuccess, 'Loan creation should fail for invalid loan term');
        System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
        System.assert(response.errorMessage.contains('Loan term exceeds maximum allowed'), 'Error message should mention invalid loan term');
    }

    @IsTest
    static void testAdjustLoanTerm_Success() {
        // Setup initial loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 12,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        Integer newLoanTerm = 10; // Valid term adjustment for an unsecured loan

        // Test the loan term adjustment
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.adjustLoanTerm(testLoan.Id, newLoanTerm);
        Test.stopTest();

        // Assert that the response indicates success
        System.assert(response.isSuccess, 'Loan term adjustment should be successful');
        System.assertEquals(response.errorMessage, null, 'Error message should be null on success');

        // Verify the loan term was updated in the database
        Loan__c updatedLoan = [SELECT Loan_Term__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(updatedLoan.Loan_Term__c, newLoanTerm, 'Loan term should be updated to new value');
    }

    @IsTest
    static void testAdjustLoanTerm_Failure_LoanNotFound() {
        // Setup an invalid loan ID
        String invalidLoanId = 'a0Q0B00000INVALID'; // Invalid ID format for testing

        // Test the loan term adjustment with an invalid loan ID
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.adjustLoanTerm(invalidLoanId, 10);
        Test.stopTest();

        // Assert that the response indicates failure
        System.assert(!response.isSuccess, 'Loan term adjustment should fail for a nonexistent loan');
        System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
        System.assert(response.errorMessage.contains('Loan not found'), 'Error message should mention loan not found');
    }

    @IsTest
    static void testAdjustLoanTerm_Failure_InvalidTerm() {
        // Setup initial loan
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Loan__c testLoan = new Loan__c(
            Loan_Type__c = 'Secured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 6,
            Interest_Rate__c = 5,
            Loan_Status__c = 'Active',
            Account__c = testAccount.Id
        );
        insert testLoan;

        Integer invalidNewLoanTerm = 12; // Invalid term adjustment for a secured loan (term > 6)

        // Test the loan term adjustment
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.adjustLoanTerm(testLoan.Id, invalidNewLoanTerm);
        Test.stopTest();

        // Assert that the response indicates failure
        System.assert(!response.isSuccess, 'Loan term adjustment should fail for invalid loan term');
        System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
        System.assert(response.errorMessage.contains('Loan term exceeds maximum allowed'), 'Error message should mention invalid loan term');
    }
}
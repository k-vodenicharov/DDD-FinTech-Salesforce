/**
 * Unit tests for LoanController create/adjust flows.
 */
@isTest
public class LoanTests {

    /** Creates a System Administrator user for runAs tests. */
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

    /** Builds serialized loan data for controller inputs. */
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

    /** Parses JSON response payloads into a map for assertions. */
    private static Map<String, Object> parseJsonResponse(String jsonResponse) {
        return (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
    }

    /** Verifies successful loan creation with valid inputs. */
    @IsTest
    static void testCreateLoan_Success() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            String loanData = generateLoanData('Unsecured', 10000, 12, 5, 'Pending', testAccount.Id);

            Test.startTest();
            ResponseWrapper response = LoanController.createLoanApex(loanData);
            Test.stopTest();

            System.assert(response.isSuccess, 'Loan creation should be successful');
            System.assertNotEquals(response.loanId, null, 'Loan ID should be populated on success');
            System.assertEquals(response.errorMessage, null, 'Error message should be null on success');
        }
    }

    /** Verifies secured loan term validation failure. */
    @IsTest
    static void testCreateLoan_Failure_InvalidTerm() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            String loanData = generateLoanData('Secured', 10000, 12, 5, 'Pending', testAccount.Id);

            Test.startTest();
            ResponseWrapper response = LoanController.createLoanApex(loanData);
            Test.stopTest();

            System.assert(!response.isSuccess, 'Loan creation should fail for invalid loan term');
            System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
            System.assert(response.errorMessage.contains('Loan term exceeds maximum allowed'), 'Error message should mention invalid loan term');
        }
    }

    /** Verifies successful term adjustment. */
    @IsTest
    static void testAdjustLoanTerm_Success() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            Loan__c testLoan = new Loan__c(
                Loan_Type__c = 'Unsecured',
                Loan_Amount__c = 10000,
                Loan_Term__c = 12,
                Interest_Rate__c = 5,
                Loan_Status__c = 'Pending',
                Account__c = testAccount.Id
            );
            insert testLoan;

            Integer newLoanTerm = 10;

            Test.startTest();
            ResponseWrapper response = LoanController.adjustLoanTerm(testLoan.Id, newLoanTerm);
            Test.stopTest();

            System.assert(response.isSuccess, 'Loan term adjustment should be successful');
            System.assertEquals(response.errorMessage, null, 'Error message should be null on success');

            Loan__c updatedLoan = [SELECT Loan_Term__c FROM Loan__c WHERE Id = :testLoan.Id];
            System.assertEquals(newLoanTerm, updatedLoan.Loan_Term__c, 'Loan term should be updated to new value');
        }
    }

    /** Verifies adjustment fails for a missing loan. */
    @IsTest
    static void testAdjustLoanTerm_Failure_LoanNotFound() {
        User admin = createAdminUser();
        System.runAs(admin) {
            String prefix = Loan__c.SObjectType.getDescribe().getKeyPrefix();
            Id invalidLoanId = (Id) (prefix + '000000000000AAA');

            Test.startTest();
            ResponseWrapper response = LoanController.adjustLoanTerm(invalidLoanId, 10);
            Test.stopTest();

            System.assert(!response.isSuccess, 'Loan term adjustment should fail for a nonexistent loan');
            System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
            System.assert(response.errorMessage.contains('Loan not found'), 'Error message should mention loan not found');
        }
    }

    /** Verifies adjustment fails for invalid secured term. */
    @IsTest
    static void testAdjustLoanTerm_Failure_InvalidTerm() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            Loan__c testLoan = new Loan__c(
                Loan_Type__c = 'Secured',
                Loan_Amount__c = 10000,
                Loan_Term__c = 6,
                Interest_Rate__c = 5,
                Loan_Status__c = 'Pending',
                Account__c = testAccount.Id
            );
            insert testLoan;

            Integer invalidNewLoanTerm = 12;

            Test.startTest();
            ResponseWrapper response = LoanController.adjustLoanTerm(testLoan.Id, invalidNewLoanTerm);
            Test.stopTest();

            System.assert(!response.isSuccess, 'Loan term adjustment should fail for invalid loan term');
            System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
            System.assert(response.errorMessage.contains('Loan term exceeds maximum allowed'), 'Error message should mention invalid loan term');
        }
    }
    
    /** Verifies max term for unsecured loans is accepted. */
    @IsTest
    static void testCreateLoan_Unsecured_MaxTerm() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            String loanData = generateLoanData('Unsecured', 10000, 12, 5, 'Pending', testAccount.Id);

            Test.startTest();
            ResponseWrapper response = LoanController.createLoanApex(loanData);
            Test.stopTest();

            System.assert(response.isSuccess, 'Loan creation should be successful for valid unsecured term');
            System.assertNotEquals(response.loanId, null, 'Loan ID should be populated on success');
            System.assertEquals(response.errorMessage, null, 'Error message should be null on success');
        }
    }
    
    /** Verifies term validation for unsecured loans. */
    @IsTest
    static void testCreateLoan_Unsecured_InvalidTerm() {
        User admin = createAdminUser();
        System.runAs(admin) {
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;

            String loanData = generateLoanData('Unsecured', 10000, 13, 5, 'Pending', testAccount.Id);

            Test.startTest();
            ResponseWrapper response = LoanController.createLoanApex(loanData);
            Test.stopTest();

            System.assert(!response.isSuccess, 'Loan creation should fail for invalid unsecured term');
            System.assertEquals(response.loanId, null, 'Loan ID should be null on failure');
            System.assert(response.errorMessage.contains('Loan term exceeds maximum allowed'), 'Error message should mention invalid loan term');
        }
    }
    
}

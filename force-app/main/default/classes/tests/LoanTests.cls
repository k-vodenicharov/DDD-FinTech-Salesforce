@isTest
public class LoanTests {

    @isTest
    static void testCreateLoanSuccess() {
        // Test data
        String loanDataJson = JSON.serialize(new Map<String, Object>{
            'Loan_Type__c' => 'Secured',
            'Loan_Amount__c' => 10000,
            'Loan_Term__c' => 6,
            'Interest_Rate__c' => 5,
            'Loan_Status__c' => 'Approved',
            'Account__c' => '001Qy00000ScY0YIAV'
        });
        
        // Call the method to test
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoan(loanDataJson);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, response);
        System.assertEquals(true, response.isSuccess);
        System.assertNotEquals(null, response.loanId);
        
        // Optionally, verify that the Loan__c record was created
        Loan__c createdLoan = [SELECT Id, Loan_Type__c, Loan_Amount__c FROM Loan__c WHERE Id = :response.loanId];
        System.assertEquals('Secured', createdLoan.Loan_Type__c);
        System.assertEquals(10000, createdLoan.Loan_Amount__c);
    }

    @isTest
    static void testCreateLoanWithMissingRequiredFields() {
        // Missing required fields
        String loanDataJson = JSON.serialize(new Map<String, Object>{
            'Loan_Type__c' => 'Secured',
            'Loan_Amount__c' => null, // Missing loan amount
            'Loan_Term__c' => 6,
            'Interest_Rate__c' => 5,
            'Loan_Status__c' => 'Approved',
            'Account__c' => '001Qy00000ScY0YIAV'
        });

        // Call the method to test
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoan(loanDataJson);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isSuccess);
        System.assertEquals('Missing required fields.', response.errorMessage);
    }

    @isTest
    static void testCreateLoanExceedsMaxLoanTerm() {
        // Loan term exceeds maximum allowed for Secured loans
        String loanDataJson = JSON.serialize(new Map<String, Object>{
            'Loan_Type__c' => 'Secured',
            'Loan_Amount__c' => 10000,
            'Loan_Term__c' => 7, // Exceeds max
            'Interest_Rate__c' => 5,
            'Loan_Status__c' => 'Approved',
            'Account__c' => '001Qy00000ScY0YIAV'
        });

        // Call the method to test
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoan(loanDataJson);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isSuccess);
        System.assertEquals('Loan term exceeds maximum allowed value for Secured loans (6 months).', response.errorMessage);
    }

    @isTest
    static void testQueueableJobExecution() {
        // Test for successful creation and processing of queueable jobs
        String loanDataJson = JSON.serialize(new Map<String, Object>{
            'Loan_Type__c' => 'Unsecured',
            'Loan_Amount__c' => 20000,
            'Loan_Term__c' => 12,
            'Interest_Rate__c' => 6,
            'Loan_Status__c' => 'Approved',
            'Account__c' => '001Qy00000ScY0YIAV'
        });

        // Create loan and queue job
        Test.startTest();
        LoanController.ResponseWrapper response = LoanController.createLoan(loanDataJson);
        Test.stopTest();

        // Execute the queued jobs
        Test.startTest();
        System.enqueueJob(new PaymentPlanQueueable(response.loanId));
        Test.stopTest();

        // Verify payment plans were created
        List<Payment_Plan__c> paymentPlans = [SELECT Id, Loan__c, Payment_Amount__c FROM Payment_Plan__c WHERE Loan__c = :response.loanId];
        System.assertEquals(12, paymentPlans.size());
        System.assertEquals(1800, paymentPlans[0].Payment_Amount__c); // Total amount divided by term
    }
}
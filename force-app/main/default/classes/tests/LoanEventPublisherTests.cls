/**
 * Unit tests for LoanEventPublisher.
 */
@IsTest
private class LoanEventPublisherTests {
    @IsTest
    static void testPublishStatusChanges() {
        Account acc = new Account(Name = 'Event Account');
        insert acc;

        Loan__c loan = new Loan__c(
            Name = 'Loan Unsecured - 1000',
            Loan_Type__c = 'Unsecured',
            Loan_Amount__c = 1000,
            Loan_Term__c = 1,
            Interest_Rate__c = 0,
            Principal_Plus_Interest__c = 1000,
            Loan_Status__c = 'Pending',
            Account__c = acc.Id
        );
        insert loan;

        List<Database.SaveResult> results;
        Test.startTest();
        results = LoanEventPublisher.publishStatusChanges(new List<Loan__c>{
            new Loan__c(Id = loan.Id, Loan_Status__c = 'Closed')
        });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one platform event publish result');
        System.assertEquals(true, results[0].isSuccess(), 'Platform event publish should succeed');
    }
}

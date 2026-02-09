/**
 * Query helper for Loan__c reads.
 */
public with sharing class LoanSelector {
    /** Returns a loan by Id with fields needed for UI and services. */
    public static Loan__c getLoanById(Id loanId) {
        return [SELECT Id, Name, Loan_Type__c, Loan_Amount__c, Loan_Term__c, Interest_Rate__c,
                       Principal_Plus_Interest__c, Loan_Status__c, Account__c, CreatedDate
                FROM Loan__c WHERE Id = :loanId WITH SECURITY_ENFORCED LIMIT 1];
    }

    /** Returns loans for a given account ordered by most recent. */
    public static List<Loan__c> getLoansByAccountId(Id accountId) {
        return [SELECT Id, Name, Loan_Type__c, Loan_Amount__c, Loan_Term__c, Interest_Rate__c,
                       Principal_Plus_Interest__c, Loan_Status__c, Account__c, CreatedDate
                FROM Loan__c WHERE Account__c = :accountId WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC];
    }
}

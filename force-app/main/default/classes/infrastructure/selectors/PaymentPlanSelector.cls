/**
 * Query helper for Payment_Plan__c reads.
 */
public with sharing class PaymentPlanSelector {
    /** Returns payment plans for a given loan. */
    public static List<Payment_Plan__c> getPaymentPlansByLoanId(Id loanId) {
        return [SELECT Id, Name, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, Loan__c, BYPASS__c
                FROM Payment_Plan__c WHERE Loan__c = :loanId WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
    }

    /** Returns payment plans for multiple loans. */
    public static List<Payment_Plan__c> getPaymentPlansByLoanIds(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Payment_Plan__c>();
        return [SELECT Id, Name, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, Loan__c, BYPASS__c
                FROM Payment_Plan__c WHERE Loan__c IN :loanIds WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
    }

    /** Returns payment plans filtered by status. */
    public static List<Payment_Plan__c> getPaymentPlansByStatus(String status) {
        return [SELECT Id, Name, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, Loan__c, BYPASS__c
                FROM Payment_Plan__c WHERE Payment_Status__c = :status WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
    }
}

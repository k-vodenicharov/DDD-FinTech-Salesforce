/**
 * Generic response wrapper for UI and REST calls.
 */
global class ResponseWrapper {
    @AuraEnabled
    global Boolean isSuccess;
    @AuraEnabled
    global String errorMessage;
    @AuraEnabled
    global String loanId;
    @AuraEnabled
    global Decimal remainingBalance;
    @AuraEnabled
    global String jobId;
}

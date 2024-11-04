public class ResponseWrapper {
    @AuraEnabled
    public Boolean isSuccess;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public String loanId;
}
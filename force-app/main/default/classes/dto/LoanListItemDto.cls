public class LoanListItemDto {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String status;
    @AuraEnabled public Decimal amount;
    @AuraEnabled public Decimal term;
    @AuraEnabled public Decimal rate;
    @AuraEnabled public Datetime created;
}

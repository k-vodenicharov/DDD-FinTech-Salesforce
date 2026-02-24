public class LoanDocumentAuditItemDto {
    @AuraEnabled public String action;
    @AuraEnabled public String actionLabel;
    @AuraEnabled public String documentType;
    @AuraEnabled public String fromStatus;
    @AuraEnabled public String toStatus;
    @AuraEnabled public Datetime actionOn;
    @AuraEnabled public String actorName;
    @AuraEnabled public String details;
    @AuraEnabled public String summary;
}

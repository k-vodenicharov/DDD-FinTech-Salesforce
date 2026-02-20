/**
 * Aura-enabled controller for loan document upload tracking.
 */
public with sharing class LoanDocumentController {
    private static Boolean cachedIsAdmin;
    @AuraEnabled(cacheable=true)
    public static List<String> getRequiredDocumentTypes(Id loanId) {
        LoanDocumentQueryService queryService = new LoanDocumentQueryService();
        return queryService.getRequiredDocumentTypesForLoan(loanId);
    }

    @AuraEnabled
    public static LoanDocumentQueryService.LoanDocumentPanelDto getPanelData(Id loanId) {
        LoanDocumentQueryService queryService = new LoanDocumentQueryService();
        return queryService.getPanelData(loanId);
    }

    @AuraEnabled
    public static ResponseWrapper assignDocumentType(Id loanId, List<Id> contentDocumentIds, String documentType) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.assignDocumentType(
                loanId,
                contentDocumentIds == null ? new Set<Id>() : new Set<Id>(contentDocumentIds),
                documentType
            );
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled
    public static ResponseWrapper approveDocument(Id loanDocumentId, String comments) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            if (!canReviewActions()) {
                throw new AuraHandledException('You do not have access to review actions.');
            }
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.approveDocument(loanDocumentId, comments);
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled
    public static ResponseWrapper rejectDocument(Id loanDocumentId, String rejectionReason, String comments) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            if (!canReviewActions()) {
                throw new AuraHandledException('You do not have access to review actions.');
            }
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.rejectDocument(loanDocumentId, rejectionReason, comments);
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled
    public static ResponseWrapper requestClarification(Id loanDocumentId, String clarificationReason) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            if (!canReviewActions()) {
                throw new AuraHandledException('You do not have access to review actions.');
            }
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.requestClarification(loanDocumentId, clarificationReason);
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled
    public static ResponseWrapper updateDocumentScanStatus(Id loanDocumentId, String scanStatus, String scanReference) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            if (!canReviewActions()) {
                throw new AuraHandledException('You do not have access to scan update actions.');
            }
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.updateDocumentScanStatus(loanDocumentId, scanStatus, scanReference);
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled
    public static ResponseWrapper updateDocumentAuthenticity(
        Id loanDocumentId,
        String authenticityStatus,
        Decimal authenticityScore,
        String authenticityReference
    ) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            if (!canReviewActions()) {
                throw new AuraHandledException('You do not have access to authenticity update actions.');
            }
            LoanDocumentCommandService commandService = new LoanDocumentCommandService();
            commandService.updateDocumentAuthenticity(
                loanDocumentId,
                authenticityStatus,
                authenticityScore,
                authenticityReference
            );
            response.isSuccess = true;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    private static Boolean canReviewActions() {
        return FeatureManagement.checkPermission('Loan_Document_Ops') || isCurrentUserAdmin();
    }

    private static Boolean isCurrentUserAdmin() {
        if (cachedIsAdmin != null) return cachedIsAdmin;
        List<Profile> rows = [
            SELECT PermissionsModifyAllData
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];
        cachedIsAdmin = !rows.isEmpty() && rows[0].PermissionsModifyAllData;
        return cachedIsAdmin;
    }
}

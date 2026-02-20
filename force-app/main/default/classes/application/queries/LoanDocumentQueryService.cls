/**
 * Query-side service for loan document panel read models.
 */
public with sharing class LoanDocumentQueryService {
    private final LoanDocumentationDomain domain;

    public LoanDocumentQueryService() {
        this.domain = new LoanDocumentationDomain();
    }

    public class RequirementItem {
        @AuraEnabled public Id loanDocumentId;
        @AuraEnabled public String documentType;
        @AuraEnabled public String status;
        @AuraEnabled public String scanStatus;
        @AuraEnabled public String authenticityStatus;
        @AuraEnabled public Decimal authenticityScore;
        @AuraEnabled public String authenticityReference;
        @AuraEnabled public Datetime authenticityCheckedOn;
        @AuraEnabled public String approvalGateState;
        @AuraEnabled public String approvalGateLabel;
        @AuraEnabled public Boolean approvalAllowed;
        @AuraEnabled public String scanReference;
        @AuraEnabled public Datetime scannedOn;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public String opsComments;
        @AuraEnabled public Datetime reviewedOn;
        @AuraEnabled public Date dueOn;
        @AuraEnabled public String slaState;
        @AuraEnabled public Datetime lastUploadOn;
        @AuraEnabled public String uploadedByName;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public String allowedMimeTypes;
        @AuraEnabled public Decimal maxSizeMb;
    }

    public class LoanDocumentPanelDto {
        @AuraEnabled public List<RequirementItem> requiredChecklist;
        @AuraEnabled public List<RequirementItem> uploadedDocuments;
        @AuraEnabled public List<AuditItem> activityTimeline;
        @AuraEnabled public List<String> missingTypes;
        @AuraEnabled public List<String> availableDocumentTypes;
        @AuraEnabled public Integer progressPercent;
        @AuraEnabled public Integer requiredTotal;
        @AuraEnabled public Integer requiredApproved;
        @AuraEnabled public Boolean isOps;
        @AuraEnabled public Boolean isAdmin;
        @AuraEnabled public Boolean canReviewActions;
        @AuraEnabled public Boolean canSeeAuditTrail;
        @AuraEnabled public Boolean canSeeInternalScanDetails;
        @AuraEnabled public Boolean hasOverdue;
        @AuraEnabled public Id openTaskId;
        @AuraEnabled public Integer opsWorkloadPendingReview;
        @AuraEnabled public Integer opsWorkloadNeedsClarification;
        @AuraEnabled public Integer opsWorkloadRejected;
        @AuraEnabled public Integer opsWorkloadBlockedByScan;
        @AuraEnabled public String opsOldestPendingDocumentType;
        @AuraEnabled public Datetime opsOldestPendingUploadedOn;
        @AuraEnabled public Integer opsOldestPendingAgeDays;
    }

    public class AuditItem {
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

    public List<String> getRequiredDocumentTypesForLoan(Id loanId) {
        LoanDocumentPanelDto dto = getPanelData(loanId);
        List<String> types = new List<String>();
        Set<String> seen = new Set<String>();
        for (RequirementItem row : dto.requiredChecklist) {
            if (String.isBlank(row.documentType)) continue;
            String normalized = domain.normalize(row.documentType);
            if (seen.contains(normalized)) continue;
            seen.add(normalized);
            types.add(row.documentType);
        }
        types.sort();
        return types;
    }

    public LoanDocumentPanelDto getPanelData(Id loanId) {
        LoanDocumentPanelDto dto = new LoanDocumentPanelDto();
        dto.requiredChecklist = new List<RequirementItem>();
        dto.uploadedDocuments = new List<RequirementItem>();
        dto.activityTimeline = new List<AuditItem>();
        dto.missingTypes = new List<String>();
        dto.availableDocumentTypes = new List<String>();
        dto.progressPercent = 0;
        dto.requiredTotal = 0;
        dto.requiredApproved = 0;
        dto.isAdmin = isCurrentUserAdmin();
        dto.isOps = FeatureManagement.checkPermission('Loan_Document_Ops') || dto.isAdmin;
        dto.canReviewActions = dto.isOps;
        dto.canSeeAuditTrail = dto.isOps;
        dto.canSeeInternalScanDetails = dto.isOps;
        dto.hasOverdue = false;
        dto.openTaskId = null;
        dto.opsWorkloadPendingReview = 0;
        dto.opsWorkloadNeedsClarification = 0;
        dto.opsWorkloadRejected = 0;
        dto.opsWorkloadBlockedByScan = 0;
        dto.opsOldestPendingDocumentType = null;
        dto.opsOldestPendingUploadedOn = null;
        dto.opsOldestPendingAgeDays = null;
        if (loanId == null) return dto;

        List<Loan__c> loans = LoanDocumentSelector.getLoansByIds(new Set<Id>{loanId});
        if (loans.isEmpty()) return dto;
        Loan__c loan = loans[0];

        List<Loan_Document_Requirement__mdt> rawRules = LoanDocumentSelector.getRequirementRules();
        List<LoanDocumentationDomain.RequirementRule> rules = mapRules(rawRules);
        LoanDocumentationDomain.LoanFacts facts = new LoanDocumentationDomain.LoanFacts();
        facts.loanId = loan.Id;
        facts.loanType = loan.Loan_Type__c;
        facts.loanStatus = loan.Loan_Status__c;
        facts.amount = loan.Loan_Amount__c;
        facts.createdDate = loan.CreatedDate == null ? Date.today() : loan.CreatedDate.date();
        Map<String, LoanDocumentationDomain.RequirementOutcome> effective = domain.resolveEffectiveRequirements(facts, rules);

        List<Loan_Document__c> latestDocs = LoanDocumentSelector.getLatestByLoanIds(new Set<Id>{loanId});
        Map<String, Loan_Document__c> latestByType = new Map<String, Loan_Document__c>();
        Set<Id> uploaderIds = new Set<Id>();
        Set<Id> contentIds = new Set<Id>();
        Map<String, String> latestStatusByType = new Map<String, String>();
        for (Loan_Document__c row : latestDocs) {
            String key = domain.normalize(row.Document_Type__c);
            if (key == null) continue;
            latestByType.put(key, row);
            if (row.Uploaded_By__c != null) uploaderIds.add(row.Uploaded_By__c);
            Id contentId = parseContentDocumentId(row.Content_Document_Id__c);
            if (contentId != null) contentIds.add(contentId);
        }

        Set<Id> linkedContentIds = LoanDocumentSelector.getLinkedDocumentIds(loanId, contentIds);
        Map<Id, LoanDocumentSelector.ContentFileInfo> contentInfoMap = LoanDocumentSelector.getContentFileInfo(linkedContentIds);
        for (Loan_Document__c row : latestDocs) {
            String key = domain.normalize(row.Document_Type__c);
            if (key == null) continue;
            Id contentId = parseContentDocumentId(row.Content_Document_Id__c);
            Boolean hasLinkedFile = contentId != null && linkedContentIds.contains(contentId);
            latestStatusByType.put(key, effectiveStatus(row.Status__c, hasLinkedFile));
        }

        Map<Id, String> uploaderNames = new Map<Id, String>();
        if (!uploaderIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :uploaderIds]) {
                uploaderNames.put(u.Id, u.Name);
            }
        }

        for (LoanDocumentationDomain.RequirementOutcome outcome : effective.values()) {
            RequirementItem item = new RequirementItem();
            item.documentType = outcome.documentType;
            item.isRequired = outcome.isRequired;
            dto.availableDocumentTypes.add(outcome.documentType);
            Loan_Document__c row = latestByType.get(domain.normalize(outcome.documentType));
            if (row != null) {
                hydrateFromRecord(item, row, uploaderNames, contentInfoMap, linkedContentIds, dto.canSeeInternalScanDetails);
            } else {
                item.status = outcome.isRequired ? 'Required' : 'Optional';
                item.dueOn = outcome.dueOn;
                item.slaState = domain.computeSlaState(item.dueOn, Date.today(), 0);
                applyApprovalGate(item, false);
            }
            item.allowedMimeTypes = outcome.allowedMimeTypes;
            item.maxSizeMb = outcome.maxSizeMb;
            if (item.slaState == 'Overdue' || item.slaState == 'Escalated') dto.hasOverdue = true;
            if (item.isRequired) dto.requiredChecklist.add(item);
        }

        for (Loan_Document__c row : latestDocs) {
            RequirementItem item = new RequirementItem();
            hydrateFromRecord(item, row, uploaderNames, contentInfoMap, linkedContentIds, dto.canSeeInternalScanDetails);
            item.isRequired = effective.containsKey(domain.normalize(row.Document_Type__c))
                ? effective.get(domain.normalize(row.Document_Type__c)).isRequired
                : false;
            LoanDocumentationDomain.RequirementOutcome rowOutcome = effective.get(domain.normalize(row.Document_Type__c));
            item.allowedMimeTypes = rowOutcome == null ? null : rowOutcome.allowedMimeTypes;
            item.maxSizeMb = rowOutcome == null ? null : rowOutcome.maxSizeMb;
            if (item.contentDocumentId != null) {
                dto.uploadedDocuments.add(item);
            }
        }

        dto.availableDocumentTypes.sort();
        dto.missingTypes = domain.computeMissingRequired(effective, latestStatusByType);
        for (RequirementItem req : dto.requiredChecklist) {
            dto.requiredTotal++;
            if (domain.normalize(req.status) == 'approved') dto.requiredApproved++;
        }
        dto.progressPercent = dto.requiredTotal == 0 ? 100 :
            Integer.valueOf(Math.floor((Decimal.valueOf(dto.requiredApproved) / Decimal.valueOf(dto.requiredTotal)) * 100));

        for (Loan_Document_Audit__c row : LoanDocumentSelector.getAuditByLoanId(loanId, 15)) {
            AuditItem item = new AuditItem();
            item.action = row.Action__c;
            item.actionLabel = toActionLabel(row.Action__c);
            item.documentType = row.Loan_Document__r == null ? null : row.Loan_Document__r.Document_Type__c;
            item.fromStatus = toStatusLabel(row.Prior_Status__c);
            item.toStatus = toStatusLabel(row.New_Status__c);
            item.actionOn = row.Action_On__c;
            item.actorName = row.Actor__r == null ? null : row.Actor__r.Name;
            item.details = row.Details__c;
            item.summary = buildAuditSummary(item);
            if (shouldIncludeAuditItem(item, dto.canSeeAuditTrail)) {
                if (!dto.canSeeAuditTrail) {
                    item.actorName = null;
                    item.details = sanitizeBorrowerAuditDetails(item);
                    item.summary = buildAuditSummary(item);
                }
                dto.activityTimeline.add(item);
            }
        }

        List<Task> openTasks = LoanDocumentSelector.getOpenMissingDocTasks(new Set<Id>{ loanId });
        if (!openTasks.isEmpty()) {
            dto.openTaskId = openTasks[0].Id;
        }

        if (dto.isOps) {
            applyOpsWorkloadStats(dto);
        }
        return dto;
    }

    private void applyOpsWorkloadStats(LoanDocumentPanelDto dto) {
        if (dto == null) return;

        for (AggregateResult row : LoanDocumentSelector.getOpsWorkloadByStatus()) {
            String statusValue = String.valueOf(row.get('statusValue'));
            Integer totalCount = Integer.valueOf(String.valueOf(row.get('totalCount')));
            String normalized = domain.normalize(statusValue);
            if (normalized == 'under_review') dto.opsWorkloadPendingReview = totalCount;
            if (normalized == 'needs_clarification') dto.opsWorkloadNeedsClarification = totalCount;
            if (normalized == 'rejected') dto.opsWorkloadRejected = totalCount;
        }
        dto.opsWorkloadBlockedByScan = LoanDocumentSelector.getBlockedByScanCount();

        List<Loan_Document__c> oldest = LoanDocumentSelector.getOldestPendingLatest(1);
        if (!oldest.isEmpty()) {
            Loan_Document__c row = oldest[0];
            Datetime uploadedOn = row.Uploaded_On__c == null ? row.CreatedDate : row.Uploaded_On__c;
            dto.opsOldestPendingDocumentType = row.Document_Type__c;
            dto.opsOldestPendingUploadedOn = uploadedOn;
            dto.opsOldestPendingAgeDays = uploadedOn == null
                ? null
                : Math.max(0, uploadedOn.date().daysBetween(Date.today()));
        }
    }

    private String toActionLabel(String action) {
        String normalized = domain.normalize(action);
        if (normalized == 'uploaded') return 'Uploaded';
        if (normalized == 'replaced') return 'Replaced';
        if (normalized == 'approved') return 'Approved';
        if (normalized == 'rejected') return 'Rejected';
        if (normalized == 'clarification_requested') return 'Clarification Requested';
        if (normalized == 'validation_failed') return 'Validation Failed';
        if (normalized == 'scan_updated') return 'Scan Updated';
        if (normalized == 'authenticity_updated') return 'Authenticity Updated';
        if (normalized == 'alert_sent') return 'Alert Sent';
        return toStatusLabel(action);
    }

    private String buildAuditSummary(AuditItem item) {
        List<String> parts = new List<String>();
        if (!String.isBlank(item.documentType)) parts.add(item.documentType);
        if (!String.isBlank(item.fromStatus) || !String.isBlank(item.toStatus)) {
            String transition = '';
            if (!String.isBlank(item.fromStatus) && !String.isBlank(item.toStatus)) {
                transition = item.fromStatus + ' -> ' + item.toStatus;
            } else if (!String.isBlank(item.toStatus)) {
                transition = item.toStatus;
            } else {
                transition = item.fromStatus;
            }
            parts.add(transition);
        }
        if (!String.isBlank(item.details)) parts.add(item.details);
        return parts.isEmpty() ? null : String.join(parts, ' | ');
    }

    private String toStatusLabel(String value) {
        if (String.isBlank(value)) return null;
        String text = value.replace('_', ' ').trim().toLowerCase();
        List<String> words = text.split('\\s+');
        for (Integer i = 0; i < words.size(); i++) {
            String w = words[i];
            if (String.isBlank(w)) continue;
            words[i] = w.left(1).toUpperCase() + (w.length() > 1 ? w.substring(1) : '');
        }
        return String.join(words, ' ');
    }

    private void hydrateFromRecord(
        RequirementItem item,
        Loan_Document__c row,
        Map<Id, String> uploaderNames,
        Map<Id, LoanDocumentSelector.ContentFileInfo> contentInfoMap,
        Set<Id> linkedContentIds,
        Boolean canSeeInternalScanDetails
    ) {
        item.loanDocumentId = row.Id;
        item.documentType = row.Document_Type__c;
        Id contentId = parseContentDocumentId(row.Content_Document_Id__c);
        Boolean hasLinkedFile = contentId != null && linkedContentIds != null && linkedContentIds.contains(contentId);
        item.status = effectiveStatus(row.Status__c, hasLinkedFile);
        item.scanStatus = row.Scan_Status__c;
        item.authenticityStatus = row.Authenticity_Status__c;
        item.authenticityScore = row.Authenticity_Score__c;
        item.authenticityReference = row.Authenticity_Reference__c;
        item.authenticityCheckedOn = row.Authenticity_Checked_On__c;
        item.scanReference = row.Scan_Reference__c;
        item.scannedOn = row.Scanned_On__c;
        item.rejectionReason = row.Rejection_Reason__c;
        item.opsComments = row.Ops_Comments__c;
        item.reviewedOn = row.Reviewed_On__c;
        item.dueOn = row.Due_On__c;
        item.slaState = row.SLA_State__c;
        item.lastUploadOn = row.Uploaded_On__c;
        item.uploadedByName = row.Uploaded_By__c == null ? null : uploaderNames.get(row.Uploaded_By__c);
        if (hasLinkedFile && contentInfoMap != null && contentInfoMap.containsKey(contentId)) {
            item.contentDocumentId = contentId;
            LoanDocumentSelector.ContentFileInfo info = contentInfoMap.get(contentId);
            item.fileName = info == null ? null : info.displayName;
            item.fileExtension = info == null ? null : info.fileExtension;
        }
        applyApprovalGate(item, hasLinkedFile);
        if (!canSeeInternalScanDetails) {
            item.scanStatus = null;
            item.scanReference = null;
            item.scannedOn = null;
            item.authenticityStatus = null;
            item.authenticityScore = null;
            item.authenticityReference = null;
            item.authenticityCheckedOn = null;
        }
    }

    private Id parseContentDocumentId(String value) {
        if (String.isBlank(value)) return null;
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    private String effectiveStatus(String originalStatus, Boolean hasLinkedFile) {
        if (hasLinkedFile == true) return originalStatus;
        return 'Required';
    }

    private void applyApprovalGate(RequirementItem item, Boolean hasLinkedFile) {
        String normalizedStatus = domain.normalize(item == null ? null : item.status);
        String normalizedScan = domain.normalize(item == null ? null : item.scanStatus);
        String normalizedAuthenticity = domain.normalize(item == null ? null : item.authenticityStatus);

        if (item == null) return;

        if (hasLinkedFile != true) {
            item.approvalGateState = 'missing_upload';
            item.approvalGateLabel = 'Upload Required';
            item.approvalAllowed = false;
            return;
        }

        if (normalizedStatus == 'approved') {
            item.approvalGateState = 'complete';
            item.approvalGateLabel = 'Already Approved';
            item.approvalAllowed = false;
            return;
        }

        if (normalizedScan == 'clean') {
            if (normalizedAuthenticity == 'verified') {
                item.approvalGateState = 'ready';
                item.approvalGateLabel = 'Ready For Approval';
                item.approvalAllowed = true;
                return;
            }
            if (normalizedAuthenticity == 'needs_review' || normalizedAuthenticity == 'pending' || String.isBlank(normalizedAuthenticity)) {
                item.approvalGateState = 'pending_authenticity';
                item.approvalGateLabel = 'Waiting For Authenticity';
                item.approvalAllowed = false;
                return;
            }
            if (normalizedAuthenticity == 'suspected_fraud') {
                item.approvalGateState = 'blocked_authenticity';
                item.approvalGateLabel = 'Blocked By Authenticity';
                item.approvalAllowed = false;
                return;
            }
            item.approvalGateState = 'pending_authenticity';
            item.approvalGateLabel = 'Waiting For Authenticity';
            item.approvalAllowed = false;
            return;
        }

        if (normalizedScan == 'infected' || normalizedScan == 'failed') {
            item.approvalGateState = 'blocked';
            item.approvalGateLabel = 'Blocked By Scan';
            item.approvalAllowed = false;
            return;
        }

        item.approvalGateState = 'pending_scan';
        item.approvalGateLabel = 'Waiting For Scan';
        item.approvalAllowed = false;
    }

    private List<LoanDocumentationDomain.RequirementRule> mapRules(List<Loan_Document_Requirement__mdt> rows) {
        List<LoanDocumentationDomain.RequirementRule> rules = new List<LoanDocumentationDomain.RequirementRule>();
        for (Loan_Document_Requirement__mdt row : rows) {
            LoanDocumentationDomain.RequirementRule rule = new LoanDocumentationDomain.RequirementRule();
            rule.documentType = row.Document_Type__c;
            rule.isRequired = row.Is_Required__c;
            rule.appliesToLoanType = row.Applies_To_Loan_Type__c;
            rule.minAmount = row.Min_Amount__c;
            rule.maxAmount = row.Max_Amount__c;
            rule.loanStatus = row.Loan_Status__c;
            rule.dueDaysFromCreated = row.Due_Days_From_Created__c == null ? null : Integer.valueOf(row.Due_Days_From_Created__c);
            rule.allowedMimeTypes = row.Allowed_Mime_Types__c;
            rule.maxSizeMb = row.Max_Size_MB__c;
            rules.add(rule);
        }
        return rules;
    }

    private Boolean isCurrentUserAdmin() {
        List<Profile> rows = [
            SELECT PermissionsModifyAllData
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ];
        return !rows.isEmpty() && rows[0].PermissionsModifyAllData;
    }

    private Boolean shouldIncludeAuditItem(AuditItem item, Boolean canSeeAuditTrail) {
        if (canSeeAuditTrail) return true;
        String action = domain.normalize(item == null ? null : item.action);
        return action == 'uploaded'
            || action == 'replaced'
            || action == 'clarification_requested'
            || action == 'approved'
            || action == 'rejected';
    }

    private String sanitizeBorrowerAuditDetails(AuditItem item) {
        String action = domain.normalize(item == null ? null : item.action);
        if (action == 'clarification_requested' || action == 'rejected') {
            return item.details;
        }
        return null;
    }
}

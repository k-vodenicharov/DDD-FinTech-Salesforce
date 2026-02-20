/**
 * Command-side service for loan document lifecycle mutations.
 */
public with sharing class LoanDocumentCommandService {
    private static final String SCAN_STATUS_PENDING = 'Pending';
    private static final String SCAN_STATUS_CLEAN = 'Clean';
    private static final String AUTH_STATUS_PENDING = 'Pending';
    private static final String AUTH_STATUS_VERIFIED = 'Verified';
    private final LoanDocumentationDomain domain;
    private final ILoanDocumentRepository repository;
    private static Boolean cachedIsAdmin;

    public LoanDocumentCommandService() {
        this.domain = new LoanDocumentationDomain();
        this.repository = new LoanDocumentRepository();
    }

    public Integer assignDocumentType(Id loanId, Set<Id> contentDocumentIds, String documentType) {
        if (loanId == null) throw new LoanDocumentException('Loan Id is required.');
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) throw new LoanDocumentException('At least one file is required.');
        if (String.isBlank(documentType)) throw new LoanDocumentException('Document type is required.');

        Set<Id> linkedDocumentIds = LoanDocumentSelector.getLinkedDocumentIds(loanId, contentDocumentIds);
        if (linkedDocumentIds.isEmpty()) throw new LoanDocumentException('No uploaded files are linked to the selected loan.');

        List<ContentVersion> latestVersions = LoanDocumentSelector.getLatestVersions(linkedDocumentIds);
        LoanDocumentationDomain.RequirementOutcome effectiveRule = getEffectiveRequirementForLoan(loanId, documentType);
        if (effectiveRule == null) {
            throw new LoanDocumentException(
                'Upload policy is not configured for document type "' + documentType +
                '". Contact admin to configure Loan_Document_Requirement metadata.'
            );
        }
        validateFilePolicy(latestVersions, effectiveRule, documentType, loanId);

        for (ContentVersion versionRecord : latestVersions) {
            versionRecord.Document_Type__c = documentType;
        }
        List<SObject> sobs = new List<SObject>();
        sobs.addAll(latestVersions);
        List<SObject> sanitized = SecurityUtil.stripUpdate(sobs);
        if (sanitized.isEmpty()) throw new LoanDocumentException('Insufficient access to update document metadata.');
        update sanitized;

        syncFromContentDocumentLinksByDocuments(loanId, linkedDocumentIds);
        return sanitized.size();
    }

    public void syncFromContentDocumentLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) return;
        Set<Id> loanIds = new Set<Id>();
        Set<Id> contentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (link == null) continue;
            if (link.LinkedEntityId != null && link.LinkedEntityId.getSObjectType() == Loan__c.SObjectType) {
                loanIds.add(link.LinkedEntityId);
                contentIds.add(link.ContentDocumentId);
            }
        }
        if (loanIds.isEmpty() || contentIds.isEmpty()) return;
        syncCore(loanIds, contentIds);
    }

    public void syncFromContentDocumentLinksByDocuments(Id loanId, Set<Id> contentDocumentIds) {
        if (loanId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) return;
        syncCore(new Set<Id>{loanId}, contentDocumentIds);
    }

    public void approveDocument(Id loanDocumentId, String comments) {
        ensureCanReview();
        Loan_Document__c doc = getDocById(loanDocumentId);
        if (doc == null) throw new LoanDocumentException('Loan document not found.');
        validateReviewable(doc);
        validateApprovalGateReady(doc);

        Loan_Document__c updateRow = new Loan_Document__c(
            Id = doc.Id,
            Status__c = 'Approved',
            Reviewed_By__c = UserInfo.getUserId(),
            Reviewed_On__c = System.now(),
            Rejection_Reason__c = null,
            Ops_Comments__c = comments
        );
        applySla(updateRow, doc.Due_On__c, doc.Alert_Level__c == null ? null : Integer.valueOf(doc.Alert_Level__c));
        repository.save(updateRow);

        repository.saveAudit(new Loan_Document_Audit__c(
            Loan__c = doc.Loan__c,
            Loan_Document__c = doc.Id,
            Action__c = 'Approved',
            Actor__c = UserInfo.getUserId(),
            Action_On__c = System.now(),
            Prior_Status__c = doc.Status__c,
            New_Status__c = 'Approved',
            Content_Document_Id__c = doc.Content_Document_Id__c,
            Details__c = String.isBlank(comments) ? 'Approved in ops review.' : comments
        ));

        refreshCaseSummaries(new Set<Id>{doc.Loan__c});
    }

    public void rejectDocument(Id loanDocumentId, String rejectionReason, String comments) {
        ensureCanReview();
        if (String.isBlank(rejectionReason)) {
            throw new LoanDocumentException('Rejection reason is required.');
        }
        Loan_Document__c doc = getDocById(loanDocumentId);
        if (doc == null) throw new LoanDocumentException('Loan document not found.');
        validateReviewable(doc);

        Loan_Document__c updateRow = new Loan_Document__c(
            Id = doc.Id,
            Status__c = 'Rejected',
            Reviewed_By__c = UserInfo.getUserId(),
            Reviewed_On__c = System.now(),
            Rejection_Reason__c = rejectionReason,
            Ops_Comments__c = comments
        );
        applySla(updateRow, doc.Due_On__c, doc.Alert_Level__c == null ? null : Integer.valueOf(doc.Alert_Level__c));
        repository.save(updateRow);

        repository.saveAudit(new Loan_Document_Audit__c(
            Loan__c = doc.Loan__c,
            Loan_Document__c = doc.Id,
            Action__c = 'Rejected',
            Actor__c = UserInfo.getUserId(),
            Action_On__c = System.now(),
            Prior_Status__c = doc.Status__c,
            New_Status__c = 'Rejected',
            Content_Document_Id__c = doc.Content_Document_Id__c,
            Details__c = rejectionReason + (String.isBlank(comments) ? '' : ' | ' + comments)
        ));

        refreshCaseSummaries(new Set<Id>{doc.Loan__c});
    }

    public void requestClarification(Id loanDocumentId, String clarificationReason) {
        ensureCanReview();
        if (String.isBlank(clarificationReason)) {
            throw new LoanDocumentException('Clarification reason is required.');
        }
        Loan_Document__c doc = getDocById(loanDocumentId);
        if (doc == null) throw new LoanDocumentException('Loan document not found.');
        validateReviewable(doc);

        Loan_Document__c updateRow = new Loan_Document__c(
            Id = doc.Id,
            Status__c = 'Needs_Clarification',
            Reviewed_By__c = UserInfo.getUserId(),
            Reviewed_On__c = System.now(),
            Ops_Comments__c = clarificationReason
        );
        applySla(updateRow, doc.Due_On__c, doc.Alert_Level__c == null ? null : Integer.valueOf(doc.Alert_Level__c));
        repository.save(updateRow);

        repository.saveAudit(new Loan_Document_Audit__c(
            Loan__c = doc.Loan__c,
            Loan_Document__c = doc.Id,
            Action__c = 'Clarification_Requested',
            Actor__c = UserInfo.getUserId(),
            Action_On__c = System.now(),
            Prior_Status__c = doc.Status__c,
            New_Status__c = 'Needs_Clarification',
            Content_Document_Id__c = doc.Content_Document_Id__c,
            Details__c = clarificationReason
        ));

        refreshCaseSummaries(new Set<Id>{doc.Loan__c});
    }

    public void updateDocumentScanStatus(Id loanDocumentId, String scanStatus, String scanReference) {
        ensureCanReview();
        if (loanDocumentId == null) {
            throw new LoanDocumentException('Loan document id is required.');
        }
        if (String.isBlank(scanStatus)) {
            throw new LoanDocumentException('Scan status is required.');
        }

        String normalizedStatus = normalizeScanStatus(scanStatus);
        Loan_Document__c doc = getDocById(loanDocumentId);
        if (doc == null) throw new LoanDocumentException('Loan document not found.');

        Loan_Document__c updateRow = new Loan_Document__c(
            Id = doc.Id,
            Scan_Status__c = normalizedStatus,
            Scan_Reference__c = String.isBlank(scanReference) ? null : scanReference.trim(),
            Scanned_On__c = System.now()
        );
        repository.save(updateRow);

        repository.saveAudit(new Loan_Document_Audit__c(
            Loan__c = doc.Loan__c,
            Loan_Document__c = doc.Id,
            Action__c = 'Scan_Updated',
            Actor__c = UserInfo.getUserId(),
            Action_On__c = System.now(),
            Prior_Status__c = doc.Status__c,
            New_Status__c = doc.Status__c,
            Content_Document_Id__c = doc.Content_Document_Id__c,
            Details__c = 'Scan status updated to ' + normalizedStatus +
                (String.isBlank(scanReference) ? '' : (' (' + scanReference.trim() + ')'))
        ));
    }

    public void updateDocumentAuthenticity(
        Id loanDocumentId,
        String authenticityStatus,
        Decimal authenticityScore,
        String authenticityReference
    ) {
        ensureCanReview();
        if (loanDocumentId == null) {
            throw new LoanDocumentException('Loan document id is required.');
        }
        if (String.isBlank(authenticityStatus)) {
            throw new LoanDocumentException('Authenticity status is required.');
        }
        if (authenticityScore != null && (authenticityScore < 0 || authenticityScore > 100)) {
            throw new LoanDocumentException('Authenticity score must be between 0 and 100.');
        }

        String normalizedStatus = normalizeAuthenticityStatus(authenticityStatus);
        Loan_Document__c doc = getDocById(loanDocumentId);
        if (doc == null) throw new LoanDocumentException('Loan document not found.');

        Loan_Document__c updateRow = new Loan_Document__c(
            Id = doc.Id,
            Authenticity_Status__c = normalizedStatus,
            Authenticity_Score__c = authenticityScore,
            Authenticity_Reference__c = String.isBlank(authenticityReference) ? null : authenticityReference.trim(),
            Authenticity_Checked_On__c = System.now()
        );
        repository.save(updateRow);

        repository.saveAudit(new Loan_Document_Audit__c(
            Loan__c = doc.Loan__c,
            Loan_Document__c = doc.Id,
            Action__c = 'Authenticity_Updated',
            Actor__c = UserInfo.getUserId(),
            Action_On__c = System.now(),
            Prior_Status__c = doc.Status__c,
            New_Status__c = doc.Status__c,
            Content_Document_Id__c = doc.Content_Document_Id__c,
            Details__c = 'Authenticity set to ' + normalizedStatus +
                (authenticityScore == null ? '' : (' (score: ' + String.valueOf(authenticityScore.setScale(0)) + ')')) +
                (String.isBlank(authenticityReference) ? '' : (' (' + authenticityReference.trim() + ')'))
        ));
    }

    public void ensureRequiredRecords(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return;
        List<Loan__c> loans = LoanDocumentSelector.getLoansByIds(loanIds);
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        List<Loan_Document_Requirement__mdt> rawRules = LoanDocumentSelector.getRequirementRules();
        Map<Id, Map<String, LoanDocumentationDomain.RequirementOutcome>> outcomesByLoan =
            buildOutcomesByLoan(loans, rawRules);

        List<Loan_Document__c> latest = LoanDocumentSelector.getLatestByLoanIds(loanIds);
        Map<String, Loan_Document__c> latestByLoanType = new Map<String, Loan_Document__c>();
        for (Loan_Document__c row : latest) {
            latestByLoanType.put(key(row.Loan__c, row.Document_Type__c), row);
        }

        List<Loan_Document__c> inserts = new List<Loan_Document__c>();
        for (Id loanId : outcomesByLoan.keySet()) {
            Map<String, LoanDocumentationDomain.RequirementOutcome> outcomes = outcomesByLoan.get(loanId);
            for (LoanDocumentationDomain.RequirementOutcome out : outcomes.values()) {
                if (out.isRequired != true) continue;
                String compositeKey = key(loanId, out.documentType);
                if (latestByLoanType.containsKey(compositeKey)) continue;
                Loan_Document__c placeholder = new Loan_Document__c(
                    Loan__c = loanId,
                    Document_Type__c = out.documentType,
                    Status__c = 'Required',
                    Is_Latest__c = true,
                    Due_On__c = out.dueOn,
                    Alert_Level__c = 0,
                    Next_Alert_On__c = loanMap.get(loanId).CreatedDate.addHours(24)
                );
                applySla(placeholder, placeholder.Due_On__c, 0);
                inserts.add(placeholder);
            }
        }
        if (!inserts.isEmpty()) repository.saveAll(inserts);
        refreshCaseSummaries(loanIds);
    }

    private void syncCore(Set<Id> loanIds, Set<Id> contentDocumentIds) {
        List<Loan__c> loans = LoanDocumentSelector.getLoansByIds(loanIds);
        if (loans.isEmpty()) return;
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        Set<String> contentDocumentIdStrings = new Set<String>();
        for (Id docId : contentDocumentIds) {
            contentDocumentIdStrings.add(String.valueOf(docId));
        }

        List<Loan_Document_Requirement__mdt> rawRules = LoanDocumentSelector.getRequirementRules();
        Map<Id, Map<String, LoanDocumentationDomain.RequirementOutcome>> outcomesByLoan =
            buildOutcomesByLoan(loans, rawRules);

        List<ContentDocumentLink> links = LoanDocumentSelector.getLoanLinks(loanIds);
        Map<Id, Set<Id>> docIdsByLoan = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : links) {
            if (!contentDocumentIds.contains(link.ContentDocumentId)) continue;
            if (!docIdsByLoan.containsKey(link.LinkedEntityId)) docIdsByLoan.put(link.LinkedEntityId, new Set<Id>());
            docIdsByLoan.get(link.LinkedEntityId).add(link.ContentDocumentId);
        }

        List<ContentVersion> versions = LoanDocumentSelector.getLatestVersions(contentDocumentIds);
        Map<Id, ContentVersion> versionByDoc = new Map<Id, ContentVersion>();
        for (ContentVersion v : versions) versionByDoc.put(v.ContentDocumentId, v);

        List<Loan_Document__c> latest = LoanDocumentSelector.getLatestByLoanIds(loanIds);
        Map<String, Loan_Document__c> latestByLoanType = new Map<String, Loan_Document__c>();
        for (Loan_Document__c row : latest) latestByLoanType.put(key(row.Loan__c, row.Document_Type__c), row);
        List<Loan_Document__c> latestByContent = LoanDocumentSelector.getLatestByLoanAndContentIds(loanIds, contentDocumentIdStrings);

        List<Loan_Document__c> updates = new List<Loan_Document__c>();
        List<Loan_Document__c> inserts = new List<Loan_Document__c>();
        List<Loan_Document_Audit__c> audits = new List<Loan_Document_Audit__c>();
        Set<Id> rowsMarkedNotLatest = new Set<Id>();
        for (Loan_Document__c row : latestByContent) {
            if (row.Is_Latest__c == true && !rowsMarkedNotLatest.contains(row.Id)) {
                updates.add(new Loan_Document__c(Id = row.Id, Is_Latest__c = false));
                rowsMarkedNotLatest.add(row.Id);
            }
        }
        for (Id loanId : docIdsByLoan.keySet()) {
            for (Id docId : docIdsByLoan.get(loanId)) {
                ContentVersion v = versionByDoc.get(docId);
                if (v == null || String.isBlank(v.Document_Type__c)) continue;
                String compositeKey = key(loanId, v.Document_Type__c);
                Loan_Document__c prior = latestByLoanType.get(compositeKey);
                if (prior != null && prior.Is_Latest__c == true && !rowsMarkedNotLatest.contains(prior.Id)) {
                    updates.add(new Loan_Document__c(Id = prior.Id, Is_Latest__c = false));
                    rowsMarkedNotLatest.add(prior.Id);
                }

                LoanDocumentationDomain.RequirementOutcome rule =
                    outcomesByLoan.get(loanId) == null ? null : outcomesByLoan.get(loanId).get(domain.normalize(v.Document_Type__c));
                validateFilePolicy(
                    new List<ContentVersion>{ v },
                    rule,
                    v.Document_Type__c,
                    loanId
                );
                Date dueOn = rule == null ? null : rule.dueOn;
                Loan_Document__c next = new Loan_Document__c(
                    Loan__c = loanId,
                    Document_Type__c = v.Document_Type__c,
                    Status__c = 'Under_Review',
                    Scan_Status__c = SCAN_STATUS_PENDING,
                    Authenticity_Status__c = AUTH_STATUS_PENDING,
                    Authenticity_Score__c = null,
                    Authenticity_Reference__c = null,
                    Authenticity_Checked_On__c = null,
                    Uploaded_By__c = v.CreatedById,
                    Uploaded_On__c = v.CreatedDate,
                    Is_Latest__c = true,
                    Due_On__c = dueOn,
                    Content_Document_Id__c = String.valueOf(docId),
                    Alert_Level__c = 0,
                    Next_Alert_On__c = loanMap.get(loanId).CreatedDate.addHours(24)
                );
                applySla(next, dueOn, 0);
                inserts.add(next);

                audits.add(new Loan_Document_Audit__c(
                    Loan__c = loanId,
                    Action__c = prior == null ? 'Uploaded' : 'Replaced',
                    Actor__c = v.CreatedById,
                    Action_On__c = System.now(),
                    Prior_Status__c = prior == null ? null : prior.Status__c,
                    New_Status__c = 'Under_Review',
                    Content_Document_Id__c = String.valueOf(docId),
                    Details__c = 'File submitted for ' + v.Document_Type__c + ': ' + v.Title +
                        ' (scan status: ' + SCAN_STATUS_PENDING + ')'
                ));
            }
        }

        if (!updates.isEmpty()) repository.saveAll(updates);
        if (!inserts.isEmpty()) repository.saveAll(inserts);
        if (!audits.isEmpty()) repository.saveAudits(audits);

        refreshCaseSummaries(loanIds);
    }

    private Map<Id, Map<String, LoanDocumentationDomain.RequirementOutcome>> buildOutcomesByLoan(
        List<Loan__c> loans,
        List<Loan_Document_Requirement__mdt> rawRules
    ) {
        List<LoanDocumentationDomain.RequirementRule> rules = mapRules(rawRules);
        Map<Id, Map<String, LoanDocumentationDomain.RequirementOutcome>> outcomesByLoan =
            new Map<Id, Map<String, LoanDocumentationDomain.RequirementOutcome>>();
        for (Loan__c loan : loans) {
            LoanDocumentationDomain.LoanFacts facts = new LoanDocumentationDomain.LoanFacts();
            facts.loanId = loan.Id;
            facts.loanType = loan.Loan_Type__c;
            facts.loanStatus = loan.Loan_Status__c;
            facts.amount = loan.Loan_Amount__c;
            facts.createdDate = loan.CreatedDate == null ? Date.today() : loan.CreatedDate.date();
            outcomesByLoan.put(loan.Id, domain.resolveEffectiveRequirements(facts, rules));
        }
        return outcomesByLoan;
    }

    private List<LoanDocumentationDomain.RequirementRule> mapRules(List<Loan_Document_Requirement__mdt> rows) {
        List<LoanDocumentationDomain.RequirementRule> rules = new List<LoanDocumentationDomain.RequirementRule>();
        if (rows == null) return rules;
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

    private void applySla(Loan_Document__c doc, Date dueOn, Integer alertLevel) {
        doc.SLA_State__c = domain.computeSlaState(dueOn, Date.today(), alertLevel);
    }

    private Loan_Document__c getDocById(Id loanDocumentId) {
        if (loanDocumentId == null) return null;
        List<Loan_Document__c> rows = [
            SELECT Id, Loan__c, Due_On__c, Alert_Level__c, Is_Latest__c, Content_Document_Id__c,
                   Uploaded_By__c, Status__c, Document_Type__c, Scan_Status__c,
                   Authenticity_Status__c, Authenticity_Score__c
            FROM Loan_Document__c
            WHERE Id = :loanDocumentId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private void validateReviewable(Loan_Document__c doc) {
        if (doc.Is_Latest__c != true) {
            throw new LoanDocumentException('Only the latest document version can be reviewed.');
        }
        if (doc.Uploaded_By__c == UserInfo.getUserId()) {
            throw new LoanDocumentException('Maker-checker policy: reviewer cannot approve or reject their own upload.');
        }
        if (String.isBlank(doc.Content_Document_Id__c)) {
            throw new LoanDocumentException('Cannot review a placeholder record without an uploaded file.');
        }
        Id contentId;
        try {
            contentId = (Id) doc.Content_Document_Id__c;
        } catch (Exception e) {
            throw new LoanDocumentException('Document file reference is invalid.');
        }
        Set<Id> linked = LoanDocumentSelector.getLinkedDocumentIds(doc.Loan__c, new Set<Id>{contentId});
        if (linked.isEmpty()) {
            throw new LoanDocumentException('Cannot review document because the uploaded file is no longer linked to the loan.');
        }
    }

    private void validateApprovalGateReady(Loan_Document__c doc) {
        if (doc == null) return;
        String scanStatus = normalizeScanStatus(doc.Scan_Status__c);
        if (scanStatus != SCAN_STATUS_CLEAN) {
            throw new LoanDocumentException(
                'Document cannot be approved until scan status is Clean. Current scan status: ' +
                (String.isBlank(doc.Scan_Status__c) ? 'Pending' : doc.Scan_Status__c) + '.'
            );
        }

        String authenticityStatus = normalizeAuthenticityStatus(doc.Authenticity_Status__c);
        if (authenticityStatus != AUTH_STATUS_VERIFIED) {
            throw new LoanDocumentException(
                'Document cannot be approved until authenticity status is Verified. Current authenticity status: ' +
                (String.isBlank(doc.Authenticity_Status__c) ? AUTH_STATUS_PENDING : doc.Authenticity_Status__c) + '.'
            );
        }
    }

    private String normalizeScanStatus(String scanStatus) {
        String value = String.isBlank(scanStatus) ? SCAN_STATUS_PENDING : scanStatus.trim();
        String normalized = value.toLowerCase().replace(' ', '_');
        if (normalized == 'clean') return 'Clean';
        if (normalized == 'pending') return 'Pending';
        if (normalized == 'infected') return 'Infected';
        if (normalized == 'failed') return 'Failed';
        throw new LoanDocumentException('Unsupported scan status: ' + scanStatus + '.');
    }

    private String normalizeAuthenticityStatus(String authenticityStatus) {
        String value = String.isBlank(authenticityStatus) ? AUTH_STATUS_PENDING : authenticityStatus.trim();
        String normalized = value.toLowerCase().replace(' ', '_');
        if (normalized == 'pending') return 'Pending';
        if (normalized == 'verified') return 'Verified';
        if (normalized == 'needs_review') return 'Needs_Review';
        if (normalized == 'suspected_fraud') return 'Suspected_Fraud';
        throw new LoanDocumentException('Unsupported authenticity status: ' + authenticityStatus + '.');
    }

    private void validateFilePolicy(
        List<ContentVersion> versions,
        LoanDocumentationDomain.RequirementOutcome rule,
        String documentType,
        Id loanId
    ) {
        if (versions == null || versions.isEmpty()) return;
        if (rule == null) {
            throw new LoanDocumentException(
                'Upload policy is not configured for document type "' + documentType +
                '". Contact admin to configure Loan_Document_Requirement metadata.'
            );
        }

        Set<String> allowedTokens = new Set<String>();
        if (!String.isBlank(rule.allowedMimeTypes)) {
            for (String t : rule.allowedMimeTypes.split('[,;]')) {
                String token = normalizePolicyToken(t);
                if (!String.isBlank(token)) allowedTokens.add(token);
            }
        }
        String allowedDisplay = buildAllowedDisplay(rule.allowedMimeTypes);

        for (ContentVersion versionRecord : versions) {
            Decimal maxSize = rule.maxSizeMb;
            if (maxSize != null && versionRecord.ContentSize != null) {
                Decimal sizeMb = Decimal.valueOf(versionRecord.ContentSize) / Decimal.valueOf(1048576);
                if (sizeMb > maxSize) {
                    repository.saveAudit(new Loan_Document_Audit__c(
                        Loan__c = loanId,
                        Action__c = 'Validation_Failed',
                        Actor__c = UserInfo.getUserId(),
                        Action_On__c = System.now(),
                        Details__c = 'Rejected by size policy for ' + documentType + ': ' + versionRecord.Title
                    ));
                    throw new LoanDocumentException(
                        'Upload blocked for ' + documentType + ': "' + versionRecord.Title + '" is ' +
                        String.valueOf(sizeMb.setScale(2)) + ' MB, max allowed is ' +
                        String.valueOf(maxSize.setScale(2)) + ' MB.'
                    );
                }
            }

            if (!allowedTokens.isEmpty()) {
                Set<String> fileTokens = getFilePolicyTokens(versionRecord);
                Boolean matches = false;
                for (String token : fileTokens) {
                    if (allowedTokens.contains(token)) {
                        matches = true;
                        break;
                    }
                }
                if (!matches) {
                    repository.saveAudit(new Loan_Document_Audit__c(
                        Loan__c = loanId,
                        Action__c = 'Validation_Failed',
                        Actor__c = UserInfo.getUserId(),
                        Action_On__c = System.now(),
                        Details__c = 'Rejected by type policy for ' + documentType + ': ' + versionRecord.Title
                    ));
                    throw new LoanDocumentException(
                        'Upload blocked for ' + documentType + ': "' + versionRecord.Title +
                        '" type is not allowed. Allowed: ' + allowedDisplay + '.'
                    );
                }
            }
        }
    }

    private Set<String> getFilePolicyTokens(ContentVersion versionRecord) {
        Set<String> tokens = new Set<String>();
        if (versionRecord == null) return tokens;

        String ext = normalizePolicyToken(versionRecord.FileExtension);
        if (!String.isBlank(ext)) tokens.add(ext);

        String fileType = normalizePolicyToken(versionRecord.FileType);
        if (!String.isBlank(fileType)) tokens.add(fileType);

        if (fileType == 'pdf' || ext == 'pdf') tokens.add('application/pdf');
        if (fileType == 'png' || ext == 'png') tokens.add('image/png');
        if (fileType == 'jpg' || fileType == 'jpeg' || ext == 'jpg' || ext == 'jpeg') {
            tokens.add('image/jpeg');
            tokens.add('jpg');
            tokens.add('jpeg');
        }
        if (fileType == 'doc' || ext == 'doc') {
            tokens.add('application/msword');
        }
        if (fileType == 'docx' || ext == 'docx') {
            tokens.add('application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        }
        // Salesforce FileType values can be WORD / WORD_X for doc/docx.
        if (fileType == 'word') {
            tokens.add('doc');
            tokens.add('application/msword');
        }
        if (fileType == 'word_x') {
            tokens.add('docx');
            tokens.add('application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        }
        return tokens;
    }

    private String normalizePolicyToken(String value) {
        if (String.isBlank(value)) return null;
        String normalized = value.trim().toLowerCase();
        while (normalized.startsWith('.')) {
            normalized = normalized.substring(1);
        }
        return normalized;
    }

    private String buildAllowedDisplay(String allowedMimeTypes) {
        if (String.isBlank(allowedMimeTypes)) return 'Any';
        List<String> cleaned = new List<String>();
        Set<String> seen = new Set<String>();
        for (String token : allowedMimeTypes.split('[,;]')) {
            String normalized = normalizePolicyToken(token);
            if (String.isBlank(normalized)) continue;
            String display = normalized;
            if (normalized == 'application/pdf') display = '.pdf';
            if (normalized == 'image/png') display = '.png';
            if (normalized == 'image/jpeg') display = '.jpg/.jpeg';
            if (normalized == 'application/msword') display = '.doc';
            if (normalized == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') display = '.docx';
            if (!seen.contains(display)) {
                seen.add(display);
                cleaned.add(display);
            }
        }
        return cleaned.isEmpty() ? 'Any' : String.join(cleaned, ', ');
    }

    private LoanDocumentationDomain.RequirementOutcome getEffectiveRequirementForLoan(Id loanId, String documentType) {
        List<Loan__c> loans = LoanDocumentSelector.getLoansByIds(new Set<Id>{loanId});
        if (loans.isEmpty()) return null;
        Loan__c loan = loans[0];
        LoanDocumentationDomain.LoanFacts facts = new LoanDocumentationDomain.LoanFacts();
        facts.loanId = loan.Id;
        facts.loanType = loan.Loan_Type__c;
        facts.loanStatus = loan.Loan_Status__c;
        facts.amount = loan.Loan_Amount__c;
        facts.createdDate = loan.CreatedDate == null ? Date.today() : loan.CreatedDate.date();

        Map<String, LoanDocumentationDomain.RequirementOutcome> effective =
            domain.resolveEffectiveRequirements(facts, mapRules(LoanDocumentSelector.getRequirementRules()));
        return effective.get(domain.normalize(documentType));
    }

    private void refreshCaseSummaries(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return;

        LoanDocumentQueryService queryService = new LoanDocumentQueryService();
        Map<Id, Loan_Document_Case__c> existing = LoanDocumentSelector.getCasesByLoanIds(loanIds);
        List<Loan_Document__c> latestDocs = LoanDocumentSelector.getLatestByLoanIds(loanIds);
        List<Loan_Document_Case__c> toSave = new List<Loan_Document_Case__c>();
        Id queueOwnerId = resolveCaseQueueOwnerId();

        Map<Id, Integer> maxAlertByLoan = new Map<Id, Integer>();
        Map<Id, Datetime> minNextAlertByLoan = new Map<Id, Datetime>();
        for (Loan_Document__c row : latestDocs) {
            if (row == null || row.Loan__c == null) continue;
            Integer alertLevel = row.Alert_Level__c == null ? 0 : Integer.valueOf(row.Alert_Level__c);
            Integer currentMax = maxAlertByLoan.containsKey(row.Loan__c) ? maxAlertByLoan.get(row.Loan__c) : -1;
            if (alertLevel > currentMax) {
                maxAlertByLoan.put(row.Loan__c, alertLevel);
            }
            if (row.Next_Alert_On__c != null) {
                Datetime currentMin = minNextAlertByLoan.get(row.Loan__c);
                if (currentMin == null || row.Next_Alert_On__c < currentMin) {
                    minNextAlertByLoan.put(row.Loan__c, row.Next_Alert_On__c);
                }
            }
        }

        for (Id loanId : loanIds) {
            LoanDocumentQueryService.LoanDocumentPanelDto panel = queryService.getPanelData(loanId);
            Integer awaiting = 0;
            Integer rejectedCount = 0;
            Integer clarificationCount = 0;
            for (LoanDocumentQueryService.RequirementItem item : panel.requiredChecklist) {
                String normalizedStatus = domain.normalize(item.status);
                if (normalizedStatus == 'under_review' || normalizedStatus == 'rejected' || normalizedStatus == 'needs_clarification') {
                    awaiting++;
                }
                if (normalizedStatus == 'rejected') rejectedCount++;
                if (normalizedStatus == 'needs_clarification') clarificationCount++;
            }

            Loan_Document_Case__c row = existing.containsKey(loanId) ? existing.get(loanId) : new Loan_Document_Case__c();
            row.Loan__c = loanId;
            row.Loan_Key__c = String.valueOf(loanId);
            row.Required_Count__c = panel.requiredTotal;
            row.Approved_Count__c = panel.requiredApproved;
            row.Missing_Count__c = panel.missingTypes == null ? 0 : panel.missingTypes.size();
            row.Awaiting_Review_Count__c = awaiting;
            row.Next_Alert_On__c = minNextAlertByLoan.get(loanId);
            row.Last_Action_On__c = System.now();
            Integer alertLevel = maxAlertByLoan.containsKey(loanId) ? maxAlertByLoan.get(loanId) : 0;
            row.Last_Alert_Level__c = alertLevel;
            row.Last_Alert_On__c = alertLevel > 0 ? System.now() : null;

            if (row.Missing_Count__c > 0 && row.First_Missing_On__c == null) {
                row.First_Missing_On__c = System.now();
            }
            if (row.Missing_Count__c == 0) {
                row.First_Missing_On__c = null;
            }
            if (panel.hasOverdue) {
                row.Status__c = 'Escalated';
            } else if (rejectedCount > 0 || clarificationCount > 0) {
                row.Status__c = 'In_Review';
            } else if (panel.requiredTotal > 0 && panel.requiredApproved == panel.requiredTotal) {
                row.Status__c = 'Complete';
            } else if (awaiting > 0) {
                row.Status__c = 'In_Review';
            } else {
                row.Status__c = 'Open';
            }

            if (queueOwnerId != null && row.Status__c != 'Complete') {
                row.OwnerId = queueOwnerId;
            }
            toSave.add(row);
        }
        repository.saveCases(toSave);
    }

    private Id resolveCaseQueueOwnerId() {
        String queueName = System.Label.Loan_Doc_Alert_Queue_DeveloperName;
        List<Group> queues = LoanDocumentSelector.getQueueByDeveloperName(queueName);
        return queues.isEmpty() ? null : queues[0].Id;
    }

    private String key(Id loanId, String docType) {
        return String.valueOf(loanId) + '|' + domain.normalize(docType);
    }

    private void ensureCanReview() {
        if (FeatureManagement.checkPermission('Loan_Document_Ops')) return;
        if (isCurrentUserAdmin()) return;
        throw new LoanDocumentException('You do not have access to review actions.');
    }

    private Boolean isCurrentUserAdmin() {
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

    public class LoanDocumentException extends Exception {}
}

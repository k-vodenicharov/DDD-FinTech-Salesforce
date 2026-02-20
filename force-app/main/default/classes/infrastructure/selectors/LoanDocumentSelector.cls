/**
 * Query helper for loan document lifecycle reads.
 */
public with sharing class LoanDocumentSelector {
    public class ContentFileInfo {
        public String title;
        public String fileExtension;
        public String displayName;
    }
    public static List<Loan_Document_Requirement__mdt> getRequirementRules() {
        return [
            SELECT DeveloperName, Document_Type__c, Is_Required__c,
                   Applies_To_Loan_Type__c, Min_Amount__c, Max_Amount__c,
                   Loan_Status__c, Due_Days_From_Created__c,
                   Allowed_Mime_Types__c, Max_Size_MB__c
            FROM Loan_Document_Requirement__mdt
            ORDER BY DeveloperName
        ];
    }

    public static List<Loan__c> getLoansByIds(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Loan__c>();
        return [
            SELECT Id, Name, Loan_Type__c, Loan_Status__c, Loan_Amount__c, CreatedDate, Account__r.Name
            FROM Loan__c
            WHERE Id IN :loanIds
        ];
    }

    public static List<Loan__c> getEscalationLoans(Datetime firstAlertCutoff) {
        return [
            SELECT Id, Name, Loan_Type__c, Loan_Status__c, Loan_Amount__c, CreatedDate, Account__r.Name
            FROM Loan__c
            WHERE Loan_Status__c IN ('Pending', 'Under Review')
              AND CreatedDate <= :firstAlertCutoff
        ];
    }

    public static List<Loan_Document__c> getLatestByLoanIds(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Loan_Document__c>();
        return [
            SELECT Id, Loan__c, Document_Type__c, Status__c, Uploaded_By__c, Uploaded_On__c,
                   Reviewed_By__c, Reviewed_On__c, Rejection_Reason__c, Ops_Comments__c,
                   Is_Latest__c, Due_On__c, SLA_State__c, Alert_Level__c, Next_Alert_On__c,
                   Content_Document_Id__c, Scan_Status__c, Scan_Reference__c, Scanned_On__c,
                   Authenticity_Status__c, Authenticity_Score__c, Authenticity_Reference__c, Authenticity_Checked_On__c,
                   LastModifiedDate
            FROM Loan_Document__c
            WHERE Loan__c IN :loanIds AND Is_Latest__c = true
        ];
    }

    public static List<Loan_Document__c> getLatestByLoanAndType(Set<Id> loanIds, Set<String> documentTypes) {
        if (loanIds == null || loanIds.isEmpty() || documentTypes == null || documentTypes.isEmpty()) {
            return new List<Loan_Document__c>();
        }
        return [
            SELECT Id, Loan__c, Document_Type__c, Status__c, Is_Latest__c, Alert_Level__c, Next_Alert_On__c,
                   Due_On__c, SLA_State__c
            FROM Loan_Document__c
            WHERE Loan__c IN :loanIds AND Is_Latest__c = true AND Document_Type__c IN :documentTypes
        ];
    }

    public static List<Loan_Document__c> getLatestByLoanAndContentIds(Set<Id> loanIds, Set<String> contentDocumentIds) {
        if (loanIds == null || loanIds.isEmpty() || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return new List<Loan_Document__c>();
        }
        return [
            SELECT Id, Loan__c, Document_Type__c, Status__c, Is_Latest__c, Content_Document_Id__c
            FROM Loan_Document__c
            WHERE Loan__c IN :loanIds AND Is_Latest__c = true AND Content_Document_Id__c IN :contentDocumentIds
        ];
    }

    public static List<ContentDocumentLink> getLoanLinks(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<ContentDocumentLink>();
        return [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :loanIds
        ];
    }

    public static List<ContentVersion> getLatestVersions(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return new List<ContentVersion>();
        return [
            SELECT Id, ContentDocumentId, Title, FileType, FileExtension, ContentSize, Document_Type__c, CreatedDate, CreatedById
            FROM ContentVersion
            WHERE IsLatest = true AND ContentDocumentId IN :contentDocumentIds
        ];
    }

    public static Map<Id, String> getContentTitles(Set<Id> contentDocumentIds) {
        Map<Id, String> titles = new Map<Id, String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return titles;
        for (ContentDocument doc : [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ]) {
            titles.put(doc.Id, doc.Title);
        }
        return titles;
    }

    public static Map<Id, ContentFileInfo> getContentFileInfo(Set<Id> contentDocumentIds) {
        Map<Id, ContentFileInfo> out = new Map<Id, ContentFileInfo>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return out;
        for (ContentVersion versionRecord : [
            SELECT ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE IsLatest = true AND ContentDocumentId IN :contentDocumentIds
        ]) {
            ContentFileInfo info = new ContentFileInfo();
            info.title = versionRecord.Title;
            info.fileExtension = versionRecord.FileExtension;
            String display = versionRecord.Title;
            if (!String.isBlank(display) && !String.isBlank(info.fileExtension)) {
                String suffix = '.' + info.fileExtension;
                if (!display.toLowerCase().endsWith(suffix.toLowerCase())) {
                    display += suffix;
                }
            }
            info.displayName = display;
            out.put(versionRecord.ContentDocumentId, info);
        }
        return out;
    }

    public static Set<Id> getLinkedDocumentIds(Id loanId, Set<Id> contentDocumentIds) {
        Set<Id> linked = new Set<Id>();
        if (loanId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) return linked;
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loanId AND ContentDocumentId IN :contentDocumentIds
        ]) {
            linked.add(link.ContentDocumentId);
        }
        return linked;
    }

    public static List<Task> getOpenMissingDocTasks(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Task>();
        return [
            SELECT Id, WhatId
            FROM Task
            WHERE WhatId IN :loanIds AND Subject = 'Missing required loan documents' AND Status != 'Completed'
        ];
    }

    public static List<AggregateResult> getOpsWorkloadByStatus() {
        return [
            SELECT Status__c statusValue, COUNT(Id) totalCount
            FROM Loan_Document__c
            WHERE Is_Latest__c = true
              AND Status__c IN ('Under_Review', 'Needs_Clarification', 'Rejected')
            GROUP BY Status__c
        ];
    }

    public static Integer getBlockedByScanCount() {
        List<AggregateResult> rows = [
            SELECT COUNT(Id) totalCount
            FROM Loan_Document__c
            WHERE Is_Latest__c = true
              AND Status__c IN ('Under_Review', 'Needs_Clarification', 'Rejected')
              AND Scan_Status__c IN ('Infected', 'Failed')
        ];
        if (rows.isEmpty()) return 0;
        Object raw = rows[0].get('totalCount');
        return raw == null ? 0 : Integer.valueOf(String.valueOf(raw));
    }

    public static List<Loan_Document__c> getOldestPendingLatest(Integer limitSize) {
        Integer safeLimit = limitSize == null || limitSize <= 0 ? 1 : limitSize;
        return [
            SELECT Id, Loan__c, Document_Type__c, Uploaded_On__c, CreatedDate
            FROM Loan_Document__c
            WHERE Is_Latest__c = true
              AND Status__c IN ('Under_Review', 'Needs_Clarification', 'Rejected')
            ORDER BY Uploaded_On__c ASC NULLS LAST, CreatedDate ASC
            LIMIT :safeLimit
        ];
    }

    public static List<Group> getQueueByDeveloperName(String queueDeveloperName) {
        if (String.isBlank(queueDeveloperName)) return new List<Group>();
        return [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :queueDeveloperName
            LIMIT 1
        ];
    }

    public static List<GroupMember> getGroupMembers(Id groupId) {
        if (groupId == null) return new List<GroupMember>();
        return [
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :groupId
        ];
    }

    public static List<User> getUsersByIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return new List<User>();
        return [SELECT Id, Email FROM User WHERE Id IN :userIds];
    }

    public static Map<Id, Loan_Document_Case__c> getCasesByLoanIds(Set<Id> loanIds) {
        Map<Id, Loan_Document_Case__c> out = new Map<Id, Loan_Document_Case__c>();
        if (loanIds == null || loanIds.isEmpty()) return out;
        for (Loan_Document_Case__c row : [
            SELECT Id, Loan__c, Loan_Key__c, Status__c, First_Missing_On__c
            FROM Loan_Document_Case__c
            WHERE Loan__c IN :loanIds
        ]) {
            out.put(row.Loan__c, row);
        }
        return out;
    }

    public static List<Loan_Document_Audit__c> getAuditByLoanId(Id loanId, Integer limitSize) {
        if (loanId == null) return new List<Loan_Document_Audit__c>();
        Integer safeLimit = limitSize == null || limitSize <= 0 ? 20 : limitSize;
        return [
            SELECT Id, Loan__c, Loan_Document__c, Action__c, Actor__c, Actor__r.Name,
                   Action_On__c, Prior_Status__c, New_Status__c, Details__c, Content_Document_Id__c,
                   Loan_Document__r.Document_Type__c
            FROM Loan_Document_Audit__c
            WHERE Loan__c = :loanId
            ORDER BY Action_On__c DESC
            LIMIT :safeLimit
        ];
    }
}

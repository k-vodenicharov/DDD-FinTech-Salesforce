/**
 * Tests for Task 11 v2 loan document lifecycle and escalation.
 */
@IsTest
private class LoanDocumentationTests {
    private static User createUser(String uniqueKey) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Test',
            LastName = uniqueKey,
            Alias = ('u' + uniqueKey).left(8),
            Email = uniqueKey + '@example.com',
            Username = uniqueKey + '.' + System.now().getTime() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static User createOpsUser(String uniqueKey) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            FirstName = 'Ops',
            LastName = uniqueKey,
            Alias = ('o' + uniqueKey).left(8),
            Email = 'ops.' + uniqueKey + '@example.com',
            Username = 'ops.' + uniqueKey + '.' + System.now().getTime() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static Loan__c createLoan(String name, String loanType, Decimal amount, String statusValue) {
        Account acc = new Account(Name = name + ' Account');
        insert acc;

        Loan__c loan = new Loan__c(
            Name = name,
            Loan_Type__c = loanType,
            Loan_Amount__c = amount,
            Loan_Term__c = 6,
            Interest_Rate__c = 5,
            Principal_Plus_Interest__c = amount + (amount * 0.05),
            Loan_Status__c = statusValue,
            Account__c = acc.Id
        );
        insert loan;
        return loan;
    }

    private static Id uploadFile(Id loanId, String title, String documentType) {
        ContentVersion versionRecord = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('file-' + title + String.valueOf(Math.abs(Crypto.getRandomInteger()))),
            FirstPublishLocationId = loanId,
            Document_Type__c = documentType
        );
        insert versionRecord;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :versionRecord.Id LIMIT 1].ContentDocumentId;
    }

    private static Id uploadFileWithPath(Id loanId, String title, String pathOnClient, String documentType) {
        ContentVersion versionRecord = new ContentVersion(
            Title = title,
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf('file-' + title + String.valueOf(Math.abs(Crypto.getRandomInteger()))),
            FirstPublishLocationId = loanId,
            Document_Type__c = documentType
        );
        insert versionRecord;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :versionRecord.Id LIMIT 1].ContentDocumentId;
    }

    private static void markScanClean(Id loanDocumentId) {
        new LoanDocumentCommandService().updateDocumentScanStatus(loanDocumentId, 'Clean', 'TEST-SCAN');
    }

    private static void markAuthenticityVerified(Id loanDocumentId) {
        new LoanDocumentCommandService().updateDocumentAuthenticity(loanDocumentId, 'Verified', 96, 'TEST-AUTH');
    }

    @IsTest
    static void testUploadCreatesLoanDocumentAndMaintainsLatest() {
        Loan__c loan = createLoan('Loan Upload Latest', 'Unsecured', 30000, 'Pending');

        Id firstDocId = uploadFile(loan.Id, 'Income-1', 'Proof of Income');
        Id secondDocId = uploadFile(loan.Id, 'Income-2', 'Proof of Income');

        List<Loan_Document__c> docs = [
            SELECT Id, Is_Latest__c, Content_Document_Id__c, Status__c, Document_Type__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Proof of Income'
            ORDER BY CreatedDate ASC
        ];

        System.assertEquals(2, docs.size(), 'Two lifecycle records should exist for replacement history.');
        System.assertEquals(false, docs[0].Is_Latest__c, 'First file should be marked non-latest.');
        System.assertEquals(true, docs[1].Is_Latest__c, 'Latest file should be marked latest.');
        System.assertEquals(String.valueOf(secondDocId), docs[1].Content_Document_Id__c, 'Latest record should point to latest file.');
        System.assertEquals('Under_Review', docs[1].Status__c, 'New uploads should enter Under Review.');
        System.assertNotEquals(null, firstDocId, 'Suppress unused warning for first doc id');
    }

    @IsTest
    static void testSingleFileCannotRemainLatestAcrossMultipleTypes() {
        Loan__c loan = createLoan('Loan Single File Single Type', 'Unsecured', 30000, 'Pending');
        Id docId = uploadFile(loan.Id, 'Reusable-Doc', 'Government ID');

        LoanDocumentCommandService svc = new LoanDocumentCommandService();
        svc.assignDocumentType(loan.Id, new Set<Id>{docId}, 'Government ID');
        svc.assignDocumentType(loan.Id, new Set<Id>{docId}, 'Signed Loan Agreement');

        List<Loan_Document__c> latestRowsForSameFile = [
            SELECT Id, Document_Type__c, Is_Latest__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id
              AND Content_Document_Id__c = :String.valueOf(docId)
              AND Is_Latest__c = true
        ];
        System.assertEquals(
            1,
            latestRowsForSameFile.size(),
            'A single ContentDocument must not remain latest for multiple document types on the same loan.'
        );
        System.assertEquals(
            'Signed Loan Agreement',
            latestRowsForSameFile[0].Document_Type__c,
            'Latest row should reflect the most recent assigned document type for that file.'
        );
    }

    @IsTest
    static void testCannotReviewNonLatestOrUnlinkedFileDocument() {
        Loan__c loan = createLoan('Loan Review Guardrails', 'Unsecured', 25000, 'Pending');
        User reviewer = createOpsUser('reviewguard');
        uploadFile(loan.Id, 'Income-v1', 'Proof of Income');
        uploadFile(loan.Id, 'Income-v2', 'Proof of Income');

        List<Loan_Document__c> rows = [
            SELECT Id, Is_Latest__c, Content_Document_Id__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Proof of Income'
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, rows.size(), 'Two versions should exist for guardrail test.');
        Loan_Document__c oldVersion = rows[0];
        Loan_Document__c latestVersion = rows[1];

        Boolean failedOldApprove = false;
        try {
            System.runAs(reviewer) {
                new LoanDocumentCommandService().approveDocument(oldVersion.Id, 'Should fail');
            }
        } catch (Exception e) {
            failedOldApprove = true;
        }
        System.assertEquals(true, failedOldApprove, 'Approving non-latest version must be blocked.');

        delete [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loan.Id AND ContentDocumentId = :((Id)latestVersion.Content_Document_Id__c)
        ];

        Boolean failedUnlinkedReject = false;
        try {
            System.runAs(reviewer) {
                new LoanDocumentCommandService().rejectDocument(latestVersion.Id, 'Missing file', 'Should fail');
            }
        } catch (Exception e) {
            failedUnlinkedReject = true;
        }
        System.assertEquals(true, failedUnlinkedReject, 'Reviewing latest version without linked file must be blocked.');
    }

    @IsTest
    static void testConditionalRequirementEvaluationForProofOfAddress() {
        Loan__c loan = createLoan('Loan Conditional', 'Unsecured', 30000, 'Pending');
        LoanDocumentCommandService svc = new LoanDocumentCommandService();
        svc.ensureRequiredRecords(new Set<Id>{loan.Id});

        LoanDocumentQueryService.LoanDocumentPanelDto panel = new LoanDocumentQueryService().getPanelData(loan.Id);
        System.assert(panel.missingTypes.contains('Proof of Address'),
            'Proof of Address should be required for unsecured high amount based on metadata.');
    }

    @IsTest
    static void testApproveRejectTransitionsAndReasonValidation() {
        Loan__c loan = createLoan('Loan Review Flow', 'Unsecured', 12000, 'Pending');
        User reviewer = createOpsUser('opsreviewer');
        uploadFile(loan.Id, 'Gov-ID', 'Government ID');
        Loan_Document__c doc = [
            SELECT Id, Status__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Government ID' AND Is_Latest__c = true
            LIMIT 1
        ];

        Test.startTest();
        System.runAs(reviewer) {
            markScanClean(doc.Id);
            markAuthenticityVerified(doc.Id);
            new LoanDocumentCommandService().approveDocument(doc.Id, 'Looks valid');
        }
        Test.stopTest();
        Loan_Document__c approved = [SELECT Status__c, Reviewed_By__c, Reviewed_On__c FROM Loan_Document__c WHERE Id = :doc.Id];
        System.assertEquals('Approved', approved.Status__c, 'Approve should set status to Approved.');
        System.assertNotEquals(null, approved.Reviewed_By__c, 'Reviewed By should be set.');
        System.assertNotEquals(null, approved.Reviewed_On__c, 'Reviewed On should be set.');

        Boolean failedAsExpected = false;
        try {
            System.runAs(reviewer) {
                new LoanDocumentCommandService().rejectDocument(doc.Id, null, 'No reason');
            }
        } catch (Exception e) {
            failedAsExpected = true;
        }
        System.assertEquals(true, failedAsExpected, 'Reject without reason should fail.');

        System.runAs(reviewer) {
            new LoanDocumentCommandService().rejectDocument(doc.Id, 'Document unreadable', 'Please re-upload');
        }
        Loan_Document__c rejected = [SELECT Status__c, Rejection_Reason__c FROM Loan_Document__c WHERE Id = :doc.Id];
        System.assertEquals('Rejected', rejected.Status__c, 'Reject should set status to Rejected.');
        System.assertEquals('Document unreadable', rejected.Rejection_Reason__c, 'Reject reason should be saved.');
    }

    @IsTest
    static void testApprovedDocumentWithoutActiveFileLinkIsMissing() {
        Loan__c loan = createLoan('Loan Missing Link', 'Unsecured', 12000, 'Pending');
        User reviewer = createOpsUser('missinglink');
        Id docId = uploadFile(loan.Id, 'Gov-ID-Link', 'Government ID');

        Loan_Document__c doc = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Government ID' AND Is_Latest__c = true
            LIMIT 1
        ];
        System.runAs(reviewer) {
            markScanClean(doc.Id);
            markAuthenticityVerified(doc.Id);
            new LoanDocumentCommandService().approveDocument(doc.Id, 'Approved for test');
        }

        delete [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :loan.Id AND ContentDocumentId = :docId
        ];

        LoanDocumentQueryService.LoanDocumentPanelDto panel = new LoanDocumentQueryService().getPanelData(loan.Id);
        System.assert(panel.missingTypes.contains('Government ID'),
            'Approved lifecycle row must not be counted complete when file is no longer linked.');
        System.assertEquals(0, panel.requiredApproved,
            'Required approved counter should exclude docs without an active file link.');
    }

    @IsTest
    static void testEscalationJobCreatesSingleTaskAndMovesAlertLevel() {
        Loan__c loan = createLoan('Loan Escalation', 'Unsecured', 12000, 'Pending');
        Test.setCreatedDate(loan.Id, System.now().addDays(-2));
        new LoanDocumentCommandService().ensureRequiredRecords(new Set<Id>{loan.Id});

        Test.startTest();
        new LoanDocumentEscalationJob().execute(null);
        Integer firstEmailInvocations = Limits.getEmailInvocations();
        new LoanDocumentEscalationJob().execute(null);
        Integer secondEmailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, Subject, WhatId, Status
            FROM Task
            WHERE WhatId = :loan.Id AND Subject = 'Missing required loan documents'
        ];
        System.assertEquals(1, tasks.size(), 'Job should create only one open task per loan.');
        System.assert(firstEmailInvocations > 0, 'Job should send missing-document notifications.');
        System.assertEquals(firstEmailInvocations, secondEmailInvocations, 'Second run should not resend until next alert window.');

        Integer maxLevel = 0;
        for (Loan_Document__c row : [
            SELECT Alert_Level__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Is_Latest__c = true
        ]) {
            if (row.Alert_Level__c != null && row.Alert_Level__c > maxLevel) {
                maxLevel = Integer.valueOf(row.Alert_Level__c);
            }
        }
        System.assert(maxLevel >= 1, 'Alert level should increment after first escalation run.');
    }

    @IsTest
    static void testMakerCheckerBlocksSelfApproval() {
        Loan__c loan = createLoan('Loan Maker Checker', 'Unsecured', 14000, 'Pending');
        uploadFile(loan.Id, 'Self-Upload', 'Government ID');
        Loan_Document__c doc = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Government ID' AND Is_Latest__c = true
            LIMIT 1
        ];

        Boolean blocked = false;
        try {
            new LoanDocumentCommandService().approveDocument(doc.Id, 'Should be blocked');
        } catch (Exception e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Uploader should not be allowed to approve own document.');
    }

    @IsTest
    static void testFilePolicyBlocksInvalidMimeForSignedAgreement() {
        Loan__c loan = createLoan('Loan File Policy', 'Unsecured', 16000, 'Pending');
        Boolean blocked = false;
        try {
            uploadFileWithPath(loan.Id, 'signed-agreement-image', 'signed-agreement.png', 'Signed Loan Agreement');
        } catch (Exception e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Signed Loan Agreement should reject non-PDF upload by metadata policy during link sync.');
    }

    @IsTest
    static void testUploadSetsScanPendingAndApprovalBlockedUntilClean() {
        Loan__c loan = createLoan('Loan Scan Gate', 'Unsecured', 10000, 'Pending');
        User reviewer = createOpsUser('scangate');
        uploadFile(loan.Id, 'Gov-ID-Scan', 'Government ID');

        Loan_Document__c doc = [
            SELECT Id, Scan_Status__c, Authenticity_Status__c, Status__c
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Government ID' AND Is_Latest__c = true
            LIMIT 1
        ];
        System.assertEquals('Pending', doc.Scan_Status__c, 'New upload must start with Pending scan status.');
        System.assertEquals('Pending', doc.Authenticity_Status__c, 'New upload must start with Pending authenticity status.');
        System.assertEquals('Under_Review', doc.Status__c, 'Upload should stay under review while waiting scan.');

        Boolean blocked = false;
        try {
            System.runAs(reviewer) {
                new LoanDocumentCommandService().approveDocument(doc.Id, 'Attempt approve while pending scan');
            }
        } catch (Exception e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Approval must be blocked until scan status is Clean.');

        System.runAs(reviewer) {
            new LoanDocumentCommandService().updateDocumentScanStatus(doc.Id, 'Clean', 'SCAN-OK-001');
            new LoanDocumentCommandService().updateDocumentAuthenticity(doc.Id, 'Verified', 98, 'AUTH-OK-001');
            new LoanDocumentCommandService().approveDocument(doc.Id, 'Approved after clean scan');
        }

        Loan_Document__c approvedDoc = [
            SELECT Status__c, Scan_Status__c, Scan_Reference__c, Scanned_On__c,
                   Authenticity_Status__c, Authenticity_Score__c, Authenticity_Reference__c, Authenticity_Checked_On__c
            FROM Loan_Document__c
            WHERE Id = :doc.Id
        ];
        System.assertEquals('Approved', approvedDoc.Status__c, 'Approval should succeed after clean scan.');
        System.assertEquals('Clean', approvedDoc.Scan_Status__c, 'Scan status should remain Clean.');
        System.assertEquals('SCAN-OK-001', approvedDoc.Scan_Reference__c, 'Scan reference should be stored.');
        System.assertNotEquals(null, approvedDoc.Scanned_On__c, 'Scanned timestamp should be set.');
        System.assertEquals('Verified', approvedDoc.Authenticity_Status__c, 'Authenticity should remain Verified.');
        System.assertEquals(98, approvedDoc.Authenticity_Score__c, 'Authenticity score should be stored.');
        System.assertEquals('AUTH-OK-001', approvedDoc.Authenticity_Reference__c, 'Authenticity reference should be stored.');
        System.assertNotEquals(null, approvedDoc.Authenticity_Checked_On__c, 'Authenticity checked timestamp should be set.');
    }

    @IsTest
    static void testApprovalBlockedUntilAuthenticityVerified() {
        Loan__c loan = createLoan('Loan Auth Gate', 'Unsecured', 11000, 'Pending');
        User reviewer = createOpsUser('authgate');
        uploadFile(loan.Id, 'Income-Auth', 'Proof of Income');

        Loan_Document__c doc = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Proof of Income' AND Is_Latest__c = true
            LIMIT 1
        ];

        System.runAs(reviewer) {
            new LoanDocumentCommandService().updateDocumentScanStatus(doc.Id, 'Clean', 'SCAN-AUTH-001');
        }

        Boolean blocked = false;
        try {
            System.runAs(reviewer) {
                new LoanDocumentCommandService().approveDocument(doc.Id, 'Attempt approve before authenticity check');
            }
        } catch (Exception e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Approval must be blocked until authenticity is Verified.');

        System.runAs(reviewer) {
            new LoanDocumentCommandService().updateDocumentAuthenticity(doc.Id, 'Verified', 91, 'AUTH-001');
            new LoanDocumentCommandService().approveDocument(doc.Id, 'Approved after authenticity verification');
        }

        Loan_Document__c approved = [
            SELECT Status__c, Authenticity_Status__c
            FROM Loan_Document__c
            WHERE Id = :doc.Id
        ];
        System.assertEquals('Approved', approved.Status__c, 'Approval should succeed after authenticity verification.');
        System.assertEquals('Verified', approved.Authenticity_Status__c, 'Authenticity status should be Verified.');
    }

    @IsTest
    static void testOpsWorkbenchMetricsAreReturnedInPanelDto() {
        Loan__c loan = createLoan('Loan Ops Metrics', 'Unsecured', 18000, 'Pending');
        User reviewer = createOpsUser('opsmetrics');
        uploadFile(loan.Id, 'Income-Metric', 'Proof of Income');

        Loan_Document__c doc = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Document_Type__c = 'Proof of Income' AND Is_Latest__c = true
            LIMIT 1
        ];

        System.runAs(reviewer) {
            new LoanDocumentCommandService().updateDocumentScanStatus(doc.Id, 'Infected', 'SCAN-BLOCK-001');
        }

        LoanDocumentQueryService.LoanDocumentPanelDto panel = new LoanDocumentQueryService().getPanelData(loan.Id);
        System.assert(panel.isOps, 'System context should have ops visibility for workbench metrics.');
        System.assert(panel.opsWorkloadPendingReview >= 1, 'Pending review workload should include the uploaded document.');
        System.assert(panel.opsWorkloadBlockedByScan >= 1, 'Blocked-by-scan workload should include infected documents.');
        System.assertEquals('Proof of Income', panel.opsOldestPendingDocumentType, 'Oldest pending type should be available for prioritization.');
        System.assertNotEquals(null, panel.opsOldestPendingAgeDays, 'Oldest pending age should be returned.');
    }

    @IsTest
    static void testCaseRoutingAndTriageSummarySync() {
        Loan__c loan = createLoan('Loan Case Sync', 'Secured', 10000, 'Pending');
        LoanDocumentCommandService svc = new LoanDocumentCommandService();
        svc.ensureRequiredRecords(new Set<Id>{ loan.Id });

        Loan_Document_Case__c initialCase = [
            SELECT Id, Status__c, Missing_Count__c, Required_Count__c, Approved_Count__c,
                   Awaiting_Review_Count__c, First_Missing_On__c, Last_Alert_Level__c, Next_Alert_On__c, OwnerId
            FROM Loan_Document_Case__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];
        System.assertEquals('Open', initialCase.Status__c, 'Initial case should be open while required docs are missing.');
        System.assert(initialCase.Missing_Count__c > 0, 'Initial case should show missing required docs.');
        System.assertNotEquals(null, initialCase.First_Missing_On__c, 'First missing timestamp should be captured.');

        Loan_Document__c boostedAlert = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Is_Latest__c = true
            LIMIT 1
        ];
        update new Loan_Document__c(
            Id = boostedAlert.Id,
            Alert_Level__c = 2,
            Next_Alert_On__c = System.now().addHours(2)
        );
        svc.ensureRequiredRecords(new Set<Id>{ loan.Id });

        Loan_Document_Case__c alertCase = [
            SELECT Last_Alert_Level__c, Next_Alert_On__c
            FROM Loan_Document_Case__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];
        System.assertEquals(2, Integer.valueOf(alertCase.Last_Alert_Level__c), 'Case should mirror highest alert level from latest docs.');
        System.assertNotEquals(null, alertCase.Next_Alert_On__c, 'Case should mirror next alert timestamp from latest docs.');

        List<Group> queues = LoanDocumentSelector.getQueueByDeveloperName(System.Label.Loan_Doc_Alert_Queue_DeveloperName);
        if (!queues.isEmpty()) {
            Loan_Document_Case__c routedCase = [
                SELECT OwnerId
                FROM Loan_Document_Case__c
                WHERE Loan__c = :loan.Id
                LIMIT 1
            ];
            System.assertEquals(queues[0].Id, routedCase.OwnerId, 'Open/in-review case should be routed to configured queue owner.');
        }

        Test.startTest();
        uploadFile(loan.Id, 'Gov-Case', 'Government ID');
        uploadFile(loan.Id, 'Income-Case', 'Proof of Income');
        uploadFile(loan.Id, 'Agreement-Case', 'Signed Loan Agreement');

        List<Loan_Document__c> reviewDocs = [
            SELECT Id
            FROM Loan_Document__c
            WHERE Loan__c = :loan.Id AND Is_Latest__c = true
              AND Document_Type__c IN ('Government ID', 'Proof of Income', 'Signed Loan Agreement')
        ];
        List<Loan_Document__c> approvals = new List<Loan_Document__c>();
        for (Loan_Document__c row : reviewDocs) {
            approvals.add(new Loan_Document__c(
                Id = row.Id,
                Status__c = 'Approved',
                Scan_Status__c = 'Clean',
                Authenticity_Status__c = 'Verified'
            ));
        }
        update approvals;
        svc.ensureRequiredRecords(new Set<Id>{ loan.Id });
        Test.stopTest();

        Loan_Document_Case__c completedCase = [
            SELECT Status__c, Missing_Count__c, Required_Count__c, Approved_Count__c,
                   Awaiting_Review_Count__c, First_Missing_On__c
            FROM Loan_Document_Case__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];
        System.assertEquals('Complete', completedCase.Status__c, 'Case should transition to complete when all required docs are approved.');
        System.assertEquals(0, Integer.valueOf(completedCase.Missing_Count__c), 'Missing count should be zero after completion.');
        System.assertEquals(completedCase.Required_Count__c, completedCase.Approved_Count__c,
            'Required and approved counts should match at completion.');
        System.assertEquals(0, Integer.valueOf(completedCase.Awaiting_Review_Count__c),
            'Awaiting review count should be zero when complete.');
        System.assertEquals(null, completedCase.First_Missing_On__c,
            'First missing timestamp should be cleared when no required docs are missing.');
    }
}

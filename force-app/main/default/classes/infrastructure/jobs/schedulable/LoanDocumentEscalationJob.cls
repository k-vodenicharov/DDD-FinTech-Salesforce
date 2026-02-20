/**
 * Scheduled job for missing required document reminders and escalation.
 */
global class LoanDocumentEscalationJob implements Schedulable {
    private static final Integer FIRST_ALERT_DELAY_HOURS = 24;

    global void execute(SchedulableContext ctx) {
        Datetime cutoff = System.now().addHours(-FIRST_ALERT_DELAY_HOURS);
        List<Loan__c> loans = LoanDocumentSelector.getEscalationLoans(cutoff);
        if (loans.isEmpty()) return;

        Set<Id> loanIds = new Set<Id>();
        for (Loan__c loan : loans) loanIds.add(loan.Id);

        LoanDocumentCommandService commandService = new LoanDocumentCommandService();
        commandService.ensureRequiredRecords(loanIds);

        LoanDocumentQueryService queryService = new LoanDocumentQueryService();
        List<String> recipients = resolveRecipients();
        if (recipients.isEmpty()) return;

        Set<Id> queueIds = resolveQueueIds();
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        List<Loan_Document__c> latest = LoanDocumentSelector.getLatestByLoanIds(loanIds);
        Map<String, Loan_Document__c> latestByLoanType = new Map<String, Loan_Document__c>();
        for (Loan_Document__c row : latest) {
            latestByLoanType.put(key(row.Loan__c, row.Document_Type__c), row);
        }

        Set<Id> taskExistingLoanIds = new Set<Id>();
        for (Task t : LoanDocumentSelector.getOpenMissingDocTasks(loanIds)) {
            taskExistingLoanIds.add(t.WhatId);
        }

        List<Loan_Document__c> updates = new List<Loan_Document__c>();
        List<Task> tasksToInsert = new List<Task>();
        LoanDocumentationDomain domain = new LoanDocumentationDomain();

        for (Id loanId : loanIds) {
            LoanDocumentQueryService.LoanDocumentPanelDto panel = queryService.getPanelData(loanId);
            if (panel == null || panel.missingTypes == null || panel.missingTypes.isEmpty()) continue;

            Boolean shouldNotify = false;
            for (String missingType : panel.missingTypes) {
                Loan_Document__c rec = latestByLoanType.get(key(loanId, missingType));
                if (rec == null) continue;

                Datetime nextAlert = rec.Next_Alert_On__c;
                if (nextAlert != null && nextAlert > System.now()) continue;

                Integer nextLevel = (rec.Alert_Level__c == null ? 0 : Integer.valueOf(rec.Alert_Level__c)) + 1;
                Loan_Document__c updateRow = new Loan_Document__c(
                    Id = rec.Id,
                    Alert_Level__c = nextLevel,
                    Next_Alert_On__c = domain.computeNextAlertOn(System.now()),
                    SLA_State__c = domain.computeSlaState(rec.Due_On__c, Date.today(), nextLevel)
                );
                updates.add(updateRow);
                shouldNotify = true;
            }

            if (!shouldNotify) continue;
            EmailService.sendMissingDocumentAlert(recipients, loanMap.get(loanId), panel.missingTypes);

            if (!taskExistingLoanIds.contains(loanId)) {
                Task t = new Task(
                    Subject = 'Missing required loan documents',
                    WhatId = loanId,
                    Status = 'Not Started',
                    Priority = 'High',
                    ActivityDate = Date.today(),
                    Description = 'Missing required document types: ' + String.join(panel.missingTypes, ', ')
                );
                if (!queueIds.isEmpty()) {
                    t.OwnerId = queueIds.iterator().next();
                }
                tasksToInsert.add(t);
                taskExistingLoanIds.add(loanId);
            }
        }

        if (!updates.isEmpty()) {
            List<SObject> sobs = new List<SObject>();
            sobs.addAll(updates);
            List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(sobs);
            if (!sanitizedUpdates.isEmpty()) update sanitizedUpdates;
        }
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    private List<String> resolveRecipients() {
        Set<String> emails = new Set<String>();
        String queueName = System.Label.Loan_Doc_Alert_Queue_DeveloperName;
        if (!String.isBlank(queueName)) {
            List<Group> queues = LoanDocumentSelector.getQueueByDeveloperName(queueName);
            if (!queues.isEmpty()) {
                Set<Id> userIds = new Set<Id>();
                for (Id qId : new Map<Id, Group>(queues).keySet()) {
                    for (GroupMember member : LoanDocumentSelector.getGroupMembers(qId)) {
                        String idPrefix = String.valueOf(member.UserOrGroupId).left(3);
                        if (idPrefix != '005') continue;
                        userIds.add(member.UserOrGroupId);
                    }
                }
                for (User u : LoanDocumentSelector.getUsersByIds(userIds)) {
                    if (!String.isBlank(u.Email)) emails.add(u.Email.trim());
                }
            }
        }
        String fallback = System.Label.Loan_Doc_Alert_Fallback_Email;
        if (!String.isBlank(fallback)) {
            for (String token : fallback.split('[,;]')) {
                if (!String.isBlank(token)) emails.add(token.trim());
            }
        }
        List<String> out = new List<String>();
        out.addAll(emails);
        out.sort();
        return out;
    }

    private Set<Id> resolveQueueIds() {
        Set<Id> ids = new Set<Id>();
        String queueName = System.Label.Loan_Doc_Alert_Queue_DeveloperName;
        for (Group queue : LoanDocumentSelector.getQueueByDeveloperName(queueName)) {
            ids.add(queue.Id);
        }
        return ids;
    }

    private String key(Id loanId, String documentType) {
        LoanDocumentationDomain domain = new LoanDocumentationDomain();
        return String.valueOf(loanId) + '|' + domain.normalize(documentType);
    }
}

import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getPanelData from '@salesforce/apex/LoanDocumentController.getPanelData';
import assignDocumentType from '@salesforce/apex/LoanDocumentController.assignDocumentType';
import approveDocument from '@salesforce/apex/LoanDocumentController.approveDocument';
import rejectDocument from '@salesforce/apex/LoanDocumentController.rejectDocument';
import requestClarification from '@salesforce/apex/LoanDocumentController.requestClarification';
import updateDocumentScanStatus from '@salesforce/apex/LoanDocumentController.updateDocumentScanStatus';
import updateDocumentAuthenticity from '@salesforce/apex/LoanDocumentController.updateDocumentAuthenticity';

/**
 * Loan record panel for file uploads and document completeness tracking.
 */
export default class LoanDocumentsPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    @track checklistRows = [];
    @track missingTypes = [];
    @track missingUploadTypes = [];
    @track awaitingApprovalTypes = [];
    @track hasMissingRequired = false;
    @track progressPercent = 0;
    @track requiredTotal = 0;
    @track requiredApproved = 0;
    @track isOps = false;
    @track isAdmin = false;
    @track canReviewActions = false;
    @track canSeeAuditTrail = false;
    @track canSeeInternalScanDetails = false;
    @track hasOverdue = false;
    @track opsWorkloadPendingReview = 0;
    @track opsWorkloadNeedsClarification = 0;
    @track opsWorkloadRejected = 0;
    @track opsWorkloadBlockedByScan = 0;
    @track opsOldestPendingDocumentType = null;
    @track opsOldestPendingUploadedOn = null;
    @track opsOldestPendingAgeDays = null;
    @track isRejectModalOpen = false;
    @track rejectReason = '';
    @track rejectComments = '';
    @track isClarifyModalOpen = false;
    @track clarifyReason = '';
    @track isLoading = false;
    @track activityTimeline = [];
    @track openTaskId = null;
    @track showFullRejection = false;
    @track showInlineUpload = false;
    @track isTimelineCollapsed = true;
    @track selectedFilter = 'all';
    @track searchTerm = '';
    @track selectedRowId = null;
    pendingRejectDocId = null;
    pendingClarifyDocId = null;

    defaultAcceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx'];
    connectedCallback() {
        this.initialize();
    }

    get filteredChecklist() {
        return [...(this.checklistRows || [])].sort((a, b) => {
            if (a.sortRank !== b.sortRank) return a.sortRank - b.sortRank;
            return (a.documentType || '').localeCompare(b.documentType || '');
        });
    }

    get needsActionRows() {
        return this.filteredChecklist.filter((row) => !this.isApprovedStatus(row.status));
    }

    get filteredNeedsActionRows() {
        return this.needsActionRows.filter((row) => this.matchesRowFilter(row) && this.matchesSearch(row));
    }

    get completedRows() {
        return this.filteredChecklist.filter((row) => this.isApprovedStatus(row.status));
    }

    get filteredCompletedRows() {
        return this.completedRows.filter((row) => this.matchesSearch(row));
    }

    get hasNeedsActionRows() {
        return this.filteredNeedsActionRows.length > 0;
    }

    get hasCompletedRows() {
        return this.filteredCompletedRows.length > 0;
    }

    get hasActivityTimeline() {
        return (this.activityTimeline || []).length > 0;
    }

    get displayRows() {
        return this.filteredChecklist.filter((row) => this.matchesRowFilter(row) && this.matchesSearch(row));
    }

    get displayRowsForList() {
        return this.displayRows.map((row) => {
            const isSelected = row.id === this.selectedRowId || (!this.selectedRowId && this.displayRows[0]?.id === row.id);
            return {
                ...row,
                listItemClass: isSelected ? 'neo-doc-item neo-doc-item-selected' : 'neo-doc-item',
                iconName: this.resolveIconName(row),
                dotClass: this.resolveDotClass(row)
            };
        });
    }

    get selectedRow() {
        if (!this.selectedRowId) return this.displayRows[0] || null;
        return this.checklistRows.find((row) => row.id === this.selectedRowId) || this.displayRows[0] || null;
    }

    get hasSelectedRow() {
        return !!this.selectedRow;
    }

    get hasDisplayRows() {
        return this.displayRows.length > 0;
    }

    get timelineToggleLabel() {
        return this.isTimelineCollapsed ? 'Show Activity Timeline' : 'Hide Activity Timeline';
    }

    get showAuditTimelineToggle() {
        return this.canSeeAuditTrail === true;
    }

    get primaryActions() {
        const row = this.selectedRow;
        if (!row) return [];
        const actions = [];
        if (this.isOps) {
            actions.push({
                value: 'preview',
                label: 'Preview',
                variant: 'neutral',
                disabled: row.disableFileActions
            });
            if (row.approvalAllowed) {
                actions.push({
                    value: 'approve',
                    label: 'Approve',
                    variant: 'success',
                    disabled: row.disableApprove
                });
                actions.push({
                    value: 'reject',
                    label: 'Reject',
                    variant: 'destructive',
                    disabled: row.disableReject
                });
            } else {
                actions.push({
                    value: 'reject',
                    label: 'Reject',
                    variant: 'destructive',
                    disabled: row.disableReject
                });
                actions.push({
                    value: 'clarify',
                    label: 'Clarify',
                    variant: 'neutral',
                    disabled: row.disableClarify
                });
            }
            return actions.slice(0, 3);
        }

        actions.push({
            value: 'toggle_upload',
            label: this.showInlineUpload ? 'Hide Upload' : (row.uploadLabel || 'Upload'),
            variant: 'brand',
            disabled: false
        });
        actions.push({
            value: 'preview',
            label: 'Preview',
            variant: 'neutral',
            disabled: row.disableFileActions
        });
        actions.push({
            value: 'download',
            label: 'Download',
            variant: 'neutral',
            disabled: row.disableFileActions
        });
        return actions.slice(0, 3);
    }

    get hasOverflowActions() {
        return this.overflowActions.length > 0;
    }

    get overflowActions() {
        const row = this.selectedRow;
        if (!row) return [];
        const primary = new Set(this.primaryActions.map((a) => a.value));
        const all = [];

        all.push({ value: 'download', label: 'Download', disabled: row.disableFileActions });
        all.push({ value: 'preview', label: 'Preview', disabled: row.disableFileActions });

        if (this.isOps) {
            all.push({ value: 'scan_clean', label: 'Mark Scan Clean', disabled: row.disableScanActions });
            all.push({ value: 'scan_infected', label: 'Mark Scan Infected', disabled: row.disableScanActions });
            all.push({ value: 'auth_verified', label: 'Mark Authentic', disabled: row.disableAuthenticityActions });
            all.push({ value: 'auth_suspected', label: 'Flag Suspected Fraud', disabled: row.disableAuthenticityActions });
            all.push({ value: 'clarify', label: 'Clarify', disabled: row.disableClarify });
            all.push({ value: 'open_task', label: 'Open Task', disabled: row.disableOpenTask });
        }

        if (!this.isOps) {
            all.push({ value: 'toggle_upload', label: this.showInlineUpload ? 'Hide Upload' : (row.uploadLabel || 'Upload'), disabled: false });
        }

        return all.filter((a) => !primary.has(a.value));
    }

    get hasRejectedNote() {
        if (!this.selectedRow) return false;
        return (this.selectedRow.status || '').toLowerCase() === 'rejected' && !!this.rejectionFullText;
    }

    get rejectionFullText() {
        if (!this.selectedRow) return '';
        const reason = (this.selectedRow.rejectionReason || '').trim();
        const comments = (this.selectedRow.opsComments || '').trim();
        if (reason && comments) return `${reason} ${comments}`;
        return reason || comments || '';
    }

    get rejectionPreviewText() {
        const text = this.rejectionFullText;
        if (!text) return '';
        if (text.length <= 120) return text;
        return `${text.slice(0, 120).trim()}...`;
    }

    get hasLongRejectedNote() {
        return this.rejectionFullText.length > 120;
    }

    get displayedRejectedNote() {
        if (!this.rejectionFullText) return '';
        return this.showFullRejection ? this.rejectionFullText : this.rejectionPreviewText;
    }

    get rejectionToggleLabel() {
        return this.showFullRejection ? 'Show less' : 'View full note';
    }

    get selectedRowStatusClass() {
        return this.selectedRow?.statusBadgeClass || 'status-badge status-required';
    }

    get selectedRowStatusLabel() {
        return this.selectedRow?.statusBadgeLabel || 'Required';
    }

    get selectedClarificationHistory() {
        const row = this.selectedRow;
        if (!row || !this.hasActivityTimeline) return [];
        const docType = (row.documentType || '').toLowerCase();
        return (this.activityTimeline || []).filter((entry) => {
            const entryDocType = (entry.documentType || '').toLowerCase();
            if (entryDocType !== docType) return false;
            const action = this.normalizeAction(entry.action);
            return action === 'clarification_requested' || action === 'uploaded' || action === 'replaced';
        });
    }

    get hasClarificationHistory() {
        return this.selectedClarificationHistory.length > 0;
    }

    get latestClarificationEntry() {
        const row = this.selectedRow;
        if (!row) return null;
        const direct = this.selectedClarificationHistory.find((entry) => this.normalizeAction(entry.action) === 'clarification_requested');
        if (direct) return direct;
        if (row.opsComments || row.reviewedOn) {
            return {
                details: row.opsComments || 'Clarification requested.',
                actorName: row.uploadedByName || 'Ops Reviewer',
                actionOnLabel: this.formatDateTime(row.reviewedOn),
                actionLabel: 'Clarification Requested'
            };
        }
        return null;
    }

    get hasClarificationDetails() {
        return !!this.latestClarificationEntry;
    }

    get clarificationRequestedByText() {
        const entry = this.latestClarificationEntry;
        if (!entry) return '';
        return entry.actorName || 'Ops Reviewer';
    }

    get clarificationRequestedOnText() {
        const entry = this.latestClarificationEntry;
        if (!entry) return '';
        return entry.actionOnLabel || '';
    }

    get clarificationMessageText() {
        const entry = this.latestClarificationEntry;
        if (!entry) return '';
        return entry.details || 'Clarification requested. Please upload corrected file.';
    }

    get showClarificationReuploadAction() {
        const row = this.selectedRow;
        if (!row || this.isOps) return false;
        return (row.status || '').toLowerCase() === 'needs_clarification';
    }

    get shortTimeline() {
        return (this.activityTimeline || []).slice(0, 8);
    }

    get clarificationInboxRows() {
        if (this.isOps) return [];
        return this.filteredChecklist
            .filter((row) => (row.status || '').toLowerCase() === 'needs_clarification')
            .map((row) => ({
                id: row.id,
                documentType: row.documentType,
                clarificationText: row.clarificationText || 'Clarification requested. Please re-upload.',
                slaText: row.slaText || 'No SLA',
                uploadLabel: row.uploadLabel || 'Upload Fix'
            }));
    }

    get hasClarificationInboxRows() {
        return this.clarificationInboxRows.length > 0;
    }

    get taskSummaryText() {
        if (this.missingUploadTypes.length > 0) {
            return `Borrower action needed: upload ${this.missingUploadTypes.join(', ')}.`;
        }
        if (this.awaitingApprovalTypes.length > 0) {
            return `Ops action needed: review ${this.awaitingApprovalTypes.join(', ')}.`;
        }
        return 'No open document tasks.';
    }

    get showOpsSlaWorkbench() {
        return this.isOps === true;
    }

    get opsWorkloadTotal() {
        return (
            (this.opsWorkloadPendingReview || 0) +
            (this.opsWorkloadNeedsClarification || 0) +
            (this.opsWorkloadRejected || 0)
        );
    }

    get opsOldestPendingText() {
        if (!this.opsOldestPendingDocumentType) return 'No pending docs in queue.';
        const age = this.opsOldestPendingAgeDays || 0;
        return `${this.opsOldestPendingDocumentType} pending for ${age} day${age === 1 ? '' : 's'}.`;
    }

    get selectedBreachRisk() {
        const row = this.selectedRow;
        if (!row || !row.dueOn) return 'Low';
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const dueDate = new Date(row.dueOn);
        dueDate.setHours(0, 0, 0, 0);
        const days = Math.round((dueDate.getTime() - today.getTime()) / (24 * 60 * 60 * 1000));
        if (days < 0) return 'High';
        if (days <= 1) return 'High';
        if (days <= 3) return 'Medium';
        return 'Low';
    }

    get selectedBreachRiskClass() {
        const risk = this.selectedBreachRisk;
        if (risk === 'High') return 'status-badge sla-overdue';
        if (risk === 'Medium') return 'status-badge sla-due-soon';
        return 'status-badge sla-not-due';
    }

    get selectedPriorityHintText() {
        const row = this.selectedRow;
        if (!row) return '';
        return `Priority hint: review oldest pending first. Current focus: ${row.documentType}.`;
    }

    get summaryBadgeLabel() {
        if (this.hasOverdue) return 'Overdue';
        if (this.missingUploadTypes.length > 0) return `Missing ${this.missingUploadTypes.length}`;
        if (this.awaitingApprovalTypes.length > 0) return `Pending ${this.awaitingApprovalTypes.length}`;
        return 'Complete';
    }

    get needsActionBadgeLabel() {
        return `${this.filteredNeedsActionRows.length} pending`;
    }

    get emptyStateMessage() {
        if (this.searchTerm) {
            return 'No documents match your current search/filter.';
        }
        if (this.selectedFilter !== 'all') {
            return 'No documents in this status right now.';
        }
        return 'No required documents are configured for this loan.';
    }

    get nextActionText() {
        if (!this.hasNeedsActionRows) return 'All required documents are approved.';
        const next = this.filteredNeedsActionRows[0] || this.needsActionRows[0];
        const status = this.formatStatusLabel(next.status || 'Required');
        return `Next action: ${next.documentType} (${status}).`;
    }

    get actionsHelpText() {
        return this.isOps
            ? 'Each item shows file details, then actions for review.'
            : 'Use Upload on each item. After upload, track status until approved.';
    }

    get hasMissingUploads() {
        return this.missingUploadTypes.length > 0;
    }

    get hasAwaitingApproval() {
        return this.awaitingApprovalTypes.length > 0;
    }

    get missingUploadsText() {
        return this.missingUploadTypes.join(', ');
    }

    get awaitingApprovalText() {
        return this.awaitingApprovalTypes.join(', ');
    }

    get summaryVariantClass() {
        if (this.hasOverdue) return 'summary-pill summary-overdue';
        if (this.missingUploadTypes.length > 0) return 'summary-pill summary-missing';
        if (this.awaitingApprovalTypes.length > 0) return 'summary-pill summary-pending';
        return 'summary-pill summary-complete';
    }

    get filterOptions() {
        return [
            { key: 'all', label: 'All' },
            { key: 'required', label: 'Missing Upload' },
            { key: 'under_review', label: 'Under Review' },
            { key: 'needs_clarification', label: 'Needs Clarification' },
            { key: 'ready', label: 'Ready To Approve' }
        ];
    }

    get filterPills() {
        return this.filterOptions.map((option) => ({
            ...option,
            className: option.key === this.selectedFilter ? 'filter-pill filter-pill-active' : 'filter-pill'
        }));
    }

    async initialize() {
        try {
            this.isLoading = true;
            await this.refreshPanel();
        } catch (error) {
            this.showError(error, 'Unable to load loan document settings.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRowUploadFinished(event) {
        try {
            this.isLoading = true;
            const documentType = event?.target?.dataset?.documentType;
            const files = event?.detail?.files || [];
            const fileNames = files.map((f) => f.name).filter((n) => !!n);
            const contentDocumentIds = files.map((f) => f.documentId).filter((id) => !!id);
            if (!contentDocumentIds.length || !documentType) return;

            await this.tagUploadedDocuments(contentDocumentIds, documentType, fileNames);
            await this.refreshPanel();
        } catch (error) {
            this.showError(error, 'Unexpected error while uploading files.');
        } finally {
            this.isLoading = false;
        }
    }

    async tagUploadedDocuments(contentDocumentIds, documentType, fileNames) {
        const result = await assignDocumentType({
            loanId: this.recordId,
            contentDocumentIds,
            documentType
        });

        if (!result?.isSuccess) {
            this.showToast('Error', result?.errorMessage || 'Unable to tag uploaded files.', 'error');
            throw new Error(result?.errorMessage || 'Unable to tag uploaded files.');
        }
        const names = (fileNames || []).slice(0, 2).join(', ');
        const suffix = (fileNames || []).length > 2 ? ` (+${fileNames.length - 2} more)` : '';
        const label = names ? `${names}${suffix}` : 'File(s)';
        this.showToast('Success', `${label} uploaded to ${documentType} and sent for review.`, 'success');
    }

    async refreshPanel() {
        if (!this.recordId) return;
        try {
            this.isLoading = true;
            const data = await getPanelData({ loanId: this.recordId });
            this.missingTypes = data?.missingTypes || [];
            this.hasMissingRequired = this.missingTypes.length > 0;
            this.progressPercent = data?.progressPercent || 0;
            this.requiredTotal = data?.requiredTotal || 0;
            this.requiredApproved = data?.requiredApproved || 0;
            this.isOps = !!data?.isOps;
            this.isAdmin = !!data?.isAdmin;
            this.canReviewActions = !!data?.canReviewActions;
            this.canSeeAuditTrail = !!data?.canSeeAuditTrail;
            this.canSeeInternalScanDetails = !!data?.canSeeInternalScanDetails;
            this.hasOverdue = !!data?.hasOverdue;
            this.openTaskId = data?.openTaskId || null;
            this.opsWorkloadPendingReview = data?.opsWorkloadPendingReview || 0;
            this.opsWorkloadNeedsClarification = data?.opsWorkloadNeedsClarification || 0;
            this.opsWorkloadRejected = data?.opsWorkloadRejected || 0;
            this.opsWorkloadBlockedByScan = data?.opsWorkloadBlockedByScan || 0;
            this.opsOldestPendingDocumentType = data?.opsOldestPendingDocumentType || null;
            this.opsOldestPendingUploadedOn = data?.opsOldestPendingUploadedOn || null;
            this.opsOldestPendingAgeDays = data?.opsOldestPendingAgeDays || null;

            this.checklistRows = (data?.requiredChecklist || []).map((row) => this.withActions(row, true));
            this.activityTimeline = (data?.activityTimeline || []).map((entry, index) => ({
                id: `${entry.actionOn || 'na'}-${index}`,
                actionLabel: entry.actionLabel || this.formatStatusLabel(entry.action || ''),
                documentType: entry.documentType || '',
                actionOn: entry.actionOn,
                actionOnLabel: this.formatDateTime(entry.actionOn),
                actorName: entry.actorName || 'System',
                details: entry.details || '',
                summary: entry.summary || ''
            }));
            this.missingUploadTypes = this.checklistRows
                .filter((row) => (row.status || '').toLowerCase() === 'required')
                .map((row) => row.documentType);
            this.awaitingApprovalTypes = this.checklistRows
                .filter((row) => ['under_review', 'rejected', 'needs_clarification'].includes((row.status || '').toLowerCase()))
                .map((row) => row.documentType);
            this.ensureSelectedRow();
        } finally {
            this.isLoading = false;
        }
    }

    withActions(row, requiredRow) {
        const id = row.loanDocumentId || `${row.documentType}-${row.contentDocumentId || 'none'}`;
        const status = (row.status || '').toLowerCase();
        const badgeClass =
            status === 'approved'
                ? 'status-badge status-approved'
                : status === 'rejected'
                    ? 'status-badge status-rejected'
                    : status === 'needs_clarification'
                        ? 'status-badge status-clarify'
                    : status === 'under_review'
                        ? 'status-badge status-review'
                        : 'status-badge status-required';
        const mismatchWarning = this.computeFileMismatchWarning(row.documentType, row.fileName);
        const policy = this.computeUploadPolicy(row);
        const gate = this.computeApprovalGate(row);
        const displayFileName = this.getDisplayFileName(row);
        const blockedReasonText = this.computeBlockedReason(row, gate);
        const statusGuidanceText = this.computeStatusGuidance(row);
        const slaBadge = this.computeSlaBadge(row);
        const primaryAlert = this.getPrimaryAlert({
            ...row,
            blockedReasonText,
            fileMismatchWarning: mismatchWarning
        });
        return {
            ...row,
            id,
            uploadLabel: row.contentDocumentId ? (status === 'rejected' ? 'Re-upload' : 'Replace') : 'Upload',
            disableFileActions: !row.contentDocumentId,
            disableApprove: !row.loanDocumentId || row.status === 'Approved' || !gate.approvalAllowed,
            disableReject: !row.loanDocumentId || row.status === 'Rejected',
            disableClarify: !row.loanDocumentId || row.status === 'Approved',
            disableOpenTask: !this.openTaskId,
            disableScanActions: !row.loanDocumentId || !row.contentDocumentId,
            disableAuthenticityActions: !row.loanDocumentId || !row.contentDocumentId,
            statusBadgeClass: badgeClass,
            statusBadgeLabel: this.formatStatusLabel(row.status || 'Required'),
            scanStatusLabel: this.formatStatusLabel(row.scanStatus || 'Pending'),
            approvalGateLabel: gate.approvalGateLabel,
            approvalGateBadgeClass: gate.approvalGateBadgeClass,
            approvalAllowed: gate.approvalAllowed,
            dueText: row.dueOn ? `Due ${this.formatDate(row.dueOn)}` : 'No due date',
            slaText: this.computeSlaText(row.dueOn),
            uploadMetaText: row.lastUploadOn ? `Last upload ${this.formatDateTime(row.lastUploadOn)}` : 'Not uploaded yet',
            uploaderText: row.uploadedByName ? `By ${row.uploadedByName}` : '',
            fileNameDisplay: displayFileName || 'Not uploaded yet',
            scanMetaText: row.scannedOn ? `Last scan ${this.formatDateTime(row.scannedOn)}${row.scanReference ? ` (${row.scanReference})` : ''}` : 'Scan not completed',
            clarificationText: this.getClarificationText(row),
            fileMismatchWarning: mismatchWarning,
            primaryAlertText: primaryAlert.text,
            primaryAlertClass: primaryAlert.className,
            summaryDueValue: row.dueOn ? this.formatDate(row.dueOn) : 'No due date',
            summaryUploadValue: row.lastUploadOn
                ? `${this.formatDateTime(row.lastUploadOn)}${row.uploadedByName ? ` by ${row.uploadedByName}` : ''}`
                : 'Not uploaded yet',
            summaryScanValue: row.scanStatus ? this.formatStatusLabel(row.scanStatus) : 'Not scanned',
            summaryAuthenticityValue: this.formatAuthenticitySummary(row),
            summaryGateValue: gate.approvalGateLabel,
            policyHintText: policy.hintText,
            acceptedFormats: policy.acceptedFormats,
            blockedReasonText,
            statusGuidanceText,
            slaBadgeLabel: slaBadge.label,
            slaBadgeClass: slaBadge.className,
            openTaskId: this.openTaskId,
            sortRank: this.computeSortRank(status),
            __required: requiredRow
        };
    }

    getDisplayFileName(row) {
        const name = (row?.fileName || '').trim();
        if (!name) return null;
        const extension = (row?.fileExtension || '').trim();
        if (!extension) return name;
        const suffix = `.${extension}`;
        if (name.toLowerCase().endsWith(suffix.toLowerCase())) return name;
        return `${name}${suffix}`;
    }

    computeApprovalGate(row) {
        const state = (row.approvalGateState || '').toLowerCase();
        const allowed = row.approvalAllowed === true;
        const label = row.approvalGateLabel || (allowed ? 'Ready For Approval' : 'Waiting For Scan');
        let cssClass = 'status-badge gate-pending';
        if (state === 'ready') cssClass = 'status-badge gate-ready';
        if (state === 'blocked') cssClass = 'status-badge gate-blocked';
        if (state === 'blocked_authenticity') cssClass = 'status-badge gate-blocked';
        if (state === 'missing_upload') cssClass = 'status-badge gate-missing';
        if (state === 'complete') cssClass = 'status-badge gate-complete';
        return {
            approvalAllowed: allowed,
            approvalGateLabel: label,
            approvalGateBadgeClass: cssClass
        };
    }

    computeBlockedReason(row, gate) {
        const status = (row?.status || '').toLowerCase();
        const gateState = (row?.approvalGateState || '').toLowerCase();
        if (!row?.contentDocumentId) return 'No file uploaded yet.';
        if (status === 'needs_clarification') return 'Ops requested clarification. Re-upload a corrected file.';
        if (status === 'rejected') return 'Document rejected. Check comments and upload a replacement.';
        if (gate?.approvalAllowed) return null;
        if (gateState === 'blocked') return 'Approval is blocked by scan result. Set scan to Clean after validation.';
        if (gateState === 'blocked_authenticity') return 'Approval is blocked by authenticity checks. Mark document authentic before approval.';
        if (gateState === 'pending_authenticity') return 'Approval is waiting for authenticity verification.';
        if (gateState === 'pending_scan' || gateState === 'pending') return 'Approval is waiting for scan completion.';
        if (gateState === 'missing_upload') return 'Upload is required before review.';
        if (gateState === 'complete') return 'This document is already approved.';
        return 'Approval is currently blocked by workflow state.';
    }

    computeStatusGuidance(row) {
        const status = (row?.status || '').toLowerCase();
        if (this.isOps) {
            if (status === 'required') return 'Waiting for borrower upload.';
            if (status === 'under_review') return 'Review file, update scan/authenticity, then approve/reject.';
            if (status === 'needs_clarification') return 'Borrower must resubmit with clarification.';
            if (status === 'rejected') return 'Waiting for borrower replacement upload.';
            if (status === 'approved') return 'Completed.';
            return 'Review pending.';
        }
        if (status === 'required') return 'Upload this required document.';
        if (status === 'under_review') return 'Uploaded. Ops review in progress.';
        if (status === 'needs_clarification') return 'Ops requested clarification. Re-upload this document.';
        if (status === 'rejected') return 'Rejected. Review reason and upload again.';
        if (status === 'approved') return 'Approved. No action needed.';
        return 'Status updated.';
    }

    computeSlaBadge(row) {
        const normalized = (row?.slaState || '').toLowerCase().replace(/\s+/g, '_');
        const label = this.computeSlaText(row?.dueOn).replace('SLA: ', '');
        if (normalized === 'overdue' || normalized === 'escalated') {
            return { label, className: 'status-badge sla-overdue' };
        }
        if (normalized === 'due_soon') {
            return { label, className: 'status-badge sla-due-soon' };
        }
        return { label, className: 'status-badge sla-not-due' };
    }

    handleManualAction(event) {
        const actionName = event.currentTarget?.dataset?.action;
        const rowId = event.currentTarget?.dataset?.rowid;
        const row = (this.checklistRows || []).find((item) => item.id === rowId);
        if (!actionName || !row) return;
        // Fire and forget; handled with internal loading/toasts.
        this.handleAction(actionName, row);
    }

    handleFilterClick(event) {
        this.selectedFilter = event.currentTarget?.dataset?.filter || 'all';
    }

    handleSearchChange(event) {
        this.searchTerm = (event.target?.value || '').trim().toLowerCase();
        this.ensureSelectedRow();
    }

    handleSelectRow(event) {
        this.selectedRowId = event.currentTarget?.dataset?.rowid || null;
        this.showFullRejection = false;
        this.showInlineUpload = false;
    }

    handleToggleRejectionNote() {
        this.showFullRejection = !this.showFullRejection;
    }

    handleOverflowSelect(event) {
        const actionName = event.detail?.value;
        if (!actionName || !this.selectedRow) return;
        this.handleAction(actionName, this.selectedRow);
    }

    toggleTimeline() {
        this.isTimelineCollapsed = !this.isTimelineCollapsed;
    }

    handleFixNow(event) {
        const rowId = event.currentTarget?.dataset?.rowid;
        if (!rowId) return;
        this.selectedFilter = 'all';
        this.selectedRowId = rowId;
        this.showInlineUpload = !this.isOps;
        const row = (this.checklistRows || []).find((item) => item.id === rowId);
        const docLabel = row?.documentType || 'document';
        this.showToast('Info', `Ready to re-upload ${docLabel}.`, 'info');
        requestAnimationFrame(() => {
            const centerPanel = this.template.querySelector('.neo-center');
            if (centerPanel) {
                centerPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        });
    }

    handleClarificationReupload() {
        const row = this.selectedRow;
        if (!row) return;
        this.showInlineUpload = true;
        this.showToast('Info', `Upload replacement for ${row.documentType}.`, 'info');
        requestAnimationFrame(() => {
            const uploadZone = this.template.querySelector('.neo-action-row-upload');
            if (uploadZone) {
                uploadZone.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });
    }

    async handleAction(actionName, row) {
        this.isLoading = true;
        try {
        if (actionName === 'preview' && row.contentDocumentId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: row.contentDocumentId }
            });
            return;
        }
        if (actionName === 'download' && row.contentDocumentId) {
            window.open(`/sfc/servlet.shepherd/document/download/${row.contentDocumentId}`, '_blank');
            return;
        }
        if (actionName === 'toggle_upload') {
            this.showInlineUpload = !this.showInlineUpload;
            return;
        }
        if (actionName === 'open_task' && row.openTaskId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.openTaskId,
                    actionName: 'view'
                }
            });
            return;
        }
        if (actionName === 'approve') {
            const result = await approveDocument({ loanDocumentId: row.loanDocumentId, comments: 'Approved in UI' });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.errorMessage || 'Unable to approve document.', 'error');
                return;
            }
            this.showToast('Success', 'Document approved.', 'success');
            await this.refreshPanel();
            return;
        }
        if (actionName === 'reject') {
            this.pendingRejectDocId = row.loanDocumentId;
            this.rejectReason = '';
            this.rejectComments = '';
            this.isRejectModalOpen = true;
            return;
        }
        if (actionName === 'clarify') {
            this.pendingClarifyDocId = row.loanDocumentId;
            this.clarifyReason = '';
            this.isClarifyModalOpen = true;
            return;
        }
        if (actionName === 'scan_clean' || actionName === 'scan_infected') {
            const nextStatus = actionName === 'scan_clean' ? 'Clean' : 'Infected';
            const result = await updateDocumentScanStatus({
                loanDocumentId: row.loanDocumentId,
                scanStatus: nextStatus,
                scanReference: 'UI-OPS'
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.errorMessage || 'Unable to update scan status.', 'error');
                return;
            }
            this.showToast('Success', `Scan status set to ${nextStatus}.`, 'success');
            await this.refreshPanel();
            return;
        }
        if (actionName === 'auth_verified' || actionName === 'auth_suspected') {
            const nextStatus = actionName === 'auth_verified' ? 'Verified' : 'Suspected_Fraud';
            const score = actionName === 'auth_verified' ? 95 : 20;
            const result = await updateDocumentAuthenticity({
                loanDocumentId: row.loanDocumentId,
                authenticityStatus: nextStatus,
                authenticityScore: score,
                authenticityReference: 'UI-OPS'
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.errorMessage || 'Unable to update authenticity status.', 'error');
                return;
            }
            const label = nextStatus === 'Verified' ? 'Verified' : 'Suspected Fraud';
            this.showToast('Success', `Authenticity set to ${label}.`, 'success');
            await this.refreshPanel();
            return;
        }
        } finally {
            this.isLoading = false;
        }
    }

    formatAuthenticitySummary(row) {
        const status = row?.authenticityStatus ? this.formatStatusLabel(row.authenticityStatus) : 'Pending';
        if (row?.authenticityScore === null || row?.authenticityScore === undefined) return status;
        return `${status} (${Math.round(Number(row.authenticityScore))}%)`;
    }

    isApprovedStatus(status) {
        return (status || '').toLowerCase() === 'approved';
    }

    computeSortRank(status) {
        if (status === 'needs_clarification') return 0;
        if (status === 'rejected') return 1;
        if (status === 'required') return 2;
        if (status === 'under_review') return 3;
        return 4;
    }

    matchesRowFilter(row) {
        if (!row) return false;
        if (this.selectedFilter === 'all') return true;
        if (this.selectedFilter === 'ready') return row.approvalAllowed === true;
        return (row.status || '').toLowerCase() === this.selectedFilter;
    }

    matchesSearch(row) {
        if (!this.searchTerm) return true;
        const haystack = [
            row.documentType || '',
            row.fileName || '',
            row.status || '',
            row.uploadedByName || ''
        ]
            .join(' ')
            .toLowerCase();
        return haystack.includes(this.searchTerm);
    }

    ensureSelectedRow() {
        const rows = this.displayRows;
        if (!rows.length) {
            this.selectedRowId = null;
            this.showFullRejection = false;
            this.showInlineUpload = false;
            return;
        }
        if (!this.selectedRowId || !rows.some((row) => row.id === this.selectedRowId)) {
            this.selectedRowId = rows[0].id;
            this.showFullRejection = false;
            this.showInlineUpload = false;
        }
    }

    resolveIconName(row) {
        const type = (row?.documentType || '').toLowerCase();
        if (type.includes('income')) return 'doctype:txt';
        if (type.includes('agreement')) return 'doctype:pdf';
        if (type.includes('government') || type.includes('id')) return 'doctype:image';
        return 'doctype:attachment';
    }

    resolveDotClass(row) {
        const status = (row?.status || '').toLowerCase();
        if (status === 'approved') return 'status-dot status-dot-green';
        if (status === 'rejected') return 'status-dot status-dot-red';
        if (status === 'needs_clarification') return 'status-dot status-dot-orange';
        if (status === 'under_review') return 'status-dot status-dot-amber';
        return 'status-dot status-dot-slate';
    }

    computeFileMismatchWarning(documentType, fileName) {
        if (!documentType || !fileName) return null;
        const type = documentType.toLowerCase();
        const file = fileName.toLowerCase();

        const looksLikeGovId = file.includes('id') || file.includes('passport') || file.includes('license');
        const looksLikeIncome = file.includes('income') || file.includes('salary') || file.includes('pay') || file.includes('statement');
        const looksLikeAgreement = file.includes('agreement') || file.includes('contract') || file.includes('signed');

        if (type.includes('government') && !looksLikeGovId) {
            return 'File name may not match Government ID document type.';
        }
        if (type.includes('income') && !looksLikeIncome) {
            return 'File name may not match Proof of Income document type.';
        }
        if (type.includes('agreement') && !looksLikeAgreement) {
            return 'File name may not match Signed Loan Agreement document type.';
        }
        return null;
    }

    computeUploadPolicy(row) {
        const acceptedFormats = this.toAcceptedFormats(row?.allowedMimeTypes);
        const sizeLabel = row?.maxSizeMb ? `Max ${row.maxSizeMb} MB` : null;
        const formatLabel = acceptedFormats.length ? `Allowed: ${acceptedFormats.join(', ')}` : 'Allowed: Any';
        const hintText = sizeLabel ? `${formatLabel} | ${sizeLabel}` : formatLabel;
        return {
            acceptedFormats: acceptedFormats.length ? acceptedFormats : this.defaultAcceptedFormats,
            hintText
        };
    }

    toAcceptedFormats(allowedMimeTypes) {
        if (!allowedMimeTypes) return [];
        const tokens = allowedMimeTypes
            .split(/[;,]/)
            .map((token) => (token || '').trim().toLowerCase())
            .filter((token) => token.length > 0);

        const out = new Set();
        tokens.forEach((token) => {
            if (token === 'application/pdf' || token === 'pdf') out.add('.pdf');
            if (token === 'image/png' || token === 'png') out.add('.png');
            if (token === 'image/jpeg' || token === 'jpg' || token === 'jpeg') {
                out.add('.jpg');
                out.add('.jpeg');
            }
            if (token === 'application/msword' || token === 'doc') out.add('.doc');
            if (
                token === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
                token === 'docx'
            ) {
                out.add('.docx');
            }
        });
        return Array.from(out);
    }

    formatStatusLabel(status) {
        const normalized = (status || '').replace(/_/g, ' ').toLowerCase();
        return normalized.replace(/(^|\s)\S/g, (char) => char.toUpperCase());
    }

    formatDate(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return value;
        return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: 'numeric' }).format(date);
    }

    formatDateTime(value) {
        if (!value) return '';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return value;
        return new Intl.DateTimeFormat(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        }).format(date);
    }

    normalizeAction(value) {
        return (value || '').toLowerCase().replace(/\s+/g, '_');
    }

    computeSlaText(dueOn) {
        if (!dueOn) return 'SLA: No due date';
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const dueDate = new Date(dueOn);
        dueDate.setHours(0, 0, 0, 0);
        const msPerDay = 24 * 60 * 60 * 1000;
        const deltaDays = Math.round((dueDate.getTime() - today.getTime()) / msPerDay);
        if (deltaDays < 0) return `SLA: Overdue by ${Math.abs(deltaDays)} day${Math.abs(deltaDays) === 1 ? '' : 's'}`;
        if (deltaDays === 0) return 'SLA: Due today';
        return `SLA: Due in ${deltaDays} day${deltaDays === 1 ? '' : 's'}`;
    }

    getClarificationText(row) {
        const status = (row?.status || '').toLowerCase();
        if (status !== 'needs_clarification') return null;
        if (row?.opsComments) return `Clarification requested: ${row.opsComments}`;
        return 'Clarification requested. Please re-upload with corrected document details.';
    }

    getPrimaryAlert(row) {
        if (row?.blockedReasonText) {
            return { text: row.blockedReasonText, className: 'doc-warning' };
        }
        const clarification = this.getClarificationText(row);
        if (clarification) {
            return { text: clarification, className: 'doc-clarification' };
        }
        if (row?.fileMismatchWarning) {
            return { text: row.fileMismatchWarning, className: 'doc-warning' };
        }
        return { text: null, className: 'doc-warning' };
    }

    handleRejectReasonChange(event) {
        this.rejectReason = event.target.value || '';
    }

    handleRejectCommentsChange(event) {
        this.rejectComments = event.target.value || '';
    }

    closeRejectModal() {
        this.isRejectModalOpen = false;
        this.pendingRejectDocId = null;
    }

    handleClarifyReasonChange(event) {
        this.clarifyReason = event.target.value || '';
    }

    closeClarifyModal() {
        this.isClarifyModalOpen = false;
        this.pendingClarifyDocId = null;
        this.clarifyReason = '';
    }

    async confirmReject() {
        if (!this.rejectReason.trim()) {
            this.showToast('Error', 'Rejection reason is required.', 'error');
            return;
        }
        try {
            this.isLoading = true;
            const result = await rejectDocument({
                loanDocumentId: this.pendingRejectDocId,
                rejectionReason: this.rejectReason,
                comments: this.rejectComments
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.errorMessage || 'Unable to reject document.', 'error');
                return;
            }
            this.closeRejectModal();
            this.showToast('Success', 'Document rejected.', 'success');
            await this.refreshPanel();
        } finally {
            this.isLoading = false;
        }
    }

    async confirmClarify() {
        if (!this.clarifyReason.trim()) {
            this.showToast('Error', 'Clarification reason is required.', 'error');
            return;
        }
        try {
            this.isLoading = true;
            const result = await requestClarification({
                loanDocumentId: this.pendingClarifyDocId,
                clarificationReason: this.clarifyReason
            });
            if (!result?.isSuccess) {
                this.showToast('Error', result?.errorMessage || 'Unable to request clarification.', 'error');
                return;
            }
            this.closeClarifyModal();
            this.showToast('Success', 'Clarification requested.', 'success');
            await this.refreshPanel();
        } finally {
            this.isLoading = false;
        }
    }

    showError(error, fallbackMessage) {
        const message = error?.body?.message || error?.message || fallbackMessage;
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}


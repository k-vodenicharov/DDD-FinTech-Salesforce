import { createElement } from 'lwc';
import LoanDocumentsPanel from 'c/loanDocumentsPanel';
import getPanelData from '@salesforce/apex/LoanDocumentController.getPanelData';

jest.mock(
    '@salesforce/apex/LoanDocumentController.getPanelData',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.assignDocumentType',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.approveDocument',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.rejectDocument',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.requestClarification',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.updateDocumentScanStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/LoanDocumentController.updateDocumentAuthenticity',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const flushPromises = () => Promise.resolve();

describe('c-loan-documents-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows missing summary badge when required docs are not uploaded', async () => {
        getPanelData.mockResolvedValue({
            requiredChecklist: [{
                loanDocumentId: null,
                documentType: 'Proof of Income',
                status: 'Required',
                dueOn: null,
                slaState: 'Not_Due',
                lastUploadOn: null,
                uploadedByName: null,
                contentDocumentId: null,
                fileName: null,
                isRequired: true
            }],
            activityTimeline: [],
            missingTypes: ['Proof of Income'],
            progressPercent: 0,
            requiredTotal: 1,
            requiredApproved: 0,
            isOps: false,
            hasOverdue: false
        });

        const element = createElement('c-loan-documents-panel', { is: LoanDocumentsPanel });
        element.recordId = 'a0J000000000001';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.summaryBadgeLabel).toBe('Missing 1');
    });

    it('shows pending summary badge for ops when under review exists', async () => {
        getPanelData.mockResolvedValue({
            requiredChecklist: [{
                loanDocumentId: 'a1A000000000001',
                documentType: 'Government ID',
                status: 'Under_Review',
                dueOn: null,
                slaState: 'Not_Due',
                lastUploadOn: null,
                uploadedByName: 'Borrower',
                contentDocumentId: '069000000000001',
                fileName: 'gov-id.pdf',
                isRequired: true
            }],
            activityTimeline: [{
                action: 'Uploaded',
                actionOn: '2026-02-17T12:00:00.000Z',
                actorName: 'Borrower',
                details: 'Uploaded Government ID'
            }],
            missingTypes: ['Government ID'],
            progressPercent: 0,
            requiredTotal: 1,
            requiredApproved: 0,
            isOps: true,
            hasOverdue: false
        });

        const element = createElement('c-loan-documents-panel', { is: LoanDocumentsPanel });
        element.recordId = 'a0J000000000002';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.summaryBadgeLabel).toBe('Pending 1');
        expect(element.hasActivityTimeline).toBe(true);
    });
});

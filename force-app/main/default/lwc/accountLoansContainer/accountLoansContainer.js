import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { graphql, gql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import prepayLoanApex from '@salesforce/apex/LoanController.prepayLoanApex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { deleteRecord } from 'lightning/uiRecordApi';

// GraphQL query for related loans on the Account.
const LOANS_QUERY = gql`
    query LoansByAccount($accountId: ID!) {
        uiapi {
            query {
                Loan__c(
                    where: { Account__c: { eq: $accountId } }
                    orderBy: { CreatedDate: { order: DESC } }
                    first: 50
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            Loan_Status__c { value }
                            Loan_Amount__c { value }
                            Loan_Term__c { value }
                            Interest_Rate__c { value }
                            CreatedDate { value }
                        }
                    }
                }
            }
        }
    }
`;

/**
 * Account-level container for loan list actions.
 */
export default class AccountLoansContainer extends NavigationMixin(LightningElement) {
    @api recordId;

    _loansResult;
    _pageRef;
    _loadErrorShown = false;
    _manualData;
    _manualErrors;
    isEditOpen = false;
    editRecordId = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this._pageRef = pageRef;
    }

    /**
     * Resolves Account Id from page state when recordId isn't passed.
     */
    get resolvedRecordId() {
        return (
            this.recordId ||
            this._pageRef?.attributes?.recordId ||
            this._pageRef?.state?.recordId ||
            null
        );
    }

    @wire(graphql, { query: LOANS_QUERY, variables: '$graphVariables' })
    wiredLoans(result) {
        this._loansResult = result;
        if (result?.data) {
            this._manualData = null;
            this._manualErrors = null;
        }
        const errors = result?.errors;
        if (errors && !this._loadErrorShown) {
            this._loadErrorShown = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: errors?.[0]?.message || 'Unable to load loans.',
                variant: 'error'
            }));
        }
    }

    get graphVariables() {
        if (!this.resolvedRecordId) return undefined;
        return { accountId: this.resolvedRecordId };
    }

    handleLoanSubmitted() {
        this.refreshLoans();
    }

    handleLoanPrepaid() {
        this.refreshLoans();
    }

    /**
     * Refreshes GraphQL data with a fallback to imperative query.
     */
    async refreshLoans() {
        if (this.resolvedRecordId && this._loansResult) {
            try {
                if (typeof refreshGraphQL === 'function') {
                    await refreshGraphQL(this._loansResult);
                    return;
                }
            } catch (e) {
                // Fall back to imperative query below.
            }

            try {
                const result = await graphql({ query: LOANS_QUERY, variables: this.graphVariables });
                this._manualData = result?.data || null;
                this._manualErrors = result?.errors || null;
            } catch (error) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || error?.message || 'Unable to refresh loans.',
                    variant: 'error'
                }));
            }
        }
    }

    /**
     * Handles row-level actions emitted by the data table.
     */
    handleRowAction(event) {
        const raw = event?.detail?.value;
        if (!raw || !raw.includes('|')) return;
        const [loanId, action] = raw.split('|');

        if (loanId && action) {
            switch(action) {
                case 'prepay':
                    this.handlePrepayLoan(loanId);
                    break;
                case 'edit':
                    this.handleEditLoan(loanId);
                    break;
                case 'delete':
                    this.handleDeleteLoan(loanId);
                    break;
                default:
                    break;
            }
        }
    }

    /**
     * Executes prepayment flow for a given loan.
     */
    async handlePrepayLoan(loanId) {
        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to prepay this loan?',
            label: 'Confirm Prepayment',
            variant: 'header'
        });
        if (confirmed) {
            try {
                const prepayResult = await prepayLoanApex({ loanId });

                if (prepayResult?.isSuccess) {
                    const remaining = prepayResult?.remainingBalance ?? 0;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: `Loan prepaid successfully. Remaining balance paid: ${remaining}.`,
                    variant: 'success'
                }));

                if (this._loansResult) {
                    await refreshGraphQL(this._loansResult);
                }
            } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: prepayResult?.errorMessage || 'Failed to process prepayment.',
                        variant: 'error'
                    }));
                }
            } catch (error) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || error?.message || 'An unexpected error occurred.',
                    variant: 'error'
                }));
            }
        }
    }

    /**
     * Opens edit modal for a loan.
     */
    handleEditLoan(loanId) {
        this.editRecordId = loanId;
        this.isEditOpen = true;
    }

    handleEditCancel() {
        this.isEditOpen = false;
        this.editRecordId = null;
    }

    /**
     * Handles successful edit submission.
     */
    async handleEditSuccess() {
        this.isEditOpen = false;
        this.editRecordId = null;
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: 'Loan updated successfully.',
            variant: 'success'
        }));
        await this.refreshLoans();
    }

    handleEditError(event) {
        const message = event?.detail?.message || 'Unable to update loan.';
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }

    /**
     * Deletes a loan after confirmation.
     */
    async handleDeleteLoan(loanId) {
        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this loan?',
            label: 'Confirm Deletion',
            variant: 'header'
        });
        if (!confirmed) return;

        try {
            await deleteRecord(loanId);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Loan deleted successfully.',
                variant: 'success'
            }));
            if (this._loansResult) {
                await refreshGraphQL(this._loansResult);
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || error?.message || 'An unexpected error occurred.',
                variant: 'error'
            }));
        }
    }

    /**
     * Maps GraphQL response into table-friendly objects.
     */
    get loans() {
        if (!this.resolvedRecordId) return [];
        if (this._manualErrors || this._loansResult?.errors) {
            console.error('Loans Error:', this._manualErrors || this._loansResult.errors);
            return [];
        }

        const data = this._manualData || this._loansResult?.data;
        const edges = data?.uiapi?.query?.Loan__c?.edges;
        if (!edges || !edges.length) {
            return [];
        }

        return edges.map(edge => {
            const node = edge?.node;
            if (!node || !node.Id) return null;

            const id = node.Id;
            const name = node.Name?.value || '';
            const status = node.Loan_Status__c?.value || '';
            const amount = node.Loan_Amount__c?.value || '';
            const term = node.Loan_Term__c?.value || '';
            const rate = node.Interest_Rate__c?.value || '';
            const created = node.CreatedDate?.value || '';

            return {
                id,
                name,
                status,
                amount,
                term,
                rate,
                created,
                prepayValue: `${id}|prepay`,
                editValue: `${id}|edit`,
                deleteValue: `${id}|delete`,
                url: `/lightning/r/Loan__c/${id}/view`
            };
        }).filter(record => record !== null);
    }
}

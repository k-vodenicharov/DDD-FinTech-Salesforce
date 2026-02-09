import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import prepayLoanApex from '@salesforce/apex/LoanController.prepayLoanApex';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import LightningConfirm from 'lightning/confirm';

/**
 * Quick action for loan prepayment.
 */
export default class PrepayLoanAction extends LightningElement {
    @api recordId;

    @track isLoading = false;
    @track errorMessage = '';

    /** Initializes local state. */
    connectedCallback() {
        this.isLoading = false;
        this.errorMessage = '';
    }

    /** Cancels the action and closes the panel. */
    handleCancel() {
        this.errorMessage = '';
        this.closeQuickAction();
    }

    /** Executes the prepayment flow after confirmation. */
    async handlePrepayClick() {
        if (this.isLoading) return;
        const confirmed = await LightningConfirm.open({
            message: 'This will mark all remaining payment plans as Completed and close the loan. Continue?',
            label: 'Confirm Prepayment',
            variant: 'header'
        });
        if (!confirmed) return;

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await prepayLoanApex({ loanId: this.recordId });

            if (result?.isSuccess) {
                const remaining = result?.remainingBalance ?? 0;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: `Loan prepaid successfully. Remaining balance paid: ${remaining}.`,
                    variant: 'success'
                }));

                this.closeQuickAction();
                getRecordNotifyChange([{ recordId: this.recordId }]);
                this.dispatchEvent(new CustomEvent('loanprepaid', { bubbles: true, composed: true }));
            } else {
                this.errorMessage = result?.errorMessage || 'Failed to process prepayment.';
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred.';
        } finally {
            this.isLoading = false;
        }
    }

    /** Closes the quick action panel. */
    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}

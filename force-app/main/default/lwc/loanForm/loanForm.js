import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import LOAN_OBJECT from '@salesforce/schema/Loan__c';
import LOAN_TYPE_FIELD from '@salesforce/schema/Loan__c.Loan_Type__c';
import LOAN_AMOUNT_FIELD from '@salesforce/schema/Loan__c.Loan_Amount__c';
import LOAN_TERM_FIELD from '@salesforce/schema/Loan__c.Loan_Term__c';
import INTEREST_RATE_FIELD from '@salesforce/schema/Loan__c.Interest_Rate__c';
import ACCOUNT_FIELD from '@salesforce/schema/Loan__c.Account__c';

/**
 * Loan creation form for Account pages.
 */
export default class LoanForm extends LightningElement {
    @api recordId;

    @track loanType = 'Secured';
    @track loanAmount;
    @track loanTerm;
    @track interestRate;
    @track errorMessage = '';

    loanTypeOptions = [
        { label: 'Secured', value: 'Secured' },
        { label: 'Unsecured', value: 'Unsecured' }
    ];

    handleLoanTypeChange(event) {
        this.loanType = event.detail.value;
    }

    handleAmountChange(event) {
        this.loanAmount = event.target.value;
    }

    handleTermChange(event) {
        this.loanTerm = event.target.value;
    }

    handleRateChange(event) {
        this.interestRate = event.target.value;
    }

    /**
     * Client-side validation for basic business rules.
     */
    validate() {
        const term = parseInt(this.loanTerm, 10);
        if (Number.isNaN(term)) return 'Loan Term must be a number.';
        if (this.loanType === 'Secured' && term > 6) {
            return 'Loan term exceeds maximum allowed for Secured loans (6 months).';
        }
        if (this.loanType === 'Unsecured' && term > 12) {
            return 'Loan term exceeds maximum allowed for Unsecured loans (12 months).';
        }
        if (!this.loanAmount || isNaN(parseFloat(this.loanAmount)) || parseFloat(this.loanAmount) <= 0) {
            return 'Loan Amount must be a positive number.';
        }
        if (this.interestRate === null || this.interestRate === undefined || this.interestRate === '' ||
            isNaN(parseFloat(this.interestRate)) || parseFloat(this.interestRate) < 0) {
            return 'Interest Rate must be a valid number.';
        }
        return null;
    }

    /**
     * Creates a Loan__c record via LDS.
     */
    async handleSave() {
        try {
            const validationError = this.validate();
            if (validationError) {
                this.errorMessage = validationError;
                return;
            }
            this.errorMessage = '';

            const fields = {};
            fields[LOAN_TYPE_FIELD.fieldApiName] = this.loanType;
            fields[LOAN_AMOUNT_FIELD.fieldApiName] = parseFloat(this.loanAmount);
            fields[LOAN_TERM_FIELD.fieldApiName] = parseInt(this.loanTerm, 10);
            fields[INTEREST_RATE_FIELD.fieldApiName] = parseFloat(this.interestRate);
            fields[ACCOUNT_FIELD.fieldApiName] = this.recordId;

            const recordInput = {
                apiName: LOAN_OBJECT.objectApiName,
                fields
            };

            const result = await createRecord(recordInput);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: `Loan created successfully with ID: ${result.id}`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('loansubmitted'));
            this.loanAmount = null;
            this.loanTerm = null;
            this.interestRate = null;
        } catch (e) {
            this.errorMessage = e?.body?.message || e?.message || 'An unexpected error occurred.';
        }
    }
}

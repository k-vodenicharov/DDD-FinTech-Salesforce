/**
 * Query-side service for read-only loan access.
 */
public with sharing class LoanQueryService {
    /**
     * Returns a loan by Id.
     */
    public Loan__c getLoanById(Id loanId) {
        return LoanSelector.getLoanById(loanId);
    }

    /**
     * Returns loans for a given account Id.
     */
    public List<Loan__c> getLoansByAccountId(Id accountId) {
        return LoanSelector.getLoansByAccountId(accountId);
    }
}

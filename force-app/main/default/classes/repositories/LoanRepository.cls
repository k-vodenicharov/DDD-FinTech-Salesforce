public class LoanRepository {
    public void save(Loan__c loan) {
        insert loan;
    }

    /**
     * Finds and returns a Loan__c record by its ID.
     * @param loanId The ID of the loan to retrieve.
     * @return Loan__c instance with specified ID.
     */
    public Loan__c findById(Id loanId) {
        return [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate FROM Loan__c WHERE Id = :loanId LIMIT 1];
    }
}
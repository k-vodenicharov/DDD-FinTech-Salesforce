public class LoanRepository {
    public void save(Loan__c loan) {
        insert loan;
    }

    public Loan__c findById(Id loanId) {
        return [SELECT Id, Loan_Term__c, Principal_Plus_Interest__c, CreatedDate FROM Loan__c WHERE Id = :loanId LIMIT 1];
    }
}
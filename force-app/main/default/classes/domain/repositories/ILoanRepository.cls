/**
 * Repository contract for Loan__c persistence and retrieval.
 */
public interface ILoanRepository {
    void save(Loan__c loan);
    void saveAll(List<Loan__c> loans);
    Loan__c findById(Id loanId);
    List<Loan__c> findAllById(Set<Id> loanIds);
    List<Loan__c> findByAccountId(Id accountId);
    void deleteRecord(Loan__c loan);
    void deleteAll(List<Loan__c> loans);
}

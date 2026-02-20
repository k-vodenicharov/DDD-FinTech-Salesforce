/**
 * Repository contract for Loan_Document__c persistence.
 */
public interface ILoanDocumentRepository {
    void saveAll(List<Loan_Document__c> records);
    void save(Loan_Document__c record);
    void saveAudit(Loan_Document_Audit__c record);
    void saveAudits(List<Loan_Document_Audit__c> records);
    void saveCase(Loan_Document_Case__c record);
    void saveCases(List<Loan_Document_Case__c> records);
}

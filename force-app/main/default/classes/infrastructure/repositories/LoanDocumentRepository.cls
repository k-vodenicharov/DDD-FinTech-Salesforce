/**
 * Infrastructure repository for Loan_Document__c.
 */
public with sharing class LoanDocumentRepository implements ILoanDocumentRepository {
    public void save(Loan_Document__c record) {
        if (record == null) return;
        if (record.Id == null) {
            insert record;
        } else {
            update record;
        }
    }

    public void saveAll(List<Loan_Document__c> records) {
        if (records == null || records.isEmpty()) return;
        List<Loan_Document__c> toInsert = new List<Loan_Document__c>();
        List<Loan_Document__c> toUpdate = new List<Loan_Document__c>();
        for (Loan_Document__c rec : records) {
            if (rec == null) continue;
            if (rec.Id == null) toInsert.add(rec); else toUpdate.add(rec);
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    public void saveAudit(Loan_Document_Audit__c record) {
        if (record == null) return;
        insert record;
    }

    public void saveAudits(List<Loan_Document_Audit__c> records) {
        if (records == null || records.isEmpty()) return;
        insert records;
    }

    public void saveCase(Loan_Document_Case__c record) {
        if (record == null) return;
        if (record.Id == null) {
            insert record;
        } else {
            update record;
        }
    }

    public void saveCases(List<Loan_Document_Case__c> records) {
        if (records == null || records.isEmpty()) return;
        List<Loan_Document_Case__c> toInsert = new List<Loan_Document_Case__c>();
        List<Loan_Document_Case__c> toUpdate = new List<Loan_Document_Case__c>();
        for (Loan_Document_Case__c rec : records) {
            if (rec == null) continue;
            if (rec.Id == null) toInsert.add(rec); else toUpdate.add(rec);
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}

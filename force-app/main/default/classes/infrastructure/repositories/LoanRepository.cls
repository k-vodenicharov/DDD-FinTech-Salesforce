/**
 * Infrastructure repository for Loan__c using CRUD/FLS enforcement.
 */
public with sharing class LoanRepository implements ILoanRepository {
    /** Inserts or updates a single loan based on Id presence. */
    public void save(Loan__c loan) {
        if (loan == null) return;
        if (loan.Id == null) {
            if (!Schema.SObjectType.Loan__c.isCreateable()) {
                throw new SecurityException('Insufficient access to create Loan.');
            }
            insert loan;
        } else {
            if (!Schema.SObjectType.Loan__c.isUpdateable()) {
                throw new SecurityException('Insufficient access to update Loan.');
            }
            update loan;
        }
    }

    /** Inserts/updates loans in bulk based on Id presence. */
    public void saveAll(List<Loan__c> loans) {
        if (loans == null || loans.isEmpty()) return;
        List<Loan__c> toInsert = new List<Loan__c>();
        List<Loan__c> toUpdate = new List<Loan__c>();
        for (Loan__c loan : loans) {
            if (loan == null) continue;
            if (loan.Id == null) toInsert.add(loan); else toUpdate.add(loan);
        }
        if (!toInsert.isEmpty()) {
            if (!Schema.SObjectType.Loan__c.isCreateable()) {
                throw new SecurityException('Insufficient access to create Loan.');
            }
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            if (!Schema.SObjectType.Loan__c.isUpdateable()) {
                throw new SecurityException('Insufficient access to update Loan.');
            }
            update toUpdate;
        }
    }

    /** Returns a single loan or null when not found. */
    public Loan__c findById(Id loanId) {
        List<Loan__c> loans = [SELECT Id, Loan_Type__c, Loan_Amount__c, Loan_Term__c, Interest_Rate__c,
                                      Principal_Plus_Interest__c, Loan_Status__c, Account__c, Name, CreatedDate
                               FROM Loan__c WHERE Id = :loanId WITH SECURITY_ENFORCED LIMIT 1];
        List<Loan__c> sanitized = sanitize(loans);
        return sanitized.isEmpty() ? null : sanitized[0];
    }

    /** Returns loans for the provided Ids. */
    public List<Loan__c> findAllById(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Loan__c>();
        List<Loan__c> loans = [SELECT Id, Loan_Type__c, Loan_Amount__c, Loan_Term__c, Interest_Rate__c,
                                      Principal_Plus_Interest__c, Loan_Status__c, Account__c, Name, CreatedDate
                               FROM Loan__c WHERE Id IN :loanIds WITH SECURITY_ENFORCED];
        return sanitize(loans);
    }

    /** Returns loans for a given account. */
    public List<Loan__c> findByAccountId(Id accountId) {
        if (accountId == null) return new List<Loan__c>();
        List<Loan__c> loans = [SELECT Id, Loan_Type__c, Loan_Amount__c, Loan_Term__c, Interest_Rate__c,
                                      Principal_Plus_Interest__c, Loan_Status__c, Account__c, Name, CreatedDate
                               FROM Loan__c WHERE Account__c = :accountId WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC];
        return sanitize(loans);
    }

    /** Applies FLS read filtering to loan records. */
    private List<Loan__c> sanitize(List<Loan__c> loans) {
        if (loans == null || loans.isEmpty()) return new List<Loan__c>();
        List<SObject> sobs = new List<SObject>();
        sobs.addAll(loans);
        List<SObject> sanitized = SecurityUtil.stripRead(sobs);
        List<Loan__c> result = new List<Loan__c>();
        for (SObject s : sanitized) {
            result.add((Loan__c) s);
        }
        return result;
    }

    /** Deletes a single loan. */
    public void deleteRecord(Loan__c loan) {
        if (loan == null) return;
        if (!Schema.SObjectType.Loan__c.isDeletable()) {
            throw new SecurityException('Insufficient access to delete Loan.');
        }
        delete loan;
    }

    /** Deletes a list of loans. */
    public void deleteAll(List<Loan__c> loans) {
        if (loans == null || loans.isEmpty()) return;
        if (!Schema.SObjectType.Loan__c.isDeletable()) {
            throw new SecurityException('Insufficient access to delete Loan.');
        }
        delete loans;
    }
}

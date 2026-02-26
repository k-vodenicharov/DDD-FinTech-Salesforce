/**
 * Infrastructure repository for Loan_Document__c.
 */
public with sharing class LoanDocumentRepository implements ILoanDocumentRepository {
    public void save(Loan_Document__c record) {
        if (record == null) return;
        if (record.Id == null) {
            assertCreateable(Schema.SObjectType.Loan_Document__c, 'Loan Document');
            List<SObject> sanitized = SecurityUtil.stripCreate(new List<SObject>{ record });
            if (sanitized.isEmpty()) throw new SecurityException('Insufficient access to create Loan Document.');
            insert (Loan_Document__c) sanitized[0];
        } else {
            assertUpdateable(Schema.SObjectType.Loan_Document__c, 'Loan Document');
            List<SObject> sanitized = SecurityUtil.stripUpdate(new List<SObject>{ record });
            if (sanitized.isEmpty()) throw new SecurityException('Insufficient access to update Loan Document.');
            update (Loan_Document__c) sanitized[0];
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
        if (!toInsert.isEmpty()) {
            assertCreateable(Schema.SObjectType.Loan_Document__c, 'Loan Document');
            List<SObject> createRows = new List<SObject>();
            createRows.addAll(toInsert);
            List<SObject> sanitizedInserts = SecurityUtil.stripCreate(createRows);
            if (!sanitizedInserts.isEmpty()) {
                insert (List<Loan_Document__c>) sanitizedInserts;
            }
        }
        if (!toUpdate.isEmpty()) {
            assertUpdateable(Schema.SObjectType.Loan_Document__c, 'Loan Document');
            List<SObject> updateRows = new List<SObject>();
            updateRows.addAll(toUpdate);
            List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(updateRows);
            if (!sanitizedUpdates.isEmpty()) {
                update (List<Loan_Document__c>) sanitizedUpdates;
            }
        }
    }

    public void saveAudit(Loan_Document_Audit__c record) {
        if (record == null) return;
        assertCreateable(Schema.SObjectType.Loan_Document_Audit__c, 'Loan Document Audit');
        List<SObject> sanitized = SecurityUtil.stripCreate(new List<SObject>{ record });
        if (sanitized.isEmpty()) throw new SecurityException('Insufficient access to create Loan Document Audit.');
        insert (Loan_Document_Audit__c) sanitized[0];
    }

    public void saveAudits(List<Loan_Document_Audit__c> records) {
        if (records == null || records.isEmpty()) return;
        assertCreateable(Schema.SObjectType.Loan_Document_Audit__c, 'Loan Document Audit');
        List<SObject> createRows = new List<SObject>();
        createRows.addAll(records);
        List<SObject> sanitized = SecurityUtil.stripCreate(createRows);
        if (!sanitized.isEmpty()) {
            insert (List<Loan_Document_Audit__c>) sanitized;
        }
    }

    public void saveCase(Loan_Document_Case__c record) {
        if (record == null) return;
        if (record.Id == null) {
            assertCreateable(Schema.SObjectType.Loan_Document_Case__c, 'Loan Document Case');
            List<SObject> sanitized = SecurityUtil.stripCreate(new List<SObject>{ record });
            if (sanitized.isEmpty()) throw new SecurityException('Insufficient access to create Loan Document Case.');
            insert (Loan_Document_Case__c) sanitized[0];
        } else {
            assertUpdateable(Schema.SObjectType.Loan_Document_Case__c, 'Loan Document Case');
            List<SObject> sanitized = SecurityUtil.stripUpdate(new List<SObject>{ record });
            if (sanitized.isEmpty()) throw new SecurityException('Insufficient access to update Loan Document Case.');
            update (Loan_Document_Case__c) sanitized[0];
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
        if (!toInsert.isEmpty()) {
            assertCreateable(Schema.SObjectType.Loan_Document_Case__c, 'Loan Document Case');
            List<SObject> createRows = new List<SObject>();
            createRows.addAll(toInsert);
            List<SObject> sanitizedInserts = SecurityUtil.stripCreate(createRows);
            if (!sanitizedInserts.isEmpty()) {
                insert (List<Loan_Document_Case__c>) sanitizedInserts;
            }
        }
        if (!toUpdate.isEmpty()) {
            assertUpdateable(Schema.SObjectType.Loan_Document_Case__c, 'Loan Document Case');
            List<SObject> updateRows = new List<SObject>();
            updateRows.addAll(toUpdate);
            List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(updateRows);
            if (!sanitizedUpdates.isEmpty()) {
                update (List<Loan_Document_Case__c>) sanitizedUpdates;
            }
        }
    }

    private static void assertCreateable(Schema.DescribeSObjectResult describeResult, String label) {
        if (!describeResult.isCreateable()) {
            throw new SecurityException('Insufficient access to create ' + label + '.');
        }
    }

    private static void assertUpdateable(Schema.DescribeSObjectResult describeResult, String label) {
        if (!describeResult.isUpdateable()) {
            throw new SecurityException('Insufficient access to update ' + label + '.');
        }
    }
}

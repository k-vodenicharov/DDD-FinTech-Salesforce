/**
 * Infrastructure repository for Payment_Plan__c using CRUD/FLS enforcement.
 */
public with sharing class PaymentPlanRepository implements IPaymentPlanRepository {
    /** Inserts or updates a single payment plan based on Id presence. */
    public void save(Payment_Plan__c paymentPlan) {
        if (paymentPlan == null) return;
        if (paymentPlan.Id == null) {
            if (!Schema.SObjectType.Payment_Plan__c.isCreateable()) {
                throw new SecurityException('Insufficient access to create Payment Plan.');
            }
            insert paymentPlan;
        } else {
            if (!Schema.SObjectType.Payment_Plan__c.isUpdateable()) {
                throw new SecurityException('Insufficient access to update Payment Plan.');
            }
            update paymentPlan;
        }
    }

    /** Inserts/updates payment plans in bulk based on Id presence. */
    public void saveAll(List<Payment_Plan__c> paymentPlans) {
        if (paymentPlans == null || paymentPlans.isEmpty()) return;
        List<Payment_Plan__c> toInsert = new List<Payment_Plan__c>();
        List<Payment_Plan__c> toUpdate = new List<Payment_Plan__c>();
        for (Payment_Plan__c plan : paymentPlans) {
            if (plan == null) continue;
            if (plan.Id == null) toInsert.add(plan); else toUpdate.add(plan);
        }
        if (!toInsert.isEmpty()) {
            if (!Schema.SObjectType.Payment_Plan__c.isCreateable()) {
                throw new SecurityException('Insufficient access to create Payment Plan.');
            }
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            if (!Schema.SObjectType.Payment_Plan__c.isUpdateable()) {
                throw new SecurityException('Insufficient access to update Payment Plan.');
            }
            update toUpdate;
        }
    }

    /** Returns a single payment plan or null when not found. */
    public Payment_Plan__c findById(Id paymentPlanId) {
        List<Payment_Plan__c> plans = [SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, BYPASS__c
                                       FROM Payment_Plan__c WHERE Id = :paymentPlanId WITH SECURITY_ENFORCED LIMIT 1];
        List<Payment_Plan__c> sanitized = sanitize(plans);
        return sanitized.isEmpty() ? null : sanitized[0];
    }

    /** Returns payment plans for the provided Ids. */
    public List<Payment_Plan__c> findAllById(Set<Id> paymentPlanIds) {
        if (paymentPlanIds == null || paymentPlanIds.isEmpty()) return new List<Payment_Plan__c>();
        List<Payment_Plan__c> plans = [SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, BYPASS__c
                                       FROM Payment_Plan__c WHERE Id IN :paymentPlanIds WITH SECURITY_ENFORCED];
        return sanitize(plans);
    }

    /** Returns payment plans for a given loan. */
    public List<Payment_Plan__c> findByLoanId(Id loanId) {
        if (loanId == null) return new List<Payment_Plan__c>();
        List<Payment_Plan__c> plans = [SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, BYPASS__c, Name
                                       FROM Payment_Plan__c WHERE Loan__c = :loanId WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
        return sanitize(plans);
    }

    /** Returns payment plans for multiple loans. */
    public List<Payment_Plan__c> findByLoanIds(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return new List<Payment_Plan__c>();
        List<Payment_Plan__c> plans = [SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, BYPASS__c, Name
                                       FROM Payment_Plan__c WHERE Loan__c IN :loanIds WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
        return sanitize(plans);
    }

    /** Returns payment plans by status. */
    public List<Payment_Plan__c> findByStatus(String status) {
        if (String.isBlank(status)) return new List<Payment_Plan__c>();
        List<Payment_Plan__c> plans = [SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c, Payment_Deadline__c, BYPASS__c
                                       FROM Payment_Plan__c WHERE Payment_Status__c = :status WITH SECURITY_ENFORCED ORDER BY Payment_Deadline__c];
        return sanitize(plans);
    }

    /** Applies FLS read filtering to payment plan records. */
    private List<Payment_Plan__c> sanitize(List<Payment_Plan__c> plans) {
        if (plans == null || plans.isEmpty()) return new List<Payment_Plan__c>();
        List<SObject> sobs = new List<SObject>();
        sobs.addAll(plans);
        List<SObject> sanitized = SecurityUtil.stripRead(sobs);
        List<Payment_Plan__c> result = new List<Payment_Plan__c>();
        for (SObject s : sanitized) {
            result.add((Payment_Plan__c) s);
        }
        return result;
    }

    /** Deletes a single payment plan. */
    public void deleteRecord(Payment_Plan__c paymentPlan) {
        if (paymentPlan == null) return;
        if (!Schema.SObjectType.Payment_Plan__c.isDeletable()) {
            throw new SecurityException('Insufficient access to delete Payment Plan.');
        }
        delete paymentPlan;
    }

    /** Deletes a list of payment plans. */
    public void deleteAll(List<Payment_Plan__c> paymentPlans) {
        if (paymentPlans == null || paymentPlans.isEmpty()) return;
        if (!Schema.SObjectType.Payment_Plan__c.isDeletable()) {
            throw new SecurityException('Insufficient access to delete Payment Plan.');
        }
        delete paymentPlans;
    }
}

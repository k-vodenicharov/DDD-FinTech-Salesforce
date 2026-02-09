/**
 * Repository contract for Payment_Plan__c persistence and retrieval.
 */
public interface IPaymentPlanRepository {
    void save(Payment_Plan__c paymentPlan);
    void saveAll(List<Payment_Plan__c> paymentPlans);
    Payment_Plan__c findById(Id paymentPlanId);
    List<Payment_Plan__c> findAllById(Set<Id> paymentPlanIds);
    List<Payment_Plan__c> findByLoanId(Id loanId);
    List<Payment_Plan__c> findByLoanIds(Set<Id> loanIds);
    List<Payment_Plan__c> findByStatus(String status);
    void deleteRecord(Payment_Plan__c paymentPlan);
    void deleteAll(List<Payment_Plan__c> paymentPlans);
}

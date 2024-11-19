public class PaymentPlanDomain {
    /**
     * Identifies upcoming payments that are due within the next 5 days and have not been approved.
     */
    public static List<Payment_Plan__c> identifyUpcomingPayments(List<Payment_Plan__c> payments) {
        List<Payment_Plan__c> upcomingPayments = new List<Payment_Plan__c>();

        for (Payment_Plan__c payment : payments) {
            if (payment.Payment_Deadline__c == Date.today().addDays(5) &&
                payment.Payment_Status__c != 'Approved') {
                upcomingPayments.add(payment);
            }
        }

        return upcomingPayments;
    }

    /**
     * Identifies missed payments based on the following conditions:
     * 1. Payment is overdue (Payment_Deadline__c is in the past)
     * 2. Payment is not marked as "Approved"
     */
    public static List<Payment_Plan__c> identifyMissedPayments(List<Payment_Plan__c> newPayments, List<Payment_Plan__c> oldPayments) {
        List<Payment_Plan__c> missedPayments = new List<Payment_Plan__c>();

        for (Integer i = 0; i < newPayments.size(); i++) {
            Payment_Plan__c newPayment = newPayments[i];
            Payment_Plan__c oldPayment = oldPayments[i];

            if (newPayment.Payment_Deadline__c < Date.today() &&
                newPayment.Payment_Status__c != 'Approved' &&
                oldPayment.Payment_Status__c != 'Approved') {
                missedPayments.add(newPayment);
            }
        }

        return missedPayments;
    }
}
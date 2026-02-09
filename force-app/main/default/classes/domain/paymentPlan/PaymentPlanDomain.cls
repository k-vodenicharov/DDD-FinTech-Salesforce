/**
 * Domain logic for payment plan schedules and status evaluation.
 */
public class PaymentPlanDomain {
    /**
     * Distributes a total amount across a term, rounding to cents and applying remainder to the first plan.
     */
    public List<Decimal> distributeAmounts(Decimal totalAmount, Integer term) {
        List<Decimal> amounts = new List<Decimal>();
        if (term == null || term <= 0) return amounts;

        Decimal total = (totalAmount == null) ? 0 : totalAmount;
        Decimal totalRounded = total.setScale(2, System.RoundingMode.HALF_UP);
        Decimal baseAmount = (totalRounded / term).setScale(2, System.RoundingMode.HALF_UP);
        // Remainder is added to the first payment to preserve totals.
        Decimal remainder = totalRounded - (baseAmount * term);

        for (Integer i = 0; i < term; i++) {
            Decimal amt = baseAmount;
            if (i == 0) {
                amt += remainder;
            }
            amounts.add(amt);
        }
        return amounts;
    }

    /**
     * Builds monthly deadlines starting from the first day of the next month.
     */
    public List<Date> buildDeadlines(Date startDate, Integer term) {
        List<Date> deadlines = new List<Date>();
        if (term == null || term <= 0) return deadlines;
        Date base = (startDate == null ? Date.today() : startDate).toStartOfMonth().addMonths(1);
        for (Integer i = 0; i < term; i++) {
            deadlines.add(base.addMonths(i));
        }
        return deadlines;
    }

    /**
     * Determines loan status from the statuses of its payment plans.
     */
    public String determineLoanStatus(List<Payment_Plan__c> plans) {
        if (plans == null || plans.isEmpty()) return 'Pending';

        Boolean allCompleted = true;
        Boolean anyFailed = false;
        Boolean anyNonPending = false;

        for (Payment_Plan__c plan : plans) {
            if (plan.Payment_Status__c == 'Failed') {
                anyFailed = true;
                allCompleted = false;
                break;
            }
            if (plan.Payment_Status__c != 'Pending') {
                anyNonPending = true;
            }
            if (plan.Payment_Status__c != 'Completed') {
                allCompleted = false;
            }
        }

        if (anyFailed) return 'Failed';
        if (allCompleted) return 'Closed';
        if (anyNonPending) return 'Under Review';
        return 'Pending';
    }
}

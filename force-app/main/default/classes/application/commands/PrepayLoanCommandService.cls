/**
 * Command-side service to prepay loans and finalize remaining plans.
 */
public with sharing class PrepayLoanCommandService {
    private final ILoanRepository loanRepository;
    private final IPaymentPlanRepository paymentPlanRepository;
    private final LoanDomain loanDomain;
    private final PaymentPlanDomain paymentPlanDomain;

    public PrepayLoanCommandService() {
        this.loanRepository = new LoanRepository();
        this.paymentPlanRepository = new PaymentPlanRepository();
        this.loanDomain = new LoanDomain();
        this.paymentPlanDomain = new PaymentPlanDomain();
    }

    /**
     * Processes a prepayment: recalculates interest, completes plans, and closes the loan.
     */
    public ResponseWrapper prepayLoan(Id loanId) {
        ResponseWrapper res = new ResponseWrapper();
        res.loanId = loanId;

        if (loanId == null) {
            res.isSuccess = false;
            res.errorMessage = 'Loan Id is required';
            return res;
        }

        try {
            Loan__c loan = loanRepository.findById(loanId);
            if (loan == null) {
                res.isSuccess = false;
                res.errorMessage = 'Loan not found';
                return res;
            }

            List<Payment_Plan__c> plans = paymentPlanRepository.findByLoanId(loanId);
            List<Payment_Plan__c> completed = new List<Payment_Plan__c>();
            List<Payment_Plan__c> openPlans = new List<Payment_Plan__c>();

            for (Payment_Plan__c plan : plans) {
                if (plan.Payment_Status__c == 'Completed') completed.add(plan);
                else openPlans.add(plan);
            }

            // Recalculate principal+interest based on actual repayment period.
            Decimal adjustedTotal = loanDomain.calculateAdjustedPrincipalPlusInterest(loan, Date.today());
            if (loan.Principal_Plus_Interest__c != adjustedTotal) {
                loan.Principal_Plus_Interest__c = adjustedTotal;
                List<SObject> sanitizedLoanTotal = SecurityUtil.stripUpdate(new List<SObject>{ loan });
                if (!sanitizedLoanTotal.isEmpty()) {
                    loanRepository.save((Loan__c) sanitizedLoanTotal[0]);
                }
            }
            Decimal completedSum = 0;
            for (Payment_Plan__c plan : completed) {
                if (plan.Payment_Amount__c != null) completedSum += plan.Payment_Amount__c;
            }

            Decimal remaining = adjustedTotal - completedSum;
            if (remaining < 0) remaining = 0;

            List<Decimal> amounts = paymentPlanDomain.distributeAmounts(remaining, openPlans.size());
            for (Integer i = 0; i < openPlans.size(); i++) {
                openPlans[i].Payment_Amount__c = amounts[i];
                openPlans[i].Payment_Status__c = 'Completed';
                openPlans[i].BYPASS__c = true;
            }

            if (!openPlans.isEmpty()) {
                List<SObject> sObjects = new List<SObject>();
                sObjects.addAll(openPlans);
                List<SObject> sanitizedPlans = SecurityUtil.stripUpdate(sObjects);
                if (!sanitizedPlans.isEmpty()) {
                    paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitizedPlans);
                }
                resetBypassFlags(openPlans);
            }

            loan.Loan_Status__c = 'Closed';
            List<SObject> sanitizedLoan = SecurityUtil.stripUpdate(new List<SObject>{ loan });
            if (!sanitizedLoan.isEmpty()) {
                LoanStatusContext.allowStatusUpdate = true;
                try {
                    loanRepository.save((Loan__c) sanitizedLoan[0]);
                } finally {
                    LoanStatusContext.allowStatusUpdate = false;
                }
            }

            res.isSuccess = true;
            res.remainingBalance = remaining;
        } catch (Exception e) {
            res.isSuccess = false;
            res.errorMessage = 'Error processing prepayment: ' + e.getMessage();
        }
        return res;
    }

    /**
     * Resets BYPASS__c after system-driven updates.
     */
    private void resetBypassFlags(List<Payment_Plan__c> plans) {
        if (plans == null || plans.isEmpty()) return;
        List<Payment_Plan__c> resets = new List<Payment_Plan__c>();
        for (Payment_Plan__c plan : plans) {
            if (plan == null || plan.Id == null) continue;
            if (plan.BYPASS__c == true) {
                resets.add(new Payment_Plan__c(Id = plan.Id, BYPASS__c = false));
            }
        }
        if (resets.isEmpty()) return;

        List<SObject> sObjects = new List<SObject>();
        sObjects.addAll(resets);
        List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(sObjects);
        if (!sanitizedUpdates.isEmpty()) {
            paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitizedUpdates);
        }
    }
}

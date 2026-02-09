/**
 * Command-side application service for Payment_Plan__c writes and adjustments.
 */
public with sharing class PaymentPlanCommandService {
    // Guard flag to prevent recursive adjustments when we update plans internally.
    private static Boolean isSystemAdjusting = false;

    private final PaymentPlanDomain paymentPlanDomain;
    private final LoanDomain loanDomain;
    private final ILoanRepository loanRepository;
    private final IPaymentPlanRepository paymentPlanRepository;

    public PaymentPlanCommandService() {
        this.paymentPlanDomain = new PaymentPlanDomain();
        this.loanDomain = new LoanDomain();
        this.loanRepository = new LoanRepository();
        this.paymentPlanRepository = new PaymentPlanRepository();
    }

    /**
     * Creates initial payment plans for newly created loans.
     */
    public void createInitialPlans(List<Loan__c> newLoans) {
        if (newLoans == null || newLoans.isEmpty()) return;

        List<Payment_Plan__c> toInsert = new List<Payment_Plan__c>();
        for (Loan__c loan : newLoans) {
            if (loan == null || loan.Id == null) continue;
            Integer term = loan.Loan_Term__c == null ? 0 : loan.Loan_Term__c.intValue();
            if (term <= 0) continue;

            Decimal total = (loan.Principal_Plus_Interest__c == null)
                ? loanDomain.recalculatePrincipalPlusInterest(loan)
                : loan.Principal_Plus_Interest__c;

            List<Decimal> amounts = paymentPlanDomain.distributeAmounts(total, term);
            List<Date> deadlines = paymentPlanDomain.buildDeadlines(
                loan.CreatedDate == null ? Date.today() : loan.CreatedDate.date(),
                term
            );

            for (Integer i = 0; i < term; i++) {
                Payment_Plan__c plan = new Payment_Plan__c(
                    Loan__c = loan.Id,
                    Payment_Amount__c = amounts[i],
                    Payment_Deadline__c = deadlines[i],
                    Payment_Status__c = 'Pending',
                    Name = 'Payment ' + (i + 1) + ' of ' + term + ' for ' + loan.Loan_Type__c
                );
                toInsert.add(plan);
            }
        }

        if (!toInsert.isEmpty()) {
            List<SObject> sObjects = new List<SObject>();
            sObjects.addAll(toInsert);
            List<SObject> sanitized = SecurityUtil.stripCreate(sObjects);
            if (!sanitized.isEmpty()) {
                paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitized);
            }
        }
    }

    /**
     * Deletes and rebuilds payment plans for the given loans.
     */
    public void rebuildInitialPlans(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return;

        List<Loan__c> loans = loanRepository.findAllById(loanIds);
        if (loans.isEmpty()) return;

        List<Payment_Plan__c> existing = paymentPlanRepository.findByLoanIds(loanIds);
        if (!existing.isEmpty()) {
            paymentPlanRepository.deleteAll(existing);
        }

        createInitialPlans(loans);
    }

    /**
     * Adjusts payment plans based on changes in loan term, rate, or amount.
     */
    public void adjustPlansForLoans(List<Loan__c> newLoans, Map<Id, Loan__c> oldMap) {
        if (newLoans == null || newLoans.isEmpty() || oldMap == null) return;

        Set<Id> changedLoanIds = new Set<Id>();
        for (Loan__c loan : newLoans) {
            Loan__c oldLoan = oldMap.get(loan.Id);
            if (oldLoan == null) continue;
            Boolean termChanged = loan.Loan_Term__c != oldLoan.Loan_Term__c;
            Boolean rateChanged = loan.Interest_Rate__c != oldLoan.Interest_Rate__c;
            Boolean amountChanged = loan.Loan_Amount__c != oldLoan.Loan_Amount__c;
            if (termChanged || rateChanged || amountChanged) {
                changedLoanIds.add(loan.Id);
            }
        }

        if (changedLoanIds.isEmpty()) return;

        adjustPlansForLoanIds(changedLoanIds);
    }

    /**
     * Adjusts payment plans for a set of loan Ids.
     */
    public void adjustPlansForLoanIds(Set<Id> loanIds) {
        if (loanIds == null || loanIds.isEmpty()) return;

        List<Loan__c> loans = loanRepository.findAllById(loanIds);
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        List<Payment_Plan__c> allPlans = paymentPlanRepository.findByLoanIds(loanIds);

        Map<Id, List<Payment_Plan__c>> plansByLoan = new Map<Id, List<Payment_Plan__c>>();
        for (Payment_Plan__c plan : allPlans) {
            if (!plansByLoan.containsKey(plan.Loan__c)) {
                plansByLoan.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            plansByLoan.get(plan.Loan__c).add(plan);
        }

        List<Payment_Plan__c> toInsert = new List<Payment_Plan__c>();
        List<Payment_Plan__c> toUpdate = new List<Payment_Plan__c>();
        List<Payment_Plan__c> toDelete = new List<Payment_Plan__c>();

        for (Id loanId : loanIds) {
            Loan__c loan = loanMap.get(loanId);
            if (loan == null) continue;

            Integer term = loan.Loan_Term__c == null ? 0 : loan.Loan_Term__c.intValue();
            if (term <= 0) continue;

            List<Payment_Plan__c> plans = plansByLoan.containsKey(loanId)
                ? plansByLoan.get(loanId)
                : new List<Payment_Plan__c>();

            List<Payment_Plan__c> completedPlans = new List<Payment_Plan__c>();
            List<Payment_Plan__c> openPlans = new List<Payment_Plan__c>();
            for (Payment_Plan__c plan : plans) {
                if (plan.Payment_Status__c == 'Completed') {
                    completedPlans.add(plan);
                } else {
                    openPlans.add(plan);
                }
            }

            if (completedPlans.size() > term) {
                throw new LoanAdjustmentException('Loan term cannot be less than completed payment plans.');
            }

            Decimal total = (loan.Principal_Plus_Interest__c == null)
                ? loanDomain.recalculatePrincipalPlusInterest(loan)
                : loan.Principal_Plus_Interest__c;

            Decimal completedSum = 0;
            for (Payment_Plan__c plan : completedPlans) {
                if (plan.Payment_Amount__c != null) completedSum += plan.Payment_Amount__c;
            }

            Integer openCount = term - completedPlans.size();
            Decimal remainingTotal = total - completedSum;
            if (remainingTotal < 0) remainingTotal = 0;

            List<Decimal> openAmounts = paymentPlanDomain.distributeAmounts(remainingTotal, openCount);

            // Anchor deadlines to the original loan timeline where possible.
            Date baseDate = loan.CreatedDate == null ? Date.today() : loan.CreatedDate.date();
            Date earliestOpenDeadline;
            for (Payment_Plan__c openPlan : openPlans) {
                if (openPlan.Payment_Deadline__c == null) continue;
                if (earliestOpenDeadline == null || openPlan.Payment_Deadline__c < earliestOpenDeadline) {
                    earliestOpenDeadline = openPlan.Payment_Deadline__c;
                }
            }

            Date lastCompletedDeadline;
            for (Payment_Plan__c completedPlan : completedPlans) {
                if (completedPlan.Payment_Deadline__c == null) continue;
                if (lastCompletedDeadline == null || completedPlan.Payment_Deadline__c > lastCompletedDeadline) {
                    lastCompletedDeadline = completedPlan.Payment_Deadline__c;
                }
            }

            Date firstOpenDeadline;
            // Prefer existing open plan deadlines; otherwise, continue after the last completed deadline.
            if (earliestOpenDeadline != null) {
                firstOpenDeadline = earliestOpenDeadline;
            } else if (lastCompletedDeadline != null) {
                firstOpenDeadline = lastCompletedDeadline.addMonths(1);
            } else {
                List<Date> initialDeadlines = paymentPlanDomain.buildDeadlines(baseDate, 1);
                firstOpenDeadline = initialDeadlines.isEmpty() ? Date.today().toStartOfMonth().addMonths(1) : initialDeadlines[0];
            }

            List<Date> openDeadlines = openCount > 0
                ? paymentPlanDomain.buildDeadlines(firstOpenDeadline.addMonths(-1), openCount)
                : new List<Date>();

            for (Integer i = 0; i < openCount; i++) {
                Date deadline = openDeadlines[i];
                Decimal amount = openAmounts[i];

                if (i < openPlans.size()) {
                    Payment_Plan__c planToUpdate = openPlans[i];
                    planToUpdate.Payment_Amount__c = amount;
                    planToUpdate.Payment_Deadline__c = deadline;
                    planToUpdate.BYPASS__c = true;
                    toUpdate.add(planToUpdate);
                } else {
                    Payment_Plan__c newPlan = new Payment_Plan__c(
                        Loan__c = loanId,
                        Payment_Amount__c = amount,
                        Payment_Deadline__c = deadline,
                        Payment_Status__c = 'Pending',
                        Name = 'Payment ' + (completedPlans.size() + i + 1) + ' of ' + term + ' for ' + loan.Loan_Type__c
                    );
                    toInsert.add(newPlan);
                }
            }

            if (openPlans.size() > openCount) {
                for (Integer i = openCount; i < openPlans.size(); i++) {
                    toDelete.add(openPlans[i]);
                }
            }
        }

        isSystemAdjusting = true;
        try {
            if (!toDelete.isEmpty()) paymentPlanRepository.deleteAll(toDelete);
            if (!toUpdate.isEmpty()) {
                List<SObject> sObjects = new List<SObject>();
                sObjects.addAll(toUpdate);
                List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(sObjects);
                if (!sanitizedUpdates.isEmpty()) {
                    paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitizedUpdates);
                }
                resetBypassFlags(toUpdate);
            }
            if (!toInsert.isEmpty()) {
                List<SObject> sObjects = new List<SObject>();
                sObjects.addAll(toInsert);
                List<SObject> sanitizedInserts = SecurityUtil.stripCreate(sObjects);
                if (!sanitizedInserts.isEmpty()) {
                    paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitizedInserts);
                }
            }
        } finally {
            isSystemAdjusting = false;
        }
    }

    /**
     * Trigger hook: validates edits before update.
     */
    public void beforeUpdate(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        if (newPlans == null || newPlans.isEmpty() || oldMap == null) return;
        enforceEditableTotals(newPlans, oldMap);
    }

    /**
     * Trigger hook: responds to status and amount changes after update.
     */
    public void handleAfterUpdate(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        if (newPlans == null || newPlans.isEmpty() || oldMap == null) return;
        if (isSystemAdjusting) return;

        Set<Id> loanIds = new Set<Id>();
        Boolean anyStatusChange = false;
        Boolean anyAmountChange = false;

        for (Payment_Plan__c plan : newPlans) {
            Payment_Plan__c oldPlan = oldMap.get(plan.Id);
            if (oldPlan == null) continue;

            if (plan.Payment_Status__c != oldPlan.Payment_Status__c) {
                anyStatusChange = true;
                loanIds.add(plan.Loan__c);
            }
            if (plan.Payment_Amount__c != oldPlan.Payment_Amount__c) {
                anyAmountChange = true;
                loanIds.add(plan.Loan__c);
            }
        }

        if (!loanIds.isEmpty() && anyStatusChange) {
            updateLoanStatuses(loanIds);
            sendFailedPaymentReminders(newPlans, oldMap);
        }

        if (!loanIds.isEmpty() && anyAmountChange) {
            adjustRemainingAmounts(loanIds, newPlans, oldMap);
        }
    }

    /**
     * Recomputes loan statuses from payment plan statuses.
     */
    private void updateLoanStatuses(Set<Id> loanIds) {
        List<Payment_Plan__c> plans = paymentPlanRepository.findByLoanIds(loanIds);
        Map<Id, List<Payment_Plan__c>> plansByLoan = new Map<Id, List<Payment_Plan__c>>();
        for (Payment_Plan__c plan : plans) {
            if (!plansByLoan.containsKey(plan.Loan__c)) {
                plansByLoan.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            plansByLoan.get(plan.Loan__c).add(plan);
        }

        List<Loan__c> toUpdate = new List<Loan__c>();
        for (Id loanId : plansByLoan.keySet()) {
            String status = paymentPlanDomain.determineLoanStatus(plansByLoan.get(loanId));
            toUpdate.add(new Loan__c(Id = loanId, Loan_Status__c = status));
        }

        if (!toUpdate.isEmpty()) {
            List<SObject> sObjects = new List<SObject>();
            sObjects.addAll(toUpdate);
            List<SObject> sanitized = SecurityUtil.stripUpdate(sObjects);
            if (!sanitized.isEmpty()) {
                LoanStatusContext.allowStatusUpdate = true;
                try {
                    loanRepository.saveAll((List<Loan__c>) sanitized);
                } finally {
                    LoanStatusContext.allowStatusUpdate = false;
                }
            }
            LoanEventPublisher.publishStatusChanges(toUpdate);
        }
    }

    /**
     * Sends borrower notifications when a payment plan transitions to Failed.
     */
    private void sendFailedPaymentReminders(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        Set<Id> loanIds = new Set<Id>();
        Map<Id, Payment_Plan__c> failedByLoan = new Map<Id, Payment_Plan__c>();

        for (Payment_Plan__c plan : newPlans) {
            Payment_Plan__c oldPlan = oldMap.get(plan.Id);
            if (oldPlan == null) continue;
            if (plan.Payment_Status__c == 'Failed' && oldPlan.Payment_Status__c != 'Failed') {
                loanIds.add(plan.Loan__c);
                failedByLoan.put(plan.Loan__c, plan);
            }
        }

        if (loanIds.isEmpty()) return;

        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>([
            SELECT Id, Account__c
            FROM Loan__c
            WHERE Id IN :loanIds
            WITH SECURITY_ENFORCED
        ]);

        Set<Id> accountIds = new Set<Id>();
        for (Loan__c loan : loanMap.values()) {
            if (loan.Account__c != null) accountIds.add(loan.Account__c);
        }
        if (accountIds.isEmpty()) return;

        Map<Id, Contact> contactByAccount = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, Email, FirstName, LastName, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
        ]) {
            if (contactByAccount.containsKey(c.AccountId)) continue;
            if (String.isBlank(c.Email)) continue;
            contactByAccount.put(c.AccountId, c);
        }

        for (Id loanId : failedByLoan.keySet()) {
            Loan__c loan = loanMap.get(loanId);
            if (loan == null) continue;
            Contact borrower = contactByAccount.get(loan.Account__c);
            if (borrower == null || String.isBlank(borrower.Email)) continue;

            Payment_Plan__c plan = failedByLoan.get(loanId);
            EmailService.sendMissedPaymentReminder(borrower.Email, borrower.FirstName + ' ' + borrower.LastName, plan);
        }
    }

    /**
     * Redistributes remaining balances across non-completed plans after manual edits.
     */
    private void adjustRemainingAmounts(Set<Id> loanIds, List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        List<Loan__c> loans = loanRepository.findAllById(loanIds);
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        List<Payment_Plan__c> allPlans = paymentPlanRepository.findByLoanIds(loanIds);

        Map<Id, Payment_Plan__c> newPlanMap = new Map<Id, Payment_Plan__c>();
        for (Payment_Plan__c plan : newPlans) {
            newPlanMap.put(plan.Id, plan);
        }

        Map<Id, List<Payment_Plan__c>> plansByLoan = new Map<Id, List<Payment_Plan__c>>();
        for (Payment_Plan__c plan : allPlans) {
            if (!plansByLoan.containsKey(plan.Loan__c)) {
                plansByLoan.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            plansByLoan.get(plan.Loan__c).add(plan);
        }

        List<Payment_Plan__c> toUpdate = new List<Payment_Plan__c>();

        for (Id loanId : plansByLoan.keySet()) {
            Loan__c loan = loanMap.get(loanId);
            if (loan == null) continue;

            Decimal total = loan.Principal_Plus_Interest__c == null
                ? loanDomain.recalculatePrincipalPlusInterest(loan)
                : loan.Principal_Plus_Interest__c;

            Decimal completedSum = 0;
            Decimal editedSum = 0;
            List<Payment_Plan__c> adjustable = new List<Payment_Plan__c>();

            for (Payment_Plan__c plan : plansByLoan.get(loanId)) {
                Payment_Plan__c current = newPlanMap.containsKey(plan.Id) ? newPlanMap.get(plan.Id) : plan;

                if (current.Payment_Status__c == 'Completed') {
                    if (current.Payment_Amount__c != null) completedSum += current.Payment_Amount__c;
                    continue;
                }

                Payment_Plan__c oldPlan = oldMap.get(current.Id);
                Boolean edited = oldPlan != null && current.Payment_Amount__c != oldPlan.Payment_Amount__c;

                if (edited) {
                    if (current.Payment_Amount__c != null) editedSum += current.Payment_Amount__c;
                } else {
                    adjustable.add(plan);
                }
            }

            Decimal remainingTotal = total - completedSum;
            if (remainingTotal < 0) remainingTotal = 0;
            Decimal adjustableTotal = remainingTotal - editedSum;
            if (adjustableTotal < 0) adjustableTotal = 0;

            List<Decimal> amounts = paymentPlanDomain.distributeAmounts(adjustableTotal, adjustable.size());
            for (Integer i = 0; i < adjustable.size(); i++) {
                Payment_Plan__c planToUpdate = adjustable[i];
                planToUpdate.Payment_Amount__c = amounts[i];
                planToUpdate.BYPASS__c = true;
                toUpdate.add(planToUpdate);
            }
        }

        if (!toUpdate.isEmpty()) {
            isSystemAdjusting = true;
            try {
                List<SObject> sObjects = new List<SObject>();
                sObjects.addAll(toUpdate);
                List<SObject> sanitizedUpdates = SecurityUtil.stripUpdate(sObjects);
                if (!sanitizedUpdates.isEmpty()) {
                    paymentPlanRepository.saveAll((List<Payment_Plan__c>) sanitizedUpdates);
                }
                resetBypassFlags(toUpdate);
            } finally {
                isSystemAdjusting = false;
            }
        }
    }

    public class LoanAdjustmentException extends Exception {}

    /**
     * Prevents manual edits that leave totals inconsistent with the remaining balance.
     */
    private void enforceEditableTotals(List<Payment_Plan__c> newPlans, Map<Id, Payment_Plan__c> oldMap) {
        if (isSystemAdjusting) return;
        Set<Id> loanIds = new Set<Id>();
        Map<Id, Payment_Plan__c> newPlanMap = new Map<Id, Payment_Plan__c>();

        for (Payment_Plan__c plan : newPlans) {
            newPlanMap.put(plan.Id, plan);
            Payment_Plan__c oldPlan = oldMap.get(plan.Id);
            if (oldPlan != null && plan.Payment_Amount__c != oldPlan.Payment_Amount__c) {
                loanIds.add(plan.Loan__c);
            }
        }

        if (loanIds.isEmpty()) return;

        List<Loan__c> loans = loanRepository.findAllById(loanIds);
        Map<Id, Loan__c> loanMap = new Map<Id, Loan__c>(loans);
        List<Payment_Plan__c> allPlans = paymentPlanRepository.findByLoanIds(loanIds);

        Map<Id, List<Payment_Plan__c>> plansByLoan = new Map<Id, List<Payment_Plan__c>>();
        for (Payment_Plan__c plan : allPlans) {
            if (!plansByLoan.containsKey(plan.Loan__c)) {
                plansByLoan.put(plan.Loan__c, new List<Payment_Plan__c>());
            }
            plansByLoan.get(plan.Loan__c).add(plan);
        }

        Map<Id, Decimal> invalidLoanTotals = new Map<Id, Decimal>();
        Map<Id, Decimal> overageLoanTotals = new Map<Id, Decimal>();
        for (Id loanId : plansByLoan.keySet()) {
            Loan__c loan = loanMap.get(loanId);
            if (loan == null) continue;

            Decimal total = loan.Principal_Plus_Interest__c == null ? 0 : loan.Principal_Plus_Interest__c;
            Decimal completedSum = 0;
            Decimal editedSum = 0;
            Integer adjustableCount = 0;

            for (Payment_Plan__c plan : plansByLoan.get(loanId)) {
                Payment_Plan__c current = newPlanMap.containsKey(plan.Id) ? newPlanMap.get(plan.Id) : plan;
                if (current.Payment_Status__c == 'Completed') {
                    if (current.Payment_Amount__c != null) completedSum += current.Payment_Amount__c;
                    continue;
                }

                Payment_Plan__c oldPlan = oldMap.get(current.Id);
                Boolean edited = oldPlan != null && current.Payment_Amount__c != oldPlan.Payment_Amount__c;
                if (edited) {
                    if (current.Payment_Amount__c != null) editedSum += current.Payment_Amount__c;
                } else {
                    adjustableCount++;
                }
            }

            Decimal remainingTotal = total - completedSum;
            if (remainingTotal < 0) remainingTotal = 0;
            Decimal diff = (remainingTotal - editedSum).abs();

            if (editedSum > remainingTotal + 0.01) {
                overageLoanTotals.put(loanId, remainingTotal.setScale(2, System.RoundingMode.HALF_UP));
                continue;
            }

            if (adjustableCount == 0 && diff > 0.01) {
                invalidLoanTotals.put(loanId, remainingTotal.setScale(2, System.RoundingMode.HALF_UP));
            }
        }

        if (invalidLoanTotals.isEmpty() && overageLoanTotals.isEmpty()) return;

        for (Payment_Plan__c plan : newPlans) {
            Payment_Plan__c oldPlan = oldMap.get(plan.Id);
            if (oldPlan == null) continue;
            if (plan.Payment_Amount__c == oldPlan.Payment_Amount__c) continue;

            if (overageLoanTotals.containsKey(plan.Loan__c)) {
                Decimal remainingTotal = overageLoanTotals.get(plan.Loan__c);
                plan.addError('Payment amounts must not exceed the remaining balance (' + remainingTotal + ').');
                continue;
            }

            if (invalidLoanTotals.containsKey(plan.Loan__c)) {
                Decimal remainingTotal = invalidLoanTotals.get(plan.Loan__c);
                plan.addError('Payment amounts must total the remaining balance (' + remainingTotal + ').');
            }
        }
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

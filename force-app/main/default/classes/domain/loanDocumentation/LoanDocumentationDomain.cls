/**
 * Domain logic for loan document requirements, completeness, and SLA.
 * Pure functions only: no SOQL/DML.
 */
public class LoanDocumentationDomain {
    public static final Integer DUE_SOON_DAYS = 2;
    public static final Integer ESCALATE_OVERDUE_DAYS = 3;

    public class LoanFacts {
        public Id loanId;
        public String loanType;
        public String loanStatus;
        public Decimal amount;
        public Date createdDate;
    }

    public class RequirementRule {
        public String documentType;
        public Boolean isRequired;
        public String appliesToLoanType;
        public Decimal minAmount;
        public Decimal maxAmount;
        public String loanStatus;
        public Integer dueDaysFromCreated;
        public String allowedMimeTypes;
        public Decimal maxSizeMb;
    }

    public class RequirementOutcome {
        public String documentType;
        public Boolean isRequired;
        public Date dueOn;
        public String allowedMimeTypes;
        public Decimal maxSizeMb;
    }

    /**
     * Resolves effective requirement rules for a specific loan.
     */
    public Map<String, RequirementOutcome> resolveEffectiveRequirements(
        LoanFacts loan,
        List<RequirementRule> rules
    ) {
        Map<String, RequirementOutcome> outcomesByType = new Map<String, RequirementOutcome>();
        if (loan == null || rules == null) return outcomesByType;

        for (RequirementRule rule : rules) {
            if (rule == null || String.isBlank(rule.documentType)) continue;
            if (!matchesLoan(rule, loan)) continue;

            String key = normalize(rule.documentType);
            RequirementOutcome existing = outcomesByType.get(key);
            RequirementOutcome candidate = new RequirementOutcome();
            candidate.documentType = rule.documentType;
            candidate.isRequired = rule.isRequired == true;
            candidate.dueOn = computeDueOn(loan.createdDate, rule.dueDaysFromCreated);
            candidate.allowedMimeTypes = rule.allowedMimeTypes;
            candidate.maxSizeMb = rule.maxSizeMb;

            if (existing == null) {
                outcomesByType.put(key, candidate);
            } else {
                RequirementOutcome merged = mergeOutcomes(existing, candidate);
                outcomesByType.put(key, merged);
            }
        }
        return outcomesByType;
    }

    /**
     * Computes missing required document types where completion requires Approved status.
     */
    public List<String> computeMissingRequired(
        Map<String, RequirementOutcome> requirementOutcomesByType,
        Map<String, String> latestStatusByType
    ) {
        List<String> missing = new List<String>();
        if (requirementOutcomesByType == null || requirementOutcomesByType.isEmpty()) return missing;

        Map<String, String> statuses = latestStatusByType == null ? new Map<String, String>() : latestStatusByType;
        for (String normalizedType : requirementOutcomesByType.keySet()) {
            RequirementOutcome outcome = requirementOutcomesByType.get(normalizedType);
            if (outcome == null || outcome.isRequired != true) continue;
            String latestStatus = statuses.get(normalizedType);
            if (normalize(latestStatus) != 'approved') {
                missing.add(outcome.documentType);
            }
        }
        missing.sort();
        return missing;
    }

    /**
     * Computes SLA state from due date and alert level.
     */
    public String computeSlaState(Date dueOn, Date today, Integer alertLevel) {
        if (dueOn == null) return 'Not_Due';
        Date baseline = today == null ? Date.today() : today;
        if (alertLevel != null && alertLevel > 0 && baseline > dueOn.addDays(ESCALATE_OVERDUE_DAYS)) {
            return 'Escalated';
        }
        if (baseline > dueOn) return 'Overdue';
        if (baseline.addDays(DUE_SOON_DAYS) >= dueOn) return 'Due_Soon';
        return 'Not_Due';
    }

    /**
     * Computes next alert timestamp for a 24h cadence.
     */
    public Datetime computeNextAlertOn(Datetime baseline) {
        Datetime point = baseline == null ? System.now() : baseline;
        return point.addHours(24);
    }

    public String normalize(String value) {
        if (String.isBlank(value)) return null;
        return value.trim().toLowerCase();
    }

    private Boolean matchesLoan(RequirementRule rule, LoanFacts loan) {
        if (rule == null || loan == null) return false;
        if (!String.isBlank(rule.appliesToLoanType) && normalize(rule.appliesToLoanType) != normalize(loan.loanType)) {
            return false;
        }
        if (!String.isBlank(rule.loanStatus) && normalize(rule.loanStatus) != normalize(loan.loanStatus)) {
            return false;
        }
        Decimal amount = loan.amount == null ? 0 : loan.amount;
        if (rule.minAmount != null && amount < rule.minAmount) return false;
        if (rule.maxAmount != null && amount > rule.maxAmount) return false;
        return true;
    }

    private Date computeDueOn(Date loanCreatedDate, Integer dueDaysFromCreated) {
        if (loanCreatedDate == null || dueDaysFromCreated == null) return null;
        return loanCreatedDate.addDays(dueDaysFromCreated);
    }

    private RequirementOutcome mergeOutcomes(RequirementOutcome a, RequirementOutcome b) {
        RequirementOutcome merged = new RequirementOutcome();
        merged.documentType = String.isBlank(a.documentType) ? b.documentType : a.documentType;
        merged.isRequired = (a.isRequired == true) || (b.isRequired == true);
        merged.dueOn = earliestDue(a.dueOn, b.dueOn);
        merged.allowedMimeTypes = chooseNonBlank(a.allowedMimeTypes, b.allowedMimeTypes);
        merged.maxSizeMb = smallestMax(a.maxSizeMb, b.maxSizeMb);
        return merged;
    }

    private Date earliestDue(Date a, Date b) {
        if (a == null) return b;
        if (b == null) return a;
        return a <= b ? a : b;
    }

    private String chooseNonBlank(String a, String b) {
        if (!String.isBlank(a)) return a;
        return b;
    }

    private Decimal smallestMax(Decimal a, Decimal b) {
        if (a == null) return b;
        if (b == null) return a;
        return a <= b ? a : b;
    }
}

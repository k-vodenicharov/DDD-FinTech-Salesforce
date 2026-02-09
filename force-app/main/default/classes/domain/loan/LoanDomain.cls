/**
 * Domain logic for loan validation and interest calculations.
 */
public class LoanDomain {
    public static final Integer MAX_SECURED_TERM = 6;
    public static final Integer MAX_UNSECURED_TERM = 12;

    /**
     * Validates loan term against secured/unsecured limits.
     */
    public Boolean validateLoanTerm(String loanType, Integer loanTerm) {
        if (loanTerm == null || loanTerm <= 0 || String.isBlank(loanType)) {
            return false;
        }
        // Normalize for case-insensitive comparisons.
        String normalized = loanType.trim().toLowerCase();
        if (normalized.contains('unsecured')) {
            return loanTerm <= MAX_UNSECURED_TERM;
        }
        if (normalized.contains('secured')) {
            return loanTerm <= MAX_SECURED_TERM;
        }
        return false;
    }

    /**
     * Builds a Loan__c instance from a loosely-typed map.
     */
    public Loan__c buildLoan(Map<String, Object> loanData) {
        Loan__c loan = new Loan__c();
        loan.Loan_Type__c = (String) loanData.get('Loan_Type__c');
        loan.Loan_Amount__c = parseDecimal(loanData.get('Loan_Amount__c'));
        loan.Loan_Term__c = parseInteger(loanData.get('Loan_Term__c'));
        loan.Interest_Rate__c = parseDecimal(loanData.get('Interest_Rate__c'));
        loan.Account__c = (Id) loanData.get('Account__c');

        loan.Loan_Status__c = 'Pending';
        loan.Name = 'Loan ' + loan.Loan_Type__c + ' - ' + loan.Loan_Amount__c;
        loan.Principal_Plus_Interest__c = calculatePrincipalPlusInterest(loan.Loan_Amount__c, loan.Interest_Rate__c);
        return loan;
    }

    /**
     * Converts a loosely typed value into Integer.
     */
    private Integer parseInteger(Object value) {
        if (value == null) return null;
        return Integer.valueOf(String.valueOf(value));
    }

    /**
     * Converts a loosely typed value into Decimal.
     */
    private Decimal parseDecimal(Object value) {
        if (value == null) return null;
        return Decimal.valueOf(String.valueOf(value));
    }

    /**
     * Calculates simple interest (principal + interest).
     */
    public Decimal calculatePrincipalPlusInterest(Decimal amount, Decimal rate) {
        Decimal interest = (amount == null || rate == null) ? 0 : (amount * rate / 100);
        return (amount == null ? 0 : amount) + interest;
    }

    /**
     * Recalculates principal+interest from a Loan__c record.
     */
    public Decimal recalculatePrincipalPlusInterest(Loan__c loan) {
        return calculatePrincipalPlusInterest(loan.Loan_Amount__c, loan.Interest_Rate__c);
    }

    /**
     * Summary: Calculates adjusted principal plus interest proportionally to months elapsed vs. original term.
     * Parameters:
     *  - loan: Loan__c — Loan record providing Loan_Amount__c, Interest_Rate__c, Loan_Term__c, CreatedDate.
     *  - prepaymentDate: Date — Effective date for calculation (defaults to today if null).
     * Returns: Decimal — Adjusted principal plus interest amount; zero when loan is null.
     * Notes: Ensures at least one elapsed month and one-month minimum original term. Uses simple interest scaled by term ratio.
     */
    public Decimal calculateAdjustedPrincipalPlusInterest(Loan__c loan, Date prepaymentDate) {
        if (loan == null) return 0;
        Date loanStart = (loan.CreatedDate == null) ? Date.today() : loan.CreatedDate.date();
        Date payDate = (prepaymentDate == null) ? Date.today() : prepaymentDate;

        Integer actualMonths = (payDate.year() * 12 + payDate.month()) - (loanStart.year() * 12 + loanStart.month());
        if (actualMonths < 1) actualMonths = 1;

        Integer originalTerm = (loan.Loan_Term__c == null) ? 1 : loan.Loan_Term__c.intValue();
        if (originalTerm < 1) originalTerm = 1;

        Decimal termRatio = Decimal.valueOf(actualMonths) / Decimal.valueOf(originalTerm);
        Decimal interest = (loan.Loan_Amount__c == null || loan.Interest_Rate__c == null)
            ? 0
            : (loan.Loan_Amount__c * loan.Interest_Rate__c / 100) * termRatio;

        return (loan.Loan_Amount__c == null ? 0 : loan.Loan_Amount__c) + interest;
    }
}

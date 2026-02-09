/**
 * Command-side application service for Loan__c writes.
 * Orchestrates validation, security checks, and persistence.
 */
public with sharing class LoanCommandService {
    private final LoanDomain loanDomain;
    private final ILoanRepository loanRepository;

    public LoanCommandService() {
        this.loanDomain = new LoanDomain();
        this.loanRepository = new LoanRepository();
    }

    /**
     * Creates a new loan from serialized input and applies business rules.
     */
    public ResponseWrapper createLoan(String loanData) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);
            Loan__c loan = loanDomain.buildLoan(data);

            Integer term = loan.Loan_Term__c == null ? 0 : loan.Loan_Term__c.intValue();
            if (!loanDomain.validateLoanTerm(loan.Loan_Type__c, term)) {
                response.isSuccess = false;
                response.errorMessage = buildLoanTermError(loan.Loan_Type__c);
                return response;
            }

            List<SObject> sanitized = SecurityUtil.stripCreate(new List<SObject>{ loan });
            if (sanitized.isEmpty()) {
                response.isSuccess = false;
                response.errorMessage = 'Insufficient access to create Loan.';
                return response;
            }
            Loan__c sanitizedLoan = (Loan__c) sanitized[0];
            loanRepository.save(sanitizedLoan);
            response.isSuccess = true;
            response.loanId = sanitizedLoan.Id;
        } catch (Exception e) {
            LoggingService.logError('LoanCommandService.createLoan', e);
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    /**
     * Updates loan term with validation and security checks.
     */
    public ResponseWrapper adjustLoanTerm(String loanId, Integer newLoanTerm) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            Loan__c loan = loanRepository.findById(loanId);
            if (loan == null) {
                response.isSuccess = false;
                response.errorMessage = 'Loan not found';
                return response;
            }

            if (!loanDomain.validateLoanTerm(loan.Loan_Type__c, newLoanTerm)) {
                response.isSuccess = false;
                response.errorMessage = buildLoanTermError(loan.Loan_Type__c);
                return response;
            }

            loan.Loan_Term__c = newLoanTerm;
            List<SObject> sanitized = SecurityUtil.stripUpdate(new List<SObject>{ loan });
            if (sanitized.isEmpty()) {
                response.isSuccess = false;
                response.errorMessage = 'Insufficient access to update Loan.';
                return response;
            }
            loanRepository.save((Loan__c) sanitized[0]);

            response.isSuccess = true;
            response.loanId = loan.Id;
        } catch (Exception e) {
            LoggingService.logError('LoanCommandService.adjustLoanTerm', e);
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    /**
     * Invocable-friendly overload for loan term adjustment.
     */
    public ResponseWrapper adjustLoanTerm(UpdateLoanTermRequest request) {
        if (request == null) {
            ResponseWrapper response = new ResponseWrapper();
            response.isSuccess = false;
            response.errorMessage = 'Request is required';
            return response;
        }
        return adjustLoanTerm((String) request.loanId, request.newTerm);
    }

    /**
     * Deletes a loan by Id when the current user has delete permission.
     */
    public ResponseWrapper deleteLoan(Id loanId) {
        ResponseWrapper response = new ResponseWrapper();
        if (loanId == null) {
            response.isSuccess = false;
            response.errorMessage = 'Loan Id is required';
            return response;
        }
        if (!Schema.SObjectType.Loan__c.isDeletable()) {
            response.isSuccess = false;
            response.errorMessage = 'Insufficient access to delete Loan.';
            return response;
        }
        try {
            Loan__c loan = loanRepository.findById(loanId);
            if (loan == null) {
                response.isSuccess = false;
                response.errorMessage = 'Loan not found';
                return response;
            }
            loanRepository.deleteRecord(loan);
            response.isSuccess = true;
            response.loanId = loanId;
        } catch (Exception e) {
            LoggingService.logError('LoanCommandService.deleteLoan', e);
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    /**
     * Trigger hook: applies defaults and validation before insert.
     */
    public void beforeInsert(List<Loan__c> newLoans) {
        if (newLoans == null) return;
        for (Loan__c loan : newLoans) {
            if (loan == null) continue;
            applyDefaultsAndValidate(loan, null);
        }
    }

    /**
     * Trigger hook: validates edits and enforces invariant rules before update.
     */
    public void beforeUpdate(List<Loan__c> newLoans, Map<Id, Loan__c> oldMap) {
        if (newLoans == null || oldMap == null) return;

        // Pre-calculate completed plan counts to prevent term reduction below completed payments.
        Map<Id, Integer> completedCounts = getCompletedPlanCounts(newLoans, oldMap);

        for (Loan__c loan : newLoans) {
            Loan__c oldLoan = oldMap.get(loan.Id);
            applyDefaultsAndValidate(loan, oldLoan);

            if (loan == null || oldLoan == null) continue;
            if (loan.Loan_Term__c == null) continue;

            Integer oldTerm = oldLoan.Loan_Term__c == null ? 0 : oldLoan.Loan_Term__c.intValue();
            Integer newTerm = loan.Loan_Term__c.intValue();
            if (newTerm < oldTerm) {
                Integer completed = completedCounts.containsKey(loan.Id) ? completedCounts.get(loan.Id) : 0;
                if (newTerm < completed) {
                    loan.addError('Loan term cannot be less than completed payment plans (' + completed + ').');
                }
            }
        }
    }

    private void applyDefaultsAndValidate(Loan__c loan, Loan__c oldLoan) {
        if (loan == null) return;

        // Enforce system-controlled status changes unless explicitly allowed by context.
        if (oldLoan != null && loan.Loan_Status__c != oldLoan.Loan_Status__c && !LoanStatusContext.allowStatusUpdate) {
            loan.addError('Loan Status is system-controlled and cannot be modified.');
            return;
        }

        if (oldLoan != null && oldLoan.Loan_Status__c == 'Closed') {
            Boolean anyChange =
                loan.Loan_Status__c != oldLoan.Loan_Status__c ||
                loan.Loan_Type__c != oldLoan.Loan_Type__c ||
                loan.Loan_Amount__c != oldLoan.Loan_Amount__c ||
                loan.Loan_Term__c != oldLoan.Loan_Term__c ||
                loan.Interest_Rate__c != oldLoan.Interest_Rate__c ||
                loan.Account__c != oldLoan.Account__c ||
                loan.Principal_Plus_Interest__c != oldLoan.Principal_Plus_Interest__c ||
                loan.Name != oldLoan.Name;

            if (anyChange) {
                loan.addError('Closed loans cannot be modified.');
                return;
            }
        }

        if (oldLoan == null) {
            loan.Loan_Status__c = 'Pending';
            if (String.isBlank(loan.Name)) {
                loan.Name = 'Loan ' + loan.Loan_Type__c + ' - ' + loan.Loan_Amount__c;
            }
        }

        if (loan.Loan_Amount__c == null || loan.Loan_Amount__c <= 0) {
            loan.addError('Loan Amount must be a positive number.');
        }

        if (loan.Interest_Rate__c == null || loan.Interest_Rate__c < 0) {
            loan.addError('Interest Rate must be a valid non-negative number.');
        }

        Integer term = loan.Loan_Term__c == null ? 0 : loan.Loan_Term__c.intValue();
        if (!loanDomain.validateLoanTerm(loan.Loan_Type__c, term)) {
            loan.addError(buildLoanTermError(loan.Loan_Type__c));
        }

        Boolean amountChanged = oldLoan == null || loan.Loan_Amount__c != oldLoan.Loan_Amount__c;
        Boolean rateChanged = oldLoan == null || loan.Interest_Rate__c != oldLoan.Interest_Rate__c;
        if (amountChanged || rateChanged || loan.Principal_Plus_Interest__c == null) {
            loan.Principal_Plus_Interest__c = loanDomain.recalculatePrincipalPlusInterest(loan);
        }
    }

    private Map<Id, Integer> getCompletedPlanCounts(List<Loan__c> newLoans, Map<Id, Loan__c> oldMap) {
        Set<Id> loanIds = new Set<Id>();
        for (Loan__c loan : newLoans) {
            Loan__c oldLoan = oldMap.get(loan.Id);
            if (loan == null || oldLoan == null) continue;
            Integer oldTerm = oldLoan.Loan_Term__c == null ? 0 : oldLoan.Loan_Term__c.intValue();
            Integer newTerm = loan.Loan_Term__c == null ? 0 : loan.Loan_Term__c.intValue();
            if (newTerm < oldTerm) {
                loanIds.add(loan.Id);
            }
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (loanIds.isEmpty()) return counts;

        for (AggregateResult ar : [
            SELECT Loan__c loanId, COUNT(Id) cnt
            FROM Payment_Plan__c
            WHERE Loan__c IN :loanIds AND Payment_Status__c = 'Completed'
            GROUP BY Loan__c
        ]) {
            counts.put((Id) ar.get('loanId'), (Integer) ar.get('cnt'));
        }
        return counts;
    }

    private String buildLoanTermError(String loanType) {
        if (!String.isBlank(loanType) && loanType.trim().toLowerCase().contains('unsecured')) {
            return 'Loan term exceeds maximum allowed for Unsecured loans (12 months).';
        }
        if (!String.isBlank(loanType) && loanType.trim().toLowerCase().contains('secured')) {
            return 'Loan term exceeds maximum allowed for Secured loans (6 months).';
        }
        return 'Loan term exceeds maximum allowed for the selected loan type.';
    }
}

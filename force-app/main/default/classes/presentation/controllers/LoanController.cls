/**
 * Aura-enabled controller for loan operations.
 */
global with sharing class LoanController {

    /** Updates loan term via command service. */
    @AuraEnabled
    public static ResponseWrapper adjustLoanTerm(String loanId, Integer newLoanTerm) {
        LoanCommandService service = new LoanCommandService();
        UpdateLoanTermRequest req = new UpdateLoanTermRequest();
        req.newTerm = newLoanTerm;
        try {
            req.loanId = (Id) loanId;
        } catch (Exception e) {
            ResponseWrapper response = new ResponseWrapper();
            response.isSuccess = false;
            response.errorMessage = 'Loan not found';
            return response;
        }
        return service.adjustLoanTerm(req);
    }

    /** Creates a loan synchronously. */
    @AuraEnabled
    global static ResponseWrapper createLoanApex(String loanData) {
        LoanCommandService service = new LoanCommandService();
        return service.createLoan(loanData);
    }

    /** Enqueues async loan creation. */
    @AuraEnabled
    public static ResponseWrapper createLoanAsync(String loanData) {
        ResponseWrapper response = new ResponseWrapper();
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);
            Id jobId = System.enqueueJob(new LoanQueueable(data));
            response.isSuccess = true;
            response.jobId = String.valueOf(jobId);
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    /** Processes prepayment for a loan. */
    @AuraEnabled
    public static ResponseWrapper prepayLoanApex(Id loanId) {
        PrepayLoanCommandService service = new PrepayLoanCommandService();
        return service.prepayLoan(loanId);
    }

    /** Deletes a loan by Id. */
    @AuraEnabled
    public static ResponseWrapper deleteLoanApex(Id loanId) {
        LoanCommandService service = new LoanCommandService();
        return service.deleteLoan(loanId);
    }

    /** Returns loans for an account for list rendering. */
    @AuraEnabled(cacheable=true)
    public static List<LoanListItem> getLoansByAccount(Id accountId) {
        if (accountId == null) return new List<LoanListItem>();

        LoanQueryService queryService = new LoanQueryService();
        List<Loan__c> loans = queryService.getLoansByAccountId(accountId);

        List<SObject> sobs = new List<SObject>();
        sobs.addAll(loans);
        List<SObject> sanitized = SecurityUtil.stripRead(sobs);
        List<LoanListItem> items = new List<LoanListItem>();
        for (SObject sob : sanitized) {
            Loan__c loan = (Loan__c) sob;
            LoanListItem item = new LoanListItem();
            item.id = loan.Id;
            item.name = loan.Name;
            item.status = loan.Loan_Status__c;
            item.amount = loan.Loan_Amount__c;
            item.term = loan.Loan_Term__c;
            item.rate = loan.Interest_Rate__c;
            item.created = loan.CreatedDate;
            items.add(item);
        }
        return items;
    }

    /** Lightweight DTO for UI consumption. */
    public class LoanListItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal term;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Datetime created;
    }
}

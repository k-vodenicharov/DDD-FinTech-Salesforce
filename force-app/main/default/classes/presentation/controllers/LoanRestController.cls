/**
 * REST controller for loan adjustments.
 */
@RestResource(urlMapping='/loan')
global with sharing class LoanRestController {
    /** Adjusts loan term via REST. */
    @HttpPatch
    global static ResponseWrapper adjustLoanTerm(String loanId, Integer newLoanTerm) {
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
}

@RestResource(urlMapping='/loan')
global with sharing class LoanController {
    
    /**
		*Http POST method to create new loan
		*Accepts loan data as JSON and returns reponse wrapper
    */

    @HttpPost
    global static ResponseWrapper createLoan(String loanData) {
        LoanService service = new LoanService();
        return service.createLoan(loanData);
    }

    global class ResponseWrapper {
        public Boolean isSuccess;
        public String errorMessage;
        public String loanId;
    }
}
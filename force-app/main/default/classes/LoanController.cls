@RestResource(urlMapping='/loan')
global with sharing class LoanController {

    @HttpPost
    global static ResponseWrapper createLoan(String loanData) {
        ResponseWrapper response = new ResponseWrapper();
        
        try {
            System.debug('Received loanData: ' + loanData);
            
            // Deserialize the JSON data from the request
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(loanData);

            // Extract fields from deserialized data
            String loanType = (String) data.get('Loan_Type__c');
            Decimal loanAmount = (Decimal) data.get('Loan_Amount__c');
            Integer loanTerm = (Integer) data.get('Loan_Term__c');
            Decimal interestRate = (Decimal) data.get('Interest_Rate__c');
            String loanStatus = (String) data.get('Loan_Status__c');
            String accountId = (String) data.get('Account__c');

            // Validate required fields
            if (loanType == null || loanAmount == null || loanTerm == null || interestRate == null || loanStatus == null || accountId == null) {
                response.isSuccess = false;
                response.errorMessage = 'Missing required fields.';
                return response;
            }

            // Validate loan term based on loan type
            if (loanType == 'Secured' && loanTerm > 6) {
                response.isSuccess = false;
                response.errorMessage = 'Loan term exceeds maximum allowed value for Secured loans (6 months).';
                return response;
            } else if (loanType == 'Unsecured' && loanTerm > 12) {
                response.isSuccess = false;
                response.errorMessage = 'Loan term exceeds maximum allowed value for Unsecured loans (12 months).';
                return response;
            }

            // Calculate Principal Plus Interest (Loan Amount + Interest)
            Decimal interestAmount = (loanAmount * interestRate) / 100;
            Decimal principalPlusInterest = loanAmount + interestAmount;

            // Create a new Loan__c record
            Loan__c newLoan = new Loan__c();
            newLoan.Loan_Type__c = loanType;
            newLoan.Loan_Amount__c = loanAmount;
            newLoan.Loan_Term__c = loanTerm;
            newLoan.Interest_Rate__c = interestRate;
            newLoan.Loan_Status__c = loanStatus;
            newLoan.Account__c = accountId;
            newLoan.Principal_Plus_Interest__c = principalPlusInterest; // Set the calculated value

            // Insert the new Loan__c record
            insert newLoan;

            // Return a successful response with loan ID
            response.isSuccess = true;
            response.loanId = newLoan.Id;
            System.debug('Loan created with ID: ' + newLoan.Id);
        } catch (Exception e) {
            // Catch any exceptions and return an error message
            response.isSuccess = false;
            response.errorMessage = e.getMessage();
            System.debug('Error: ' + e.getMessage());
        }

        return response;
    }

    global class ResponseWrapper {
        public Boolean isSuccess;
        public String errorMessage;
        public String loanId;
    }
}
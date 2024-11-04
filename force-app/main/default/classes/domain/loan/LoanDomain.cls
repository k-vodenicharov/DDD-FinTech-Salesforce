public class LoanDomain {
    public static Loan__c createLoan(Map<String, Object> loanData) {
        
        // Extract and typecast each value
        String loanType = (String) loanData.get('Loan_Type__c');
        Decimal loanAmount = (Decimal) loanData.get('Loan_Amount__c');
        Integer loanTerm = (Integer) loanData.get('Loan_Term__c');
        Decimal interestRate = (Decimal) loanData.get('Interest_Rate__c');
        String loanStatus = (String) loanData.get('Loan_Status__c');
        String accountId = (String) loanData.get('Account__c');
        
        // Validation to check for required fields
        if (loanType == null || loanAmount == null || loanTerm == null || interestRate == null || loanStatus == null || accountId == null) {
            throw new IllegalArgumentException('Missing required fields.');
        }
        
        // Maximum loan term based on loan type
        if (loanType == 'Secured' && loanTerm > 6) {
            throw new IllegalArgumentException('Loan term exceeds maximum allowed value for Secured loans (6 months).');
        } else if (loanType == 'Unsecured' && loanTerm > 12) {
            throw new IllegalArgumentException('Loan term exceeds maximum allowed value for Unsecured loans (12 months).');
        }

        // Calculate Principal Plus Interest
        Decimal interestAmount = (loanAmount * interestRate) / 100;
        Decimal principalPlusInterest = loanAmount + interestAmount;

        Loan__c newLoan = new Loan__c();
        newLoan.Loan_Type__c = loanType;
        newLoan.Loan_Amount__c = loanAmount;
        newLoan.Loan_Term__c = loanTerm;
        newLoan.Interest_Rate__c = interestRate;
        newLoan.Loan_Status__c = loanStatus;
        newLoan.Account__c = accountId;
        newLoan.Principal_Plus_Interest__c = principalPlusInterest;

        return newLoan;
    }
}
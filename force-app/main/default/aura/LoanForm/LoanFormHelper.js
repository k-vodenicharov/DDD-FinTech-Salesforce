({
    saveLoanRecord: function(component) {
        // Fetch the loan data from component attributes
        var loanData = {
            Loan_Type__c: component.get("v.loanType"),
            Loan_Amount__c: component.get("v.loanAmount"),
            Loan_Term__c: component.get("v.loanTerm"),
            Interest_Rate__c: component.get("v.interestRate"),
            Loan_Status__c: component.get("v.loanStatus"),
            Account__c: component.get("v.accountId") // Ensure this field is populated correctly
        };

        // Convert the loan data to JSON string
        var loanDataJson = JSON.stringify(loanData);
        console.log('Loan Data JSON:', loanDataJson);

        // Call the Apex method
        var action = component.get("c.createLoanApex");
        action.setParams({
            loanData: loanDataJson
        });

        // Define the callback
        action.setCallback(this, function(response) {
            var state = response.getState();
            console.log('State:', state);
            console.log('Response:', response.getReturnValue());

            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                if (result.isSuccess) {
                    // Loan record created successfully
                    alert('Loan created successfully. Loan ID: ' + result.loanId);
                } else {
                    // Handle error from Apex response
                    alert('Error: ' + result.errorMessage);
                    console.log('Apex Error Message:', result.errorMessage);
                }
            } else if (state === "ERROR") {
                // Get error details from response
                var errors = response.getError();
                if (errors && errors[0] && errors[0].message) {
                    alert('Error: ' + errors[0].message);
                    console.log('Error details:', errors[0].message);
                } else {
                    alert('Unknown error');
                    console.log('Unknown error occurred');
                }
            }
        });

        // Enqueue the action
        $A.enqueueAction(action);
    }
})
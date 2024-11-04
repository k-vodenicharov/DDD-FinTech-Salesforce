({
    saveLoan: function (component, event, helper) {
        try {
            // Fetch form field values
            var loanType = component.get("v.loanType");
            var loanAmount = parseFloat(component.get("v.loanAmount"));
            var loanTerm = parseInt(component.get("v.loanTerm"), 10);
            var interestRate = parseFloat(component.get("v.interestRate"));
            var loanStatus = component.get("v.loanStatus");
            var accountId = component.get("v.recordId");

            // Validate loan term based on loan type
            var maxLoanTerm;
            if (loanType === 'Secured') {
                maxLoanTerm = 6;
            } else if (loanType === 'Unsecured') {
                maxLoanTerm = 12;
            } else {
                maxLoanTerm = null; // No restrictions for other loan types
            }

            if (maxLoanTerm !== null && loanTerm > maxLoanTerm) {
                // Set error message and return without saving the loan
                component.set("v.errorMessage", "Loan term exceeds maximum allowed value for " + loanType + " loans (" + maxLoanTerm + " months).");
                return;
            }

            // Clear any existing error messages
            component.set("v.errorMessage", "");

            // Prepare loan data for saving
            var loanData = {
                Loan_Type__c: loanType,
                Loan_Amount__c: loanAmount,
                Loan_Term__c: loanTerm,
                Interest_Rate__c: interestRate,
                Loan_Status__c: loanStatus,
                Account__c: accountId
            };

            // Call Apex controller method
            var action = component.get("c.createLoanApex");
            action.setParams({
                loanData: JSON.stringify(loanData)
            });

            // Handle the callback
            action.setCallback(this, function (response) {
                var state = response.getState();
                if (state === "SUCCESS") {
                    var responseValue = response.getReturnValue();
                    if (responseValue.isSuccess) {
                        console.log('Loan created successfully with ID: ' + responseValue.loanId);

                        // Refresh the Account record view to reflect the new loan in the related list
                        var refreshEvent = $A.get("e.force:refreshView");
                        if (refreshEvent) {
                            refreshEvent.fire(); // This will refresh the whole view
                        }

                    } else {
                        // Display the error message from the server
                        component.set("v.errorMessage", responseValue.errorMessage);
                    }
                } else if (state === "ERROR") {
                    var errors = response.getError();
                    if (errors && errors[0] && errors[0].message) {
                        component.set("v.errorMessage", errors[0].message);
                    } else {
                        component.set("v.errorMessage", "An unknown error occurred.");
                    }
                }
            });

            // Enqueue the action to send to the server
            $A.enqueueAction(action);

        } catch (error) {
            component.set("v.errorMessage", "An error occurred: " + error.message);
        }
    }
})
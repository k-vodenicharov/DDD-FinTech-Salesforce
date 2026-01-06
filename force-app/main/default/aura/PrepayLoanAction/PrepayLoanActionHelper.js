({
    runPrepay: function (component) {
        component.set("v.isProcessing", true);
        component.set("v.errorMessage", "");

        var action = component.get("c.prepayLoanApex");
        action.setParams({
            loanId: component.get("v.recordId")
        });

        action.setCallback(this, function (response) {
            component.set("v.isProcessing", false);
            var state = response.getState();
            if (state === "SUCCESS") {
                var res = response.getReturnValue();
                if (res && res.success) {
                    var toast = $A.get("e.force:showToast");
                    if (toast) {
                        toast.setParams({
                            title: "Success",
                            message: res.message || "Loan prepaid successfully.",
                            type: "success",
                            mode: "dismissible"
                        });
                        toast.fire();
                    }
                    var refresh = $A.get("e.force:refreshView");
                    if (refresh) {
                        refresh.fire();
                    }
                    var close = $A.get("e.force:closeQuickAction");
                    if (close) {
                        close.fire();
                    }
                } else {
                    component.set("v.errorMessage", (res && res.error) ? res.error : "Prepayment failed.");
                }
            } else {
                var errors = response.getError();
                var msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unknown error during prepayment.";
                component.set("v.errorMessage", msg);
            }
        });

        $A.enqueueAction(action);
    }
})

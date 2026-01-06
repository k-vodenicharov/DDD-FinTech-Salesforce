({
    handleInit: function (component, event, helper) {
        // Do nothing on init; wait for user confirm
    },

    handlePrepay: function (component, event, helper) {
        helper.runPrepay(component);
    },

    handleCancel: function (component, event, helper) {
        var closeAction = $A.get("e.force:closeQuickAction");
        if (closeAction) {
            closeAction.fire();
        }

        // Also try to navigate back if opened as override
        var navService = component.find("navService");
        if (navService) {
        }
    }
})

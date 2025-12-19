public class BeforePaymentPlanUpdateHandler {
    
    /**
     * Handles before update logic for Payment_Plan__c records.
     * Ensures that when a user manually edits a Payment_Plan__c.Payment_Amount__c,
     * the total of all Payment_Plan__c records for the same loan equals the loan's Principal_Plus_Interest__c.
     * Distributes the difference evenly among remaining open plans.
     */
    public static void handleBeforeUpdate(List<Payment_Plan__c> newPlans, List<Payment_Plan__c> oldPlans) {
        // Map to hold loan IDs and their associated payment plans
        Map<Id, List<Payment_Plan__c>> loanPlansMap = new Map<Id, List<Payment_Plan__c>>();
        
        // Get all unique loan IDs from the updated plans
        Set<Id> loanIds = new Set<Id>();
        for (Payment_Plan__c plan : newPlans) {
            if (plan.Loan__c != null) {
                loanIds.add(plan.Loan__c);
            }
        }
        
        // Query all payment plans for these loans to calculate totals
        if (!loanIds.isEmpty()) {
            Map<Id, Decimal> loanTotalsMap = new Map<Id, Decimal>();
            
            // First, fetch the Principal_Plus_Interest__c for each loan
            for (Loan__c loan : [
                SELECT Id, Principal_Plus_Interest__c
                FROM Loan__c
                WHERE Id IN :loanIds
            ]) {
                loanTotalsMap.put(loan.Id, loan.Principal_Plus_Interest__c);
            }
            
            // Now, collect all payment plans for these loans
            List<Payment_Plan__c> allPlansForLoans = [
                SELECT Id, Loan__c, Payment_Amount__c, Payment_Status__c
                FROM Payment_Plan__c
                WHERE Loan__c IN :loanIds
                ORDER BY Id
            ];
            
            // Group plans by loan
            for (Payment_Plan__c plan : allPlansForLoans) {
                if (!loanPlansMap.containsKey(plan.Loan__c)) {
                    loanPlansMap.put(plan.Loan__c, new List<Payment_Plan__c>());
                }
                loanPlansMap.get(plan.Loan__c).add(plan);
            }
            
            // Process each loan's payment plans
            for (Id loanId : loanPlansMap.keySet()) {
                List<Payment_Plan__c> plans = loanPlansMap.get(loanId);
                Decimal totalAmount = loanTotalsMap.get(loanId);
                
                // Calculate current total of all plans for this loan
                Decimal currentTotal = 0;
                for (Payment_Plan__c plan : plans) {
                    currentTotal += plan.Payment_Amount__c;
                }
                
                // If the total is already correct, no adjustment needed
                if (Math.abs(currentTotal - totalAmount) < 0.01) {
                    continue;
                }
                
                // Identify which plans are not yet completed (eligible for adjustment)
                List<Payment_Plan__c> adjustablePlans = new List<Payment_Plan__c>();
                for (Payment_Plan__c plan : plans) {
                    if (plan.Payment_Status__c != 'Completed') {
                        adjustablePlans.add(plan);
                    }
                }
                
                // If there are no adjustable plans, skip adjustment
                if (adjustablePlans.isEmpty()) {
                    continue;
                }
                
                // Calculate the difference
                Decimal difference = totalAmount - currentTotal;
                
                // Distribute the difference evenly among adjustable plans
                Decimal distribution = difference / adjustablePlans.size();
                
                // Apply the distribution to each adjustable plan
                for (Payment_Plan__c plan : adjustablePlans) {
                    plan.Payment_Amount__c += distribution;
                }
            }
        }
    }
}

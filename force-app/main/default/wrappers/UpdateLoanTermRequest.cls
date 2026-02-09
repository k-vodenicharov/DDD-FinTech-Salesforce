/**
 * Invocable request wrapper for loan term adjustments.
 */
public class UpdateLoanTermRequest {
    @InvocableVariable(required=true)
    public Id loanId;

    @InvocableVariable(required=true)
    public Integer newTerm;
}

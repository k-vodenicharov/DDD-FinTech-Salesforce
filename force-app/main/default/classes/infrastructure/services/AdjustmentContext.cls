/**
 * Context flag to avoid double-queueing adjustments when invoked directly.
 */
public class AdjustmentContext {
    public static Boolean skipQueueable = false;
}

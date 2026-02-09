/**
 * Minimal logging wrapper for consistent error reporting.
 */
public class LoggingService {
    /** Logs an exception with context. */
    public static void logError(String context, Exception ex) {
        String msg = (ex == null) ? 'Unknown error' : ex.getMessage();
        System.debug(LoggingLevel.ERROR, context + ': ' + msg);
    }

    /** Logs a message with context. */
    public static void logError(String context, String message) {
        System.debug(LoggingLevel.ERROR, context + ': ' + message);
    }
}

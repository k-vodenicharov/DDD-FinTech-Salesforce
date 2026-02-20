/**
 * Trigger handler for ContentDocumentLink lifecycle events.
 */
public class ContentDocumentLinkTriggerHandler {
    private static Boolean isRunning = false;

    public static void afterInsert(List<ContentDocumentLink> newLinks) {
        if (isRunning) return;
        isRunning = true;
        try {
            LoanDocumentCommandService service = new LoanDocumentCommandService();
            service.syncFromContentDocumentLinks(newLinks);
        } finally {
            isRunning = false;
        }
    }
}

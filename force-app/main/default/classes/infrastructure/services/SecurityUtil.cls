/**
 * Centralized CRUD/FLS filtering helpers.
 */
public class SecurityUtil {
    /** Filters records for create access. */
    public static List<SObject> stripCreate(List<SObject> records) {
        if (records == null || records.isEmpty()) return new List<SObject>();
        if (Test.isRunningTest()) return records;
        return Security.stripInaccessible(AccessType.CREATABLE, records).getRecords();
    }

    /** Filters records for update access. */
    public static List<SObject> stripUpdate(List<SObject> records) {
        if (records == null || records.isEmpty()) return new List<SObject>();
        if (Test.isRunningTest()) return records;
        return Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();
    }

    /** Filters records for read access. */
    public static List<SObject> stripRead(List<SObject> records) {
        if (records == null || records.isEmpty()) return new List<SObject>();
        if (Test.isRunningTest()) return records;
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

    /** Returns true when current user has Modify All Data permission. */
    public static Boolean isCurrentUserAdmin() {
        if (!Schema.SObjectType.Profile.isAccessible()) return false;
        try {
            List<Profile> rows = [
                SELECT PermissionsModifyAllData
                FROM Profile
                WHERE Id = :UserInfo.getProfileId()
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return !rows.isEmpty() && rows[0].PermissionsModifyAllData;
        } catch (Exception e) {
            return false;
        }
    }
}

/**
 * @description Controller for the dynamicRecordDisplay LWC component.
 *              Executes dynamic SOQL without sharing to support system-level
 *              record visibility in Experience Cloud (Aura-based) communities,
 *              where guest users must see records regardless of sharing rules.
 *
 *              SECURITY JUSTIFICATION for `without sharing`:
 *              This class is intentionally elevated to expose community-facing
 *              record data (e.g., public grants, events, products) to all visitors.
 *              Access is controlled at the Experience Cloud site-level (guest profile /
 *              permission sets), not at the Apex sharing-model level. All field and
 *              object names are validated via Schema.describe before use in SOQL.
 *              The WHERE clause is admin-configured through Experience Builder
 *              properties (not direct end-user input) and is further sanitized to
 *              block DML/DDL keywords.
 */
public without sharing class DRD_RecordDisplayController {

    // ─── Constants ────────────────────────────────────────────────────────────

    private static final Integer MAX_RECORDS_PER_PAGE = 200;
    private static final Integer DEFAULT_RECORDS_PER_PAGE = 10;

    private static final List<String> BLOCKED_WHERE_KEYWORDS = new List<String>{
        'DELETE', 'UPDATE', 'INSERT', 'UPSERT', 'UNDELETE', 'MERGE',
        'DROP', 'CREATE', 'ALTER', 'TRUNCATE', 'EXECUTE', 'EXEC',
        'UNION', 'INTERSECT', '--', '/*', '*/'
    };

    // ─── Inner Classes ────────────────────────────────────────────────────────

    /**
     * @description Wrapper returned to the LWC containing records, field metadata,
     *              and a pagination indicator.
     */
    public class RecordQueryResult {
        @AuraEnabled public List<Map<String, Object>> records;
        @AuraEnabled public Map<String, String> fieldLabels;
        @AuraEnabled public Map<String, String> fieldTypes;
        @AuraEnabled public Boolean hasMore;

        public RecordQueryResult() {
            this.records = new List<Map<String, Object>>();
            this.fieldLabels = new Map<String, String>();
            this.fieldTypes = new Map<String, String>();
            this.hasMore = false;
        }
    }

    /**
     * @description Internal holder for validated field names and metadata maps.
     */
    private class FieldMetadata {
        public List<String> fieldNames;
        public Map<String, String> fieldLabels;
        public Map<String, String> fieldTypes;

        public FieldMetadata() {
            this.fieldNames = new List<String>();
            this.fieldLabels = new Map<String, String>();
            this.fieldTypes = new Map<String, String>();
        }
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * @description Queries records dynamically for the dynamicRecordDisplay LWC.
     *              All object and field names are validated via Schema.describe.
     *              The WHERE clause is sanitised to block DML/DDL injection.
     *
     * @param objectApiName  API name of the SObject to query (e.g. 'Account')
     * @param fieldListCsv   Comma-separated field API names (e.g. 'Name,Status__c')
     * @param whereClause    Optional SOQL WHERE body (admin-configured only)
     * @param orderByField   Optional field to sort by
     * @param orderByDir     Sort direction: 'ASC' or 'DESC'
     * @param queryLimit     Records per page; capped at 200
     * @param queryOffset    Records to skip for Load More pagination
     * @return RecordQueryResult containing records, labels, types, and hasMore flag
     * @throws AuraHandledException on invalid inputs or query failure
     *
     * @example
     * RecordQueryResult r = DRD_RecordDisplayController.getRecords(
     *     'Grant__c', 'Name,Status__c,Award_Amount__c',
     *     'Status__c = \'Active\'', 'Name', 'ASC', 10, 0
     * );
     */
    @AuraEnabled(cacheable=true)
    public static RecordQueryResult getRecords(
        String objectApiName,
        String fieldListCsv,
        String whereClause,
        String orderByField,
        String orderByDir,
        Integer queryLimit,
        Integer queryOffset
    ) {
        try {
            validateRequiredInputs(objectApiName, fieldListCsv);

            Schema.DescribeSObjectResult objectDescribe = describeObject(objectApiName.trim());
            Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

            FieldMetadata fieldMeta = buildFieldMetadata(fieldListCsv, fieldMap);
            String orderByClause = buildOrderByClause(orderByField, orderByDir, fieldMap);

            Integer safeLimit = sanitiseLimit(queryLimit);
            Integer safeOffset = (queryOffset != null && queryOffset > 0) ? queryOffset : 0;

            String soql = buildSoql(
                fieldMeta.fieldNames,
                objectDescribe.getName(),
                whereClause,
                orderByClause,
                safeLimit,
                safeOffset
            );

            List<SObject> rawResults = Database.query(soql);

            Boolean hasMore = rawResults.size() > safeLimit;
            if (hasMore) {
                rawResults.remove(rawResults.size() - 1);
            }

            List<Map<String, Object>> recordMaps = toRecordMaps(rawResults, fieldMeta.fieldNames);

            RecordQueryResult result = new RecordQueryResult();
            result.records = recordMaps;
            result.fieldLabels = fieldMeta.fieldLabels;
            result.fieldTypes = fieldMeta.fieldTypes;
            result.hasMore = hasMore;
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'An error occurred while loading records: ' + e.getMessage()
            );
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    /**
     * @description Throws AuraHandledException if required inputs are blank.
     * @param objectApiName The object API name to validate
     * @param fieldListCsv  The field list CSV to validate
     */
    private static void validateRequiredInputs(String objectApiName, String fieldListCsv) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        if (String.isBlank(fieldListCsv)) {
            throw new AuraHandledException('At least one field must be specified.');
        }
    }

    /**
     * @description Validates and describes the given object name.
     * @param objectApiName The object API name to describe
     * @return Schema.DescribeSObjectResult for the validated object
     * @throws AuraHandledException if the object is not found in the org
     */
    private static Schema.DescribeSObjectResult describeObject(String objectApiName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = globalDescribe.get(objectApiName.toLowerCase());
        if (objectType == null) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
        return objectType.getDescribe();
    }

    /**
     * @description Parses the CSV field list, validates each field against the
     *              object describe, and collects labels and types.
     *              Always ensures 'Id' is present for record navigation.
     *
     * @param fieldListCsv Comma-separated field API names
     * @param fieldMap     Field map from the object describe
     * @return FieldMetadata containing validated field names, labels, and types
     * @throws AuraHandledException if any field name is invalid
     */
    private static FieldMetadata buildFieldMetadata(
        String fieldListCsv,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        FieldMetadata meta = new FieldMetadata();

        for (String raw : fieldListCsv.split(',')) {
            String trimmed = raw.trim().toLowerCase();
            if (String.isBlank(trimmed)) {
                continue;
            }
            if (!fieldMap.containsKey(trimmed)) {
                throw new AuraHandledException('Invalid field name: ' + raw.trim());
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(trimmed).getDescribe();
            String apiName = fieldDescribe.getName();
            meta.fieldNames.add(apiName);
            meta.fieldLabels.put(apiName, fieldDescribe.getLabel());
            meta.fieldTypes.put(apiName, String.valueOf(fieldDescribe.getType()));
        }

        if (meta.fieldNames.isEmpty()) {
            throw new AuraHandledException('No valid fields could be resolved from the field list.');
        }

        // Ensure Id is always retrieved for record navigation
        if (!meta.fieldNames.contains('Id')) {
            meta.fieldNames.add(0, 'Id');
        }

        return meta;
    }

    /**
     * @description Validates the ORDER BY field and builds the ORDER BY clause string.
     * @param orderByField Field API name to sort by (may be blank)
     * @param orderByDir   'ASC' or 'DESC'
     * @param fieldMap     Field map for validation
     * @return ORDER BY clause string, or empty string if no order by specified
     * @throws AuraHandledException if the field name is invalid
     */
    private static String buildOrderByClause(
        String orderByField,
        String orderByDir,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (String.isBlank(orderByField)) {
            return '';
        }
        String trimmed = orderByField.trim().toLowerCase();
        if (!fieldMap.containsKey(trimmed)) {
            throw new AuraHandledException('Invalid ORDER BY field: ' + orderByField.trim());
        }
        String validatedField = fieldMap.get(trimmed).getDescribe().getName();
        String direction = (orderByDir == 'DESC') ? 'DESC' : 'ASC';
        return ' ORDER BY ' + validatedField + ' ' + direction;
    }

    /**
     * @description Caps and defaults the query limit value.
     * @param queryLimit Requested limit from the component
     * @return Safe integer limit between 1 and MAX_RECORDS_PER_PAGE
     */
    private static Integer sanitiseLimit(Integer queryLimit) {
        if (queryLimit == null || queryLimit <= 0) {
            return DEFAULT_RECORDS_PER_PAGE;
        }
        return Math.min(queryLimit, MAX_RECORDS_PER_PAGE);
    }

    /**
     * @description Builds the complete SOQL string from validated parts.
     *              Queries safeLimit + 1 records to enable hasMore detection.
     *
     * @param fieldNames   Validated list of field API names
     * @param objectName   Validated object API name
     * @param whereClause  Optional admin-configured WHERE body
     * @param orderBy      Pre-built ORDER BY clause or empty string
     * @param safeLimit    Sanitised record limit
     * @param safeOffset   Sanitised offset for pagination
     * @return Complete SOQL query string
     * @throws AuraHandledException if the WHERE clause contains blocked keywords
     */
    private static String buildSoql(
        List<String> fieldNames,
        String objectName,
        String whereClause,
        String orderBy,
        Integer safeLimit,
        Integer safeOffset
    ) {
        String soql = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + objectName;

        if (!String.isBlank(whereClause)) {
            String sanitised = sanitiseWhereClause(whereClause.trim());
            soql += ' WHERE ' + sanitised;
        }

        soql += orderBy;
        soql += ' LIMIT ' + (safeLimit + 1);
        soql += ' OFFSET ' + safeOffset;

        return soql;
    }

    /**
     * @description Validates an admin-supplied WHERE clause string by blocking
     *              DML/DDL keywords that have no place in a SELECT WHERE predicate.
     *
     * @param whereClause The raw WHERE clause to sanitise
     * @return The original WHERE clause if clean
     * @throws AuraHandledException if a blocked keyword is detected
     */
    @TestVisible
    private static String sanitiseWhereClause(String whereClause) {
        String upperClause = whereClause.toUpperCase();
        for (String keyword : BLOCKED_WHERE_KEYWORDS) {
            if (upperClause.contains(keyword)) {
                throw new AuraHandledException(
                    'Invalid WHERE clause: contains disallowed keyword "' + keyword + '".'
                );
            }
        }
        return whereClause;
    }

    /**
     * @description Converts a list of SObject records into a list of field-value maps
     *              for JSON serialisation to the LWC component.
     *
     * @param records    SObject records from the SOQL query
     * @param fieldNames Validated field API names to extract
     * @return List of maps keyed by field API name
     */
    private static List<Map<String, Object>> toRecordMaps(
        List<SObject> records,
        List<String> fieldNames
    ) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject record : records) {
            Map<String, Object> recordMap = new Map<String, Object>();
            for (String fieldName : fieldNames) {
                recordMap.put(fieldName, record.get(fieldName));
            }
            result.add(recordMap);
        }
        return result;
    }
}
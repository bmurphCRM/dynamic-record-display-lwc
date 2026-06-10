/**
 * @description Test class for DRD_RecordDisplayController.
 *              Covers happy paths, pagination, field/object validation,
 *              WHERE clause sanitisation, and bulk scenarios.
 */
@IsTest
private class DRD_RecordDisplayControllerTest {

    // ─── Constants ────────────────────────────────────────────────────────────

    private static final Integer SETUP_RECORD_COUNT = 12;
    private static final Integer DEFAULT_PAGE_SIZE   = 10;
    private static final String  OBJECT_ACCOUNT      = 'Account';
    private static final String  FIELDS_NAME_TYPE    = 'Name,Type';
    private static final String  FIELD_NAME_ONLY     = 'Name';

    // ─── Test Setup ───────────────────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < SETUP_RECORD_COUNT; i++) {
            accounts.add(new Account(
                Name     = 'DRD Test Account ' + String.valueOf(i).leftPad(2, '0'),
                Type     = 'Prospect',
                Industry = 'Technology'
            ));
        }
        insert accounts;
    }

    // ─── Happy Path ───────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnRecords_WhenValidObjectAndFields() {
        // Given / When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELDS_NAME_TYPE, null, null, null,
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual(DEFAULT_PAGE_SIZE, result.records.size(),
            'Should return exactly ' + DEFAULT_PAGE_SIZE + ' records on first page');
        Assert.isTrue(result.hasMore,
            'hasMore should be true when more records exist beyond the page');
        Assert.isTrue(result.fieldLabels.containsKey('Name'),
            'fieldLabels map should contain Name');
        Assert.isTrue(result.fieldTypes.containsKey('Name'),
            'fieldTypes map should contain Name');
        Assert.isTrue(result.fieldTypes.containsKey('Type'),
            'fieldTypes map should contain Type');
    }

    @IsTest
    static void shouldReturnFieldLabels_WhenValidFields() {
        // Given / When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELDS_NAME_TYPE, null, null, null, 5, 0
            );
        Test.stopTest();

        // Then
        Assert.isNotNull(result.fieldLabels.get('Name'),
            'Label for Name field should be present');
        Assert.isNotNull(result.fieldLabels.get('Type'),
            'Label for Type field should be present');
    }

    @IsTest
    static void shouldIncludeIdInResults_WhenIdNotInFieldList() {
        // Given: field list without Id
        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, null, null, 5, 0
            );
        Test.stopTest();

        // Then: Id should always be present for navigation
        Assert.isFalse(result.records.isEmpty(), 'Records list should not be empty');
        Assert.isNotNull(result.records[0].get('Id'),
            'Id should always be present in record maps for navigation');
    }

    @IsTest
    static void shouldReturnAllRemainingRecords_WhenLastPage() {
        // Given: 12 records exist; first page takes 10; second page should return 2
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, 'Name', 'ASC',
                DEFAULT_PAGE_SIZE, DEFAULT_PAGE_SIZE
            );
        Test.stopTest();

        // Then
        Assert.areEqual(2, result.records.size(),
            'Second page should contain the remaining 2 records');
        Assert.isFalse(result.hasMore,
            'hasMore should be false on the last page');
    }

    @IsTest
    static void shouldRespectOrderByAsc_WhenOrderByFieldAndDirProvided() {
        // Given / When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, 'Name', 'ASC',
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then: first record name should come before last record name alphabetically
        String firstName = (String) result.records[0].get('Name');
        String lastName  = (String) result.records[result.records.size() - 1].get('Name');
        Assert.isTrue(
            firstName.compareTo(lastName) <= 0,
            'Records should be sorted in ASC order by Name'
        );
    }

    @IsTest
    static void shouldRespectOrderByDesc_WhenOrderByDirIsDesc() {
        // Given / When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, 'Name', 'DESC',
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then
        String firstName = (String) result.records[0].get('Name');
        String lastName  = (String) result.records[result.records.size() - 1].get('Name');
        Assert.isTrue(
            firstName.compareTo(lastName) >= 0,
            'Records should be sorted in DESC order by Name'
        );
    }

    @IsTest
    static void shouldFilterRecords_WhenValidWhereClauseProvided() {
        // Given: only 'Prospect' accounts were created in setup
        String whereClause = 'Type = \'Prospect\'';

        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELDS_NAME_TYPE, whereClause, null, null,
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then
        Assert.isFalse(result.records.isEmpty(),
            'Should return records matching the WHERE clause');
        for (Map<String, Object> record : result.records) {
            Assert.areEqual('Prospect', record.get('Type'),
                'All returned records should have Type = Prospect');
        }
    }

    @IsTest
    static void shouldReturnEmptyList_WhenWhereClauseMatchesNoRecords() {
        // Given: no accounts with Type = 'Competitor'
        String whereClause = 'Type = \'Competitor\'';

        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, whereClause, null, null,
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then
        Assert.isNotNull(result.records, 'Records list should not be null');
        Assert.areEqual(0, result.records.size(),
            'No records should be returned when WHERE clause matches nothing');
        Assert.isFalse(result.hasMore,
            'hasMore should be false when no records are returned');
    }

    @IsTest
    static void shouldDefaultLimit_WhenQueryLimitIsNull() {
        // Given: null limit should default to 10
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, null, null, null, 0
            );
        Test.stopTest();

        // Then
        Assert.areEqual(DEFAULT_PAGE_SIZE, result.records.size(),
            'Null queryLimit should default to ' + DEFAULT_PAGE_SIZE + ' records');
    }

    @IsTest
    static void shouldCapLimit_WhenQueryLimitExceedsMaximum() {
        // Given: requesting 999 records should be capped at 200
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, null, null, 999, 0
            );
        Test.stopTest();

        // Then: only SETUP_RECORD_COUNT records exist, should return all of them
        Assert.areEqual(SETUP_RECORD_COUNT, result.records.size(),
            'Capped limit should still return all available records up to cap');
    }

    @IsTest
    static void shouldHandleFieldsWithWhitespace_WhenCsvHasSpaces() {
        // Given: field list with extra spaces around names
        String fieldsWithSpaces = ' Name , Type , Industry ';

        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, fieldsWithSpaces, null, null, null, 5, 0
            );
        Test.stopTest();

        // Then
        Assert.isFalse(result.records.isEmpty(),
            'Should handle CSV with surrounding whitespace gracefully');
        Assert.isTrue(result.fieldLabels.containsKey('Name'),
            'Name should be resolved despite surrounding whitespace');
    }

    // ─── Pagination ───────────────────────────────────────────────────────────

    @IsTest
    static void shouldReturnHasMoreFalse_WhenOnSinglePageOfResults() {
        // Given: request a page larger than the total record count
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, null, null, 50, 0
            );
        Test.stopTest();

        // Then
        Assert.areEqual(SETUP_RECORD_COUNT, result.records.size(),
            'Should return all ' + SETUP_RECORD_COUNT + ' records when page size exceeds total');
        Assert.isFalse(result.hasMore,
            'hasMore should be false when all records fit on one page');
    }

    // ─── Negative / Validation Paths ──────────────────────────────────────────

    @IsTest
    static void shouldThrowAuraHandledException_WhenObjectApiNameIsBlank() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                '', FIELD_NAME_ONLY, null, null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for blank objectApiName');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('object api name is required'),
                'Exception message should indicate objectApiName is required'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenObjectApiNameIsNull() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                null, FIELD_NAME_ONLY, null, null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for null objectApiName');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('object api name is required'),
                'Exception message should indicate objectApiName is required'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenFieldListIsBlank() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, '', null, null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for blank fieldListCsv');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('field'),
                'Exception message should mention fields'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenObjectApiNameIsInvalid() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                'NotARealObject__xyz', FIELD_NAME_ONLY, null, null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for invalid objectApiName');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('invalid object'),
                'Exception message should indicate invalid object name'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenFieldNameIsInvalid() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, 'Name,NotARealField__xyz', null, null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for invalid field name');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('invalid field'),
                'Exception message should indicate invalid field name'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenOrderByFieldIsInvalid() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, 'NotARealField__xyz', 'ASC', 10, 0
            );
            Assert.fail('Expected AuraHandledException for invalid ORDER BY field');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('invalid order by'),
                'Exception message should indicate invalid ORDER BY field'
            );
        }
        Test.stopTest();
    }

    // ─── WHERE Clause Sanitisation ────────────────────────────────────────────

    @IsTest
    static void shouldThrowAuraHandledException_WhenWhereClauseContainsDelete() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, 'Name = \'test\' DELETE', null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for DELETE keyword in WHERE clause');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('disallowed keyword'),
                'Exception message should mention disallowed keyword'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldThrowAuraHandledException_WhenWhereClauseContainsUnion() {
        // Given / When / Then
        Test.startTest();
        try {
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, 'Name = \'x\' UNION SELECT Id FROM Contact', null, null, 10, 0
            );
            Assert.fail('Expected AuraHandledException for UNION in WHERE clause');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().containsIgnoreCase('disallowed keyword'),
                'Exception message should mention disallowed keyword'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void shouldAcceptCleanWhereClause_WhenNoBlockedKeywordsPresent() {
        // Given: a legitimate WHERE clause
        String cleanWhere = 'Type = \'Prospect\' AND Industry = \'Technology\'';

        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, cleanWhere, null, null, 10, 0
            );
        Test.stopTest();

        // Then: should not throw, should return matching records
        Assert.isNotNull(result, 'Result should not be null for a clean WHERE clause');
        Assert.isFalse(result.records.isEmpty(),
            'Should return records matching the clean WHERE clause');
    }

    // ─── Bulk Test ────────────────────────────────────────────────────────────

    @IsTest
    static void shouldHandleBulkQuery_WhenManyRecordsExist() {
        // Given: insert 251 additional accounts to exceed trigger batch boundary
        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 0; i < 251; i++) {
            bulkAccounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert bulkAccounts;

        // When
        Test.startTest();
        DRD_RecordDisplayController.RecordQueryResult result =
            DRD_RecordDisplayController.getRecords(
                OBJECT_ACCOUNT, FIELD_NAME_ONLY, null, null, null,
                DEFAULT_PAGE_SIZE, 0
            );
        Test.stopTest();

        // Then
        Assert.areEqual(DEFAULT_PAGE_SIZE, result.records.size(),
            'Should return exactly one page of records even with 263 total records');
        Assert.isTrue(result.hasMore,
            'hasMore should be true when bulk records exceed one page');
    }
}
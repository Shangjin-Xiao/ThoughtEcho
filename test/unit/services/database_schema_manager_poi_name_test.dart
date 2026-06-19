import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

import '../../test_helpers.dart';

void main() {
  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
  });
  group('DatabaseSchemaManager.poiNameSelectExpressionFromTableInfo', () {
    test('uses NULL AS poi_name when legacy table has no poi_name', () {
      final tableInfo = <Map<String, Object?>>[
        {'name': 'id'},
        {'name': 'tag_ids'},
      ];

      final expression =
          DatabaseSchemaManager.poiNameSelectExpressionFromTableInfo(tableInfo);

      expect(expression, equals('NULL AS poi_name'));
    });

    test('uses poi_name when table already has poi_name column', () {
      final tableInfo = <Map<String, Object?>>[
        {'name': 'id'},
        {'name': 'poi_name'},
        {'name': 'tag_ids'},
      ];

      final expression =
          DatabaseSchemaManager.poiNameSelectExpressionFromTableInfo(tableInfo);

      expect(expression, equals('poi_name'));
    });
  });

  group('DatabaseSchemaManager v20 validation targets', () {
    test('required tables include chat persistence tables', () {
      // Use the actual required tables set from production code
      final requiredTables = DatabaseSchemaManager.requiredTablesForValidation;

      expect(requiredTables.contains('quotes'), isTrue);
      expect(requiredTables.contains('categories'), isTrue);
      expect(requiredTables.contains('quote_tags'), isTrue);
      expect(requiredTables.contains('chat_sessions'), isTrue);
      expect(requiredTables.contains('chat_messages'), isTrue);
    });
  });
}

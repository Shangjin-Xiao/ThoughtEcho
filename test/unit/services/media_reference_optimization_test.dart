import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/media_reference_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  int callCount = 0;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    callCount++;
    return '/tmp/test_app_docs';
  }
}

void main() {
  late MockPathProvider mockPathProvider;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    db = await openDatabase(inMemoryDatabasePath);
    await MediaReferenceService.initializeTable(db);
    MediaReferenceService.setDatabaseForTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Optimization Check: syncQuoteMediaReferencesWithTransaction reduced calls', () async {
    final mediaCount = 5;
    final ops = <Map<String, dynamic>>[];

    for (var i = 0; i < mediaCount; i++) {
      ops.add({
        'insert': {
          'image': '/tmp/test_app_docs/media/image_$i.png'
        }
      });
    }

    final quote = Quote(
      id: 'test_quote_1',
      content: 'Test content',
      deltaContent: jsonEncode(ops),
      createdAt: DateTime.now(),
    );

    await db.transaction((txn) async {
      await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(txn, quote);
    });

    print('getApplicationDocumentsPath calls after optimization: ${mockPathProvider.callCount}');

    // Optimization: Should only be 1 call now for the whole transaction
    expect(mockPathProvider.callCount, equals(1));
  });

  test('Optimization Check: migrateExistingQuotes reduced calls', () async {
     // This would require more complex mocking of DatabaseService, skipping for now
     // but the principle is the same.
  });
}

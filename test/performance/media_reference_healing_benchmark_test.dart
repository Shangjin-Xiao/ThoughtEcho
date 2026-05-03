import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/media_reference_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  int callCount = 0;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    callCount++;
    // 减少延迟以加快测试速度，或者不加延迟
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

  test(
    'Benchmark: syncQuoteMediaReferencesWithTransaction N+1 issue',
    () async {
      final mediaCount = 10; // 减少数量以确保快速运行
      final ops = <Map<String, dynamic>>[];

      for (var i = 0; i < mediaCount; i++) {
        ops.add({
          'insert': {'image': '/tmp/test_app_docs/media/image_$i.png'},
        });
      }

      final quote = Quote(
        id: 'test_quote_1',
        content: 'Test content',
        deltaContent: jsonEncode(ops),
        date: DateTime.now().toIso8601String(),
      );

      final stopwatch = Stopwatch()..start();

      await db.transaction((txn) async {
        await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
          txn,
          quote,
        );
      });

      stopwatch.stop();

      // ⚡ Bolt: After optimization, it should be exactly 1 call
      expect(mockPathProvider.callCount, equals(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

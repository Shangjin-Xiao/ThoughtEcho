import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/database_backup_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseBackupService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  setUp(() async {
    final dbPath =
        join(Directory.systemTemp.path, 'test_backup_perf_tombstone.db');
    if (File(dbPath).existsSync()) {
      File(dbPath).deleteSync();
    }
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await DatabaseSchemaManager().createTables(db);
      },
    );
    service = DatabaseBackupService();
  });

  tearDown(() async {
    await db.close();
  });

  test('Benchmark importDataWithLWWMerge - N+1 Tombstone Deletion', () async {
    const quoteCount = 10000;

    // 1. Prepare existing data
    await db.transaction((txn) async {
      for (int i = 0; i < quoteCount; i++) {
        await txn.insert('quotes', {
          'id': 'quote_$i',
          'content': 'Content $i',
          'date': DateTime.now().toIso8601String(),
          'last_modified': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        });
      }
    });

    // 2. Prepare tombstone data to merge
    final tombstonesToMerge = List.generate(quoteCount, (i) {
      return {
        'quote_id': 'quote_$i',
        'deleted_at': DateTime.now().toIso8601String(),
      };
    });

    final mergeData = {
      'categories': [],
      'quotes': [],
      'tombstones': tombstonesToMerge,
    };

    // 3. Measure
    final stopwatch = Stopwatch()..start();
    await service.importDataFromMap(db, mergeData, clearExisting: false);
    stopwatch.stop();

    debugPrint(
        'Time taken to process $quoteCount tombstones: ${stopwatch.elapsedMilliseconds} ms');

    final remainingQuotes = await db.query('quotes');
    expect(remainingQuotes.length, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

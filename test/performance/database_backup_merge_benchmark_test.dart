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
    final dbPath = join(Directory.systemTemp.path, 'test_backup_perf.db');
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

  test(
    'Benchmark importDataWithLWWMerge',
    () async {
      const categoryCount = 1;
      const quoteCount = 1;

      // 1. Prepare existing data
      await db.transaction((txn) async {
        for (int i = 0; i < categoryCount ~/ 2; i++) {
          await txn.insert('categories', {
            'id': 'cat_$i',
            'name': 'Category $i',
            'last_modified': DateTime.now().toIso8601String(),
          });
        }
        for (int i = 0; i < quoteCount ~/ 2; i++) {
          await txn.insert('quotes', {
            'id': 'quote_$i',
            'content': 'Content $i',
            'date': DateTime.now().toIso8601String(),
            'last_modified': DateTime.now().toIso8601String(),
          });
        }
      });

      // 2. Prepare data to merge
      final categoriesToMerge = List.generate(categoryCount, (i) {
        return {
          'id': 'cat_$i',
          'name': 'Category $i',
          'last_modified': DateTime.now()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        };
      });

      final quotesToMerge = List.generate(quoteCount, (i) {
        final int halfCatCount = categoryCount ~/ 2;
        return {
          'id': 'quote_$i',
          'content': 'Updated Content $i',
          'date': DateTime.now().toIso8601String(),
          'last_modified': DateTime.now()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'tag_ids': (i % 5 == 0 && halfCatCount > 0)
              ? 'cat_${i % halfCatCount}'
              : '',
        };
      });

      final mergeData = {
        'categories': categoriesToMerge,
        'quotes': quotesToMerge,
      };

      // 3. Measure
      final stopwatch = Stopwatch()..start();
      final report = await service.importDataWithLWWMerge(db, mergeData);
      stopwatch.stop();

      debugPrint(
        'Time taken to merge $categoryCount categories and $quoteCount quotes: ${stopwatch.elapsedMilliseconds} ms',
      );
      debugPrint('Report: ${report.summary}');

      expect(
        report.insertedCategories + report.updatedCategories,
        categoryCount,
      );
      expect(report.insertedQuotes + report.updatedQuotes, quoteCount);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

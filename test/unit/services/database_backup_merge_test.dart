import 'dart:io';
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
    final dbPath = join(Directory.systemTemp.path, 'test_backup_merge.db');
    if (File(dbPath).existsSync()) {
      File(dbPath).deleteSync();
    }
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await DatabaseSchemaManager.createTables(db);
      },
    );
    service = DatabaseBackupService();
  });

  tearDown(() async {
    await db.close();
  });

  test('LWW Merge should correctly handle categories and quotes', () async {
    // 1. Prepare existing data
    await db.insert('categories', {
      'id': 'cat_1',
      'name': 'Old Category',
      'last_modified': '2023-01-01T00:00:00Z',
    });
    await db.insert('quotes', {
      'id': 'quote_1',
      'content': 'Old Content',
      'date': '2023-01-01T00:00:00Z',
      'last_modified': '2023-01-01T00:00:00Z',
    });

    // 2. Data to merge
    final mergeData = {
      'categories': [
        {
          'id': 'cat_1',
          'name': 'New Category Name', // Name match might happen or ID match
          'last_modified': '2023-02-01T00:00:00Z',
        },
        {
          'id': 'cat_2',
          'name': 'Brand New Category',
          'last_modified': '2023-02-01T00:00:00Z',
        },
      ],
      'quotes': [
        {
          'id': 'quote_1',
          'content': 'New Content',
          'date': '2023-01-01T00:00:00Z',
          'last_modified': '2023-02-01T00:00:00Z',
          'tag_ids': 'cat_1,cat_2',
        },
        {
          'id': 'quote_2',
          'content': 'Another Quote',
          'date': '2023-02-01T00:00:00Z',
          'last_modified': '2023-02-01T00:00:00Z',
        },
      ],
    };

    // 3. Execute merge
    final report = await service.importDataWithLWWMerge(db, mergeData);

    // 4. Verify results
    expect(report.updatedCategories, 1);
    expect(report.insertedCategories, 1);
    expect(report.updatedQuotes, 1);
    expect(report.insertedQuotes, 1);

    final cat1 = (await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: ['cat_1'],
    )).first;
    expect(cat1['name'], 'New Category Name');

    final quote1 = (await db.query(
      'quotes',
      where: 'id = ?',
      whereArgs: ['quote_1'],
    )).first;
    expect(quote1['content'], 'New Content');

    final tags = await db.query(
      'quote_tags',
      where: 'quote_id = ?',
      whereArgs: ['quote_1'],
    );
    expect(tags.length, 2);
  });
}

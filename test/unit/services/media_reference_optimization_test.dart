import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

class MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  int callCount = 0;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    callCount++;
    return '/tmp/test_app_docs';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await db.execute('''
      CREATE TABLE quotes(
        id TEXT PRIMARY KEY,
        content TEXT,
        delta_content TEXT,
        date TEXT
      )
    ''');
    await MediaReferenceService.initializeTable(db);
    MediaReferenceService.setDatabaseForTesting(db);

    final mediaDir = Directory('/tmp/test_app_docs/media');
    if (mediaDir.existsSync()) {
      mediaDir.deleteSync(recursive: true);
    }
    mediaDir.createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    final mediaDir = Directory('/tmp/test_app_docs/media');
    if (mediaDir.existsSync()) {
      mediaDir.deleteSync(recursive: true);
    }
  });

  test(
    'Optimization Check: syncQuoteMediaReferencesWithTransaction reduced calls',
    () async {
      final mediaCount = 5;
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

      mockPathProvider.callCount = 0;

      await db.transaction((txn) async {
        await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
          txn,
          quote,
        );
      });

      // Optimization: path lookup should not scale with every media item.
      expect(mockPathProvider.callCount, lessThan(mediaCount));
    },
  );

  test('syncQuoteMediaReferencesBatch replaces stale refs for many quotes '
      'in one pass', () async {
    // Arrange: stale references for quotes in the batch, plus one outside it
    for (var i = 0; i < 3; i++) {
      await db.insert('media_references', {
        'id': 'stale_$i',
        'file_path': 'media/stale_$i.png',
        'quote_id': 'batch_quote_$i',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await db.insert('media_references', {
      'id': 'untouched',
      'file_path': 'media/other.png',
      'quote_id': 'other_quote',
      'created_at': DateTime.now().toIso8601String(),
    });

    final quotes = List.generate(
      120,
      (i) => Quote(
        id: 'batch_quote_$i',
        content: 'Batch content $i',
        deltaContent: i.isEven
            ? jsonEncode([
                {
                  'insert': {'image': '/tmp/test_app_docs/media/img_$i.png'},
                },
              ])
            : null,
        date: DateTime.now().toIso8601String(),
      ),
    );

    // Act
    final synced = await MediaReferenceService.syncQuoteMediaReferencesBatch(
      quotes,
      cachedAppPath: '/tmp/test_app_docs',
    );

    // Assert
    expect(synced, quotes.length);
    final staleRows = await db.query(
      'media_references',
      where: "file_path LIKE 'media/stale_%'",
    );
    expect(staleRows, isEmpty);

    final batchRows = await db.query(
      'media_references',
      where: "quote_id LIKE 'batch_quote_%'",
    );
    expect(batchRows, hasLength(60));
    expect(batchRows.map((r) => r['file_path']), contains('media/img_0.png'));

    final untouched = await db.query(
      'media_references',
      where: 'quote_id = ?',
      whereArgs: ['other_quote'],
    );
    expect(untouched, hasLength(1));
  });

  test(
    'quickCheckAndDeleteOrphans batches orphan checks and heals refs',
    () async {
      final orphanFile = File('/tmp/test_app_docs/media/orphan.png')
        ..writeAsStringSync('orphan');
      final storedRefFile = File('/tmp/test_app_docs/media/stored.png')
        ..writeAsStringSync('stored');
      final contentRefFile = File('/tmp/test_app_docs/media/content.png')
        ..writeAsStringSync('content');

      await db.insert('quotes', {
        'id': 'quote_content_ref',
        'content': 'image path: media/content.png',
        'delta_content': null,
        'date': DateTime.now().toIso8601String(),
      });
      await db.insert('media_references', {
        'id': 'stored_ref',
        'file_path': 'media/stored.png',
        'quote_id': 'quote_stored_ref',
        'created_at': DateTime.now().toIso8601String(),
      });

      final deletedCount =
          await MediaReferenceService.quickCheckAndDeleteOrphans([
            orphanFile.path,
            storedRefFile.path,
            contentRefFile.path,
          ], cachedAppPath: '/tmp/test_app_docs');

      expect(deletedCount, 1);
      expect(orphanFile.existsSync(), isFalse);
      expect(storedRefFile.existsSync(), isTrue);
      expect(contentRefFile.existsSync(), isTrue);

      final healedRefs = await db.query(
        'media_references',
        where: 'file_path = ? AND quote_id = ?',
        whereArgs: ['media/content.png', 'quote_content_ref'],
      );
      expect(healedRefs, hasLength(1));
    },
  );

  test(
    'quickCheckAndDeleteOrphans keeps file URI references with encoded path',
    () async {
      final referencedFile = File(
        '/tmp/test_app_docs/media/stored relative.png',
      )..writeAsStringSync('stored');
      final fileUri = referencedFile.uri.toString();

      await db.insert('quotes', {
        'id': 'quote_file_uri_ref',
        'content': 'image path: $fileUri',
        'delta_content': jsonEncode([
          {
            'insert': {'image': fileUri},
          },
        ]),
        'date': DateTime.now().toIso8601String(),
      });

      final deletedCount =
          await MediaReferenceService.quickCheckAndDeleteOrphans([
            referencedFile.path,
          ], cachedAppPath: '/tmp/test_app_docs');

      expect(deletedCount, 0);
      expect(referencedFile.existsSync(), isTrue);

      final healedRefs = await db.query(
        'media_references',
        where: 'file_path = ? AND quote_id = ?',
        whereArgs: ['media/stored relative.png', 'quote_file_uri_ref'],
      );
      expect(healedRefs, hasLength(1));
    },
  );
}

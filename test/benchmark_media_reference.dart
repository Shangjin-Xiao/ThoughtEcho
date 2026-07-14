import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/media_reference_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Benchmark getReferencedFilesBatch', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    MediaReferenceService.setDatabaseForTesting(db);

    await db.execute('''
      CREATE TABLE quotes (
        id TEXT PRIMARY KEY,
        content TEXT,
        delta_content TEXT
      )
    ''');

    await MediaReferenceService.initializeTable(db);

    // insert some mock data
    final batch = db.batch();
    final quoteIds = <String>[];
    for (int i = 0; i < 5000; i++) {
      final quoteId = const Uuid().v4();
      quoteIds.add(quoteId);

      batch.insert('quotes', {
        'id': quoteId,
        'content': '',
      });

      batch.insert('media_references', {
        'id': const Uuid().v4(),
        'file_path': 'path/to/file_$i.png',
        'quote_id': quoteId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);

    print('Warming up...');
    await MediaReferenceService.getReferencedFilesBatch(quoteIds);

    print('Running baseline benchmark...');
    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < 10; i++) {
      await MediaReferenceService.getReferencedFilesBatch(quoteIds);
    }

    stopwatch.stop();
    print('Elapsed: ${stopwatch.elapsedMilliseconds} ms');
  });
}

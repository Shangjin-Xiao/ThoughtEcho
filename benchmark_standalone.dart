import 'dart:math' as math;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;

  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE media_references (
      id TEXT PRIMARY KEY,
      file_path TEXT NOT NULL,
      quote_id TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');

  final batch = db.batch();
  final quoteIds = <String>[];
  for (int i = 0; i < 5000; i++) {
    final quoteId = 'quote_$i';
    quoteIds.add(quoteId);
    batch.insert('media_references', {
      'id': 'ref_$i',
      'file_path': 'path/to/file_$i.png',
      'quote_id': quoteId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  await batch.commit(noResult: true);

  print('Warming up...');

  Future<void> runSequential() async {
    const int maxChunkSize = 900;
    for (var start = 0; start < quoteIds.length; start += maxChunkSize) {
      final end = math.min(start + maxChunkSize, quoteIds.length);
      final chunk = quoteIds.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.query(
        'media_references',
        columns: ['quote_id', 'file_path'],
        where: 'quote_id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  Future<void> runBatch() async {
    const int maxChunkSize = 900;
    final b = db.batch();
    for (var start = 0; start < quoteIds.length; start += maxChunkSize) {
      final end = math.min(start + maxChunkSize, quoteIds.length);
      final chunk = quoteIds.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      b.query(
        'media_references',
        columns: ['quote_id', 'file_path'],
        where: 'quote_id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
    await b.commit();
  }

  await runSequential();
  await runBatch();

  final iters = 100;

  final sw1 = Stopwatch()..start();
  for (int i = 0; i < iters; i++) {
    await runSequential();
  }
  sw1.stop();
  print('Sequential time: ${sw1.elapsedMilliseconds} ms');

  final sw2 = Stopwatch()..start();
  for (int i = 0; i < iters; i++) {
    await runBatch();
  }
  sw2.stop();
  print('Batch time: ${sw2.elapsedMilliseconds} ms');
}

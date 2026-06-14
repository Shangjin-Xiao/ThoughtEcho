// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Benchmark N+1 Insert vs Batch Insert', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE quote_tags (
        quote_id TEXT,
        tag_id TEXT
      )
    ''');

    const int tagCount = 1000;
    final List<Map<String, dynamic>> tags = List.generate(
      tagCount,
      (index) => {'tag_id': 'tag_$index'},
    );

    // Baseline: N+1 sequential inserts
    final stopwatchN1 = Stopwatch()..start();
    for (final tag in tags) {
      await db.insert('quote_tags', {
        'quote_id': 'quote_1',
        'tag_id': tag['tag_id'],
      });
    }
    stopwatchN1.stop();

    // Clear table for fair test
    await db.delete('quote_tags');

    // Optimized: Batch insert
    final stopwatchBatch = Stopwatch()..start();
    final batch = db.batch();
    for (final tag in tags) {
      batch.insert('quote_tags', {
        'quote_id': 'quote_2',
        'tag_id': tag['tag_id'],
      });
    }
    await batch.commit(noResult: true);
    stopwatchBatch.stop();

    print('--- Benchmark Results (1000 inserts) ---');
    print('N+1 Inserts: ${stopwatchN1.elapsedMilliseconds} ms');
    print('Batch Insert: ${stopwatchBatch.elapsedMilliseconds} ms');
    print(
        'Improvement: ${stopwatchN1.elapsedMilliseconds / stopwatchBatch.elapsedMilliseconds}x faster');

    await db.close();
  });
}

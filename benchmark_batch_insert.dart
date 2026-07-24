import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final dbFactory = databaseFactoryFfi;
  final db = await dbFactory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE quotes (
              id TEXT PRIMARY KEY,
              category_id TEXT,
              last_modified TEXT,
              content TEXT,
              delta_content TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE quote_tags (
              quote_id TEXT,
              tag_id TEXT
            )
          ''');
        },
      ));

  final List<Map<String, dynamic>> quotes = List.generate(500, (i) => {
    'id': Uuid().v4(),
    'content': 'Test content $i',
    'delta_content': json.encode([{'insert': 'Test content $i\n'}]),
    'last_modified': DateTime.now().toUtc().toIso8601String(),
  });

  final List<List<Map<String, Object?>>> tagsList = List.generate(500, (i) => [
    {'tag_id': 'tag1'},
    {'tag_id': 'tag2'},
  ]);

  // Baseline (sequential)
  final stopwatch = Stopwatch()..start();
  for (int i = 0; i < quotes.length; i++) {
    final quote = quotes[i];
    final tags = tagsList[i];

    final clonedQuote = Map<String, dynamic>.from(quote);
    clonedQuote['id'] = Uuid().v4();
    clonedQuote['category_id'] = 'conflict_cat';

    await db.insert('quotes', clonedQuote);
    if (tags.isNotEmpty) {
      final batch = db.batch();
      for (final tag in tags) {
        batch.insert('quote_tags', {
          'quote_id': clonedQuote['id'],
          'tag_id': tag['tag_id'],
        });
      }
      await batch.commit(noResult: true);
    }
  }
  stopwatch.stop();
  final sequentialTime = stopwatch.elapsedMilliseconds;
  print('Sequential time: $sequentialTime ms');

  // Clear db
  await db.execute('DELETE FROM quotes');
  await db.execute('DELETE FROM quote_tags');

  // Optimized (batch)
  stopwatch.reset();
  stopwatch.start();
  final batch = db.batch();
  for (int i = 0; i < quotes.length; i++) {
    final quote = quotes[i];
    final tags = tagsList[i];

    final clonedQuote = Map<String, dynamic>.from(quote);
    clonedQuote['id'] = Uuid().v4();
    clonedQuote['category_id'] = 'conflict_cat';

    batch.insert('quotes', clonedQuote);
    for (final tag in tags) {
      batch.insert('quote_tags', {
        'quote_id': clonedQuote['id'],
        'tag_id': tag['tag_id'],
      });
    }
  }
  await batch.commit(continueOnError: true, noResult: true);
  stopwatch.stop();
  final batchTime = stopwatch.elapsedMilliseconds;
  print('Batch time: $batchTime ms');

  print('Improvement: ${((sequentialTime - batchTime) / sequentialTime * 100).toStringAsFixed(2)}%');
}

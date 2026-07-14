import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final dbPath = join(Directory.systemTemp.path, 'test_perf.db');
  if (File(dbPath).existsSync()) {
    File(dbPath).deleteSync();
  }

  var db = await databaseFactory.openDatabase(dbPath, options: OpenDatabaseOptions(
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE quotes (
          id TEXT PRIMARY KEY,
          content TEXT,
          delta_content TEXT,
          date TEXT,
          last_modified TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE quote_tombstones (
          quote_id TEXT PRIMARY KEY,
          deleted_at TEXT,
          device_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE media_references (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quote_id TEXT,
          file_path TEXT
        )
      ''');
    },
  ));

  int count = 2000;
  var batch = db.batch();
  for (int i = 0; i < count; i++) {
    batch.insert('quotes', {
      'id': 'quote_$i',
      'content': 'Content $i',
      'last_modified': '2023-01-01T00:00:00.000Z',
    });
    if (i % 2 == 0) {
      batch.insert('media_references', {
        'quote_id': 'quote_$i',
        'file_path': 'path/to/media_$i.png'
      });
    }
  }
  await batch.commit(noResult: true);

  var tombstones = List.generate(count, (i) => {
    'quote_id': 'quote_$i',
    'deleted_at': '2023-01-02T00:00:00.000Z',
    'device_id': 'dev1'
  });

  // Benchmark Original (Simulated)
  final sw1 = Stopwatch()..start();
  await db.transaction((txn) async {
    final existingTombstoneRows = await txn.query('quote_tombstones');
    final Map<String, Map<String, dynamic>> localTombstoneMap = {
      for (final row in existingTombstoneRows) (row['quote_id'] as String): row,
    };
    final tbatch = txn.batch();

    for (var item in tombstones) {
      final quoteId = item['quote_id'] as String;
      final incomingDeletedAt = item['deleted_at'] as String;

      final quoteRows = await txn.query(
        'quotes',
        columns: ['last_modified', 'delta_content', 'content'],
        where: 'id = ?',
        whereArgs: [quoteId],
        limit: 1,
      );

      if (quoteRows.isNotEmpty) {
        final refRows = await txn.query(
          'media_references',
          columns: ['file_path'],
          where: 'quote_id = ?',
          whereArgs: [quoteId],
        );
      }

      tbatch.insert('quote_tombstones', {
        'quote_id': quoteId,
        'deleted_at': incomingDeletedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await tbatch.commit(noResult: true);
  });
  sw1.stop();
  print('Original approach took: ${sw1.elapsedMilliseconds}ms');

  // Clear tombstones for second run
  await db.delete('quote_tombstones');

  // Benchmark Optimized
  final sw2 = Stopwatch()..start();
  await db.transaction((txn) async {
    final existingTombstoneRows = await txn.query('quote_tombstones');
    final Map<String, Map<String, dynamic>> localTombstoneMap = {
      for (final row in existingTombstoneRows) (row['quote_id'] as String): row,
    };

    final validQuoteIds = tombstones.map((e) => e['quote_id'] as String).toList();
    final Map<String, Map<String, dynamic>> existingQuotes = {};
    final Map<String, List<String>> existingMediaRefs = {};

    if (validQuoteIds.isNotEmpty) {
      const int queryBatchSize = 500;
      final queryBatch = txn.batch();
      for (int i = 0; i < validQuoteIds.length; i += queryBatchSize) {
        final end = (i + queryBatchSize < validQuoteIds.length) ? i + queryBatchSize : validQuoteIds.length;
        final batchIds = validQuoteIds.sublist(i, end);
        final placeholders = List.filled(batchIds.length, '?').join(',');

        queryBatch.query('quotes',
          columns: ['id', 'last_modified', 'delta_content', 'content'],
          where: 'id IN ($placeholders)',
          whereArgs: batchIds,
        );
        queryBatch.query('media_references',
          columns: ['quote_id', 'file_path'],
          where: 'quote_id IN ($placeholders)',
          whereArgs: batchIds,
        );
      }
      final queryResults = await queryBatch.commit();
      for (int i = 0; i < queryResults.length; i += 2) {
        final qRows = queryResults[i] as List<Object?>;
        for (final rowObj in qRows) {
          final r = rowObj as Map<String, dynamic>;
          existingQuotes[r['id'] as String] = r;
        }
        final rRows = queryResults[i+1] as List<Object?>;
        for (final rowObj in rRows) {
          final r = rowObj as Map<String, dynamic>;
          existingMediaRefs.putIfAbsent(r['quote_id'] as String, () => []).add(r['file_path'] as String);
        }
      }
    }

    final tbatch = txn.batch();
    for (var item in tombstones) {
      final quoteId = item['quote_id'] as String;
      final incomingDeletedAt = item['deleted_at'] as String;

      final quoteRow = existingQuotes[quoteId];
      if (quoteRow != null) {
        final refs = existingMediaRefs[quoteId];
      }

      tbatch.insert('quote_tombstones', {
        'quote_id': quoteId,
        'deleted_at': incomingDeletedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await tbatch.commit(noResult: true);
  });
  sw2.stop();
  print('Optimized approach took: ${sw2.elapsedMilliseconds}ms');

  await db.close();
}

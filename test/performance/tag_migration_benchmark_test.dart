import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'Benchmark Tag Migration (Single batch.insert vs Chunked multi-row rawInsert)',
      () async {
    final db = await openDatabase(inMemoryDatabasePath);
    // Setup tables
    await db.execute('CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE quotes(id TEXT PRIMARY KEY, tag_ids TEXT)');
    await db.execute(
        'CREATE TABLE quote_tags(quote_id TEXT, tag_id TEXT, PRIMARY KEY(quote_id, tag_id))');

    // Seed data
    final uuid = const Uuid();
    final random = Random(42);
    final categoryIds = List.generate(100, (_) => uuid.v4());

    // Batch insert categories
    final categoryBatch = db.batch();
    for (final id in categoryIds) {
      categoryBatch.insert('categories', {'id': id, 'name': 'Category $id'});
    }
    await categoryBatch.commit(noResult: true);

    // Insert 2000 quotes, each with 1-5 tags
    final quotes = List.generate(2000, (i) {
      final numTags = random.nextInt(5) + 1;
      final tags =
          (List.of(categoryIds)..shuffle(random)).take(numTags).toList();
      return {
        'id': uuid.v4(),
        'tag_ids': tags.join(','),
      };
    });

    // Batch insert quotes
    final quoteBatch = db.batch();
    for (final quote in quotes) {
      quoteBatch.insert('quotes', quote);
    }
    await quoteBatch.commit(noResult: true);

    debugPrint('Seeded 2000 quotes and 100 categories.');

    // --- Benchmark Baseline (Sequential batch.insert per tag) ---
    final stopwatchBaseline = Stopwatch()..start();
    await db.transaction((txn) async {
      final quotesWithTags = await txn.query(
        'quotes',
        columns: const <String>['id', 'tag_ids'],
        where: "tag_ids IS NOT NULL AND tag_ids != ''",
      );

      if (quotesWithTags.isEmpty) return;

      final categories =
          await txn.query('categories', columns: const <String>['id']);
      final categoryIdsSet = categories.map((c) => c['id'] as String).toSet();

      final batch = txn.batch();

      for (final quote in quotesWithTags) {
        final quoteId = quote['id'] as String;
        final tagIds = (quote['tag_ids'] as String)
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty && categoryIdsSet.contains(id));

        for (final tagId in tagIds) {
          batch.insert(
            'quote_tags',
            <String, Object?>{'quote_id': quoteId, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      await batch.commit(noResult: true);
    });
    stopwatchBaseline.stop();
    debugPrint(
        'Baseline (batch.insert) took: ${stopwatchBaseline.elapsedMilliseconds}ms');

    // Verify count
    final countBaseline = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM quote_tags'));
    debugPrint('Baseline inserted $countBaseline records.');

    // --- Cleanup for Chunked Multi-Row Benchmark ---
    await db.delete('quote_tags');

    // --- Benchmark Chunked Multi-row rawInsert ---
    final stopwatchOptimized = Stopwatch()..start();
    await db.transaction((txn) async {
      final quotesWithTags = await txn.query(
        'quotes',
        columns: const <String>['id', 'tag_ids'],
        where: "tag_ids IS NOT NULL AND tag_ids != ''",
      );

      if (quotesWithTags.isEmpty) return;

      final categories =
          await txn.query('categories', columns: const <String>['id']);
      final categoryIdsSet = categories.map((c) => c['id'] as String).toSet();

      final tagRelations = <MapEntry<String, String>>[];

      for (final quote in quotesWithTags) {
        final quoteId = quote['id'] as String;
        final tagIds = (quote['tag_ids'] as String)
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty && categoryIdsSet.contains(id));

        for (final tagId in tagIds) {
          tagRelations.add(MapEntry(quoteId, tagId));
        }
      }

      final batch = txn.batch();
      if (tagRelations.length == 1) {
        batch.insert(
          'quote_tags',
          <String, Object?>{
            'quote_id': tagRelations.first.key,
            'tag_id': tagRelations.first.value,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else if (tagRelations.length > 1) {
        const chunkSize = 400;
        for (var i = 0; i < tagRelations.length; i += chunkSize) {
          final end = (i + chunkSize < tagRelations.length)
              ? i + chunkSize
              : tagRelations.length;
          final chunk = tagRelations.sublist(i, end);
          final valuePlaceholders =
              List.filled(chunk.length, '(?, ?)').join(', ');
          final args = <Object?>[];
          for (final rel in chunk) {
            args.addAll([rel.key, rel.value]);
          }
          batch.rawInsert(
            'INSERT OR IGNORE INTO quote_tags (quote_id, tag_id) VALUES $valuePlaceholders',
            args,
          );
        }
      }

      await batch.commit(noResult: true);
    });
    stopwatchOptimized.stop();
    debugPrint(
        'Optimized (chunked rawInsert) took: ${stopwatchOptimized.elapsedMilliseconds}ms');

    // Verify count (Optimized)
    final countOptimized = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM quote_tags'));
    debugPrint('Optimized inserted $countOptimized records.');

    // Ensure both strategies produce the exact same result.
    expect(countOptimized, countBaseline);

    final improvement = (stopwatchBaseline.elapsedMilliseconds -
            stopwatchOptimized.elapsedMilliseconds) /
        stopwatchBaseline.elapsedMilliseconds *
        100;
    debugPrint(
      'Performance Improvement: ${improvement.toStringAsFixed(2)}%',
    );

    await db.close();
  });
}

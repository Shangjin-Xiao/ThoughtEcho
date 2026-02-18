import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Benchmark Tag Migration (N+1 vs Optimized)', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    // Setup tables
    await db.execute('CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE quotes(id TEXT PRIMARY KEY, tag_ids TEXT)');
    await db.execute(
        'CREATE TABLE quote_tags(quote_id TEXT, tag_id TEXT, PRIMARY KEY(quote_id, tag_id))');

    // Seed data
    final uuid = const Uuid();
    final random = Random();
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
      final tags = (List.of(categoryIds)..shuffle()).take(numTags).toList();
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

    print('Seeded 2000 quotes and 100 categories.');

    // --- Benchmark Slow (N+1) ---
    final stopwatchSlow = Stopwatch()..start();
    await db.transaction((txn) async {
      // Logic copied from _migrateTagDataSafely (simplified for repro)
      final quotesWithTags = await txn.query(
        'quotes',
        columns: ['id', 'tag_ids'],
        where: 'tag_ids IS NOT NULL AND tag_ids != ""',
      );

      for (final quote in quotesWithTags) {
        final quoteId = quote['id'] as String;
        final tagIdsString = quote['tag_ids'] as String?;
        if (tagIdsString == null || tagIdsString.isEmpty) continue;

        final tagIds = tagIdsString
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();

        final validTagIds = <String>[];
        for (final tagId in tagIds) {
          // N+1 Query here
          final categoryExists = await txn.query(
            'categories',
            where: 'id = ?',
            whereArgs: [tagId],
            limit: 1,
          );

          if (categoryExists.isNotEmpty) {
            validTagIds.add(tagId);
          }
        }

        for (final tagId in validTagIds) {
          await txn.insert(
              'quote_tags',
              {
                'quote_id': quoteId,
                'tag_id': tagId,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
    stopwatchSlow.stop();
    print('Slow migration took: ${stopwatchSlow.elapsedMilliseconds}ms');

    // Verify count
    final countSlow = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM quote_tags'));
    print('Slow migration inserted $countSlow records.');

    // --- Cleanup for Fast Benchmark ---
    await db.delete('quote_tags');

    // --- Benchmark Fast (Optimized) ---
    final stopwatchFast = Stopwatch()..start();
    await db.transaction((txn) async {
      final quotesWithTags = await txn.query(
        'quotes',
        columns: ['id', 'tag_ids'],
        where: 'tag_ids IS NOT NULL AND tag_ids != ""',
      );

      if (quotesWithTags.isEmpty) return;

      // 1. Fetch all category IDs once
      final allCategories = await txn.query('categories', columns: ['id']);
      final allCategoryIds =
          allCategories.map((c) => c['id'] as String).toSet();

      // 2. Prepare batch
      final batch = txn.batch();

      for (final quote in quotesWithTags) {
        final quoteId = quote['id'] as String;
        final tagIdsString = quote['tag_ids'] as String?;
        if (tagIdsString == null || tagIdsString.isEmpty) continue;

        final tagIds = tagIdsString
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();

        // 3. In-memory check
        final validTagIds = tagIds.where((id) => allCategoryIds.contains(id));

        for (final tagId in validTagIds) {
          // 4. Batch insert
          batch.insert(
              'quote_tags',
              {
                'quote_id': quoteId,
                'tag_id': tagId,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      // 5. Commit batch
      await batch.commit(noResult: true);
    });
    stopwatchFast.stop();
    print('Fast migration took: ${stopwatchFast.elapsedMilliseconds}ms');

    // Verify count
    final countFast = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM quote_tags'));
    print('Fast migration inserted $countFast records.');

    expect(countFast, countSlow);
    expect(stopwatchFast.elapsedMilliseconds,
        lessThan(stopwatchSlow.elapsedMilliseconds));

    final improvement = (stopwatchSlow.elapsedMilliseconds -
            stopwatchFast.elapsedMilliseconds) /
        stopwatchSlow.elapsedMilliseconds *
        100;
    print('Performance Improvement: ${improvement.toStringAsFixed(2)}%');

    await db.close();
  });
}

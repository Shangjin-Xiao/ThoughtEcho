// ignore_for_file: avoid_print
import 'dart:io';

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

  test('Benchmark media directory listing: listSync vs async list Stream',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('webdav_media_bench');
    try {
      const fileCount = 300;
      final dir1 = Directory('${tempDir.path}/media1/images');
      final dir2 = Directory('${tempDir.path}/media2/images');
      await dir1.create(recursive: true);
      await dir2.create(recursive: true);

      for (var i = 0; i < fileCount; i++) {
        await File('${dir1.path}/img_$i.jpg').writeAsString('test');
        await File('${dir2.path}/img_$i.jpg').writeAsString('test');
      }

      final mediaRoot1 = Directory('${tempDir.path}/media1');
      final mediaRoot2 = Directory('${tempDir.path}/media2');

      // 1. Synchronous listSync on mediaRoot1
      final swSync = Stopwatch()..start();
      final syncFiles =
          mediaRoot1.listSync(recursive: true).whereType<File>().toList();
      swSync.stop();

      // 2. Asynchronous Stream list on independent mediaRoot2 with event loop responsiveness check
      int eventLoopTicks = 0;
      bool isListing = true;
      void tickLoop() {
        if (!isListing) return;
        eventLoopTicks++;
        Future.microtask(tickLoop);
      }

      Future.microtask(tickLoop);

      final swAsync = Stopwatch()..start();
      final asyncFiles =
          await mediaRoot2.list(recursive: true).whereType<File>().toList();
      swAsync.stop();
      isListing = false;

      expect(asyncFiles.length, equals(syncFiles.length));
      expect(asyncFiles.length, equals(fileCount));
      // 验证异步流处理期间事件循环保持活跃且微任务能够得到执行
      expect(eventLoopTicks, greaterThanOrEqualTo(1));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

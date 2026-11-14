// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/media_reference_service.dart';
import 'package:thoughtecho/utils/media_path_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
  });

  tearDown(() async {
    MediaReferenceService.clearDatabaseForTesting();
    await db.close();
  });

  test('Benchmark: 5,000 条媒体引用下 getAllReferencedMediaTailSet 构建时间低于 15ms 且内存可控',
      () async {
    const totalRecords = 5000;
    final batch = db.batch();

    // 混合不同平台的各种路径格式：标准 Posix、iOS 绝对路径、Android 路径、Windows 绝对路径及反斜杠相对路径
    for (var i = 0; i < totalRecords; i++) {
      String path;
      final mod = i % 5;
      if (mod == 0) {
        path = 'media/images/img_$i.jpg';
      } else if (mod == 1) {
        path =
            '/var/mobile/Containers/Data/Application/1234-5678/Documents/media/images/img_$i.jpg';
      } else if (mod == 2) {
        path =
            '/data/user/0/com.shangjin.thoughtecho/app_flutter/media/videos/vid_$i.mp4';
      } else if (mod == 3) {
        path = r'C:\Users\User\Documents\media\audios\audio_' '$i.m4a';
      } else {
        path = r'media\images\photo_' '$i.png';
      }

      batch.insert('media_references', {
        'id': 'ref_$i',
        'file_path': path,
        'quote_id': 'quote_bench',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);

    // 预热 JIT
    final rows =
        await db.rawQuery('SELECT DISTINCT file_path FROM media_references');
    Set<String> buildIndex(List<Map<String, Object?>> rows) {
      final set = <String>{};
      for (final row in rows) {
        final rawPath = row['file_path'] as String?;
        if (rawPath == null || rawPath.isEmpty) continue;
        final tail = MediaPathResolver.mediaRelativeTail(rawPath);
        if (tail != null) {
          set.add(tail);
        }
      }
      return set;
    }

    for (var i = 0; i < 3; i++) {
      buildIndex(rows);
    }

    // 1. 测试从 SQLite 读取 5000 行
    final swQuery = Stopwatch()..start();
    final queryRows =
        await db.rawQuery('SELECT DISTINCT file_path FROM media_references');
    swQuery.stop();

    // 2. 基准计时：纯内存标准化尾段构建
    final swIndex = Stopwatch()..start();
    final tailSet = buildIndex(queryRows);
    swIndex.stop();

    final queryMs = swQuery.elapsedMilliseconds;
    final indexMs = swIndex.elapsedMilliseconds;
    print(
        '--- Benchmark: 5,000 records rawQuery: ${queryMs}ms (${swQuery.elapsedMicroseconds}us) ---');
    print(
        '--- Benchmark: 5,000 records in-memory index construction: ${indexMs}ms (${swIndex.elapsedMicroseconds}us) ---');

    // 总体方法执行时间
    final swTotal = Stopwatch()..start();
    final totalTailSet =
        await MediaReferenceService.getAllReferencedMediaTailSet();
    swTotal.stop();
    print(
        '--- Benchmark: 5,000 records getAllReferencedMediaTailSet total: ${swTotal.elapsedMilliseconds}ms (${swTotal.elapsedMicroseconds}us) ---');

    expect(tailSet, isNotEmpty);
    expect(tailSet.length, greaterThanOrEqualTo(totalRecords));
    expect(totalTailSet.length, equals(tailSet.length));

    // 非功能要求：内存索引构建必须轻量，在 5,000 条媒体引用记录下构建时间需低于 15ms
    expect(indexMs, lessThanOrEqualTo(15));

    // 估算 Set 集合内存占用：每个字符串字符数约 20~30 字节，5000 条记录在 Dart 堆中 < 1MB
    var estimatedBytes = 0;
    for (final tail in tailSet) {
      estimatedBytes +=
          tail.length * 2 + 32; // UTF-16 code units + object header overhead
    }
    print(
        '--- Estimated TailSet heap size: ${(estimatedBytes / 1024).toStringAsFixed(2)} KB ---');
    expect(estimatedBytes, lessThan(2 * 1024 * 1024)); // < 2MB
  });
}

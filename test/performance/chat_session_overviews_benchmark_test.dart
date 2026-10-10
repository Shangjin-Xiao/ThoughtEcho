import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

import '../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Benchmark getSessionOverviews in ChatSessionService', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_overviews_benchmark_');
    final dbPath = path.join(tempDir.path, 'chat.db');

    ChatSessionService? service;

    addTearDown(() async {
      await service?.close();
      await deleteDatabase(dbPath);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    service = ChatSessionService(databasePath: dbPath);
    await service.init();

    // Baseline: Generate a large number of sessions
    const sessionCount = 1500; // Need at least more than 500 to trigger chunks
    final sessionIds = <String>[];

    // Using batch for quick insertion
    final db = await databaseFactory.openDatabase(dbPath);
    final batch = db.batch();

    final createdTime =
        DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String();

    for (var i = 0; i < sessionCount; i++) {
      final sessionId = 'session-$i';
      sessionIds.add(sessionId);
      batch.insert('chat_sessions', {
        'id': sessionId,
        'session_type': 'note',
        'title': 'Session $i',
        'created_at': createdTime,
        'last_active_at': createdTime,
        'is_pinned': 0,
      });
      batch.insert('chat_messages', {
        'id': 'message-$i',
        'session_id': sessionId,
        'role': 'user',
        'content': 'Test message $i',
        'created_at': createdTime,
        'included_in_context': 1,
      });
    }
    await batch.commit(noResult: true);
    await db.close();
    // 关闭先前的连接，避免覆盖仍持有数据库连接的实例造成连接泄漏
    await service.close();

    // Re-initialize to ensure it uses a fresh, open connection.
    service = ChatSessionService(databasePath: dbPath);
    await service.init();

    // Warm up
    await service.getSessionOverviews(sessionIds.sublist(0, 50));

    final stopwatch = Stopwatch()..start();
    final result = await service.getSessionOverviews(sessionIds);
    stopwatch.stop();

    // 注意：当前基准运行在 sqflite_common_ffi 后端，主要验证 FFI 下批处理与数据解析开销；
    // 原生平台（Android/iOS/macOS）上通过减少 Method Channel IPC 往返收益将更显著。
    debugPrint(
        'Optimized time for $sessionCount sessions (FFI): ${stopwatch.elapsedMilliseconds} ms');

    // 性能回归保护阈值：1500 条会话在任何环境下均应在 5 秒内完成批量概览提取
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    expect(result.length, sessionCount);
    expect(result['session-0']?.messageCount, 1);
    expect(result['session-0']?.snippet, 'Test message 0');
  });
}

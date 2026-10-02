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

    const sessionCount = 500;
    const messagesPerSession = 20;

    final sessionIds = <String>[];

    // Seed test data using batch on open database
    final db = await openDatabase(dbPath);
    final batch = db.batch();
    final now = DateTime.now();

    for (var i = 0; i < sessionCount; i++) {
      final sessionId = 'session-$i';
      sessionIds.add(sessionId);

      batch.insert('chat_sessions', {
        'id': sessionId,
        'session_type': 'agent',
        'title': 'Session $i',
        'created_at': now.toIso8601String(),
        'last_active_at': now.toIso8601String(),
        'is_pinned': 0,
      });

      for (var j = 0; j < messagesPerSession; j++) {
        final msgTime = now.add(Duration(seconds: j));
        batch.insert('chat_messages', {
          'id': 'msg-$i-$j',
          'session_id': sessionId,
          'role': j.isEven ? 'user' : 'assistant',
          'content': 'Message content $j for session $i',
          'created_at': msgTime.toIso8601String(),
          'included_in_context': 1,
        });
      }
    }
    await batch.commit(noResult: true);

    // Re-initialize service with updated DB contents
    await service.close();
    service = ChatSessionService(databasePath: dbPath);

    // Benchmark getSessionOverviews
    final stopwatch = Stopwatch()..start();
    final overviews = await service.getSessionOverviews(sessionIds);
    stopwatch.stop();

    debugPrint(
        'getSessionOverviews time for $sessionCount sessions ($messagesPerSession msgs/session): ${stopwatch.elapsedMilliseconds} ms');

    expect(overviews.length, sessionCount);
    expect(overviews['session-0']?.messageCount, messagesPerSession);
    expect(overviews['session-0']?.snippet, 'Message content 19 for session 0');
  });
}

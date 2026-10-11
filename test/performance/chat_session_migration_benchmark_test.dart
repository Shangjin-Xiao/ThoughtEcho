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

  test('Benchmark migrateFromMainDatabase in ChatSessionService', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_migration_benchmark_');
    final mainDbPath = path.join(tempDir.path, 'main.db');
    final targetDbPath = path.join(tempDir.path, 'chat.db');

    addTearDown(() async {
      await deleteDatabase(mainDbPath);
      await deleteDatabase(targetDbPath);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final mainDb = await openDatabase(
      mainDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_sessions(
            id TEXT PRIMARY KEY,
            session_type TEXT NOT NULL DEFAULT 'note',
            note_id TEXT,
            title TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            last_active_at TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages(
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'user',
            content TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            included_in_context INTEGER NOT NULL DEFAULT 1,
            meta_json TEXT,
            content_format TEXT,
            delta_json TEXT
          )
        ''');
      },
    );

    // Seed large legacy data (5000 sessions, 10000 messages)
    const sessionCount = 5000;
    const messageCountPerSession = 2;
    final now = DateTime.now().toIso8601String();

    for (var chunkStart = 0; chunkStart < sessionCount; chunkStart += 500) {
      final batch = mainDb.batch();
      for (var i = chunkStart; i < chunkStart + 500 && i < sessionCount; i++) {
        final sessionId = 'legacy-session-$i';
        batch.insert('chat_sessions', {
          'id': sessionId,
          'session_type': 'note',
          'note_id': null,
          'title': 'Legacy Session $i',
          'created_at': now,
          'last_active_at': now,
          'is_pinned': 0,
        });
        for (var j = 0; j < messageCountPerSession; j++) {
          batch.insert('chat_messages', {
            'id': 'legacy-msg-$i-$j',
            'session_id': sessionId,
            'role': j % 2 == 0 ? 'user' : 'assistant',
            'content': 'Legacy message content $i-$j',
            'created_at': now,
            'included_in_context': 1,
            'meta_json': null,
            'content_format': null,
            'delta_json': null,
          });
        }
      }
      await batch.commit(noResult: true);
    }

    final service = ChatSessionService(databasePath: targetDbPath);
    await service.init();

    final stopwatch = Stopwatch()..start();
    await service.migrateFromMainDatabase(mainDb);
    stopwatch.stop();

    debugPrint(
        'Migration time for $sessionCount sessions and ${sessionCount * messageCountPerSession} messages: ${stopwatch.elapsedMilliseconds} ms');

    final sessions = await service.getAllSessions(limit: 10000);
    expect(sessions.length, sessionCount);

    await service.close();
    await mainDb.close();
  });
}

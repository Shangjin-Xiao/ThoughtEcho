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

  test('Benchmark empty sessions cleanup in ChatSessionService', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('chat_cleanup_benchmark_');
    final dbPath = path.join(tempDir.path, 'chat.db');

    final db = await openDatabase(
      dbPath,
      version: 2,
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
            included_in_context INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );

    // Insert 500 empty chat sessions created 10 minutes ago
    const count = 500;
    final createdTime =
        DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String();

    final batch = db.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('chat_sessions', {
        'id': 'empty-session-$i',
        'session_type': 'note',
        'title': 'Empty Session $i',
        'created_at': createdTime,
        'last_active_at': createdTime,
        'is_pinned': 0,
      });
    }
    await batch.commit(noResult: true);
    await db.close();

    final service = ChatSessionService(databasePath: dbPath);

    final stopwatch = Stopwatch()..start();
    final sessions = await service.getAllSessions();
    stopwatch.stop();

    debugPrint(
      'Cleaned up $count empty sessions in ${stopwatch.elapsedMilliseconds} ms',
    );
    expect(sessions, isEmpty);

    await service.close();
    await deleteDatabase(dbPath);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
}

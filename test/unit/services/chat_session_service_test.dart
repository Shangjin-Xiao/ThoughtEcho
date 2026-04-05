import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

import '../../test_helpers.dart';

class _FakeDatabase implements Database {
  _FakeDatabase({
    this.sessionsQueryResult = const <Map<String, Object?>>[],
  });

  final List<Map<String, Object?>> sessionsQueryResult;
  int chatSessionsInsertCount = 0;
  int chatMessagesInsertCount = 0;
  int chatSessionsUpdateCount = 0;
  final Completer<void> unblockWrites = Completer<void>();

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await unblockWrites.future;
    if (table == 'chat_sessions') {
      chatSessionsInsertCount++;
    } else if (table == 'chat_messages') {
      chatMessagesInsertCount++;
    }
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'chat_sessions') {
      return sessionsQueryResult;
    }
    return const <Map<String, Object?>>[];
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await unblockWrites.future;
    if (table == 'chat_sessions') {
      chatSessionsUpdateCount++;
    }
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(milliseconds: 400),
  Duration interval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(interval);
  }
  fail('Condition not met within $timeout');
}

void main() {
  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
  });

  group('ChatSessionService startup race handling', () {
    test('read waits and restores session after database is injected',
        () async {
      final service = ChatSessionService();
      final now = DateTime.now().toIso8601String();
      final db = _FakeDatabase(
        sessionsQueryResult: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'session-1',
            'session_type': 'note',
            'note_id': 'note-1',
            'title': 'Recovered',
            'created_at': now,
            'last_active_at': now,
            'is_pinned': 0,
          },
        ],
      );

      var resolved = false;
      final pending = service.getLatestSessionForNote('note-1').then((value) {
        resolved = true;
        return value;
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolved, isFalse);

      service.setDatabase(db);

      final result = await pending;
      expect(result, isNotNull);
      expect(result!.id, equals('session-1'));
      expect(resolved, isTrue);
    });

    test('createSession waits and persists after database injection', () async {
      final service = ChatSessionService();
      final db = _FakeDatabase();
      db.unblockWrites.complete();
      final sessionFuture = service.createSession(
        sessionType: 'note',
        noteId: 'note-2',
        title: 'Early chat',
      );

      var finished = false;
      sessionFuture.then((_) => finished = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isFalse);

      service.setDatabase(db);
      final session = await sessionFuture;
      expect(session.noteId, equals('note-2'));
      expect(db.chatSessionsInsertCount, equals(1));
    });

    test('addMessage waits and persists after database injection', () async {
      final service = ChatSessionService();
      final db = _FakeDatabase();
      db.unblockWrites.complete();
      final messageFuture = service.addMessage(
        'session-pending',
        ChatMessage(
          id: 'msg-1',
          content: 'hello',
          isUser: true,
          role: 'user',
          timestamp: DateTime.now(),
        ),
      );

      var messageFinished = false;
      messageFuture.then((_) => messageFinished = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messageFinished, isFalse);

      service.setDatabase(db);
      await messageFuture;
      await _waitFor(() => messageFinished);
      expect(db.chatMessagesInsertCount, equals(1));
      expect(db.chatSessionsUpdateCount, equals(1));
    });

    test('write operations queue when database not ready and flush later',
        () async {
      final service = ChatSessionService();
      final message = ChatMessage(
        id: 'queued-msg',
        content: 'queued',
        isUser: true,
        role: 'user',
        timestamp: DateTime.now(),
      );

      await service.addMessage('queued-session', message);

      final db = _FakeDatabase();
      service.setDatabase(db);
      db.unblockWrites.complete();

      await _waitFor(() => db.chatMessagesInsertCount == 1);
      expect(db.chatMessagesInsertCount, equals(1));
      expect(db.chatSessionsUpdateCount, equals(1));
    });
  });
}

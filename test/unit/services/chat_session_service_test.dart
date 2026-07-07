import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

import '../../test_helpers.dart';

class _FakeDatabase implements Database, Transaction {
  _FakeDatabase({this.sessionsQueryResult = const <Map<String, Object?>>[]});

  final List<Map<String, Object?>> sessionsQueryResult;
  int chatSessionsInsertCount = 0;
  int chatMessagesInsertCount = 0;
  int chatSessionsUpdateCount = 0;
  final Completer<void> unblockWrites = Completer<void>();

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    return await action(this);
  }

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
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatSessionService startup race handling', () {
    test(
      'read waits and restores session after database is injected',
      () async {
        final service = ChatSessionService(openOwnDatabase: false);
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
      },
    );

    test('createSession waits and persists after database injection', () async {
      final service = ChatSessionService(openOwnDatabase: false);
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
      final service = ChatSessionService(openOwnDatabase: false);
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

    test(
      'write operations queue when database not ready and flush later',
      () async {
        final service = ChatSessionService(openOwnDatabase: false);
        final message = ChatMessage(
          id: 'queued-msg',
          content: 'queued',
          isUser: true,
          role: 'user',
          timestamp: DateTime.now(),
        );

        final messageFuture = service.addMessage('queued-session', message);

        final db = _FakeDatabase();
        service.setDatabase(db);
        db.unblockWrites.complete();

        await messageFuture;

        await _waitFor(() => db.chatMessagesInsertCount == 1);
        expect(db.chatMessagesInsertCount, equals(1));
        expect(db.chatSessionsUpdateCount, equals(1));
      },
    );
  });

  group('ChatSessionService independent chat database', () {
    late Directory tempDir;
    late String databasePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chat_session_test_');
      databasePath = path.join(tempDir.path, 'chat.db');
    });

    tearDown(() async {
      await deleteDatabase(databasePath);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('opens its own chat database without main database injection',
        () async {
      final service = ChatSessionService(databasePath: databasePath);

      final session = await service.createSession(
        sessionType: 'agent',
        title: 'AI Chat',
      );
      await service.addMessage(
        session.id,
        ChatMessage(
          id: 'message-1',
          content: 'hello from independent chat db',
          isUser: true,
          role: 'user',
          timestamp: DateTime.now(),
        ),
      );

      final messages = await service.getMessages(session.id);
      final db = await openDatabase(databasePath);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      await db.close();

      expect(messages, hasLength(1));
      expect(messages.single.content, contains('independent chat db'));
      expect(tables.map((row) => row['name']), contains('chat_sessions'));
      expect(tables.map((row) => row['name']), isNot(contains('quotes')));
      await service.close();
    });

    test('repairs legacy chat_messages missing rich content columns', () async {
      final legacyDb = await openDatabase(databasePath);
      await legacyDb.execute('''
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
      await legacyDb.execute('''
        CREATE TABLE chat_messages(
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'user',
          content TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          included_in_context INTEGER NOT NULL DEFAULT 1,
          meta_json TEXT
        )
      ''');
      await legacyDb.setVersion(1);
      await legacyDb.close();

      final service = ChatSessionService(databasePath: databasePath);
      final session = await service.createSession(
        sessionType: 'agent',
        title: 'Migrated chat',
      );
      await service.addMessage(
        session.id,
        ChatMessage(
          id: 'message-1',
          content: 'hello',
          isUser: true,
          role: 'user',
          timestamp: DateTime.now(),
        ),
      );

      final messages = await service.getMessages(session.id);

      expect(messages, hasLength(1));
      expect(messages.single.contentFormat, isNull);
      expect(messages.single.deltaJson, isNull);
      await service.close();
    });

    test('searches titles and message bodies with hit snippets', () async {
      final service = ChatSessionService(databasePath: databasePath);
      final session = await service.createSession(
        sessionType: 'agent',
        title: 'Weekly reflection',
      );
      await service.addMessage(
        session.id,
        ChatMessage(
          id: 'message-1',
          content:
              'A long prefix that should not be returned as the only preview. '
              'The important keyword appears near the end with useful context.',
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.now(),
        ),
      );

      final results = await service.searchSessions('keyword');

      expect(results, hasLength(1));
      expect(results.single.session.id, session.id);
      expect(results.single.snippet, contains('keyword'));
      expect(results.single.snippet, contains('important'));
      expect(results.single.snippet.startsWith('A long prefix'), isFalse);
      expect(results.single.isTruncated, isTrue);
      await service.close();
    });

    test('migrates legacy chat tables from main database idempotently',
        () async {
      final mainDbPath = path.join(tempDir.path, 'main.db');
      final mainDb = await openDatabase(mainDbPath);
      await mainDb.execute('''
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
      await mainDb.execute('''
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
      final now = DateTime.now().toIso8601String();
      await mainDb.insert('chat_sessions', {
        'id': 'legacy-session',
        'session_type': 'agent',
        'note_id': null,
        'title': 'Legacy chat',
        'created_at': now,
        'last_active_at': now,
        'is_pinned': 0,
      });
      await mainDb.insert('chat_messages', {
        'id': 'legacy-message',
        'session_id': 'legacy-session',
        'role': 'user',
        'content': 'old chat content',
        'created_at': now,
        'included_in_context': 1,
        'meta_json': null,
        'content_format': null,
        'delta_json': null,
      });

      final service = ChatSessionService(databasePath: databasePath);
      await service.init();
      await service.migrateFromMainDatabase(mainDb);
      await service.migrateFromMainDatabase(mainDb);

      final sessions = await service.getAllSessions();
      final messages = await service.getMessages('legacy-session');

      expect(sessions.map((s) => s.id), contains('legacy-session'));
      expect(messages, hasLength(1));
      expect(messages.single.content, 'old chat content');

      await service.close();
      await mainDb.close();
      await deleteDatabase(mainDbPath);
    });
  });
}

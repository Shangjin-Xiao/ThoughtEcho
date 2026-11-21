import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(TestHarness.tearDown);

  late Directory tempDir;
  late String dbPath;
  late ChatSessionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_sync_test_');
    dbPath = p.join(tempDir.path, 'chat.db');
    service = ChatSessionService(databasePath: dbPath);
    await service.init();
  });

  tearDown(() async {
    await service.close();
    service.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ChatSession?> querySession(String targetPath, String sessionId) async {
    final db = await openDatabase(targetPath, singleInstance: true);
    final rows = await db.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatSession.fromMap(rows.first);
  }

  Future<List<Map<String, Object?>>> queryTombstones(String targetPath) async {
    final db = await openDatabase(targetPath, singleInstance: true);
    return db.query(
      'chat_tombstones',
      orderBy: 'entity_type ASC, entity_id ASC',
    );
  }

  group('chat.db schema v2 -> v3 迁移', () {
    test('升级时创建 chat_tombstones 并按契约回填 sessions/messages 的 updated_at',
        () async {
      final legacyPath = p.join(tempDir.path, 'legacy_v2_chat.db');
      final rawV2 = await openDatabase(
        legacyPath,
        version: 2,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE chat_sessions(
              id TEXT PRIMARY KEY,
              session_type TEXT NOT NULL DEFAULT 'agent',
              note_id TEXT,
              title TEXT NOT NULL DEFAULT '新对话',
              created_at TEXT NOT NULL,
              last_active_at TEXT NOT NULL,
              is_pinned INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE chat_messages(
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at TEXT NOT NULL,
              included_in_context INTEGER NOT NULL DEFAULT 1,
              meta_json TEXT,
              content_format TEXT NOT NULL DEFAULT 'plain',
              delta_json TEXT,
              FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
            )
          ''');
        },
      );

      await rawV2.insert('chat_sessions', <String, Object?>{
        'id': 's_with_active',
        'session_type': 'agent',
        'title': '旧会话A',
        'created_at': '2026-10-01T08:00:00.000Z',
        'last_active_at': '2026-10-02T12:30:00.000Z',
        'is_pinned': 0,
      });
      await rawV2.insert('chat_sessions', <String, Object?>{
        'id': 's_empty_active',
        'session_type': 'note',
        'note_id': 'note_1',
        'title': '旧会话B',
        'created_at': '2026-10-03T09:15:00.000Z',
        'last_active_at': '',
        'is_pinned': 1,
      });
      await rawV2.insert('chat_messages', <String, Object?>{
        'id': 'm_legacy_1',
        'session_id': 's_with_active',
        'role': 'user',
        'content': '合成测试提问一',
        'created_at': '2026-10-02T12:30:00.000Z',
      });
      await rawV2.close();

      final upgraded = ChatSessionService(databasePath: legacyPath);
      try {
        await upgraded.init();

        final inspectDb = await openDatabase(legacyPath, singleInstance: true);
        expect(await inspectDb.getVersion(), 3);

        final sessionRows = await inspectDb.query(
          'chat_sessions',
          orderBy: 'id ASC',
        );
        final byId = <String, Map<String, Object?>>{
          for (final r in sessionRows) r['id'] as String: r,
        };
        expect(
          byId['s_with_active']!['updated_at'],
          '2026-10-02T12:30:00.000000Z',
        );
        expect(
          byId['s_empty_active']!['updated_at'],
          '2026-10-03T09:15:00.000000Z',
        );

        final messageRows = await inspectDb.query('chat_messages');
        expect(messageRows, hasLength(1));
        expect(
          messageRows.single['updated_at'],
          '2026-10-02T12:30:00.000000Z',
        );

        final tombstones = await inspectDb.query('chat_tombstones');
        expect(tombstones, isEmpty);
      } finally {
        await upgraded.close();
        upgraded.dispose();
      }
    });
  });

  group('写入路径 updated_at 与墓碑边界', () {
    test(
        '元数据修改刷新会话 updated_at，addMessage 仅推进会话 last_active_at 且刷新消息 updated_at',
        () async {
      final created = await service.createSession(
        sessionType: 'agent',
        title: '初始标题',
      );
      expect(created.updatedAt, isNotNull);
      expect(created.updatedAt!.isUtc, isTrue);

      final initialSessionUpdatedAt = created.updatedAt!;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      final msgTime = DateTime.now().toUtc();
      final msg1 = ChatMessage(
        id: 'm1',
        content: '第一版消息内容',
        isUser: true,
        role: 'user',
        timestamp: msgTime,
      );
      await service.addMessage(created.id, msg1);

      final afterMsgSession = await querySession(dbPath, created.id);
      expect(afterMsgSession, isNotNull);
      // addMessage 不得刷新会话 updated_at，以免覆盖对端标题/置顶修改
      expect(afterMsgSession!.updatedAt, initialSessionUpdatedAt);
      expect(
        !afterMsgSession.lastActiveAt.isBefore(created.lastActiveAt),
        isTrue,
      );

      final loadedMsgs1 = await service.getMessages(created.id);
      expect(loadedMsgs1.single.updatedAt, isNotNull);
      final firstMsgUpdated = loadedMsgs1.single.updatedAt!;

      // 消息覆盖回写（如保存笔记回写 meta_json / 工具状态回写）必须刷新消息 updated_at
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await service.addMessage(
        created.id,
        msg1.copyWith(
          content: '回写后的消息内容',
          metaJson: '{"saved_note_id":"synthetic_note_1"}',
        ),
      );
      final loadedMsgs2 = await service.getMessages(created.id);
      expect(loadedMsgs2.single.content, '回写后的消息内容');
      expect(loadedMsgs2.single.updatedAt!.isAfter(firstMsgUpdated), isTrue);

      // 修改标题、置顶时必须刷新会话 updated_at
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await service.updateSessionTitle(created.id, '重命名标题');
      final afterTitle = (await querySession(dbPath, created.id))!;
      expect(afterTitle.updatedAt!.isAfter(initialSessionUpdatedAt), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 15));
      await service.togglePin(created.id);
      final afterPin = (await querySession(dbPath, created.id))!;
      expect(afterPin.isPinned, isTrue);
      expect(afterPin.updatedAt!.isAfter(afterTitle.updatedAt!), isTrue);
    });

    test('显式删除会话/消息/清空/按笔记删除均在同一事务写入墓碑', () async {
      final s1 = await service.createSession(
        sessionType: 'agent',
        title: '会话1',
      );
      await service.addMessage(
        s1.id,
        ChatMessage(
          id: 's1_m1',
          content: '测试消息1',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 10, 0),
        ),
      );
      await service.addMessage(
        s1.id,
        ChatMessage(
          id: 's1_m2',
          content: '测试回复1',
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.utc(2026, 11, 1, 10, 1),
        ),
      );

      // 删除单条消息
      await service.deleteMessage('s1_m1');
      var tombs = await queryTombstones(dbPath);
      expect(
        tombs.any(
          (t) => t['entity_type'] == 'message' && t['entity_id'] == 's1_m1',
        ),
        isTrue,
      );

      // 清空会话消息
      await service.clearMessages(s1.id);
      tombs = await queryTombstones(dbPath);
      expect(
        tombs.any(
          (t) => t['entity_type'] == 'message' && t['entity_id'] == 's1_m2',
        ),
        isTrue,
      );

      // 删除整个会话（连带级联消息）
      await service.addMessage(
        s1.id,
        ChatMessage(
          id: 's1_m3',
          content: '测试消息3',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 10, 2),
        ),
      );
      await service.deleteSession(s1.id);
      tombs = await queryTombstones(dbPath);
      expect(
        tombs.any(
          (t) => t['entity_type'] == 'session' && t['entity_id'] == s1.id,
        ),
        isTrue,
      );
      expect(
        tombs.any(
          (t) => t['entity_type'] == 'message' && t['entity_id'] == 's1_m3',
        ),
        isTrue,
      );

      // 批量删除会话 & 按笔记删除会话
      final s2 = await service.createSession(
        sessionType: 'agent',
        title: '批量删会话',
      );
      await service.addMessage(
        s2.id,
        ChatMessage(
          id: 's2_m1',
          content: '批量删消息',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 11, 0),
        ),
      );
      await service.deleteSessions(<String>[s2.id]);

      final sNote = await service.createSession(
        sessionType: 'note',
        noteId: 'note_to_purge',
        title: '关联笔记会话',
      );
      await service.addMessage(
        sNote.id,
        ChatMessage(
          id: 'sn_m1',
          content: '笔记关联提问',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 11, 5),
        ),
      );
      await service.deleteSessionsForNote('note_to_purge');

      tombs = await queryTombstones(dbPath);
      final tombPairs =
          tombs.map((t) => '${t['entity_type']}:${t['entity_id']}').toSet();
      expect(
        tombPairs,
        containsAll(<String>[
          'session:${s2.id}',
          'message:s2_m1',
          'session:${sNote.id}',
          'message:sn_m1',
        ]),
      );
    });

    test('deleteEmptySession 与后台空会话清扫不写墓碑，且有用户消息时拒绝误删', () async {
      // 1. 完全无消息的空会话
      final empty1 = await service.createSession(
        sessionType: 'agent',
        title: '纯空会话',
      );
      expect(await service.deleteEmptySession(empty1.id), isTrue);
      expect(await querySession(dbPath, empty1.id), isNull);
      expect(await queryTombstones(dbPath), isEmpty);

      // 2. 仅有 assistant 欢迎语、无 user 消息的空会话
      final emptyWithGreeting = await service.createSession(
        sessionType: 'agent',
        title: '仅欢迎语会话',
      );
      await service.addMessage(
        emptyWithGreeting.id,
        ChatMessage(
          id: 'greet_1',
          content: '你好，我是测试助手',
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.utc(2026, 11, 1, 12, 0),
        ),
      );
      expect(await service.deleteEmptySession(emptyWithGreeting.id), isTrue);
      expect(await querySession(dbPath, emptyWithGreeting.id), isNull);
      expect(await queryTombstones(dbPath), isEmpty);

      // 3. 已有 user 消息时 deleteEmptySession 不得删除
      final nonEmpty = await service.createSession(
        sessionType: 'agent',
        title: '有效会话',
      );
      await service.addMessage(
        nonEmpty.id,
        ChatMessage(
          id: 'user_msg_1',
          content: '真实提问',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 12, 5),
        ),
      );
      expect(await service.deleteEmptySession(nonEmpty.id), isFalse);
      expect(await querySession(dbPath, nonEmpty.id), isNotNull);
      expect(await queryTombstones(dbPath), isEmpty);

      // 4. getAllSessions 后台清理超 5 分钟空会话同样不写墓碑
      final db = await openDatabase(dbPath, singleInstance: true);
      final staleTime = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      await db.insert('chat_sessions', <String, Object?>{
        'id': 'stale_empty_bg',
        'session_type': 'agent',
        'title': '过期空会话',
        'created_at': staleTime,
        'last_active_at': staleTime,
        'updated_at': staleTime,
        'is_pinned': 0,
      });

      final reopened = ChatSessionService(databasePath: dbPath);
      try {
        await reopened.init();
        await reopened.getAllSessions();
        expect(await querySession(dbPath, 'stale_empty_bg'), isNull);
        expect(await queryTombstones(dbPath), isEmpty);
      } finally {
        await reopened.close();
        reopened.dispose();
      }
    });
  });

  group('流式导出、LWW 合并与覆盖恢复', () {
    test('分页流式导出完整写出 sessions、messages 与 tombstones', () async {
      final session = await service.createSession(
        sessionType: 'agent',
        title: '分页测试会话',
      );
      for (var i = 0; i < 7; i++) {
        await service.addMessage(
          session.id,
          ChatMessage(
            id: 'page_msg_$i',
            content: '分页消息文本 $i',
            isUser: i.isEven,
            role: i.isEven ? 'user' : 'assistant',
            timestamp: DateTime.utc(2026, 11, 2, 10, i),
          ),
        );
      }
      await service.deleteMessage('page_msg_6');

      final exported = await service.exportChatSectionForTesting(
        messagePageSize: 3,
      );
      expect(exported['format'], 1);
      expect((exported['sessions'] as List), hasLength(1));
      expect((exported['messages'] as List), hasLength(6));
      expect(
        (exported['messages'] as List).map((m) => (m as Map)['id']).toList(),
        <String>[
          'page_msg_0',
          'page_msg_1',
          'page_msg_2',
          'page_msg_3',
          'page_msg_4',
          'page_msg_5',
        ],
      );
      expect((exported['tombstones'] as List), hasLength(1));
      expect(
        ((exported['tombstones'] as List).single as Map)['entity_id'],
        'page_msg_6',
      );
    });

    test(
        '会话与消息 LWW：updated_at 择新覆盖元数据、last_active_at 取晚、created_at 取早，孤儿 note_id 会话保留',
        () async {
      final db = await openDatabase(dbPath, singleInstance: true);
      await db.insert('chat_sessions', <String, Object?>{
        'id': 's_lww',
        'session_type': 'agent',
        'note_id': null,
        'title': '本地旧标题',
        'created_at': '2026-11-01T10:00:00.000Z',
        'last_active_at': '2026-11-05T18:00:00.000Z', // 本地活跃时间更晚
        'updated_at': '2026-11-02T10:00:00.000Z', // 但元数据较旧
        'is_pinned': 0,
      });
      await db.insert('chat_messages', <String, Object?>{
        'id': 'm_lww',
        'session_id': 's_lww',
        'role': 'assistant',
        'content': '本地旧回复',
        'created_at': '2026-11-01T10:01:00.000Z',
        'updated_at': '2026-11-01T10:01:00.000Z',
        'included_in_context': 1,
        'content_format': 'plain',
      });

      var notifiedCount = 0;
      service.addListener(() => notifiedCount++);

      final stats = await service.mergeChatSection(<String, dynamic>{
        'format': 1,
        'sessions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 's_lww',
            'session_type': 'note',
            'note_id': 'non_existent_orphan_note', // 主库不存在的孤儿 note_id 必须保留
            'title': '远端新标题',
            'created_at': '2026-10-28T09:00:00.000Z', // 远端创建时间更早
            'last_active_at': '2026-11-03T12:00:00.000Z', // 远端活跃时间较早
            'updated_at': '2026-11-04T12:00:00.000Z', // 远端元数据更新
            'is_pinned': 1,
            'unknown_future_col': 'ignored_value',
          },
        ],
        'messages': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'm_lww',
            'session_id': 's_lww',
            'role': 'assistant',
            'content': '远端更新后回复',
            'created_at': '2026-11-01T10:01:00.000Z',
            'updated_at': '2026-11-04T12:05:00.000Z',
            'included_in_context': 1,
            'meta_json': '{"saved_note_id":"orphan_1"}',
            'content_format': 'plain',
            'extra_col': 123,
          },
        ],
        'tombstones': const <Object?>[],
      });

      expect(stats.sessionsUpdated, 1);
      expect(stats.messagesUpdated, 1);
      expect(notifiedCount, 1);

      final mergedSession = (await querySession(dbPath, 's_lww'))!;
      expect(mergedSession.title, '远端新标题');
      expect(mergedSession.isPinned, isTrue);
      expect(mergedSession.sessionType, 'note');
      expect(mergedSession.noteId, 'non_existent_orphan_note');
      expect(
        mergedSession.createdAt,
        DateTime.parse('2026-10-28T09:00:00.000Z'),
      );
      expect(
        mergedSession.lastActiveAt,
        DateTime.parse('2026-11-05T18:00:00.000Z'),
      );
      expect(
        mergedSession.updatedAt,
        DateTime.parse('2026-11-04T12:00:00.000Z'),
      );

      final mergedMsg = (await service.getMessages('s_lww')).single;
      expect(mergedMsg.content, '远端更新后回复');
      expect(mergedMsg.metaJson, '{"saved_note_id":"orphan_1"}');
    });

    test('双向墓碑：deleted_at >= updated_at 删除并级联，updated_at > deleted_at 复活并清理旧墓碑',
        () async {
      final db = await openDatabase(dbPath, singleInstance: true);
      // 本地会话 s_to_kill (updated_at == 远端墓碑 deleted_at，验证 >= 边界)
      await db.insert('chat_sessions', <String, Object?>{
        'id': 's_to_kill',
        'session_type': 'agent',
        'title': '待墓碑删除会话',
        'created_at': '2026-11-01T00:00:00.000Z',
        'last_active_at': '2026-11-02T10:00:00.000Z',
        'updated_at': '2026-11-02T10:00:00.000Z',
        'is_pinned': 0,
      });
      await db.insert('chat_messages', <String, Object?>{
        'id': 'm_cascade',
        'session_id': 's_to_kill',
        'role': 'user',
        'content': '级联待删消息',
        'created_at': '2026-11-02T10:00:00.000Z',
        'updated_at': '2026-11-02T10:00:00.000Z',
      });

      // 本地会话 s_local_newer (updated_at > 远端墓碑 deleted_at，应保留)
      await db.insert('chat_sessions', <String, Object?>{
        'id': 's_local_newer',
        'session_type': 'agent',
        'title': '本地重新编辑过的会话',
        'created_at': '2026-11-01T00:00:00.000Z',
        'last_active_at': '2026-11-04T10:00:00.000Z',
        'updated_at': '2026-11-04T10:00:00.000Z',
        'is_pinned': 1,
      });

      // 本地墓碑：s_resurrect 曾被删，但远端传来更新的 updated_at 应复活并删除墓碑；
      // s_stay_dead 远端 updated_at <= 本地墓碑 deleted_at 应被拦截跳过。
      await db.insert('chat_tombstones', <String, Object?>{
        'entity_type': 'session',
        'entity_id': 's_resurrect',
        'deleted_at': '2026-11-03T00:00:00.000Z',
      });
      await db.insert('chat_tombstones', <String, Object?>{
        'entity_type': 'session',
        'entity_id': 's_stay_dead',
        'deleted_at': '2026-11-03T00:00:00.000Z',
      });

      final stats = await service.mergeChatSection(<String, dynamic>{
        'format': 1,
        'sessions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 's_resurrect',
            'session_type': 'agent',
            'title': '复活会话',
            'created_at': '2026-11-01T00:00:00.000Z',
            'last_active_at': '2026-11-05T00:00:00.000Z',
            'updated_at': '2026-11-05T00:00:00.000Z',
            'is_pinned': 0,
          },
          <String, Object?>{
            'id': 's_stay_dead',
            'session_type': 'agent',
            'title': '不应复活会话',
            'created_at': '2026-11-01T00:00:00.000Z',
            'last_active_at': '2026-11-03T00:00:00.000Z',
            'updated_at': '2026-11-03T00:00:00.000Z', // == deleted_at -> 跳过
            'is_pinned': 0,
          },
        ],
        'messages': <Map<String, Object?>>[
          // 父会话 s_to_kill 被墓碑删除，此孤立消息应跳过并计入 messagesSkipped
          <String, Object?>{
            'id': 'm_orphan_remote',
            'session_id': 's_to_kill',
            'role': 'user',
            'content': '缺父会话消息',
            'created_at': '2026-11-02T11:00:00.000Z',
            'updated_at': '2026-11-02T11:00:00.000Z',
          },
          <String, Object?>{
            'id': 'm_resurrected',
            'session_id': 's_resurrect',
            'role': 'user',
            'content': '复活会话下的消息',
            'created_at': '2026-11-05T00:00:00.000Z',
            'updated_at': '2026-11-05T00:00:00.000Z',
          },
        ],
        'tombstones': <Map<String, Object?>>[
          <String, Object?>{
            'entity_type': 'session',
            'entity_id': 's_to_kill',
            'deleted_at': '2026-11-02T10:00:00.000Z', // == local updated_at
          },
          <String, Object?>{
            'entity_type': 'session',
            'entity_id': 's_local_newer',
            'deleted_at': '2026-11-03T00:00:00.000Z', // < local updated_at
          },
        ],
      });

      expect(stats.sessionsDeleted, 1);
      expect(stats.sessionsAdded, 1);
      expect(stats.sessionsSkipped, 1);
      expect(stats.messagesAdded, 1);
      expect(stats.messagesSkipped, 1);

      expect(await querySession(dbPath, 's_to_kill'), isNull);
      expect(await service.getMessages('s_to_kill'), isEmpty);
      expect(await querySession(dbPath, 's_local_newer'), isNotNull);
      expect(await querySession(dbPath, 's_resurrect'), isNotNull);
      expect(await service.getMessages('s_resurrect'), hasLength(1));
      expect(await querySession(dbPath, 's_stay_dead'), isNull);

      final tombs = await queryTombstones(dbPath);
      final sessionTombIds = tombs
          .where((t) => t['entity_type'] == 'session')
          .map((t) => t['entity_id'] as String)
          .toSet();
      final cutoffTombIds = tombs
          .where((t) => t['entity_type'] == 'session_cutoff')
          .map((t) => t['entity_id'] as String)
          .toSet();
      expect(sessionTombIds, contains('s_to_kill'));
      expect(sessionTombIds, contains('s_stay_dead'));
      expect(sessionTombIds, isNot(contains('s_resurrect')));
      expect(sessionTombIds, isNot(contains('s_local_newer')));
      expect(cutoffTombIds, contains('s_resurrect'));
      expect(cutoffTombIds, contains('s_local_newer'));
    });

    test('坏行与缺父会话消息被安全跳过并计数', () async {
      final stats = await service.mergeChatSection(<String, dynamic>{
        'format': 1,
        'sessions': <Object?>[
          'not_a_map',
          <String, Object?>{'id': '', 'created_at': '2026-11-01T00:00:00Z'},
          <String, Object?>{
            'id': 'bad_ts_session',
            'created_at': 'not-a-timestamp',
            'last_active_at': '2026-11-01T00:00:00Z',
          },
          <String, Object?>{
            'id': 'good_session',
            'session_type': 'agent',
            'title': '合法会话',
            'created_at': '2026-11-01T00:00:00.000Z',
            'last_active_at': '2026-11-01T00:00:00.000Z',
            'updated_at': '2026-11-01T00:00:00.000Z',
          },
        ],
        'messages': <Object?>[
          42,
          <String, Object?>{
            'id': 'missing_parent_msg',
            'session_id': 'ghost_session',
            'role': 'user',
            'content': '缺父会话消息正文',
            'created_at': '2026-11-01T00:01:00.000Z',
          },
          <String, Object?>{
            'id': 'bad_role_msg',
            'session_id': 'good_session',
            'role': '',
            'content': '空角色坏行',
            'created_at': '2026-11-01T00:01:00.000Z',
          },
          <String, Object?>{
            'id': 'good_msg',
            'session_id': 'good_session',
            'role': 'user',
            'content': '合法消息',
            'created_at': '2026-11-01T00:02:00.000Z',
            'updated_at': '2026-11-01T00:02:00.000Z',
          },
        ],
        'tombstones': <Object?>[
          <String, Object?>{'entity_type': 'unknown', 'entity_id': 'x'},
        ],
      });

      expect(stats.sessionsAdded, 1);
      expect(stats.sessionsSkipped, 4);
      expect(stats.messagesAdded, 1);
      expect(stats.messagesSkipped, 3);
      expect(await service.getMessages('good_session'), hasLength(1));
    });

    test('覆盖恢复：传入合法 chat 段整库替换，传入 null（旧包无此键）保留本地不动', () async {
      final localSession = await service.createSession(
        sessionType: 'agent',
        title: '本地原会话',
      );
      await service.addMessage(
        localSession.id,
        ChatMessage(
          id: 'local_msg_1',
          content: '本地原消息',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 8, 0),
        ),
      );

      // 1. 旧备份无 chat 段 -> 本地完全不动
      await service.restoreChatSection(null);
      expect(await querySession(dbPath, localSession.id), isNotNull);
      expect(await service.getMessages(localSession.id), hasLength(1));

      // 2. 新备份含 chat 段 -> 整库替换会话、消息与墓碑
      final replacementJson = jsonDecode('''
      {
        "format": 1,
        "sessions": [
          {
            "id": "restored_s1",
            "session_type": "agent",
            "title": "恢复的会话",
            "created_at": "2026-11-10T09:00:00.000Z",
            "last_active_at": "2026-11-10T09:05:00.000Z",
            "updated_at": "2026-11-10T09:05:00.000Z",
            "is_pinned": 1
          }
        ],
        "messages": [
          {
            "id": "restored_m1",
            "session_id": "restored_s1",
            "role": "user",
            "content": "恢复的消息内容",
            "created_at": "2026-11-10T09:05:00.000Z",
            "updated_at": "2026-11-10T09:05:00.000Z",
            "included_in_context": 1,
            "content_format": "plain"
          }
        ],
        "tombstones": [
          {
            "entity_type": "session",
            "entity_id": "deleted_old_s",
            "deleted_at": "2026-11-09T00:00:00.000Z"
          }
        ]
      }
      ''') as Map<String, dynamic>;

      await service.restoreChatSection(replacementJson);

      expect(await querySession(dbPath, localSession.id), isNull);
      final restoredSession = await querySession(dbPath, 'restored_s1');
      expect(restoredSession, isNotNull);
      expect(restoredSession!.title, '恢复的会话');
      expect(
        (await service.getMessages('restored_s1')).single.id,
        'restored_m1',
      );
      final tombs = await queryTombstones(dbPath);
      expect(tombs, hasLength(1));
      expect(tombs.single['entity_id'], 'deleted_old_s');
    });
  });

  group('审查回归：跨时区时间戳排序、离线新消息防静默丢失与同时间戳收敛', () {
    test(
        '问题6：UTC+8 设备 09:00+08:00 提问、UTC 设备 02:00Z 回复，双向同步后两端消息与会话排序严格一致，旧库无偏移时间自动归一化',
        () async {
      final dir = await Directory.systemTemp.createTemp('chat_tz_');
      final pathUtc8 = p.join(dir.path, 'utc8.db');
      final pathUtc0 = p.join(dir.path, 'utc0.db');
      final devUtc8 = ChatSessionService(databasePath: pathUtc8);
      final devUtc0 = ChatSessionService(databasePath: pathUtc0);
      try {
        await devUtc8.init();
        await devUtc0.init();

        // 模拟 UTC+8 设备写入带 +08:00 偏移的历史行（2026-11-19T09:00:00+08:00 == 01:00:00Z）
        final payloadFromUtc8 = <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 's_cross_tz',
              'session_type': 'agent',
              'title': '跨时区讨论会话',
              'created_at': '2026-11-19T09:00:00+08:00',
              'last_active_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
              'is_pinned': 0,
            },
            <String, Object?>{
              'id': 's_older_utc8',
              'session_type': 'agent',
              'title': '更早的 UTC+8 会话',
              // 2026-11-19T09:30:00+08:00 == 01:30:00Z，字典序 '09:30' 虽大于 '02:00Z'，但真实时间早于 02:00Z！
              'created_at': '2026-11-19T09:30:00+08:00',
              'last_active_at': '2026-11-19T09:30:00+08:00',
              'updated_at': '2026-11-19T09:30:00+08:00',
              'is_pinned': 0,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm_question_utc8',
              'session_id': 's_cross_tz',
              'role': 'user',
              'content': '来自东八区上午九点的提问',
              'created_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
            },
            <String, Object?>{
              'id': 'm_older_utc8_msg',
              'session_id': 's_older_utc8',
              'role': 'user',
              'content': '另一条东八区会话里的用户消息',
              'created_at': '2026-11-19T09:30:00+08:00',
              'updated_at': '2026-11-19T09:30:00+08:00',
            },
          ],
          'tombstones': const <Object?>[],
        };

        // UTC 设备在 1 小时后（2026-11-19T02:00:00Z）回复消息
        final payloadFromUtc0 = <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 's_cross_tz',
              'session_type': 'agent',
              'title': '跨时区讨论会话',
              'created_at': '2026-11-19T01:00:00.000Z',
              'last_active_at': '2026-11-19T02:00:00.000Z',
              'updated_at': '2026-11-19T01:00:00.000Z',
              'is_pinned': 0,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm_reply_utc0',
              'session_id': 's_cross_tz',
              'role': 'assistant',
              'content': '一小时后来自零时区的回复',
              'created_at': '2026-11-19T02:00:00.000Z',
              'updated_at': '2026-11-19T02:00:00.000Z',
            },
          ],
          'tombstones': const <Object?>[],
        };

        await devUtc8.mergeChatSection(payloadFromUtc8);
        await devUtc8.mergeChatSection(payloadFromUtc0);

        await devUtc0.mergeChatSection(payloadFromUtc0);
        await devUtc0.mergeChatSection(payloadFromUtc8);

        for (final dev in <ChatSessionService>[devUtc8, devUtc0]) {
          final msgs = await dev.getMessages('s_cross_tz');
          expect(
            msgs.map((m) => m.id).toList(),
            <String>['m_question_utc8', 'm_reply_utc0'],
          );
          final sessions = await dev.getAllSessions();
          // s_cross_tz 最新活跃为 02:00Z > s_older_utc8 的 01:30Z，故排在最前
          expect(
            sessions.map((s) => s.id).toList(),
            <String>['s_cross_tz', 's_older_utc8'],
          );
        }

        // 同时验证旧库遗留偏移字符串在重新打开 init 时被幂等归一化为标准 Z 格式
        final legacyDbPath = p.join(dir.path, 'legacy_offset.db');
        final rawLegacy = await openDatabase(
          legacyDbPath,
          version: 3,
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE chat_sessions (
                id TEXT PRIMARY KEY,
                session_type TEXT NOT NULL,
                note_id TEXT,
                title TEXT,
                created_at TEXT NOT NULL,
                last_active_at TEXT NOT NULL,
                updated_at TEXT,
                is_pinned INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE chat_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE chat_tombstones (
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                deleted_at TEXT NOT NULL,
                PRIMARY KEY (entity_type, entity_id)
              )
            ''');
            await db.insert('chat_sessions', <String, Object?>{
              'id': 'legacy_s',
              'session_type': 'agent',
              'title': '历史偏移会话',
              'created_at': '2026-11-19T09:00:00+08:00',
              'last_active_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
            });
            await db.insert('chat_messages', <String, Object?>{
              'id': 'legacy_m',
              'session_id': 'legacy_s',
              'role': 'user',
              'content': '历史偏移消息',
              'created_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
            });
          },
        );
        await rawLegacy.close();

        final migratedService = ChatSessionService(databasePath: legacyDbPath);
        try {
          await migratedService.init();
          // Devin 审查回归 #26：直接查验底层 SQLite 原生表，确认启动归一化已在落盘层写回定宽 6 位 UTC 且保留 *_backup 快照
          final inspectLegacyDb =
              await openDatabase(legacyDbPath, singleInstance: true);
          final rawSessionRow =
              (await inspectLegacyDb.query('chat_sessions')).single;
          final rawMsgRow =
              (await inspectLegacyDb.query('chat_messages')).single;
          expect(rawSessionRow['created_at'], '2026-11-19T01:00:00.000000Z');
          expect(
            rawSessionRow['last_active_at'],
            '2026-11-19T01:00:00.000000Z',
          );
          expect(rawSessionRow['updated_at'], '2026-11-19T01:00:00.000000Z');
          expect(
            rawSessionRow['created_at_backup'],
            '2026-11-19T09:00:00+08:00',
          );
          expect(rawMsgRow['created_at'], '2026-11-19T01:00:00.000000Z');
          expect(rawMsgRow['updated_at'], '2026-11-19T01:00:00.000000Z');
          expect(rawMsgRow['created_at_backup'], '2026-11-19T09:00:00+08:00');

          final exported = await migratedService.exportChatSectionForTesting();
          final sRow = (exported['sessions'] as List).single as Map;
          final mRow = (exported['messages'] as List).single as Map;
          expect(sRow['created_at'], '2026-11-19T01:00:00.000000Z');
          expect(mRow['created_at'], '2026-11-19T01:00:00.000000Z');
        } finally {
          await migratedService.close();
          migratedService.dispose();
        }
      } finally {
        await devUtc8.close();
        devUtc8.dispose();
        await devUtc0.close();
        devUtc0.dispose();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        '关联隐患1：设备 A 在 T5 删除会话 S（含旧消息 M1 墓碑），设备 B 离线在 T6>T5 新增消息 M2，正反同步均保留 S 与 M2、删除 M1 并校准 last_active_at',
        () async {
      Future<void> runScenario({required bool aToBFirst}) async {
        final dir = await Directory.systemTemp.createTemp('chat_resurrect_');
        final pathA = p.join(dir.path, 'a.db');
        final pathB = p.join(dir.path, 'b.db');
        final devA = ChatSessionService(databasePath: pathA);
        final devB = ChatSessionService(databasePath: pathB);
        try {
          await devA.init();
          await devB.init();

          // 1. 初始状态（T1）：两端均持有会话 s_shared 与首条消息 m1
          final initPayload = <String, dynamic>{
            'format': 1,
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'id': 's_shared',
                'session_type': 'agent',
                'title': '共享对话',
                'created_at': '2026-11-10T01:00:00.000Z',
                'last_active_at': '2026-11-10T01:00:00.000Z',
                'updated_at': '2026-11-10T01:00:00.000Z',
                'is_pinned': 0,
              },
            ],
            'messages': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'm1_old',
                'session_id': 's_shared',
                'role': 'user',
                'content': '早期消息 M1',
                'created_at': '2026-11-10T01:00:00.000Z',
                'updated_at': '2026-11-10T01:00:00.000Z',
              },
            ],
            'tombstones': const <Object?>[],
          };
          await devA.restoreChatSection(initPayload);
          await devB.restoreChatSection(initPayload);

          // 2. 设备 A 在 T5 (05:00Z) 删除会话 s_shared（同时产生 s_shared 与 m1_old 的 T5 墓碑）
          final rawA = await openDatabase(pathA, singleInstance: true);
          await rawA
              .delete('chat_messages', where: 'session_id = ?', whereArgs: [
            's_shared',
          ]);
          await rawA.delete('chat_sessions', where: 'id = ?', whereArgs: [
            's_shared',
          ]);
          await rawA.insert('chat_tombstones', <String, Object?>{
            'entity_type': 'session',
            'entity_id': 's_shared',
            'deleted_at': '2026-11-10T05:00:00.000Z',
          });
          await rawA.insert('chat_tombstones', <String, Object?>{
            'entity_type': 'message',
            'entity_id': 'm1_old',
            'deleted_at': '2026-11-10T05:00:00.000Z',
          });

          // 3. 设备 B 离线在 T6 (06:00Z > T5) 发送新消息 m2_offline_new（注意 s_shared.updated_at 仍停留在 T1！）
          await devB.addMessage(
            's_shared',
            ChatMessage(
              id: 'm2_offline_new',
              content: '离线新发送的重要消息 M2',
              isUser: true,
              role: 'user',
              timestamp: DateTime.utc(2026, 11, 10, 6, 0),
            ),
          );
          final rawB = await openDatabase(pathB, singleInstance: true);
          await rawB.update(
            'chat_messages',
            <String, Object?>{
              'created_at': '2026-11-10T06:00:00.000Z',
              'updated_at': '2026-11-10T06:00:00.000Z',
            },
            where: 'id = ?',
            whereArgs: const <Object?>['m2_offline_new'],
          );
          await rawB.update(
            'chat_sessions',
            <String, Object?>{
              'last_active_at': '2026-11-10T06:00:00.000Z',
              'updated_at': '2026-11-10T01:00:00.000Z',
            },
            where: 'id = ?',
            whereArgs: const <Object?>['s_shared'],
          );

          // 4. 双向交换快照
          if (aToBFirst) {
            await devB.mergeChatSection(
              await devA.exportChatSectionForTesting(),
            );
            await devA.mergeChatSection(
              await devB.exportChatSectionForTesting(),
            );
          } else {
            await devA.mergeChatSection(
              await devB.exportChatSectionForTesting(),
            );
            await devB.mergeChatSection(
              await devA.exportChatSectionForTesting(),
            );
          }

          // 5. 两端均保留 s_shared 与 m2_offline_new，删除 m1_old，且 last_active_at 校准为 06:00Z
          for (final pPath in <String>[pathA, pathB]) {
            final s = await querySession(pPath, 's_shared');
            expect(s, isNotNull);
            expect(
              s!.lastActiveAt.toUtc().toIso8601String(),
              '2026-11-10T06:00:00.000Z',
            );
          }
          expect(
            (await devA.getMessages('s_shared')).map((m) => m.id).toList(),
            <String>['m2_offline_new'],
          );
          expect(
            (await devB.getMessages('s_shared')).map((m) => m.id).toList(),
            <String>['m2_offline_new'],
          );
        } finally {
          await devA.close();
          devA.dispose();
          await devB.close();
          devB.dispose();
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }

      await runScenario(aToBFirst: true);
      await runScenario(aToBFirst: false);
    });

    test(
        '关联隐患2 & 问题3：同 ID 同时间戳会话/消息平局满足交换律，删除末尾消息回退校准 last_active_at，非法 format 抛 FormatException',
        () async {
      // 1. 非法 format 立即抛 FormatException 且不破坏已有会话
      final keepSession = await service.createSession(
        sessionType: 'agent',
        title: '受保护的本机对话',
      );
      for (final badFormat in <Object?>['bad', 0, -2, 1.5]) {
        await expectLater(
          () => service.mergeChatSection(<String, dynamic>{
            'format': badFormat,
            'sessions': const <Object?>[],
          }),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          () => service.restoreChatSection(<String, dynamic>{
            'format': badFormat,
            'sessions': const <Object?>[],
          }),
          throwsA(isA<FormatException>()),
        );
      }
      expect(await querySession(dbPath, keepSession.id), isNotNull);

      // 2. 删除会话最后一条消息后，last_active_at 自动回退校准到剩余最新消息时间
      await service.restoreChatSection(<String, dynamic>{
        'format': 1,
        'sessions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 's_recalc',
            'session_type': 'agent',
            'title': '校准会话',
            'created_at': '2026-11-10T01:00:00.000Z',
            'last_active_at': '2026-11-10T05:00:00.000Z',
            'updated_at': '2026-11-10T01:00:00.000Z',
          },
        ],
        'messages': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'm_first',
            'session_id': 's_recalc',
            'role': 'user',
            'content': '首条保留消息',
            'created_at': '2026-11-10T02:00:00.000Z',
            'updated_at': '2026-11-10T02:00:00.000Z',
          },
          <String, Object?>{
            'id': 'm_second_deleted',
            'session_id': 's_recalc',
            'role': 'assistant',
            'content': '将被远端墓碑删除的末尾消息',
            'created_at': '2026-11-10T05:00:00.000Z',
            'updated_at': '2026-11-10T05:00:00.000Z',
          },
        ],
      });
      await service.mergeChatSection(<String, dynamic>{
        'format': 1,
        'tombstones': <Map<String, Object?>>[
          <String, Object?>{
            'entity_type': 'message',
            'entity_id': 'm_second_deleted',
            'deleted_at': '2026-11-10T06:00:00.000Z',
          },
        ],
      });
      final recalibrated = await querySession(dbPath, 's_recalc');
      expect(
        recalibrated!.lastActiveAt.toUtc().toIso8601String(),
        '2026-11-10T02:00:00.000Z',
      );

      // 3. 同 ID 同时间戳会话与消息合并满足交换律（A->B == B->A）
      final dir = await Directory.systemTemp.createTemp('chat_tie_');
      final dev1 = ChatSessionService(databasePath: p.join(dir.path, '1.db'));
      final dev2 = ChatSessionService(databasePath: p.join(dir.path, '2.db'));
      try {
        await dev1.init();
        await dev2.init();
        final pAlpha = <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 's_tie',
              'session_type': 'agent',
              'title': '标题 Alpha',
              'created_at': '2026-11-15T01:00:00.000Z',
              'last_active_at': '2026-11-15T01:00:00.000Z',
              'updated_at': '2026-11-15T02:00:00.000Z',
              'is_pinned': 0,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm_tie',
              'session_id': 's_tie',
              'role': 'assistant',
              'content': '回复版本 Alpha',
              'created_at': '2026-11-15T01:05:00.000Z',
              'updated_at': '2026-11-15T02:00:00.000Z',
            },
          ],
        };
        final pBeta = <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 's_tie',
              'session_type': 'agent',
              'title': '标题 Beta',
              'created_at': '2026-11-15T09:00:00+08:00',
              'last_active_at': '2026-11-15T09:00:00+08:00',
              'updated_at': '2026-11-15T10:00:00+08:00',
              'is_pinned': 1,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'm_tie',
              'session_id': 's_tie',
              'role': 'assistant',
              'content': '回复版本 Beta',
              'created_at': '2026-11-15T09:05:00+08:00',
              'updated_at': '2026-11-15T10:00:00+08:00',
            },
          ],
        };

        await dev1.mergeChatSection(pAlpha);
        await dev1.mergeChatSection(pBeta);

        await dev2.mergeChatSection(pBeta);
        await dev2.mergeChatSection(pAlpha);

        final s1 = (await dev1.getAllSessions()).single;
        final s2 = (await dev2.getAllSessions()).single;
        expect(s1.title, s2.title);
        expect(s1.isPinned, s2.isPinned);
        expect(
          (await dev1.getMessages('s_tie')).single.content,
          (await dev2.getMessages('s_tie')).single.content,
        );
      } finally {
        await dev1.close();
        dev1.dispose();
        await dev2.close();
        dev2.dispose();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('回归防护：跨多批（>500 条）同 updated_at 消息重复同步时流式决胜，无假更新、跳过墓碑消息且同时间戳差异双向收敛',
        () async {
      final dir = await Directory.systemTemp.createTemp('chat_bulk_tie_');
      final pathA = p.join(dir.path, 'dev_a.db');
      final pathB = p.join(dir.path, 'dev_b.db');
      final devA = ChatSessionService(databasePath: pathA);
      final devB = ChatSessionService(databasePath: pathB);
      await devA.init();
      await devB.init();

      try {
        const totalMessages = 520;
        const sharedUpdatedIso = '2026-11-16T10:00:00.000Z';
        // 4 条分布在 3 个 200 行分批窗口中的同时间戳正文冲突：
        // 索引 5 与 405 在 devB 字典序更大，索引 205 与 515 在 devA 字典序更大。
        const bWinsIndices = <int>{5, 405};
        const aWinsIndices = <int>{205, 515};
        // 2 条已被同时间戳消息墓碑覆盖的旧消息（不应再进入决胜或产生假更新）。
        const tombstonedIndices = <int>{110, 310};

        List<Map<String, Object?>> buildMessages({required bool isDeviceA}) {
          return List<Map<String, Object?>>.generate(totalMessages, (index) {
            final id = 'msg_${index.toString().padLeft(4, '0')}';
            final createdAt = DateTime.utc(2026, 11, 16, 8, 0)
                .add(Duration(seconds: index))
                .toIso8601String();
            String content;
            if (bWinsIndices.contains(index)) {
              content = isDeviceA ? '候选正文-Alpha-$index' : '候选正文-Zulu-$index';
            } else if (aWinsIndices.contains(index)) {
              content = isDeviceA ? '候选正文-Zulu-$index' : '候选正文-Alpha-$index';
            } else {
              content = '完全一致的历史对话正文-$index-${'段落文本' * 8}';
            }
            return <String, Object?>{
              'id': id,
              'session_id': 's_bulk',
              'role': index.isEven ? 'user' : 'assistant',
              'content': content,
              'created_at': createdAt,
              'updated_at': sharedUpdatedIso,
            };
          });
        }

        Map<String, dynamic> buildInitialSection({required bool isDeviceA}) {
          return <String, dynamic>{
            'format': 1,
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'id': 's_bulk',
                'session_type': 'agent',
                'title': '大批量重复同步测试会话',
                'created_at': '2026-11-16T08:00:00.000Z',
                'last_active_at': '2026-11-16T10:00:00.000Z',
                'updated_at': sharedUpdatedIso,
                'is_pinned': 0,
              },
            ],
            'messages': buildMessages(isDeviceA: isDeviceA),
            'tombstones': <Map<String, Object?>>[
              for (final idx in tombstonedIndices)
                <String, Object?>{
                  'entity_type': 'message',
                  'entity_id': 'msg_${idx.toString().padLeft(4, '0')}',
                  'deleted_at': sharedUpdatedIso,
                },
            ],
          };
        }

        await devA.restoreChatSection(buildInitialSection(isDeviceA: true));
        await devB.restoreChatSection(buildInitialSection(isDeviceA: false));
        // 模拟两台设备本地先残留了将被同时间戳墓碑删除的那 2 条消息，检验墓碑跳过决胜并正确删除。
        for (final dbPath in <String>[pathA, pathB]) {
          final rawDb = await openDatabase(dbPath, singleInstance: true);
          for (final idx in tombstonedIndices) {
            await rawDb.insert(
              'chat_messages',
              <String, Object?>{
                'id': 'msg_${idx.toString().padLeft(4, '0')}',
                'session_id': 's_bulk',
                'role': 'user',
                'content': '待被同时间戳墓碑清理的消息-$idx',
                'created_at': '2026-11-16T08:00:00.000Z',
                'updated_at': sharedUpdatedIso,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        final snapshotFromB = await devB.exportChatSectionForTesting();
        final snapshotFromA = await devA.exportChatSectionForTesting();

        final firstMergeOnA = await devA.mergeChatSection(snapshotFromB);
        final firstMergeOnB = await devB.mergeChatSection(snapshotFromA);

        // devA 仅对 devB 字典序获胜的 2 条消息执行更新，其余 518 条远端行（516 条存活未更新 + 2 条命中墓碑跳过）计入 messagesSkipped，本地 2 条残留消息被删除。
        expect(firstMergeOnA.messagesAdded, 0);
        expect(firstMergeOnA.messagesUpdated, bWinsIndices.length);
        expect(firstMergeOnA.messagesDeleted, tombstonedIndices.length);
        expect(
          firstMergeOnA.messagesSkipped,
          totalMessages - bWinsIndices.length,
        );

        // devB 对称地仅对 devA 字典序获胜的 2 条消息执行更新。
        expect(firstMergeOnB.messagesAdded, 0);
        expect(firstMergeOnB.messagesUpdated, aWinsIndices.length);
        expect(firstMergeOnB.messagesDeleted, tombstonedIndices.length);
        expect(
          firstMergeOnB.messagesSkipped,
          totalMessages - aWinsIndices.length,
        );

        // 再次执行常规重复同步时：0 新增、0 更新、0 删除，全部 518 条存活消息均走 messagesSkipped。
        final repeatOnA = await devA.mergeChatSection(
          await devB.exportChatSectionForTesting(),
        );
        expect(repeatOnA.messagesAdded, 0);
        expect(repeatOnA.messagesUpdated, 0);
        expect(repeatOnA.messagesDeleted, 0);
        expect(
          repeatOnA.messagesSkipped,
          totalMessages - tombstonedIndices.length,
        );

        final msgsA = await devA.getMessages('s_bulk');
        final msgsB = await devB.getMessages('s_bulk');
        expect(msgsA, hasLength(totalMessages - tombstonedIndices.length));
        expect(msgsB, hasLength(totalMessages - tombstonedIndices.length));
        for (var i = 0; i < msgsA.length; i++) {
          expect(msgsA[i].id, msgsB[i].id);
          expect(msgsA[i].content, msgsB[i].content);
        }
        final byIdA = <String, ChatMessage>{for (final m in msgsA) m.id: m};
        for (final idx in <int>{...aWinsIndices, ...bWinsIndices}) {
          final id = 'msg_${idx.toString().padLeft(4, '0')}';
          expect(byIdA[id]?.content, '候选正文-Zulu-$idx');
        }
      } finally {
        await devA.close();
        devA.dispose();
        await devB.close();
        devB.dispose();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        'Devin 审查回归 #20：B 离线发送 10:00 旧消息、A 在 11:00 删除会话、B 在 12:00 继续回复，双向及第三端 C 同步均保留 12:00 新回复且彻底清除 <=11:00 的漏网旧消息',
        () async {
      Future<void> verifyOrder({required bool mergeAFirst}) async {
        final dir = await Directory.systemTemp.createTemp('cutoff_chat_sync_');
        final pathA = p.join(dir.path, 'a.db');
        final pathB = p.join(dir.path, 'b.db');
        final pathC = p.join(dir.path, 'c.db');
        final devA = ChatSessionService(databasePath: pathA);
        final devB = ChatSessionService(databasePath: pathB);
        final devC = ChatSessionService(databasePath: pathC);
        try {
          await devA.init();
          await devB.init();
          await devC.init();

          const sId = 'shared_conv_cutoff';
          final baseSection = <String, dynamic>{
            'format': 1,
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'id': sId,
                'session_type': 'agent',
                'title': '跨端共享会话',
                'created_at': '2026-11-21T09:00:00.000000Z',
                'last_active_at': '2026-11-21T09:00:00.000000Z',
                'updated_at': '2026-11-21T09:00:00.000000Z',
                'is_pinned': 0,
              },
            ],
            'messages': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'm_init_0900',
                'session_id': sId,
                'role': 'user',
                'content': '09:00 初始共享消息',
                'created_at': '2026-11-21T09:00:00.000000Z',
                'updated_at': '2026-11-21T09:00:00.000000Z',
              },
            ],
            'tombstones': <Object?>[],
          };
          await devA.restoreChatSection(baseSection);
          await devB.restoreChatSection(baseSection);
          await devC.restoreChatSection(baseSection);

          // C 离线在 09:30 发了一条 A/B 都没见过的早期消息
          final rawC = await openDatabase(pathC, singleInstance: true);
          await rawC.insert('chat_messages', <String, Object?>{
            'id': 'm_c_unseen_0930',
            'session_id': sId,
            'role': 'user',
            'content': '09:30 第三端离线消息（早于会话删除时间）',
            'created_at': '2026-11-21T09:30:00.000000Z',
            'updated_at': '2026-11-21T09:30:00.000000Z',
          });

          // B 离线在 10:00 发了一条 A 没见过的消息
          final rawB = await openDatabase(pathB, singleInstance: true);
          await rawB.insert('chat_messages', <String, Object?>{
            'id': 'm_b_unseen_1000',
            'session_id': sId,
            'role': 'user',
            'content': '10:00 B 端离线旧消息（早于会话删除时间）',
            'created_at': '2026-11-21T10:00:00.000000Z',
            'updated_at': '2026-11-21T10:00:00.000000Z',
          });

          // A 在 11:00 删除整个会话（仅能为 m_init_0900 写单消息墓碑，未见过 m_b_unseen_1000 与 m_c_unseen_0930）
          final rawA = await openDatabase(pathA, singleInstance: true);
          await rawA.delete(
            'chat_messages',
            where: 'session_id = ?',
            whereArgs: const <Object?>[sId],
          );
          await rawA.delete(
            'chat_sessions',
            where: 'id = ?',
            whereArgs: const <Object?>[sId],
          );
          await rawA.insert('chat_tombstones', <String, Object?>{
            'entity_type': 'session',
            'entity_id': sId,
            'deleted_at': '2026-11-21T11:00:00.000000Z',
          });
          await rawA.insert('chat_tombstones', <String, Object?>{
            'entity_type': 'message',
            'entity_id': 'm_init_0900',
            'deleted_at': '2026-11-21T11:00:00.000000Z',
          });

          // B 在 12:00 继续在该会话发言
          await rawB.insert('chat_messages', <String, Object?>{
            'id': 'm_b_post_1200',
            'session_id': sId,
            'role': 'assistant',
            'content': '12:00 删除之后的新回复',
            'created_at': '2026-11-21T12:00:00.000000Z',
            'updated_at': '2026-11-21T12:00:00.000000Z',
          });
          await rawB.update(
            'chat_sessions',
            <String, Object?>{
              'last_active_at': '2026-11-21T12:00:00.000000Z',
            },
            where: 'id = ?',
            whereArgs: const <Object?>[sId],
          );

          if (mergeAFirst) {
            await devA.mergeChatSection(
              await devB.exportChatSectionForTesting(),
            );
            await devB.mergeChatSection(
              await devA.exportChatSectionForTesting(),
            );
          } else {
            await devB.mergeChatSection(
              await devA.exportChatSectionForTesting(),
            );
            await devA.mergeChatSection(
              await devB.exportChatSectionForTesting(),
            );
          }

          // A 与 B 上均只保留 12:00 新消息，10:00 漏网旧消息已被彻底拦截/删除
          expect(
            (await devA.getMessages(sId)).map((m) => m.id).toList(),
            <String>['m_b_post_1200'],
          );
          expect(
            (await devB.getMessages(sId)).map((m) => m.id).toList(),
            <String>['m_b_post_1200'],
          );

          // 随后第三端 C 与 A 双向同步：C 上 09:30 的漏网旧消息同样被 session_cutoff 清除且不会回流到 A
          await devA.mergeChatSection(await devC.exportChatSectionForTesting());
          await devC.mergeChatSection(await devA.exportChatSectionForTesting());
          expect(
            (await devA.getMessages(sId)).map((m) => m.id).toList(),
            <String>['m_b_post_1200'],
          );
          expect(
            (await devC.getMessages(sId)).map((m) => m.id).toList(),
            <String>['m_b_post_1200'],
          );
        } finally {
          await devA.close();
          devA.dispose();
          await devB.close();
          devB.dispose();
          await devC.close();
          devC.dispose();
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }

      await verifyOrder(mergeAFirst: true);
      await verifyOrder(mergeAFirst: false);
    });

    test(
        'Devin 审查回归 #24 & #25：微秒与整毫秒（.123000Z vs .123001Z）严格按时间序排列，且纯无时区历史时间戳不臆测当前时区并保留 *_backup',
        () async {
      final dir = await Directory.systemTemp.createTemp('fixed_iso_tz_test_');
      final pathSubMs = p.join(dir.path, 'sub_ms.db');
      final pathOffsetless = p.join(dir.path, 'offsetless.db');
      final svcSubMs = ChatSessionService(databasePath: pathSubMs);
      try {
        await svcSubMs.init();
        final s = await svcSubMs.createSession(
          sessionType: 'agent',
          title: '微秒精度顺序测试',
        );
        // 第一条恰好在整毫秒 .123000，第二条在 1 微秒后的 .123001
        await svcSubMs.addMessage(
          s.id,
          ChatMessage(
            id: 'm_exact_ms',
            isUser: true,
            role: 'user',
            content: '整毫秒提问',
            timestamp: DateTime.utc(2026, 11, 21, 10, 0, 0, 123, 0),
          ),
        );
        await svcSubMs.addMessage(
          s.id,
          ChatMessage(
            id: 'm_plus_1us',
            isUser: false,
            role: 'assistant',
            content: '1微秒后回答',
            timestamp: DateTime.utc(2026, 11, 21, 10, 0, 0, 123, 1),
          ),
        );

        final ordered = await svcSubMs.getMessages(s.id);
        expect(
          ordered.map((m) => m.id).toList(),
          <String>['m_exact_ms', 'm_plus_1us'],
        );

        final rawSubDb = await openDatabase(pathSubMs, singleInstance: true);
        final rawRows = await rawSubDb.query(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: <Object?>[s.id],
          orderBy: 'created_at ASC',
        );
        expect(
          rawRows.map((r) => r['id']).toList(),
          <String>['m_exact_ms', 'm_plus_1us'],
        );
        expect(rawRows.first['created_at'], '2026-11-21T10:00:00.123000Z');
        expect(rawRows.last['created_at'], '2026-11-21T10:00:00.123001Z');

        // 构造包含：(a) 同事件存在 UTC updated_at 的无偏移 created_at；(b) 纯无时区无对照的旧消息
        final rawOld = await openDatabase(
          pathOffsetless,
          version: 3,
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE chat_sessions (
                id TEXT PRIMARY KEY,
                session_type TEXT NOT NULL,
                note_id TEXT,
                title TEXT,
                created_at TEXT NOT NULL,
                last_active_at TEXT NOT NULL,
                updated_at TEXT,
                is_pinned INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE chat_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE chat_tombstones (
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                deleted_at TEXT NOT NULL,
                PRIMARY KEY (entity_type, entity_id)
              )
            ''');
            await db.insert('chat_sessions', <String, Object?>{
              'id': 's_pure_local',
              'session_type': 'agent',
              'title': '纯无时区历史会话',
              'created_at': '2026-10-01T09:00:00.5',
              'last_active_at': '2026-10-01T09:00:00.5',
              'updated_at': null,
            });
            await db.insert('chat_messages', <String, Object?>{
              'id': 'm_paired_utc',
              'session_id': 's_pure_local',
              'role': 'user',
              'content': '带同事件 UTC updated_at 的历史消息',
              'created_at': '2026-10-01T09:00:00.123',
              'updated_at': '2026-10-01T01:00:00.123Z',
            });
            await db.insert('chat_messages', <String, Object?>{
              'id': 'm_pure_offsetless',
              'session_id': 's_pure_local',
              'role': 'assistant',
              'content': '纯无时区历史消息（绝不伪造 Z）',
              'created_at': '2026-10-01T09:05:00.5',
              'updated_at': null,
            });
          },
        );
        await rawOld.close();

        final svcOffsetless = ChatSessionService(databasePath: pathOffsetless);
        try {
          await svcOffsetless.init();
          final inspectOld =
              await openDatabase(pathOffsetless, singleInstance: true);
          final sOld = (await inspectOld.query('chat_sessions')).single;
          // 纯无时区会话保留无 Z 的 6 位定宽格式，且保存原始备份列
          expect(sOld['created_at'], '2026-10-01T09:00:00.500000');
          expect(sOld['created_at_backup'], '2026-10-01T09:00:00.5');

          final mRows = await inspectOld.query(
            'chat_messages',
            orderBy: 'id ASC',
          );
          final byMsgId = <String, Map<String, Object?>>{
            for (final r in mRows) r['id'] as String: r,
          };
          // 有同事件显式 UTC updated_at 对照的行精确换算为 UTC 并备份原值
          expect(
            byMsgId['m_paired_utc']!['created_at'],
            '2026-10-01T01:00:00.123000Z',
          );
          expect(
            byMsgId['m_paired_utc']!['created_at_backup'],
            '2026-10-01T09:00:00.123',
          );
          // 纯无时区无对照的行保留无 Z 定宽字符串，绝不臆测当前时区盖上伪造 Z
          expect(
            byMsgId['m_pure_offsetless']!['created_at'],
            '2026-10-01T09:05:00.500000',
          );
          expect(
            byMsgId['m_pure_offsetless']!['created_at_backup'],
            '2026-10-01T09:05:00.5',
          );
        } finally {
          await svcOffsetless.close();
          svcOffsetless.dispose();
        }
      } finally {
        await svcSubMs.close();
        svcSubMs.dispose();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });
  });
}

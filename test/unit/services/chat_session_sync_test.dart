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
          '2026-10-02T12:30:00.000Z',
        );
        expect(
          byId['s_empty_active']!['updated_at'],
          '2026-10-03T09:15:00.000Z',
        );

        final messageRows = await inspectDb.query('chat_messages');
        expect(messageRows, hasLength(1));
        expect(
          messageRows.single['updated_at'],
          '2026-10-02T12:30:00.000Z',
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
      final tombIds = tombs.map((t) => t['entity_id'] as String).toSet();
      expect(tombIds, contains('s_to_kill'));
      expect(tombIds, contains('s_stay_dead'));
      expect(tombIds, isNot(contains('s_resurrect')));
      expect(tombIds, isNot(contains('s_local_newer')));
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
}

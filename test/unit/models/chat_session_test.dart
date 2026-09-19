import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/models/chat_session.dart';

void main() {
  group('ChatSession.fromMap', () {
    test('应该能正确从完整的 SQLite Map 构建 ChatSession 对象', () {
      final nowStr = DateTime.now().toIso8601String();
      final map = {
        'id': 'session-123',
        'session_type': 'agent',
        'note_id': 'note-456',
        'title': '测试会话',
        'created_at': nowStr,
        'last_active_at': nowStr,
        'is_pinned': 1,
      };

      final session = ChatSession.fromMap(map);

      expect(session.id, equals('session-123'));
      expect(session.sessionType, equals('agent'));
      expect(session.noteId, equals('note-456'));
      expect(session.title, equals('测试会话'));
      expect(session.createdAt.toIso8601String(), equals(nowStr));
      expect(session.lastActiveAt.toIso8601String(), equals(nowStr));
      expect(session.isPinned, isTrue);
      expect(session.messages, isEmpty);
    });

    test('当可选字段缺失或为 null 时应用默认值', () {
      final map = <String, dynamic>{
        'id': 'session-default',
      };

      final session = ChatSession.fromMap(map);

      expect(session.id, equals('session-default'));
      expect(session.sessionType, equals('note'));
      expect(session.noteId, isNull);
      expect(session.title, equals(''));
      expect(session.isPinned, isFalse);
      expect(session.createdAt, isA<DateTime>());
      expect(session.lastActiveAt, isA<DateTime>());
    });

    test('当 created_at/last_active_at 为无效时间字符串时回退至 DateTime.now()', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final map = {
        'id': 'session-invalid-date',
        'created_at': 'not-a-valid-date',
        'last_active_at': '',
      };

      final session = ChatSession.fromMap(map);
      final after = DateTime.now().add(const Duration(seconds: 1));

      expect(session.createdAt.isAfter(before), isTrue);
      expect(session.createdAt.isBefore(after), isTrue);
      expect(session.lastActiveAt.isAfter(before), isTrue);
      expect(session.lastActiveAt.isBefore(after), isTrue);
    });

    test('当 id 缺失或为空时抛出 FormatException', () {
      expect(
        () => ChatSession.fromMap({}),
        throwsFormatException,
      );
      expect(
        () => ChatSession.fromMap({'id': null}),
        throwsFormatException,
      );
      expect(
        () => ChatSession.fromMap({'id': ''}),
        throwsFormatException,
      );
    });
  });

  group('ChatSession.toMap', () {
    test('应该正确序列化为 SQLite Map 格式', () {
      final createdAt = DateTime(2025, 1, 1, 10, 0, 0);
      final lastActiveAt = DateTime(2025, 1, 1, 11, 0, 0);
      final session = ChatSession(
        id: 'session-map',
        sessionType: 'note',
        noteId: 'note-1',
        title: 'Map测试',
        createdAt: createdAt,
        lastActiveAt: lastActiveAt,
        isPinned: true,
      );

      final map = session.toMap();

      expect(map['id'], equals('session-map'));
      expect(map['session_type'], equals('note'));
      expect(map['note_id'], equals('note-1'));
      expect(map['title'], equals('Map测试'));
      expect(map['created_at'], equals(createdAt.toIso8601String()));
      expect(map['last_active_at'], equals(lastActiveAt.toIso8601String()));
      expect(map['is_pinned'], equals(1));
    });

    test('isPinned 为 false 时 is_pinned 为 0', () {
      final session = ChatSession(
        id: 'session-unpinned',
        sessionType: 'agent',
        title: 'Unpinned',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        isPinned: false,
      );

      final map = session.toMap();

      expect(map['is_pinned'], equals(0));
    });
  });

  group('ChatSession.fromJson', () {
    test('应该能正确从完整 JSON 构建 ChatSession，包含嵌套的消息列表', () {
      final nowStr = DateTime.now().toIso8601String();
      final json = {
        'id': 'session-json-1',
        'sessionType': 'agent',
        'noteId': 'note-json',
        'title': 'JSON会话',
        'createdAt': nowStr,
        'lastActiveAt': nowStr,
        'isPinned': true,
        'messages': [
          {
            'id': 'msg-1',
            'content': 'Hello',
            'role': 'user',
          },
          {
            'id': 'msg-2',
            'content': 'Hi there!',
            'role': 'assistant',
          },
        ],
      };

      final session = ChatSession.fromJson(json);

      expect(session.id, equals('session-json-1'));
      expect(session.sessionType, equals('agent'));
      expect(session.noteId, equals('note-json'));
      expect(session.title, equals('JSON会话'));
      expect(session.isPinned, isTrue);
      expect(session.messages.length, equals(2));
      expect(session.messages[0].id, equals('msg-1'));
      expect(session.messages[0].content, equals('Hello'));
      expect(session.messages[1].id, equals('msg-2'));
      expect(session.messages[1].content, equals('Hi there!'));
    });

    test('当缺少 title 时可以正确降级回退到 noteTitle 属性', () {
      final json = {
        'id': 'session-title-fallback',
        'noteTitle': '笔记标题回退',
      };

      final session = ChatSession.fromJson(json);

      expect(session.title, equals('笔记标题回退'));
    });

    test('缺失属性时能够安全退回默认值', () {
      final json = <String, dynamic>{};

      final session = ChatSession.fromJson(json);

      expect(session.id, equals(''));
      expect(session.sessionType, equals('note'));
      expect(session.noteId, isNull);
      expect(session.title, equals(''));
      expect(session.isPinned, isFalse);
      expect(session.messages, isEmpty);
      expect(session.createdAt, isA<DateTime>());
      expect(session.lastActiveAt, isA<DateTime>());
    });

    test('包含损坏消息项时能跳过坏数据并保留合法消息', () {
      final json = {
        'id': 'session-bad-messages',
        'messages': [
          'invalid message item',
          null,
          {
            'id': 'msg-valid',
            'content': '有效消息',
            'role': 'user',
          },
          {
            'id': 'msg-invalid-role',
            'role': 12345, // 会在 ChatMessage.fromJson 中引发类型错误
          },
        ],
      };

      final session = ChatSession.fromJson(json);

      expect(session.messages.length, equals(1));
      expect(session.messages.first.id, equals('msg-valid'));
    });
  });

  group('ChatSession.toJson', () {
    test('应该能正确序列化为 JSON 格式', () {
      final createdAt = DateTime(2025, 1, 1, 10, 0, 0);
      final lastActiveAt = DateTime(2025, 1, 1, 11, 0, 0);
      final msg = ChatMessage(
        id: 'msg-to-json',
        content: 'Testing toJson',
        isUser: true,
        timestamp: createdAt,
      );

      final session = ChatSession(
        id: 'session-to-json',
        sessionType: 'note',
        noteId: 'note-to-json',
        title: 'ToJson Test',
        createdAt: createdAt,
        lastActiveAt: lastActiveAt,
        messages: [msg],
        isPinned: true,
      );

      final json = session.toJson();

      expect(json['id'], equals('session-to-json'));
      expect(json['sessionType'], equals('note'));
      expect(json['noteId'], equals('note-to-json'));
      expect(json['title'], equals('ToJson Test'));
      expect(json['createdAt'], equals(createdAt.toIso8601String()));
      expect(json['lastActiveAt'], equals(lastActiveAt.toIso8601String()));
      expect(json['isPinned'], isTrue);
      expect(json['messages'], isA<List>());
      final messagesList = json['messages'] as List;
      expect(messagesList.length, equals(1));
      expect(messagesList[0]['id'], equals('msg-to-json'));
    });
  });

  group('ChatSession.copyWith', () {
    final now = DateTime.now();
    final original = ChatSession(
      id: 'session-original',
      sessionType: 'note',
      noteId: 'note-orig',
      title: 'Original Title',
      createdAt: now,
      lastActiveAt: now,
      messages: const [],
      isPinned: false,
    );

    test('未指定任何参数时返回属性相同的拷贝', () {
      final copy = original.copyWith();

      expect(copy.id, equals(original.id));
      expect(copy.sessionType, equals(original.sessionType));
      expect(copy.noteId, equals(original.noteId));
      expect(copy.title, equals(original.title));
      expect(copy.createdAt, equals(original.createdAt));
      expect(copy.lastActiveAt, equals(original.lastActiveAt));
      expect(copy.messages, equals(original.messages));
      expect(copy.isPinned, equals(original.isPinned));
    });

    test('能正确更新传入的新字段', () {
      final newTime = DateTime(2026, 1, 1);
      final newMsg = ChatMessage(
        id: 'm1',
        content: 'new',
        isUser: true,
        timestamp: newTime,
      );

      final updated = original.copyWith(
        id: 'session-updated',
        sessionType: 'agent',
        noteId: 'note-new',
        title: 'Updated Title',
        createdAt: newTime,
        lastActiveAt: newTime,
        messages: [newMsg],
        isPinned: true,
      );

      expect(updated.id, equals('session-updated'));
      expect(updated.sessionType, equals('agent'));
      expect(updated.noteId, equals('note-new'));
      expect(updated.title, equals('Updated Title'));
      expect(updated.createdAt, equals(newTime));
      expect(updated.lastActiveAt, equals(newTime));
      expect(updated.messages, equals([newMsg]));
      expect(updated.isPinned, isTrue);
    });

    test('当 clearNoteId 为 true 时将 noteId 清空为 null', () {
      final cleared = original.copyWith(clearNoteId: true);

      expect(cleared.noteId, isNull);
    });
  });

  group('ChatSession 相等性与 hashCode 测试', () {
    test('id 相同的对象判定为相等并拥有相同的 hashCode', () {
      final now = DateTime.now();
      final session1 = ChatSession(
        id: 'session-equal',
        sessionType: 'note',
        title: 'Title 1',
        createdAt: now,
        lastActiveAt: now,
      );

      final session2 = ChatSession(
        id: 'session-equal',
        sessionType: 'agent',
        title: 'Title 2',
        createdAt: now,
        lastActiveAt: now,
      );

      expect(session1 == session2, isTrue);
      expect(session1.hashCode, equals(session2.hashCode));
    });

    test('id 不同的对象判定为不相等', () {
      final now = DateTime.now();
      final session1 = ChatSession(
        id: 'session-1',
        sessionType: 'note',
        title: 'Title',
        createdAt: now,
        lastActiveAt: now,
      );

      final session2 = ChatSession(
        id: 'session-2',
        sessionType: 'note',
        title: 'Title',
        createdAt: now,
        lastActiveAt: now,
      );

      expect(session1 == session2, isFalse);
    });
  });
}

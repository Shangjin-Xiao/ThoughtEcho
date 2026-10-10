import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/models/chat_session.dart';

void main() {
  group('ChatMessage 反序列化防御测试', () {
    test('ChatMessage.fromJson 能容忍 id 缺失、为 null 或为 int 类型', () {
      final jsonOmitId = <String, dynamic>{
        'content': 'omitted id',
        'isUser': true,
      };
      final msgOmitted = ChatMessage.fromJson(jsonOmitId);
      expect(msgOmitted.id, '');

      final jsonWithIntId = {
        'id': 12345,
        'content': 'hello',
        'isUser': true,
      };
      final msg = ChatMessage.fromJson(jsonWithIntId);
      expect(msg.id, '12345');
      expect(msg.content, 'hello');

      final jsonWithNullId = <String, dynamic>{
        'id': null,
        'content': 'world',
      };
      final msgNull = ChatMessage.fromJson(jsonWithNullId);
      expect(msgNull.id, '');
    });

    test(
        'ChatMessage.fromJson 能容忍异构字段类型 (role/isUser/includedInContext/metaJson)',
        () {
      final rawJson = {
        'id': 'msg_100',
        'content': 'test heterogeneity',
        'role': 404, // role 为 int
        'isUser': 'false', // string 形式的 bool
        'includedInContext': 0, // int 形式的 bool
        'metaJson': {'tool_call_id': 'call_1'}, // 直接传入了 Map 对象而非 String
        'deltaJson': [
          {'insert': 'hello'}
        ], // 直接传入了 List 对象
      };

      final msg = ChatMessage.fromJson(rawJson);
      expect(msg.id, 'msg_100');
      expect(msg.role, '404');
      expect(msg.isUser, false);
      expect(msg.includedInContext, false);
      expect(msg.metaJson, '{"tool_call_id":"call_1"}');
      expect(msg.parsedMeta, equals({'tool_call_id': 'call_1'}));
      expect(msg.deltaJson, '[{"insert":"hello"}]');
    });

    test(
        'ChatMessage.fromJson 在缺少 role 时安全从 isUser 解析角色，并支持非 string 键的 metaJson',
        () {
      final rawJson = {
        'id': 'msg_101',
        'content': 'test without role',
        'isUser': 'false', // string 形式的 bool
      };
      final msg = ChatMessage.fromJson(rawJson);
      expect(msg.isUser, false);
      expect(msg.role, 'assistant');

      final rawJsonWithIntKeys = {
        'id': 'msg_102',
        'content': 'test non string key meta',
        'metaJson': {123: 'val'},
      };
      final msg2 = ChatMessage.fromJson(rawJsonWithIntKeys);
      expect(msg2.parsedMeta, equals({'123': 'val'}));
    });

    test('ChatMessage.parsedMeta 安全处理损坏的 metaJson 字符串', () {
      final msgCorruptedMeta = ChatMessage(
        id: 'msg_err',
        content: 'test',
        isUser: true,
        timestamp: DateTime.now(),
        metaJson: '{broken_json_string',
      );

      // 不应抛出异常，返回 null
      expect(msgCorruptedMeta.parsedMeta, isNull);
      // 二次获取直接使用缓存状态，不重复尝试解析
      expect(msgCorruptedMeta.parsedMeta, isNull);
    });

    test('ChatMessage.fromMap 支持 int 类型 id 转换，缺少/空 id 抛出 FormatException', () {
      final mapWithIntId = {
        'id': 999,
        'content': 'test',
        'role': 'user',
        'included_in_context': '1',
      };
      final msg = ChatMessage.fromMap(mapWithIntId);
      expect(msg.id, '999');
      expect(msg.content, 'test');
      expect(msg.includedInContext, true);

      final mapOmitIdKey = <String, dynamic>{
        'content': 'test without id key',
      };
      expect(() => ChatMessage.fromMap(mapOmitIdKey), throwsFormatException);

      final mapWithNullId = <String, dynamic>{
        'id': null,
        'content': 'test',
      };
      expect(() => ChatMessage.fromMap(mapWithNullId), throwsFormatException);

      final mapWithEmptyId = <String, dynamic>{
        'id': '',
        'content': 'test',
      };
      expect(() => ChatMessage.fromMap(mapWithEmptyId), throwsFormatException);
    });
  });

  group('ChatSession 反序列化防御测试', () {
    test(
        'ChatSession.fromJson 能容忍非 String 类型的 id 且能安全解析 role 为 int 的消息与过滤无法解析的项',
        () {
      final rawJson = {
        'id': 8888,
        'sessionType': 'note',
        'title': '测试会话',
        'isPinned': 'true', // string 形式的 bool
        'messages': [
          null,
          'invalid_string_item',
          123,
          {
            'id': 'msg_1',
            'content': 'valid message',
            'role': 'user',
          },
          // 包含类型不匹配属性的 Map（role 为 int 也可以被 safe parsing 安全防御）
          {
            'id': 'msg_bad_role',
            'content': 'bad role message',
            'role': 123,
          },
          <dynamic, dynamic>{
            'id': 777,
            'content': 'another message from dynamic map',
            'role': 'assistant',
          },
        ],
      };

      final session = ChatSession.fromJson(rawJson);
      expect(session.id, '8888');
      expect(session.isPinned, true);
      expect(session.messages.length, 3);
      expect(session.messages[0].id, 'msg_1');
      expect(session.messages[0].content, 'valid message');
      expect(session.messages[1].id, 'msg_bad_role');
      expect(session.messages[1].role, '123');
      expect(session.messages[2].id, '777');
      expect(session.messages[2].content, 'another message from dynamic map');
    });

    test('ChatSession.fromMap 能够防御性处理 is_pinned 和 session_type', () {
      final map = {
        'id': 99,
        'session_type': 1,
        'title': 'Test',
        'created_at': '2026-03-29T00:00:00.000Z',
        'last_active_at': '2026-03-29T00:00:00.000Z',
        'is_pinned': '1',
      };

      final session = ChatSession.fromMap(map);
      expect(session.id, '99');
      expect(session.sessionType, '1');
      expect(session.isPinned, true);
    });
  });
}

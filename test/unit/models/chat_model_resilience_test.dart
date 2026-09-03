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

    test('ChatMessage.fromMap 支持 int 类型 id 转换，缺少/空 id 抛出 FormatException', () {
      final mapWithIntId = {
        'id': 999,
        'content': 'test',
        'role': 'user',
      };
      final msg = ChatMessage.fromMap(mapWithIntId);
      expect(msg.id, '999');
      expect(msg.content, 'test');

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
        'ChatSession.fromJson 能容忍非 String 类型的 id 且能安全过滤非 Map 或全损坏的 messages 元素',
        () {
      final rawJson = {
        'id': 8888,
        'sessionType': 'note',
        'title': '测试会话',
        'messages': [
          null,
          'invalid_string_item',
          123,
          {
            'id': 'msg_1',
            'content': 'valid message',
            'role': 'user',
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
      expect(session.messages.length, 2);
      expect(session.messages[0].id, 'msg_1');
      expect(session.messages[0].content, 'valid message');
      expect(session.messages[1].id, '777');
      expect(session.messages[1].content, 'another message from dynamic map');
    });
  });
}

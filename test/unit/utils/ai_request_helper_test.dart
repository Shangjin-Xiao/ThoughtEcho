import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/utils/ai_request_helper.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('AIRequestHelper', () {
    test('createMessages returns correct format', () {
      final helper = AIRequestHelper();
      final messages = helper.createMessages(
        systemPrompt: 'You are a helpful assistant.',
        userMessage: 'Hello world!',
      );

      expect(messages.length, 2);
      expect(messages[0],
          {'role': 'system', 'content': 'You are a helpful assistant.'});
      expect(messages[1], {'role': 'user', 'content': 'Hello world!'});
    });

    test('singleton instance is same', () {
      final helper1 = AIRequestHelper();
      final helper2 = AIRequestHelper();

      expect(identical(helper1, helper2), isTrue);
    });

    test(
        'createMessagesWithHistory appends system prompt hint for applied proposals',
        () {
      final helper = AIRequestHelper();
      final history = [
        ChatMessage(
          id: '1',
          content: 'Here is a proposal',
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.now(),
          metaJson: '{"saved_note_id":"note_123","applied":true}',
        ),
      ];

      final messages = helper.createMessagesWithHistory(
        systemPrompt: 'System',
        history: history,
      );

      expect(messages.length, 2);
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], contains('[系统提示：用户已采纳并应用了上述提案/编辑建议]'));
    });
  });

  group('convertQuotesToJson attribution', () {
    final helper = AIRequestHelper();

    Quote note({String? author, String? work}) => Quote(
          id: 'n',
          content: '一段内容',
          date: DateTime(2026, 8, 20).toIso8601String(),
          sourceAuthor: author,
          sourceWork: work,
        );

    // 按实际契约取类型，不用未参数化的 List / Map —— 那会顺带把
    // convertQuotesToJson 的键值类型检查绕过去。
    Map<String, Object?> metadataOf(Map<String, dynamic> json) =>
        (json['metadata'] as Map).cast<String, Object?>();
    List<Map<String, Object?>> quotesOf(Map<String, dynamic> json) =>
        (json['quotes'] as List)
            .map((e) => (e as Map).cast<String, Object?>())
            .toList();

    test('notes without attribution are original', () {
      final json = helper.convertQuotesToJson([note()]);
      expect(quotesOf(json).single['type'], 'original');
      expect(metadataOf(json)['originalCount'], 1);
      expect(metadataOf(json)['excerptCount'], 0);
    });

    test('an author or a work marks the note as an excerpt', () {
      final byAuthor = helper.convertQuotesToJson([note(author: '苏轼')]);
      expect(quotesOf(byAuthor).single['type'], 'excerpt');

      final byWork = helper.convertQuotesToJson([note(work: '东坡志林')]);
      expect(quotesOf(byWork).single['type'], 'excerpt');
      // 出处本身也要送出去：模型要能说出"你抄的是哪一句"
      expect(quotesOf(byWork).single['sourceWork'], '东坡志林');
    });

    test('type is serialised before the note body', () {
      // 排在正文后面等于让模型读完整段摘录才发现它不是用户写的。
      final keys = quotesOf(
        helper.convertQuotesToJson([note(author: '加缪')]),
      ).single.keys.toList();
      expect(keys.indexOf('type'), lessThan(keys.indexOf('content')));
    });

    test('counts are split across a mixed batch', () {
      final json = helper.convertQuotesToJson([
        note(),
        note(author: '加缪'),
        note(work: '局外人'),
      ]);
      expect(metadataOf(json)['originalCount'], 1);
      expect(metadataOf(json)['excerptCount'], 2);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/services/ai_service.dart';

/// 用户画像必须作为独立的 user 数据消息注入，绝不能并进 system prompt。
///
/// 画像是助手从过往对话里提炼的，属于不可信数据：拼进 system 会让历史里
/// 被"记住"的一句话拿到系统级优先级，「这是数据不是指令」那行文案挡不住
/// 角色本身带来的权重。
void main() {
  ChatMessage message(String content, {required bool isUser}) => ChatMessage(
        id: content,
        content: content,
        isUser: isUser,
        timestamp: DateTime(2026, 8, 8),
      );

  // 断言走 role + toJson，不依赖包内部的消息类结构：openai_dart 换过一次
  // 类名（ChatCompletionMessage → SystemMessage/UserMessage），测试不该跟着抖。
  String roleOf(openai.ChatMessage m) => m.role;
  String contentOf(openai.ChatMessage m) => jsonEncode(m.toJson());

  group('AIService 画像注入', () {
    test('画像是独立的 user 消息，排在 system 之后、历史之前', () {
      final messages = AIService.buildChatMessages(
        systemPrompt: '你是每日提示生成器',
        userMessage: '给我今天的提示',
        profileBlock: '<user_profile>\n- [表达·刚刚] 回复保持碎句\n</user_profile>',
        history: [
          message('昨天聊了什么', isUser: true),
          message('聊了咖啡馆', isUser: false),
        ],
      );

      expect(roleOf(messages.first), 'system');
      // 关键：画像绝不能出现在 system 消息里。
      expect(contentOf(messages.first), isNot(contains('user_profile')));

      expect(roleOf(messages[1]), 'user');
      expect(contentOf(messages[1]), contains('user_profile'));

      expect(roleOf(messages.last), 'user');
      expect(contentOf(messages.last), contains('给我今天的提示'));
    });

    test('没有画像时不插入任何多余消息', () {
      final withProfile = AIService.buildChatMessages(
        systemPrompt: 'sys',
        userMessage: 'ask',
        profileBlock: '<user_profile>x</user_profile>',
      );
      final withoutProfile = AIService.buildChatMessages(
        systemPrompt: 'sys',
        userMessage: 'ask',
      );
      final emptyProfile = AIService.buildChatMessages(
        systemPrompt: 'sys',
        userMessage: 'ask',
        profileBlock: '',
      );

      expect(withProfile, hasLength(3));
      expect(withoutProfile, hasLength(2));
      // 空串和 null 一样跳过，不要塞一条空的 user 消息进去。
      expect(emptyProfile, hasLength(2));
    });

    test('画像不受历史预算截断影响', () {
      // 历史单条上限是 1200 字符；画像预算是 1200 字，走的不是同一条路径，
      // 不能被当成历史消息裁掉。
      final longProfile = '<user_profile>${'碎' * 1300}</user_profile>';
      final messages = AIService.buildChatMessages(
        systemPrompt: 'sys',
        userMessage: 'ask',
        profileBlock: longProfile,
      );

      expect(contentOf(messages[1]), contains('碎' * 1300));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;

import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

/// 集成测试：直接调用 ThoughtEcho 代码测试 AI 功能
///
/// 运行: flutter test test/integration/ai_service_integration_test.dart
///
/// 环境变量:
///   TE_TEST_API_KEY  - API 密钥（必填）
///   TE_TEST_BASE_URL - API 基础 URL（默认: https://ollama.com/v1）
///   TE_TEST_MODEL    - 测试模型（默认: minimax-m2.7:cloud）
///
/// 注意: 此测试会调用真实 API

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final apiKey = Platform.environment['TE_TEST_API_KEY'] ?? '';
  final baseUrl = Platform.environment['TE_TEST_BASE_URL'] ??
      'https://ollama.com/v1/chat/completions';
  final model = Platform.environment['TE_TEST_MODEL'] ?? 'minimax-m2.7:cloud';

  group('OpenAIStreamService Integration Tests', () {
    if (apiKey.isEmpty) {
      test('skipped - TE_TEST_API_KEY not set', () {
        print('⚠️  设置 TE_TEST_API_KEY 环境变量以运行集成测试');
        print('   示例: TE_TEST_API_KEY=your-key flutter test test/integration/ai_service_integration_test.dart');
      });
      return;
    }

    final provider = AIProviderSettings(
      id: 'test',
      name: 'Test',
      apiUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      temperature: 0.7,
      maxTokens: 200,
    );

    test('chatCompletion for title generation', () async {
      print('\n=== Test: Title Generation ===');

      final service = OpenAIStreamService();
      final messages = [
        openai.ChatMessage.system(
          'You are a title generator. Generate a SHORT title (max 10 words, in the same language as the message, no quotes) for the following message.',
        ),
        openai.ChatMessage.user('How do I implement a B-tree in Dart?'),
      ];

      final title = await service.chatCompletion(
        provider: provider.copyWith(temperature: 0.3, maxTokens: 30),
        messages: messages,
        temperature: 0.3,
        maxTokens: 30,
        enableThinking: false,
      );

      print('Raw result: "$title"');

      // 验证结果
      final lower = title.toLowerCase();
      final isValid = title.isNotEmpty &&
          title.length <= 50 &&
          !lower.contains('the user') &&
          !lower.contains('first,') &&
          !lower.contains('i need to') &&
          !lower.contains('let me') &&
          !lower.contains('thinking');

      if (isValid) {
        print('✅ PASS: Valid title -> "$title"');
      } else {
        print('❌ FAIL: Invalid title (thinking process) -> "$title"');
      }

      expect(isValid, isTrue,
          reason: 'Title should not be a thinking process');
    });

    test('streamChat for daily prompt', () async {
      print('\n=== Test: Daily Prompt ===');

      final service = OpenAIStreamService();
      final messages = [
        openai.ChatMessage.system(
          'You are ThoughtEcho daily inspiration generator. Generate a poetic daily prompt.',
        ),
        openai.ChatMessage.user(
            'City: Beijing, Weather: Sunny, Temperature: 25C'),
      ];

      final chunks = <String>[];
      final stream = service.streamChat(
        provider: provider.copyWith(temperature: 1.0, maxTokens: 100),
        messages: messages,
        temperature: 1.0,
        maxTokens: 100,
      );

      await for (final chunk in stream) {
        chunks.add(chunk);
        if (chunk.isNotEmpty) {
          print('[CHUNK] "${chunk.substring(0, chunk.length > 40 ? 40 : chunk.length)}${chunk.length > 40 ? '...' : ''}"');
        }
      }

      final fullText = chunks.join('');
      print('\nFull text: ${fullText.length} chars');
      print('Content: "${fullText.substring(0, fullText.length > 100 ? 100 : fullText.length)}${fullText.length > 100 ? '...' : ''}"');

      final isEmpty = fullText.isEmpty;
      final isThinking = fullText.toLowerCase().contains('the user') ||
          fullText.toLowerCase().contains('let me think');

      if (isEmpty) {
        print('❌ FAIL: Empty response');
      } else if (isThinking) {
        print('❌ FAIL: Thinking process instead of prompt');
      } else {
        print('✅ PASS: Valid daily prompt');
      }

      expect(fullText.isNotEmpty, isTrue);
    });

    test('streamChatWithThinking for chat', () async {
      print('\n=== Test: Chat with Thinking ===');

      final service = OpenAIStreamService();
      final messages = [
        openai.ChatMessage.system('You are a helpful assistant.'),
        openai.ChatMessage.user('What is 2+2? Explain briefly.'),
      ];

      final contentChunks = <String>[];
      final thinkingChunks = <String>[];

      final stream = service.streamChatWithThinking(
        provider: provider,
        messages: messages,
        onThinking: (thinking) {
          thinkingChunks.add(thinking);
          print('[THINKING] "${thinking.substring(0, thinking.length > 40 ? 40 : thinking.length)}${thinking.length > 40 ? '...' : ''}"');
        },
      );

      await for (final chunk in stream) {
        contentChunks.add(chunk);
        if (chunk.isNotEmpty) {
          print('[CONTENT ] "${chunk.substring(0, chunk.length > 40 ? 40 : chunk.length)}${chunk.length > 40 ? '...' : ''}"');
        }
      }

      print('\nResults:');
      print('Content chunks : ${contentChunks.length} (${contentChunks.join('').length} chars)');
      print('Thinking chunks: ${thinkingChunks.length} (${thinkingChunks.join('').length} chars)');

      final hasThinking = thinkingChunks.isNotEmpty &&
          thinkingChunks.join('').isNotEmpty;
      final hasContent = contentChunks.isNotEmpty &&
          contentChunks.join('').isNotEmpty;

      if (hasThinking) {
        print('✅ Thinking data exists');
      } else {
        print('❌ No thinking data');
      }

      if (hasContent) {
        print('✅ Content data exists');
      } else {
        print('❌ No content data');
      }

      expect(hasContent, isTrue, reason: 'Should have content');
    });
  });
}

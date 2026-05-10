import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 功能验证测试：直接调用 API 测试 ThoughtEcho 的 AI 功能
///
/// 运行: dart run test/debug/ai_feature_test.dart
///
/// 环境变量:
///   TE_TEST_API_KEY  - API 密钥（必填）
///   TE_TEST_BASE_URL - API 基础 URL（默认: https://ollama.com/v1）
///   TE_TEST_MODEL    - 测试模型（默认: minimax-m2.7:cloud）
///
/// 此文件保留用于持续验证 AI 功能是否正常。

final _apiKey = Platform.environment['TE_TEST_API_KEY'] ?? '';
final _baseUrl = Platform.environment['TE_TEST_BASE_URL'] ?? 'https://ollama.com/v1';
final _model = Platform.environment['TE_TEST_MODEL'] ?? 'minimax-m2.7:cloud';

String get _normalizedUrl {
  var url = _baseUrl;
  if (url.endsWith('/chat/completions')) {
    url = url.substring(0, url.length - '/chat/completions'.length);
  }
  while (url.endsWith('/')) url = url.substring(0, url.length - 1);
  if (!url.endsWith('/v1') && !url.contains('/v1/')) url = '$url/v1';
  return url;
}

// ============ Test 1: 标题生成 ============
Future<bool> testTitleGeneration() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 1: 标题生成                                            ║');
  print('╚════════════════════════════════════════════════════════════╝');

  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse('$_normalizedUrl/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.write(jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': 'You are a title generator. Generate a SHORT title (max 10 words, in the same language as the message, no quotes) for the following message.'},
        {'role': 'user', 'content': 'How do I implement a B-tree in Dart?'},
      ],
      'temperature': 0.3,
      'max_tokens': 30,
      'stream': false,
    }));

    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
    final msg = (body['choices'] as List<dynamic>)[0]['message']
        as Map<String, dynamic>;

    final content = msg['content'] as String? ?? '';
    final reasoning = msg['reasoning'] as String? ?? '';
    final reasoningContent = msg['reasoning_content'] as String? ?? '';

    print('content          : "${content.substring(0, content.length > 80 ? 80 : content.length)}${content.length > 80 ? '...' : ''}"');
    print('reasoning        : "${reasoning.substring(0, reasoning.length > 80 ? 80 : reasoning.length)}${reasoning.length > 80 ? '...' : ''}"');
    print('reasoning_content: "${reasoningContent.substring(0, reasoningContent.length > 80 ? 80 : reasoningContent.length)}${reasoningContent.length > 80 ? '...' : ''}"');

    // 模拟 extractTextFromCompletion
    var extracted = content;
    if (extracted.isEmpty && reasoning.isNotEmpty) extracted = reasoning;
    if (extracted.isEmpty && reasoningContent.isNotEmpty) extracted = reasoningContent;

    print('\n[extractTextFromCompletion result]: "${extracted.substring(0, extracted.length > 80 ? 80 : extracted.length)}${extracted.length > 80 ? '...' : ''}"');

    // 模拟标题有效性检查
    final lower = extracted.toLowerCase();
    final isValid = extracted.isNotEmpty &&
        extracted.length <= 50 &&
        !lower.contains('the user') &&
        !lower.contains('first,') &&
        !lower.contains('i need to') &&
        !lower.contains('let me') &&
        !lower.contains('thinking');

    if (isValid) {
      print('✅ PASS: 返回有效标题 -> "$extracted"');
      return true;
    } else {
      print('❌ FAIL: 返回无效内容（思考过程），需要降级');
      print('   降级结果: "How do I implement a..."');
      return false;
    }
  } finally {
    client.close();
  }
}

// ============ Test 2: 每日提示 ============
Future<bool> testDailyPrompt() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 2: 每日提示                                            ║');
  print('╚════════════════════════════════════════════════════════════╝');

  final client = HttpClient();
  var contentLen = 0, reasoningLen = 0;
  final contentChunks = <String>[];
  final reasoningChunks = <String>[];

  try {
    final req = await client.postUrl(
      Uri.parse('$_normalizedUrl/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'text/event-stream');
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.write(jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': 'You are ThoughtEcho daily inspiration generator. Based on user context, generate a poetic, reflective daily prompt. Keep it under 100 tokens. Be warm and encouraging.'},
        {'role': 'user', 'content': 'City: Beijing, Weather: Sunny, Temperature: 25C'},
      ],
      'temperature': 1.0,
      'max_tokens': 100,
      'stream': true,
    }));

    final res = await req.close();
    await for (final chunk in res.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('data: ')) continue;
        final d = t.substring(6);
        if (d == '[DONE]') continue;
        try {
          final j = jsonDecode(d) as Map<String, dynamic>;
          final delta = (j['choices'] as List<dynamic>?)?[0]['delta']
              as Map<String, dynamic>?;
          if (delta == null) continue;
          final c = delta['content'] as String?;
          final r = delta['reasoning'] as String?;
          final rc = delta['reasoning_content'] as String?;
          if (c != null && c.isNotEmpty) {
            contentLen += c.length;
            contentChunks.add(c);
          }
          if (r != null && r.isNotEmpty) {
            reasoningLen += r.length;
            reasoningChunks.add(r);
          }
          if (rc != null && rc.isNotEmpty) {
            reasoningLen += rc.length;
            reasoningChunks.add(rc);
          }
        } catch (_) {}
      }
    }
  } finally {
    client.close();
  }

  final fullContent = contentChunks.join('');
  final fullReasoning = reasoningChunks.join('');

  print('content chunks  : ${contentChunks.length} (total $contentLen chars)');
  print('reasoning chunks: ${reasoningChunks.length} (total $reasoningLen chars)');
  print('\nfull content:');
  print('  "$fullContent"');
  print('\nfull reasoning:');
  print('  "${fullReasoning.substring(0, fullReasoning.length > 120 ? 120 : fullReasoning.length)}${fullReasoning.length > 120 ? '...' : ''}"');

  // 判断内容类型
  final isPoeticPrompt = fullContent.contains('Beijing') ||
      fullContent.contains('阳光') ||
      fullContent.contains('温暖') ||
      fullContent.contains('☀️');
  final isThinkingProcess = fullContent.toLowerCase().contains('the user') ||
      fullContent.toLowerCase().contains('let me think');

  if (isPoeticPrompt && !isThinkingProcess) {
    print('\n✅ PASS: 返回正常每日提示内容');
    return true;
  } else if (isThinkingProcess) {
    print('\n❌ FAIL: 返回的是思考过程，不是每日提示');
    return false;
  } else if (fullContent.isEmpty && fullReasoning.isNotEmpty) {
    print('\n❌ FAIL: content 为空，只有 reasoning');
    return false;
  } else {
    print('\n⚠️  UNCLEAR: 内容类型不明确');
    return false;
  }
}

// ============ Test 3: 聊天 + Thinking 显示 ============
Future<bool> testChatWithThinking() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 3: 聊天 + Thinking 显示                                ║');
  print('╚════════════════════════════════════════════════════════════╝');

  final client = HttpClient();
  final thinkingParts = <String>[];
  final responseChunks = <String>[];
  var contentLen = 0, reasoningLen = 0;

  try {
    final req = await client.postUrl(
      Uri.parse('$_normalizedUrl/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'text/event-stream');
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.write(jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': 'What is 2+2? Explain briefly.'},
      ],
      'temperature': 0.7,
      'max_tokens': 200,
      'stream': true,
    }));

    final res = await req.close();
    await for (final chunk in res.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('data: ')) continue;
        final d = t.substring(6);
        if (d == '[DONE]') continue;
        try {
          final j = jsonDecode(d) as Map<String, dynamic>;
          final delta = (j['choices'] as List<dynamic>?)?[0]['delta']
              as Map<String, dynamic>?;
          if (delta == null) continue;
          final c = delta['content'] as String?;
          final r = delta['reasoning'] as String?;
          final rc = delta['reasoning_content'] as String?;
          if (c != null && c.isNotEmpty) {
            contentLen += c.length;
            responseChunks.add(c);
            print('[CONTENT +${c.length}] "${c.substring(0, c.length > 50 ? 50 : c.length)}${c.length > 50 ? '...' : ''}"');
          }
          if (r != null && r.isNotEmpty) {
            reasoningLen += r.length;
            thinkingParts.add(r);
            print('[THINK  +${r.length}] "${r.substring(0, r.length > 50 ? 50 : r.length)}${r.length > 50 ? '...' : ''}"');
          }
          if (rc != null && rc.isNotEmpty) {
            reasoningLen += rc.length;
            thinkingParts.add(rc);
            print('[THINK2 +${rc.length}] "${rc.substring(0, rc.length > 50 ? 50 : rc.length)}${rc.length > 50 ? '...' : ''}"');
          }
        } catch (_) {}
      }
    }
  } finally {
    client.close();
  }

  print('\n--- Summary ---');
  print('content length  : $contentLen');
  print('thinking length : $reasoningLen');
  print('thinking chunks : ${thinkingParts.length}');

  final fullResponse = responseChunks.join('');
  final fullThinking = thinkingParts.join('');

  print('\n[UI 状态检查]');
  print('message.content       : "${fullResponse.substring(0, fullResponse.length > 60 ? 60 : fullResponse.length)}${fullResponse.length > 60 ? '...' : ''}"');
  print('message.thinkingChunks: ${thinkingParts.length} chunks, ${fullThinking.length} chars');
  print('!isUser               : true (assistant)');
  print('thinkingChunks.isEmpty: ${thinkingParts.isEmpty}');

  final thinkingVisible = thinkingParts.isNotEmpty && fullThinking.isNotEmpty;

  if (thinkingVisible) {
    print('\n✅ PASS: thinking 数据存在，UI 条件满足');
    print('   ThinkingWidget 应该渲染');
    return true;
  } else {
    print('\n❌ FAIL: thinking 数据为空，UI 不会渲染');
    return false;
  }
}

// ============ 主入口 ============
Future<void> main() async {
  if (_apiKey.isEmpty) {
    print('⚠️  未设置环境变量 TE_TEST_API_KEY，跳过测试');
    print('   示例: TE_TEST_API_KEY=your-key dart run test/debug/ai_feature_test.dart');
    exit(0);
  }

  print('╔══════════════════════════════════════════════════════════════╗');
  print('║ ThoughtEcho AI 功能验证测试                                   ║');
  print('║ 模型: $_model                                               ║');
  print('╚══════════════════════════════════════════════════════════════╝');

  final results = <String, bool>{
    '标题生成': await testTitleGeneration(),
    '每日提示': await testDailyPrompt(),
    '聊天Thinking': await testChatWithThinking(),
  };

  print('\n╔══════════════════════════════════════════════════════════════╗');
  print('║ 测试结果总结                                                  ║');
  print('╠══════════════════════════════════════════════════════════════╣');
  for (final entry in results.entries) {
    final status = entry.value ? '✅ PASS' : '❌ FAIL';
    print('║ ${entry.key.padRight(20)} $status                              ║');
  }
  print('╚══════════════════════════════════════════════════════════════╝');

  final allPassed = results.values.every((v) => v);
  if (!allPassed) {
    print('\n⚠️  部分测试失败，请检查上述详细输出');
    exit(1);
  } else {
    print('\n🎉 所有测试通过！');
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Standalone 功能验证测试（绕过 Flutter 测试环境的 HTTP 拦截）
/// 直接模拟 OpenAIStreamService 的请求构建逻辑，发送真实 HTTP 请求
///
/// 运行: dart run test/debug/ai_feature_verify_test.dart
///
/// 环境变量:
///   TE_TEST_API_KEY  - API 密钥（必填）
///   TE_TEST_BASE_URL - API 基础 URL（默认: https://ollama.com/v1）
///   TE_TEST_MODEL    - 测试模型（默认: minimax-m2.7:cloud）

final _apiKey = Platform.environment['TE_TEST_API_KEY'] ?? '';
final _baseUrl = Platform.environment['TE_TEST_BASE_URL'] ?? 'https://ollama.com/v1';
final _model = Platform.environment['TE_TEST_MODEL'] ?? 'minimax-m2.7:cloud';

/// 模拟 OpenAIStreamService.normalizeOpenAIBaseUrl
String normalizeOpenAIBaseUrl(String apiUrl) {
  final trimmed = apiUrl.trim();
  if (trimmed.isEmpty) throw const FormatException('空字符串');

  final uri = Uri.parse(trimmed);
  if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
    throw const FormatException('缺少 http/https 协议');
  }

  var path = uri.path;
  const chatSuffix = '/chat/completions';
  if (path.endsWith(chatSuffix)) {
    path = path.substring(0, path.length - chatSuffix.length);
    if (path.isEmpty) path = '/v1';
  }
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty || path == '/') path = '/v1';
  if (!path.endsWith('/v1') && !path.contains('/v1/') && path != '/v1') {
    path = '$path/v1';
  }

  final scheme = uri.hasScheme ? '${uri.scheme}://' : '';
  final host = uri.host;
  final port = uri.hasPort && uri.port != 0 ? ':${uri.port}' : '';
  return '$scheme$host$port$path';
}

Future<Map<String, dynamic>> postNonStream(Map<String, dynamic> body) async {
  final normalized = normalizeOpenAIBaseUrl(_baseUrl);
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$normalized/chat/completions'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> postStream(
  Map<String, dynamic> body, {
  required void Function(String? content, String? reasoning) onDelta,
  required void Function(int contentLen, int reasoningLen) onDone,
}) async {
  final normalized = normalizeOpenAIBaseUrl(_baseUrl);
  final client = HttpClient();
  var contentLen = 0, reasoningLen = 0;
  try {
    final req = await client.postUrl(Uri.parse('$normalized/chat/completions'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'text/event-stream');
    req.headers.set('Authorization', 'Bearer $_apiKey');
    req.write(jsonEncode(body));
    final res = await req.close();
    await for (final chunk in res.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('data: ')) continue;
        final d = t.substring(6);
        if (d == '[DONE]') continue;
        try {
          final j = jsonDecode(d) as Map<String, dynamic>;
          final delta = (j['choices'] as List<dynamic>?)?[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;
          final c = delta['content'] as String?;
          final r = delta['reasoning'] as String?;
          final rc = delta['reasoning_content'] as String?;
          if (c != null && c.isNotEmpty) {
            contentLen += c.length;
            onDelta(c, null);
          }
          if (r != null && r.isNotEmpty) {
            reasoningLen += r.length;
            onDelta(null, r);
          }
          if (rc != null && rc.isNotEmpty) {
            reasoningLen += rc.length;
            onDelta(null, rc);
          }
        } catch (_) {}
      }
    }
  } finally {
    client.close();
    onDone(contentLen, reasoningLen);
  }
}

Future<bool> testTitle() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 1: 标题生成 (非流式)                                   ║');
  print('╚════════════════════════════════════════════════════════════╝');

  final res = await postNonStream({
    'model': _model,
    'messages': [
      {'role': 'system', 'content': 'You are a title generator. Generate a SHORT title (max 10 words, in the same language as the message, no quotes) for the following message.'},
      {'role': 'user', 'content': 'How do I implement a B-tree in Dart?'},
    ],
    'temperature': 0.3,
    'max_tokens': 30,
    'stream': false,
  });

  final msg = (res['choices'] as List<dynamic>)[0]['message'] as Map<String, dynamic>;
  final content = msg['content'] as String? ?? '';
  final reasoning = msg['reasoning'] as String? ?? '';

  print('content  : "$content"');
  print('reasoning: "${reasoning.substring(0, reasoning.length > 100 ? 100 : reasoning.length)}${reasoning.length > 100 ? '...' : ''}"');

  // 模拟 extractTextFromCompletion
  var extracted = content;
  if (extracted.isEmpty && reasoning.isNotEmpty) extracted = reasoning;

  print('\n[extractTextFromCompletion]: "$extracted"');

  final lower = extracted.toLowerCase();
  final isValid = extracted.isNotEmpty &&
      !lower.contains('the user') &&
      !lower.contains('first,') &&
      !lower.contains('i need to') &&
      !lower.contains('let me') &&
      !lower.contains('thinking');

  if (isValid) {
    print('✅ PASS: Valid title');
    return true;
  } else {
    print('❌ FAIL: Invalid (thinking process), fallback needed');
    return false;
  }
}

Future<bool> testDailyPrompt() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 2: 每日提示 (流式)                                     ║');
  print('╚════════════════════════════════════════════════════════════╝');

  var contentLen = 0, reasoningLen = 0;
  final contentChunks = <String>[];

  await postStream({
    'model': _model,
    'messages': [
      {'role': 'system', 'content': 'You are ThoughtEcho daily inspiration generator. Generate a poetic daily prompt.'},
      {'role': 'user', 'content': 'City: Beijing, Weather: Sunny, Temperature: 25C'},
    ],
    'temperature': 1.0,
    'max_tokens': 100,
    'stream': true,
  }, onDelta: (c, r) {
    if (c != null && c.isNotEmpty) contentChunks.add(c);
  }, onDone: (c, r) {
    contentLen = c;
    reasoningLen = r;
  });

  final fullContent = contentChunks.join('');
  print('content: $contentLen chars');
  print('reasoning: $reasoningLen chars');
  print('text: "${fullContent.substring(0, fullContent.length > 120 ? 120 : fullContent.length)}${fullContent.length > 120 ? '...' : ''}"');

  if (fullContent.isNotEmpty) {
    print('✅ PASS: Has content');
    return true;
  } else {
    print('❌ FAIL: Empty content');
    return false;
  }
}

Future<bool> testChatThinking() async {
  print('\n╔════════════════════════════════════════════════════════════╗');
  print('║ TEST 3: 聊天 + Thinking (流式)                              ║');
  print('╚════════════════════════════════════════════════════════════╝');

  var contentLen = 0, reasoningLen = 0;
  final thinkingParts = <String>[];
  final contentParts = <String>[];

  await postStream({
    'model': _model,
    'messages': [
      {'role': 'system', 'content': 'You are a helpful assistant.'},
      {'role': 'user', 'content': 'What is 2+2? Explain briefly.'},
    ],
    'temperature': 0.7,
    'max_tokens': 200,
    'stream': true,
  }, onDelta: (c, r) {
    if (c != null && c.isNotEmpty) {
      contentLen += c.length;
      contentParts.add(c);
      print('[CONTENT +${c.length}] "${c.substring(0, c.length > 40 ? 40 : c.length)}${c.length > 40 ? '...' : ''}"');
    }
    if (r != null && r.isNotEmpty) {
      reasoningLen += r.length;
      thinkingParts.add(r);
      print('[THINK  +${r.length}] "${r.substring(0, r.length > 40 ? 40 : r.length)}${r.length > 40 ? '...' : ''}"');
    }
  }, onDone: (c, r) {
    contentLen = c;
    reasoningLen = r;
  });

  print('\nSummary: content=$contentLen thinking=$reasoningLen');

  final hasContent = contentParts.isNotEmpty;
  final hasThinking = thinkingParts.isNotEmpty;

  if (hasContent) print('✅ Content exists');
  else print('❌ No content');

  if (hasThinking) print('✅ Thinking exists (${thinkingParts.length} chunks)');
  else print('❌ No thinking');

  return hasContent && hasThinking;
}

Future<void> main() async {
  if (_apiKey.isEmpty) {
    print('⚠️  未设置环境变量 TE_TEST_API_KEY，跳过测试');
    print('   示例: TE_TEST_API_KEY=your-key dart run test/debug/ai_feature_verify_test.dart');
    exit(0);
  }

  print('╔══════════════════════════════════════════════════════════════╗');
  print('║ ThoughtEcho 功能验证 (Standalone)                            ║');
  print('╚══════════════════════════════════════════════════════════════╝');

  final results = {
    'Title': await testTitle(),
    'Daily Prompt': await testDailyPrompt(),
    'Chat+Thinking': await testChatThinking(),
  };

  print('\n╔══════════════════════════════════════════════════════════════╗');
  results.forEach((k, v) {
    print('║ ${k.padRight(20)} ${v ? '✅ PASS' : '❌ FAIL'}');
  });
  print('╚══════════════════════════════════════════════════════════════╝');
}

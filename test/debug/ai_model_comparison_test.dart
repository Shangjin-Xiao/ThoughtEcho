import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 多模型对比测试
///
/// 运行: dart run test/debug/ai_model_comparison_test.dart
///
/// 环境变量:
///   TE_TEST_API_KEY  - API 密钥（必填）
///   TE_TEST_BASE_URL - API 基础 URL（默认: https://ollama.com/v1）

final _apiKey = Platform.environment['TE_TEST_API_KEY'] ?? '';
final _baseUrl = Platform.environment['TE_TEST_BASE_URL'] ?? 'https://ollama.com/v1';

String normalizeUrl(String url) {
  var u = url;
  if (u.endsWith('/chat/completions')) {
    u = u.substring(0, u.length - '/chat/completions'.length);
  }
  while (u.endsWith('/')) u = u.substring(0, u.length - 1);
  if (!u.endsWith('/v1') && !u.contains('/v1/')) u = '$u/v1';
  return u;
}

Future<void> testModel(String model) async {
  print('\n${'=' * 60}');
  print('MODEL: $model');
  print('=' * 60);

  final normalized = normalizeUrl(_baseUrl);
  final client = HttpClient();

  try {
    // Test 1: Title generation (non-streaming)
    print('\n--- Title Generation ---');
    final req1 = await client.postUrl(Uri.parse('$normalized/chat/completions'));
    req1.headers.set('Content-Type', 'application/json');
    req1.headers.set('Authorization', 'Bearer $_apiKey');
    req1.write(jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': 'You are a title generator. Generate a SHORT title (max 10 words, no quotes) for the following message.'},
        {'role': 'user', 'content': 'How do I implement a B-tree in Dart?'},
      ],
      'temperature': 0.3,
      'max_tokens': 30,
      'stream': false,
    }));
    final res1 = await req1.close();
    final body1 = jsonDecode(await res1.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final msg1 = (body1['choices'] as List<dynamic>)[0]['message'] as Map<String, dynamic>;
    final content1 = msg1['content'] as String? ?? '';
    final reasoning1 = msg1['reasoning'] as String? ?? '';
    print('content  : "${content1.substring(0, content1.length > 60 ? 60 : content1.length)}${content1.length > 60 ? '...' : ''}"');
    print('reasoning: "${reasoning1.substring(0, reasoning1.length > 60 ? 60 : reasoning1.length)}${reasoning1.length > 60 ? '...' : ''}"');
    print(content1.isNotEmpty && content1.length <= 50 ? '✅ Title OK' : '❌ Title FAIL');

    // Test 2: Daily prompt (streaming)
    print('\n--- Daily Prompt ---');
    var content2Len = 0, reasoning2Len = 0;
    final req2 = await client.postUrl(Uri.parse('$normalized/chat/completions'));
    req2.headers.set('Content-Type', 'application/json');
    req2.headers.set('Accept', 'text/event-stream');
    req2.headers.set('Authorization', 'Bearer $_apiKey');
    req2.write(jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': 'Generate a poetic daily prompt.'},
        {'role': 'user', 'content': 'City: Beijing, Sunny, 25C'},
      ],
      'temperature': 1.0,
      'max_tokens': 100,
      'stream': true,
    }));
    final res2 = await req2.close();
    await for (final chunk in res2.transform(utf8.decoder)) {
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
          if (c != null && c.isNotEmpty) content2Len += c.length;
          if (r != null && r.isNotEmpty) reasoning2Len += r.length;
        } catch (_) {}
      }
    }
    print('content : $content2Len chars');
    print('thinking: $reasoning2Len chars');
    print(content2Len > 0 ? '✅ Prompt OK' : '❌ Prompt FAIL');

    // Test 3: Chat with thinking
    print('\n--- Chat ---');
    var content3Len = 0, reasoning3Len = 0;
    final req3 = await client.postUrl(Uri.parse('$normalized/chat/completions'));
    req3.headers.set('Content-Type', 'application/json');
    req3.headers.set('Accept', 'text/event-stream');
    req3.headers.set('Authorization', 'Bearer $_apiKey');
    req3.write(jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': 'What is 2+2?'},
      ],
      'temperature': 0.7,
      'max_tokens': 100,
      'stream': true,
    }));
    final res3 = await req3.close();
    await for (final chunk in res3.transform(utf8.decoder)) {
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
          if (c != null && c.isNotEmpty) content3Len += c.length;
          if (r != null && r.isNotEmpty) reasoning3Len += r.length;
        } catch (_) {}
      }
    }
    print('content : $content3Len chars');
    print('thinking: $reasoning3Len chars');
    print(content3Len > 0 ? '✅ Chat OK' : '❌ Chat FAIL');

  } catch (e) {
    print('ERROR: $e');
  } finally {
    client.close();
  }
}

Future<void> main() async {
  if (_apiKey.isEmpty) {
    print('⚠️  未设置环境变量 TE_TEST_API_KEY，跳过测试');
    print('   示例: TE_TEST_API_KEY=your-key dart run test/debug/ai_model_comparison_test.dart');
    exit(0);
  }

  final models = [
    'minimax-m2.7:cloud',
    'gemma4:31b-cloud',
    'deepseek-v3.2:cloud',
    'qwen3-vl:235b',
  ];

  for (final model in models) {
    await testModel(model);
  }

  print('\n${'=' * 60}');
  print('SUMMARY');
  print('=' * 60);
}

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/daily_prompt_generator.dart';

/// 真实 API 端到端测试：每日提示与会话标题
///
/// 与 `ai_service_integration_test.dart` 的区别：那个文件直接调
/// `OpenAIStreamService`，绕过了 `hasValidApiKeyAsync()` 的密钥校验和
/// provider 解析——真实故障恰恰发生在这些闸门里。本文件从
/// `AIService` 的公开入口出发，把安全存储、密钥校验、provider 解析、
/// token 预算和降级逻辑一起覆盖。
///
/// 运行：
/// ```bash
/// TE_TEST_API_KEY=... TE_TEST_BASE_URL=https://ollama.com/v1 \
///   TE_TEST_MODEL=gpt-oss:20b-cloud \
///   timeout 300s flutter test --reporter compact --timeout 120s \
///   test/integration/ai_service_live_features_test.dart
/// ```
///
/// 环境变量：
///   TE_TEST_API_KEY  - API 密钥（未设置则整组跳过）
///   TE_TEST_BASE_URL - API 基础 URL（默认 https://ollama.com/v1）
///   TE_TEST_MODEL    - 测试模型（默认 gpt-oss:20b-cloud，推理模型）
///
/// 注意：会调用真实 API 并消耗额度；密钥只从环境变量读取，不写入仓库。
class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  _FakeSettingsService(this._provider);

  final AIProviderSettings _provider;

  @override
  String? get localeCode => 'zh';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [_provider],
        currentProviderId: _provider.id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 默认注入返回 400 的 mock HttpClient，必须解除才能走真实网络。
  HttpOverrides.global = null;

  final apiKey = Platform.environment['TE_TEST_API_KEY'] ?? '';
  final baseUrl =
      Platform.environment['TE_TEST_BASE_URL'] ?? 'https://ollama.com/v1';
  final model = Platform.environment['TE_TEST_MODEL'] ?? 'gpt-oss:20b-cloud';

  group('AIService 真实 API 端到端', () {
    if (apiKey.isEmpty) {
      test('skipped - TE_TEST_API_KEY not set', () {
        print('⚠️  设置 TE_TEST_API_KEY 环境变量以运行真实 API 测试');
      });
      return;
    }

    const providerId = 'live-test-provider';
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    final secureStore = <String, String>{};
    late AIService aiService;
    late AppLocalizations l10n;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      SecureStorageService.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return secureStore[call.arguments['key']];
          case 'write':
            secureStore[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'delete':
            secureStore.remove(call.arguments['key']);
            return null;
          case 'readAll':
            return secureStore;
        }
        return null;
      });

      // 密钥只经 APIKeyManager 写入模拟的安全存储，和线上路径一致。
      await APIKeyManager().saveProviderApiKey(providerId, apiKey);

      final provider = AIProviderSettings(
        id: providerId,
        name: 'Live Test',
        apiKey: '',
        apiUrl: baseUrl,
        model: model,
      );
      aiService = AIService(settingsService: _FakeSettingsService(provider));
      l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    test('密钥校验放行非 sk- 前缀的密钥', () async {
      // 回归：前缀白名单曾让所有非 sk-/or_ 密钥（Ollama Cloud、Gemini、
      // 智谱等）判定为无效，导致下面两个功能静默降级到本地兜底。
      expect(await aiService.hasValidApiKeyAsync(), isTrue);
    });

    test('generateSessionTitle 返回模型生成的标题而非本地截断', () async {
      const message = '我最近在读《人类简史》，想把书里关于农业革命的那部分观点整理成笔记，还想加上自己的想法。';
      final localFallback = '${message.substring(0, 20)}...';

      final title = await aiService.generateSessionTitle(message);
      print('标题: "$title"');

      expect(title, isNotEmpty);
      expect(title, isNot('Chat'), reason: '不应走异常兜底');
      expect(title, isNot(localFallback), reason: '不应走本地截断兜底');
      expect(title.length, lessThanOrEqualTo(50));
    });

    test('streamGenerateDailyPrompt 流出模型内容而非默认模板', () async {
      final defaultPrompt = DailyPromptGenerator.getDefaultPrompt(l10n);

      final chunks = <String>[];
      await for (final chunk in aiService.streamGenerateDailyPrompt(
        l10n,
        city: '北京',
        weather: '晴',
        temperature: '25°C',
      )) {
        chunks.add(chunk);
      }

      final text = chunks.join('').trim();
      print('每日提示（${text.length} 字）: "$text"');

      expect(text, isNotEmpty, reason: 'token 预算过小会让 content 为空');
      expect(text, isNot(defaultPrompt), reason: '不应走默认模板兜底');
    });
  });
}

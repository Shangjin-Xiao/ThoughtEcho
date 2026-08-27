import 'package:openai_dart/openai_dart.dart' as openai;

import '../models/ai_provider_settings.dart';
import '../services/api_key_manager.dart';
import '../services/openai_stream_service.dart';

/// 设置页「测试连接」按钮背后的实际请求。
///
/// **必须和真正聊天时走同一条链路**（[OpenAIStreamService] → openai_dart），否则
/// 测试结论和实际可用性对不上。原来这里走的是 `AINetworkManager.makeRequest`，
/// 它把用户填的 `apiUrl` 当成完整 endpoint 直接 POST；而服务商文档给的通常是
/// base URL（`https://api.deepseek.com/v1`），往 `/v1` 发 POST 得到的正是
/// **405 Method Not Allowed**——一份能正常聊天的配置被测试按钮判死。
///
/// 真实链路早就迁到 openai_dart 了，由它按 base URL 自己拼 `/chat/completions`
/// （见 [OpenAIStreamService.normalizeOpenAIBaseUrl]），只有这两个测试按钮留在了
/// 老路上。
class AIConnectionTester {
  const AIConnectionTester._();

  /// 发一次最小的聊天请求验证配置。
  ///
  /// 返回模型的回复文本（可能为空字符串）。任何失败都以异常抛出，调用方负责转成
  /// 用户可读的提示。
  ///
  /// [provider] 的 `apiKey` 为空时会回落到 [APIKeyManager]，这样设置列表里那个
  /// 不带密钥的配置对象也能直接拿来测；编辑页则会把输入框里还没保存的密钥填进来，
  /// 于是「先测后存」也成立。
  static Future<String> test({
    required AIProviderSettings provider,
    required String systemPrompt,
    required String userMessage,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final resolved = provider.apiKey.isNotEmpty
        ? provider
        : provider.copyWith(
            apiKey: await APIKeyManager().getProviderApiKey(provider.id),
          );

    return await OpenAIStreamService()
        .chatCompletion(
          provider: resolved,
          messages: [
            openai.ChatMessage.system(systemPrompt),
            openai.ChatMessage.user(userMessage),
          ],
          temperature: 0.1,
          maxTokens: _testMaxTokens,
          // 思考模型会把 token 预算全花在推理上、正文返回空，测试没必要为此付钱等待。
          enableThinking: false,
        )
        .timeout(timeout);
  }

  /// 测试请求的 token 上限。只要能回一句话就够，给推理模型留一点余量。
  static const int _testMaxTokens = 64;
}

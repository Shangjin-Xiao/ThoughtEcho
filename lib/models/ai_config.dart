import 'ai_settings.dart';

/// AI配置的抽象接口
/// 统一AIProviderSettings和AISettings的公共行为
abstract class AIConfig {
  String get id;
  String get name;
  String get apiKey;
  String get apiUrl;
  String get model;
  double get temperature;
  int get maxTokens;
  bool get isEnabled;

  /// 构建请求头
  Map<String, String> buildHeaders();

  /// 调整请求数据体
  Map<String, dynamic> adjustData(Map<String, dynamic> data);
}

/// 包装旧版AISettings以实现AIConfig接口
class LegacyAIConfigWrapper implements AIConfig {
  final AISettings _settings;

  LegacyAIConfigWrapper(this._settings);

  AISettings get settings => _settings;

  @override
  String get id => 'legacy'; // 为旧版设置提供一个默认ID

  @override
  String get name => 'Legacy Settings'; // 为旧版设置提供一个默认名称

  @override
  String get apiKey => _settings.apiKey;

  @override
  String get apiUrl => _settings.apiUrl;

  @override
  String get model => _settings.model;

  @override
  double get temperature => _settings.temperature;

  @override
  int get maxTokens => _settings.maxTokens;

  @override
  bool get isEnabled => true; // 旧版设置始终启用

  @override
  Map<String, String> buildHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    // 根据不同的AI服务提供商设置认证头
    if (apiUrl.contains('openai.com') || apiUrl.contains('api.openai.com')) {
      headers['Authorization'] = 'Bearer $apiKey';
    } else if (apiUrl.contains('anthropic.com')) {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (apiUrl.contains('openrouter.ai')) {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['HTTP-Referer'] = 'https://thoughtecho.app';
      headers['X-Title'] = 'ThoughtEcho App';
    } else if (apiUrl.contains('deepseek.com')) {
      headers['Authorization'] = 'Bearer $apiKey';
    } else {
      // 默认使用Bearer token
      headers['Authorization'] = 'Bearer $apiKey';
    }

    return headers;
  }

  @override
  Map<String, dynamic> adjustData(Map<String, dynamic> data) {
    final adjustedData = Map<String, dynamic>.from(data);

    // 确保包含必要的字段
    adjustedData['model'] = adjustedData['model'] ?? model;
    adjustedData['temperature'] = adjustedData['temperature'] ?? temperature;
    adjustedData['max_tokens'] = adjustedData['max_tokens'] ?? maxTokens;

    // 确保stream参数是boolean类型
    if (adjustedData.containsKey('stream')) {
      adjustedData['stream'] =
          adjustedData['stream'] == true || adjustedData['stream'] == 'true';
    }

    // Anthropic特殊处理
    if (apiUrl.contains('anthropic.com')) {
      adjustedData.remove('model');
      // Anthropic API需要确保stream参数正确
      if (adjustedData.containsKey('stream') &&
          adjustedData['stream'] == true) {
        adjustedData['stream'] = true; // 确保是boolean类型
      }
    }

    return adjustedData;
  }
}

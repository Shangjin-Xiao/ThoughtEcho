import 'ai_config.dart';

/// AI服务商的具体配置实现
class AIProviderSettings implements AIConfig {
  static const Object _copyWithUnset = Object();

  @override
  final String id;
  @override
  final String name;
  @override
  final String apiKey; // 仅用于临时传递，实际API Key存储在加密存储中
  @override
  final String apiUrl;
  @override
  final String model;
  @override
  final double temperature;
  @override
  final int maxTokens;
  final String? hostOverride;
  @override
  final bool isEnabled;

  /// null: 自动推断；true: 强制开启；false: 强制关闭
  final bool? enableThinking;

  /// 判断当前模型是否支持思考/推理模式
  bool get supportsThinking {
    final m = model.toLowerCase();
    if (m.startsWith('anthropic/')) {
      return true;
    }
    // Claude 3.5+ 支持 extended thinking
    if (m.contains('claude-3') &&
        (m.contains('sonnet') || m.contains('opus'))) {
      return true;
    }
    // DeepSeek Reasoner / R1 系列
    if (m.contains('deepseek') &&
        (m.contains('reasoner') || m.contains('r1'))) {
      return true;
    }
    // OpenAI o1/o3 系列
    if (m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      return true;
    }
    // Qwen QwQ / reasoning 系列
    if (m.contains('qwq') ||
        m.contains('qwen3') ||
        m.contains('qwen') && m.contains('reason')) {
      return true;
    }
    // 兜底：用户手动强制开启时，显示支持思考能力
    return enableThinking == true;
  }

  const AIProviderSettings({
    required this.id,
    required this.name,
    this.apiKey = '', // 默认为空，实际API Key通过APIKeyManager管理
    required this.apiUrl,
    required this.model,
    this.temperature = 0.7,
    this.maxTokens = 32000,
    this.hostOverride,
    this.isEnabled = true,
    this.enableThinking,
  });

  bool get isAnthropicMessagesApi {
    if (id == 'anthropic') {
      return true;
    }
    return apiUrl.toLowerCase().contains('/v1/messages');
  }

  bool get isLikelyOpenAICompatible {
    if (isAnthropicMessagesApi) {
      return false;
    }
    final lowerUrl = apiUrl.toLowerCase();
    return id == 'openai' ||
        id == 'openrouter' ||
        id == 'deepseek' ||
        lowerUrl.contains('openai.com') ||
        lowerUrl.contains('openrouter.ai') ||
        lowerUrl.contains('deepseek.com');
  }

  /// 规范化请求 URL，兼容「base URL」与「完整 endpoint」两种输入。
  ///
  /// OpenAI 兼容接口若只配置到 `/v1`，会自动补全为 `/v1/chat/completions`。
  String resolveRequestUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return trimmed;
    }

    var path = uri.path.trim();
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    if (isAnthropicMessagesApi) {
      return uri.replace(path: path).toString();
    }

    const chatCompletionsPath = '/chat/completions';
    if (path.endsWith(chatCompletionsPath)) {
      return uri.replace(path: path).toString();
    }

    if (isLikelyOpenAICompatible && path.endsWith('/v1')) {
      return uri.replace(path: '$path$chatCompletionsPath').toString();
    }

    return uri.replace(path: path).toString();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      // 'apiKey': apiKey, // API Key不存储在配置文件中，而是在加密存储中
      'apiUrl': apiUrl,
      'model': model,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'hostOverride': hostOverride,
      'isEnabled': isEnabled,
      'enableThinking': enableThinking,
    };
  }

  factory AIProviderSettings.fromJson(Map<String, dynamic> map) {
    return AIProviderSettings(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      // apiKey: map['apiKey'] ?? '', // 不从配置文件读取，而是从加密存储读取
      apiUrl: map['apiUrl'] ?? '',
      model: map['model'] ?? '',
      temperature: map['temperature'] != null
          ? (map['temperature'] as num).toDouble()
          : 0.7,
      maxTokens:
          map['maxTokens'] != null ? (map['maxTokens'] as num).toInt() : 1000,
      hostOverride: map['hostOverride'],
      isEnabled: map['isEnabled'] ?? true,
      enableThinking: map['enableThinking'] as bool?,
    );
  }

  AIProviderSettings copyWith({
    String? id,
    String? name,
    String? apiKey,
    String? apiUrl,
    String? model,
    double? temperature,
    int? maxTokens,
    String? hostOverride,
    bool? isEnabled,
    Object? enableThinking = _copyWithUnset,
  }) {
    return AIProviderSettings(
      id: id ?? this.id,
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey, // 仅用于临时传递
      apiUrl: apiUrl ?? this.apiUrl,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      hostOverride: hostOverride ?? this.hostOverride,
      isEnabled: isEnabled ?? this.isEnabled,
      enableThinking: identical(enableThinking, _copyWithUnset)
          ? this.enableThinking
          : enableThinking as bool?,
    );
  }

  /// 预设的服务商配置
  static List<AIProviderSettings> getPresetProviders() {
    return [
      const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiKey: '',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-3.5-turbo',
      ),
      const AIProviderSettings(
        id: 'anthropic',
        name: 'Anthropic Claude',
        apiKey: '',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-3-haiku-20240307',
      ),
      const AIProviderSettings(
        id: 'openrouter',
        name: 'OpenRouter',
        apiKey: '',
        apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
        model: 'meta-llama/llama-3.1-8b-instruct:free',
      ),
      const AIProviderSettings(
        id: 'deepseek',
        name: 'DeepSeek',
        apiKey: '',
        apiUrl: 'https://api.deepseek.com/v1/chat/completions',
        model: 'deepseek-chat',
      ),
      const AIProviderSettings(
        id: 'custom',
        name: '自定义服务商',
        apiKey: '',
        apiUrl: '',
        model: '',
      ),
    ];
  }

  /// 创建默认设置
  static AIProviderSettings defaultSettings() {
    return const AIProviderSettings(
      id: 'default',
      name: '默认配置',
      apiKey: '',
      apiUrl: '',
      model: '',
      temperature: 0.7,
      maxTokens: 32000,
      isEnabled: false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AIProviderSettings && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'AIProviderSettings{id: $id, name: $name, model: $model}';
  }

  @override
  Map<String, String> buildHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (apiUrl.contains('openai.com') ||
        apiUrl.contains('openrouter.ai') ||
        id == 'openai' ||
        id == 'openrouter') {
      headers['Authorization'] = 'Bearer $apiKey';
      if (id == 'openrouter') {
        headers['HTTP-Referer'] = 'https://thoughtecho.app';
        headers['X-Title'] = 'ThoughtEcho App';
      }
    } else if (apiUrl.contains('anthropic.com') || id == 'anthropic') {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (apiUrl.contains('deepseek.com') || id == 'deepseek') {
      headers['Authorization'] = 'Bearer $apiKey';
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    return headers;
  }

  @override
  Map<String, dynamic> adjustData(Map<String, dynamic> data) {
    final adjustedData = Map<String, dynamic>.from(data);

    // 仅在调用方未提供且provider存在非空值时，才填充model
    if (!adjustedData.containsKey('model') ||
        (adjustedData['model'] is String &&
            (adjustedData['model'] as String).isEmpty)) {
      if (model.isNotEmpty) {
        adjustedData['model'] = model;
      }
    }

    // 不强制注入temperature和max_tokens，若调用方未提供则交由服务端使用默认值
    if (adjustedData.containsKey('temperature') &&
        adjustedData['temperature'] == null) {
      adjustedData.remove('temperature');
    }
    if (adjustedData.containsKey('max_tokens') &&
        adjustedData['max_tokens'] == null) {
      adjustedData.remove('max_tokens');
    }

    // 确保stream参数是boolean类型
    if (adjustedData.containsKey('stream')) {
      adjustedData['stream'] =
          adjustedData['stream'] == true || adjustedData['stream'] == 'true';
    }

    // Anthropic特殊处理
    if (apiUrl.contains('anthropic.com') || id == 'anthropic') {
      // Anthropic API不在请求体中包含model，而是在URL中
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

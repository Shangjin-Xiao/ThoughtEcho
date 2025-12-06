import 'ai_config.dart';

/// AI服务商的具体配置实现
class AIProviderSettings implements AIConfig {
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
  });
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

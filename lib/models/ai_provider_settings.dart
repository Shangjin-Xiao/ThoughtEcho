/// AI服务商配置
class AIProviderSettings {
  final String id;
  final String name;
  final String apiKey;
  final String apiUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final String? hostOverride;
  final bool isEnabled;

  const AIProviderSettings({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.apiUrl,
    required this.model,
    this.temperature = 0.7,
    this.maxTokens = 1000,
    this.hostOverride,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiKey': apiKey,
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
      apiKey: map['apiKey'] ?? '',
      apiUrl: map['apiUrl'] ?? '',
      model: map['model'] ?? '',
      temperature: map['temperature'] != null ? (map['temperature'] as num).toDouble() : 0.7,
      maxTokens: map['maxTokens'] != null ? (map['maxTokens'] as num).toInt() : 1000,
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
      apiKey: apiKey ?? this.apiKey,
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
}

/// 多AI服务商管理器
class MultiAISettings {
  final List<AIProviderSettings> providers;
  final String currentProviderId;
  final int maxRetries;
  final Duration retryDelay;
  final bool enableFailover;
  const MultiAISettings({
    this.providers = const [],
    this.currentProviderId = '',
    this.maxRetries = 2,
    this.retryDelay = const Duration(seconds: 3),
    this.enableFailover = false, // 默认禁用自动故障转移，让用户手动控制
  });

  /// 获取当前活跃的服务商
  AIProviderSettings? get currentProvider {
    try {
      return providers.firstWhere((p) => p.id == currentProviderId);
    } catch (e) {
      return null;
    }
  }

  /// 获取所有可用的服务商（有API Key且启用的）
  List<AIProviderSettings> get availableProviders {
    return providers
        .where((p) => p.isEnabled && p.apiKey.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'providers': providers.map((p) => p.toJson()).toList(),
      'currentProviderId': currentProviderId,
      'maxRetries': maxRetries,
      'retryDelay': retryDelay.inMilliseconds,
      'enableFailover': enableFailover,
    };
  }

  factory MultiAISettings.fromJson(Map<String, dynamic> map) {
    return MultiAISettings(
      providers: (map['providers'] as List<dynamic>?)
              ?.map((p) => AIProviderSettings.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      currentProviderId: map['currentProviderId'] ?? '',
      maxRetries: map['maxRetries'] ?? 2,
      retryDelay: Duration(milliseconds: map['retryDelay'] ?? 3000),
      enableFailover: map['enableFailover'] ?? false, // 默认禁用故障转移
    );
  }

  factory MultiAISettings.defaultSettings() {
    final presetProviders = AIProviderSettings.getPresetProviders();
    return MultiAISettings(
      providers: presetProviders,
      currentProviderId: presetProviders.first.id,
    );
  }

  MultiAISettings copyWith({
    List<AIProviderSettings>? providers,
    String? currentProviderId,
    int? maxRetries,
    Duration? retryDelay,
    bool? enableFailover,
  }) {
    return MultiAISettings(
      providers: providers ?? this.providers,
      currentProviderId: currentProviderId ?? this.currentProviderId,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      enableFailover: enableFailover ?? this.enableFailover,
    );
  }
}

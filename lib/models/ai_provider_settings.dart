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

  /// Claude 里**不**支持 extended thinking 的老型号。
  ///
  /// 用「排除旧的」而不是「列举新的」：Anthropic 从 3.7 起每一代都带思考，
  /// 正向白名单会在每次发新模型时悄悄失效（`claude-sonnet-4-5` 这种命名
  /// 根本匹配不上 `claude-3`）。
  static const _legacyClaudeModels = <String>[
    'claude-instant',
    'claude-1',
    'claude-2',
    'claude-3-opus',
    'claude-3-sonnet',
    'claude-3-haiku',
    'claude-3.5',
    'claude-3-5',
  ];

  /// 判断当前模型是否支持思考/推理模式。
  ///
  /// 只用来决定「深度思考」开关是否出现、以及未显式配置时的默认值；
  /// 用户在 provider 上写死 [enableThinking] 时以用户的为准。
  bool get supportsThinking {
    final m = model.toLowerCase();

    // 通用标记：各家普遍把推理能力直接写进模型名
    // （kimi-k2-thinking、doubao-seed-thinking、gemini-2.0-flash-thinking…）
    if (m.contains('thinking') ||
        m.contains('reasoner') ||
        m.contains('reasoning')) {
      return true;
    }

    // Anthropic：3.7 起全系支持
    if ((m.contains('claude') || m.startsWith('anthropic/')) &&
        !_legacyClaudeModels.any(m.contains)) {
      return true;
    }

    // OpenAI o 系列（允许 azure/o1、openai/o3 这类命名空间前缀）与 GPT-5 起的推理模型
    if (RegExp(r'(^|[/\-_])(o1|o3|o4)\b').hasMatch(m)) {
      return true;
    }
    if (RegExp(r'gpt-?[5-9]').hasMatch(m)) {
      return true;
    }

    // Gemini：2.5 起默认带 thinking，1.5/2.0 不带
    if (m.contains('gemini') &&
        RegExp(r'gemini[-_.]?(2[-.]5|[3-9])').hasMatch(m)) {
      return true;
    }

    // DeepSeek：R1 / Reasoner，以及 V3.1 起的混合推理
    if (m.contains('deepseek') &&
        (m.contains('r1') || RegExp(r'v3[-.][1-9]').hasMatch(m))) {
      return true;
    }

    // Qwen QwQ / Qwen3 起的推理系列
    if (m.contains('qwq') || RegExp(r'qwen[-_]?[3-9]').hasMatch(m)) {
      return true;
    }

    // 智谱 GLM-4.5 起、MiniMax M 系列
    if (RegExp(r'glm-?(4[-.][5-9]|[5-9])').hasMatch(m)) {
      return true;
    }
    if (RegExp(r'minimax[-_.]?m[1-9]').hasMatch(m)) {
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

  @override
  bool get isAnthropicMessagesApi {
    if (id == 'anthropic') {
      return true;
    }
    return apiUrl.toLowerCase().contains('/v1/messages');
  }

  /// 规范化请求 URL，兼容「base URL」与「完整 endpoint」两种输入。
  ///
  /// 服务商文档给出的多半是 base URL（`https://ollama.com/v1`），这里统一补成
  /// `/chat/completions`，用户少踩一次 404。
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
    if (path == '/') path = '';
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Anthropic
    if (id == 'anthropic' || uri.host.contains('anthropic.com')) {
      if (path.isEmpty) {
        return uri.replace(path: '/v1/messages').toString();
      } else if (path.endsWith('/v1')) {
        return uri.replace(path: '$path/messages').toString();
      } else if (path.endsWith('/messages')) {
        return uri.replace(path: path).toString();
      }
    }

    // OpenAI 兼容：已经是完整 endpoint 就原样返回。
    if (path.endsWith('/chat/completions')) {
      return uri.replace(path: path).toString();
    }

    // 只填了域名，按 OpenAI 官方布局补全。
    if (path.isEmpty) {
      return uri.replace(path: '/v1/chat/completions').toString();
    }

    // 只填到 base URL（服务商文档里给的通常就是这个）时补上 endpoint。
    // 覆盖 `/v1`、`/api/paas/v4`、`/api/v3`、`/compatible-mode/v1`、
    // `/v1beta/openai` 等各家写法：末段是版本号或 `openai` 都算 base URL。
    if (_looksLikeOpenAIBaseUrl(path)) {
      return uri.replace(path: '$path/chat/completions').toString();
    }

    return uri.replace(path: path).toString();
  }

  /// 末段是 `v1` / `v4` / `v1beta` / `openai` 这类版本或兼容层标记时，
  /// 认为用户填的是 base URL 而不是完整 endpoint。
  static bool _looksLikeOpenAIBaseUrl(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    final last = segments.last.toLowerCase();
    return last == 'openai' || RegExp(r'^v\d+[a-z]*$').hasMatch(last);
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
    } else if (isAnthropicMessagesApi || apiUrl.contains('anthropic.com')) {
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
    if (isAnthropicMessagesApi || apiUrl.contains('anthropic.com')) {
      // Anthropic API需要确保stream参数正确
      if (adjustedData.containsKey('stream') &&
          adjustedData['stream'] == true) {
        adjustedData['stream'] = true; // 确保是boolean类型
      }
    }

    return adjustedData;
  }
}

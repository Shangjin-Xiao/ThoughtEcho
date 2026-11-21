import 'ai_config.dart';
import 'ai_model_metadata.dart';

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

  /// 目录服务商标识（与实例唯一 `id: provider_<timestamp>` 解耦，例如 `openrouter`、`openai`）。
  final String? providerSlug;

  /// 接口协议类型，为 null 时按历史规则由 `id` / `apiUrl` 自动推断。
  final AIProtocolType? protocol;

  /// 可选的 `models.dev` 模型能力与配额元数据。
  final AIModelMetadata? modelMetadata;

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

  // 提取为静态成员，避免每次调用 supportsThinking 和 resolveRequestUrl 时重复编译正则表达式
  static final RegExp _oSeriesRegex = RegExp(r'(^|[/\-_])(o1|o3|o4)\b');
  static final RegExp _gpt5PlusRegex = RegExp(r'gpt-?[5-9]');
  static final RegExp _gemini25PlusRegex =
      RegExp(r'gemini[-_.]?(2[-.]5|[3-9])');
  static final RegExp _deepseekV3Regex = RegExp(r'v3[-.][1-9]');
  static final RegExp _qwen3PlusRegex = RegExp(r'qwen[-_]?[3-9]');
  static final RegExp _gemma4PlusRegex = RegExp(r'gemma[-_.]?[4-9]');
  static final RegExp _glm45PlusRegex = RegExp(r'glm-?(4[-.][5-9]|[5-9])');
  static final RegExp _minimaxMRegex = RegExp(r'minimax[-_.]?m[1-9]');
  static final RegExp _versionPathRegex = RegExp(r'^v\d+[a-z]*$');

  String get _normalizedSlug => (providerSlug ?? '').trim().toLowerCase();

  /// 判断当前模型是否支持思考/推理模式。
  ///
  /// 只用来决定「深度思考」开关是否出现、以及未显式配置时的默认值；
  /// 用户在 provider 上强制开启 [enableThinking] 时优先返回 `true`，
  /// 其次优先取 [modelMetadata] 的 `reasoning`，无元数据时回退正则推断。
  bool get supportsThinking {
    if (enableThinking == true) {
      return true;
    }

    final metadataReasoning = modelMetadata?.reasoning;
    if (metadataReasoning != null) {
      return metadataReasoning;
    }

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
    if (_oSeriesRegex.hasMatch(m)) {
      return true;
    }
    if (_gpt5PlusRegex.hasMatch(m)) {
      return true;
    }

    // Gemini：2.5 起默认带 thinking，1.5/2.0 不带
    if (m.contains('gemini') && _gemini25PlusRegex.hasMatch(m)) {
      return true;
    }

    // DeepSeek：R1 / Reasoner，以及 V3.1 起的混合推理
    if (m.contains('deepseek') &&
        (m.contains('r1') || _deepseekV3Regex.hasMatch(m))) {
      return true;
    }

    // Qwen QwQ / Qwen3 起的推理系列
    if (m.contains('qwq') || _qwen3PlusRegex.hasMatch(m)) {
      return true;
    }

    // Gemma 4 起带思考。它和上面几家不同：默认不吐 reasoning，要在请求里
    // 明确要（见 AgentService 的 reasoning_effort），所以更要认出来。
    if (_gemma4PlusRegex.hasMatch(m)) {
      return true;
    }

    // 智谱 GLM-4.5 起、MiniMax M 系列
    if (_glm45PlusRegex.hasMatch(m)) {
      return true;
    }
    if (_minimaxMRegex.hasMatch(m)) {
      return true;
    }

    return false;
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
    this.providerSlug,
    this.protocol,
    this.modelMetadata,
  });

  /// 判断给定 URL 是否显式指向原生 Anthropic Messages 端点（如 `/v1/messages` 或 `/messages`）。
  static bool hasAnthropicMessagesEndpoint(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      var path = uri.path.trim();
      while (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      final lowerPath = path.toLowerCase();
      if (lowerPath.endsWith('/chat/completions')) return false;
      return lowerPath.endsWith('/messages');
    }
    final lower = trimmed.toLowerCase();
    if (lower.contains('/chat/completions')) return false;
    return lower.contains('/v1/messages') || lower.endsWith('/messages');
  }

  /// 判断给定 URL 的主机名是否属于 Anthropic 官方域名（`anthropic.com` 及其子域名）。
  static bool isAnthropicOfficialHost(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final host = Uri.tryParse(trimmed)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return host == 'anthropic.com' || host.endsWith('.anthropic.com');
  }

  /// 判断给定 URL 是否为 Anthropic 官方共享的 OpenAI 兼容地址（如 `https://api.anthropic.com/v1`，且非 `/messages`）。
  static bool isSharedAnthropicOpenAIBaseUrl(String rawUrl) {
    return isAnthropicOfficialHost(rawUrl) &&
        !hasAnthropicMessagesEndpoint(rawUrl);
  }

  @override
  bool get isAnthropicMessagesApi {
    final lowerUrl = apiUrl.toLowerCase();
    if (lowerUrl.contains('/chat/completions')) {
      return false;
    }
    if (hasAnthropicMessagesEndpoint(apiUrl)) {
      return true;
    }
    if (protocol != null) {
      return protocol == AIProtocolType.anthropicMessages;
    }
    return false;
  }

  /// 是否为 OpenRouter 服务商（优先识别 [providerSlug]，兼容旧 `id` 与域名判断）。
  bool get isOpenRouter {
    return _normalizedSlug == 'openrouter' ||
        id == 'openrouter' ||
        apiUrl.toLowerCase().contains('openrouter.ai');
  }

  /// 是否为 Ollama（云端或本地）服务商。
  bool get isOllama {
    final lowerUrl = apiUrl.toLowerCase();
    return _normalizedSlug == 'ollama' ||
        _normalizedSlug == 'ollama_local' ||
        _normalizedSlug == 'ollama_cloud' ||
        _normalizedSlug == 'ollama-cloud' ||
        id == 'ollama' ||
        id == 'ollama_local' ||
        id == 'ollama_cloud' ||
        lowerUrl.contains('ollama.com') ||
        lowerUrl.contains(':11434');
  }

  /// 是否为 Google Gemini 官方兼容服务。
  bool get isGemini {
    return _normalizedSlug == 'gemini' ||
        _normalizedSlug == 'google' ||
        id == 'gemini' ||
        apiUrl.toLowerCase().contains('generativelanguage.googleapis.com');
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

    // Anthropic 原生 Messages 端点（显式 /chat/completions 与共享 /v1 兼容层走下方 OpenAI 分支）
    final lowerPath = path.toLowerCase();
    if (!lowerPath.endsWith('/chat/completions') &&
        (isAnthropicMessagesApi || hasAnthropicMessagesEndpoint(trimmed))) {
      if (path.isEmpty) {
        return uri.replace(path: '/v1/messages').toString();
      } else if (path.endsWith('/v1')) {
        return uri.replace(path: '$path/messages').toString();
      } else if (path.endsWith('/messages')) {
        return uri.replace(path: path).toString();
      }
      return uri.replace(path: '$path/v1/messages').toString();
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
    return last == 'openai' || _versionPathRegex.hasMatch(last);
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
      'providerSlug': providerSlug,
      'protocol': protocol?.storageKey,
      'modelMetadata': modelMetadata?.toJson(),
    };
  }

  factory AIProviderSettings.fromJson(Map<String, dynamic> map) {
    final rawSlug = map['providerSlug'];
    final normalizedSlug =
        rawSlug is String && rawSlug.trim().isNotEmpty ? rawSlug.trim() : null;
    final rawProtocol = map['protocol'];
    final rawMetadata = map['modelMetadata'];
    final apiUrl = (map['apiUrl'] ?? '') as String;
    final parsedProtocol = rawProtocol is String
        ? AIProtocolType.fromStorageKey(rawProtocol)
        : null;
    // 迁移曾仅凭 anthropic.com 主机名将共享 `/v1` 基地址误判为原生 Messages 协议的已保存记录
    final effectiveProtocol =
        parsedProtocol == AIProtocolType.anthropicMessages &&
                isSharedAnthropicOpenAIBaseUrl(apiUrl)
            ? AIProtocolType.openAICompatible
            : parsedProtocol;

    return AIProviderSettings(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      // apiKey: map['apiKey'] ?? '', // 不从配置文件读取，而是从加密存储读取
      apiUrl: apiUrl,
      model: map['model'] ?? '',
      temperature: map['temperature'] != null
          ? (map['temperature'] as num).toDouble()
          : 0.7,
      maxTokens:
          map['maxTokens'] != null ? (map['maxTokens'] as num).toInt() : 1000,
      hostOverride: map['hostOverride'],
      isEnabled: map['isEnabled'] ?? true,
      enableThinking: map['enableThinking'] as bool?,
      providerSlug: normalizedSlug,
      protocol: effectiveProtocol,
      modelMetadata: rawMetadata is Map
          ? AIModelMetadata.fromJson(Map<String, dynamic>.from(rawMetadata))
          : null,
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
    Object? providerSlug = _copyWithUnset,
    Object? protocol = _copyWithUnset,
    Object? modelMetadata = _copyWithUnset,
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
      providerSlug: identical(providerSlug, _copyWithUnset)
          ? this.providerSlug
          : providerSlug as String?,
      protocol: identical(protocol, _copyWithUnset)
          ? this.protocol
          : protocol as AIProtocolType?,
      modelMetadata: identical(modelMetadata, _copyWithUnset)
          ? this.modelMetadata
          : modelMetadata as AIModelMetadata?,
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

    if (isAnthropicMessagesApi) {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
      return headers;
    }

    headers['Authorization'] = 'Bearer $apiKey';
    if (isOpenRouter) {
      headers['HTTP-Referer'] = 'https://thoughtecho.app';
      headers['X-Title'] = 'ThoughtEcho App';
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

    // Anthropic 原生协议特殊处理
    if (isAnthropicMessagesApi) {
      // Anthropic API需要确保stream参数正确
      if (adjustedData.containsKey('stream') &&
          adjustedData['stream'] == true) {
        adjustedData['stream'] = true; // 确保是boolean类型
      }
    }

    return adjustedData;
  }
}

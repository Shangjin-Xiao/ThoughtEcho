import 'package:flutter/foundation.dart';

/// AI 服务商接口协议类型。
///
/// 支持与 `models.dev` 目录中的 `npm` SDK 标识对齐映射。
enum AIProtocolType {
  /// OpenAI Chat Completions 兼容协议（`@ai-sdk/openai`、`@ai-sdk/openai-compatible` 等）
  openAICompatible,

  /// Anthropic Messages 协议（`@ai-sdk/anthropic`）
  anthropicMessages;

  String get storageKey => name;

  static AIProtocolType? fromStorageKey(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    switch (normalized) {
      case 'openAICompatible':
      case 'openai_compatible':
      case 'openai-compatible':
      case 'openai':
        return AIProtocolType.openAICompatible;
      case 'anthropicMessages':
      case 'anthropic_messages':
      case 'anthropic-messages':
      case 'anthropic':
        return AIProtocolType.anthropicMessages;
      default:
        return null;
    }
  }

  /// 从 `models.dev` 服务商条目的 `npm` 字段解析协议类型；无法识别时返回 `null`。
  static AIProtocolType? tryFromModelsDevNpm(String? npm) {
    final normalized = npm?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == '@ai-sdk/anthropic' || normalized.contains('anthropic')) {
      return AIProtocolType.anthropicMessages;
    }
    if (normalized == '@ai-sdk/openai-compatible' ||
        normalized == '@ai-sdk/openai' ||
        normalized.contains('openai') ||
        normalized.contains('openrouter')) {
      return AIProtocolType.openAICompatible;
    }
    return null;
  }

  /// 从 `models.dev` 的 `npm` 字段解析协议类型，缺省回退为 [openAICompatible]。
  static AIProtocolType fromModelsDevNpm(String? npm) {
    return tryFromModelsDevNpm(npm) ?? AIProtocolType.openAICompatible;
  }
}

/// 对齐 `https://models.dev/api.json` 标准结构的不可变模型能力与配额元数据。
@immutable
class AIModelMetadata {
  final String? modelsDevProviderId;
  final String? modelsDevModelId;
  final String? family;
  final bool? reasoning;
  final bool? toolCall;
  final bool? attachment;
  final bool? temperature;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final double? inputCostPerMillion;
  final double? outputCostPerMillion;
  final double? cacheReadCostPerMillion;

  const AIModelMetadata({
    this.modelsDevProviderId,
    this.modelsDevModelId,
    this.family,
    this.reasoning,
    this.toolCall,
    this.attachment,
    this.temperature,
    List<String>? inputModalities,
    this.outputModalities = const <String>[],
    bool? supportsVision,
    this.contextWindow,
    this.maxOutputTokens,
    this.inputCostPerMillion,
    this.outputCostPerMillion,
    this.cacheReadCostPerMillion,
  }) : inputModalities = inputModalities ??
            (supportsVision == true
                ? const <String>['text', 'image']
                : supportsVision == false
                    ? const <String>['text']
                    : const <String>[]);

  /// 模型是否支持图像输入（对应 `models.dev` 中 `modalities.input` 包含 `'image'`）。
  bool get supportsVision =>
      inputModalities.any((m) => m.toLowerCase() == 'image');

  static const Object _sentinel = Object();

  /// 从 `https://models.dev/api.json` 的单个 model JSON 对象解析元数据。
  factory AIModelMetadata.fromModelsDevJson(
    Map<String, dynamic> json, {
    String? providerId,
    String? modelId,
  }) {
    final modalities = json['modalities'] is Map
        ? Map<String, dynamic>.from(json['modalities'] as Map)
        : null;
    final limit = json['limit'] is Map
        ? Map<String, dynamic>.from(json['limit'] as Map)
        : null;
    final cost = json['cost'] is Map
        ? Map<String, dynamic>.from(json['cost'] as Map)
        : null;

    return AIModelMetadata(
      modelsDevProviderId: _asNonEmptyString(
        providerId ??
            json['modelsDevProviderId'] ??
            json['provider_id'] ??
            json['providerId'],
      ),
      modelsDevModelId: _asNonEmptyString(
        modelId ?? json['modelsDevModelId'] ?? json['id'],
      ),
      family: _asNonEmptyString(json['family']),
      reasoning: _asBool(json['reasoning']),
      toolCall: _asBool(json['tool_call'] ?? json['toolCall']),
      attachment: _asBool(json['attachment']),
      temperature: _asBool(json['temperature']),
      inputModalities: List<String>.unmodifiable(
        _asStringList(modalities?['input'] ?? json['inputModalities']),
      ),
      outputModalities: List<String>.unmodifiable(
        _asStringList(modalities?['output'] ?? json['outputModalities']),
      ),
      contextWindow: _asInt(limit?['context'] ?? json['contextWindow']),
      maxOutputTokens: _asInt(limit?['output'] ?? json['maxOutputTokens']),
      inputCostPerMillion: _asDouble(
        cost?['input'] ?? json['inputCostPerMillion'],
      ),
      outputCostPerMillion: _asDouble(
        cost?['output'] ?? json['outputCostPerMillion'],
      ),
      cacheReadCostPerMillion: _asDouble(
        cost?['cache_read'] ??
            cost?['cacheRead'] ??
            json['cacheReadCostPerMillion'],
      ),
    );
  }

  /// 从本地持久化或备份 JSON 恢复元数据。
  factory AIModelMetadata.fromJson(Map<String, dynamic> json) {
    // 兼容直接传入 models.dev 嵌套结构或本地扁平序列化结构
    if (json.containsKey('limit') ||
        json.containsKey('cost') ||
        json.containsKey('modalities') ||
        json.containsKey('tool_call')) {
      return AIModelMetadata.fromModelsDevJson(json);
    }

    return AIModelMetadata(
      modelsDevProviderId: _asNonEmptyString(json['modelsDevProviderId']),
      modelsDevModelId: _asNonEmptyString(json['modelsDevModelId']),
      family: _asNonEmptyString(json['family']),
      reasoning: _asBool(json['reasoning']),
      toolCall: _asBool(json['toolCall']),
      attachment: _asBool(json['attachment']),
      temperature: _asBool(json['temperature']),
      inputModalities: json['inputModalities'] is List
          ? List<String>.unmodifiable(_asStringList(json['inputModalities']))
          : null,
      supportsVision: _asBool(json['supportsVision']),
      outputModalities: List<String>.unmodifiable(
        _asStringList(json['outputModalities']),
      ),
      contextWindow: _asInt(json['contextWindow']),
      maxOutputTokens: _asInt(json['maxOutputTokens']),
      inputCostPerMillion: _asDouble(json['inputCostPerMillion']),
      outputCostPerMillion: _asDouble(json['outputCostPerMillion']),
      cacheReadCostPerMillion: _asDouble(json['cacheReadCostPerMillion']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'modelsDevProviderId': modelsDevProviderId,
      'modelsDevModelId': modelsDevModelId,
      'family': family,
      'reasoning': reasoning,
      'toolCall': toolCall,
      'attachment': attachment,
      'temperature': temperature,
      'inputModalities': inputModalities,
      'outputModalities': outputModalities,
      'supportsVision': supportsVision,
      'contextWindow': contextWindow,
      'maxOutputTokens': maxOutputTokens,
      'inputCostPerMillion': inputCostPerMillion,
      'outputCostPerMillion': outputCostPerMillion,
      'cacheReadCostPerMillion': cacheReadCostPerMillion,
    };
  }

  AIModelMetadata copyWith({
    Object? modelsDevProviderId = _sentinel,
    Object? modelsDevModelId = _sentinel,
    Object? family = _sentinel,
    Object? reasoning = _sentinel,
    Object? toolCall = _sentinel,
    Object? attachment = _sentinel,
    Object? temperature = _sentinel,
    List<String>? inputModalities,
    List<String>? outputModalities,
    Object? contextWindow = _sentinel,
    Object? maxOutputTokens = _sentinel,
    Object? inputCostPerMillion = _sentinel,
    Object? outputCostPerMillion = _sentinel,
    Object? cacheReadCostPerMillion = _sentinel,
  }) {
    return AIModelMetadata(
      modelsDevProviderId: identical(modelsDevProviderId, _sentinel)
          ? this.modelsDevProviderId
          : modelsDevProviderId as String?,
      modelsDevModelId: identical(modelsDevModelId, _sentinel)
          ? this.modelsDevModelId
          : modelsDevModelId as String?,
      family: identical(family, _sentinel) ? this.family : family as String?,
      reasoning:
          identical(reasoning, _sentinel) ? this.reasoning : reasoning as bool?,
      toolCall:
          identical(toolCall, _sentinel) ? this.toolCall : toolCall as bool?,
      attachment: identical(attachment, _sentinel)
          ? this.attachment
          : attachment as bool?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as bool?,
      inputModalities: inputModalities != null
          ? List<String>.unmodifiable(inputModalities)
          : this.inputModalities,
      outputModalities: outputModalities != null
          ? List<String>.unmodifiable(outputModalities)
          : this.outputModalities,
      contextWindow: identical(contextWindow, _sentinel)
          ? this.contextWindow
          : contextWindow as int?,
      maxOutputTokens: identical(maxOutputTokens, _sentinel)
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      inputCostPerMillion: identical(inputCostPerMillion, _sentinel)
          ? this.inputCostPerMillion
          : inputCostPerMillion as double?,
      outputCostPerMillion: identical(outputCostPerMillion, _sentinel)
          ? this.outputCostPerMillion
          : outputCostPerMillion as double?,
      cacheReadCostPerMillion: identical(cacheReadCostPerMillion, _sentinel)
          ? this.cacheReadCostPerMillion
          : cacheReadCostPerMillion as double?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AIModelMetadata &&
        other.modelsDevProviderId == modelsDevProviderId &&
        other.modelsDevModelId == modelsDevModelId &&
        other.family == family &&
        other.reasoning == reasoning &&
        other.toolCall == toolCall &&
        other.attachment == attachment &&
        other.temperature == temperature &&
        listEquals(other.inputModalities, inputModalities) &&
        listEquals(other.outputModalities, outputModalities) &&
        other.contextWindow == contextWindow &&
        other.maxOutputTokens == maxOutputTokens &&
        other.inputCostPerMillion == inputCostPerMillion &&
        other.outputCostPerMillion == outputCostPerMillion &&
        other.cacheReadCostPerMillion == cacheReadCostPerMillion;
  }

  @override
  int get hashCode => Object.hash(
        modelsDevProviderId,
        modelsDevModelId,
        family,
        reasoning,
        toolCall,
        attachment,
        temperature,
        Object.hashAll(inputModalities),
        Object.hashAll(outputModalities),
        contextWindow,
        maxOutputTokens,
        inputCostPerMillion,
        outputCostPerMillion,
        cacheReadCostPerMillion,
      );

  static String? _asNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _asBool(Object? value) {
    return value is bool ? value : null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value % 1 == 0) {
      return value.toInt();
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double && value.isFinite) return value;
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
}

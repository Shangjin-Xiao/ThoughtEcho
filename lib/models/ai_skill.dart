import 'dart:convert';
import 'package:collection/collection.dart';

/// AI Skill 数据模型
///
/// 用于描述一个可被注册 to OpenAI tool calling 的技能定义。
class AISkill {
  static final RegExp _openAIToolNamePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

  final String id;
  final String name;
  final String triggerWord;
  final String systemPrompt;
  final String? description;
  final Map<String, Object?> inputProperties;
  final List<String> requiredInputs;

  AISkill({
    required String id,
    required String name,
    required String triggerWord,
    required String systemPrompt,
    this.description,
    Map<String, Object?> inputProperties = const {},
    List<String> requiredInputs = const [],
  })  : id = id.trim(),
        name = name.trim(),
        triggerWord = triggerWord.trim(),
        systemPrompt = systemPrompt.trim(),
        inputProperties = Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(inputProperties),
        ),
        requiredInputs = List<String>.unmodifiable(
          List<String>.from(requiredInputs),
        ) {
    if (this.id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'id cannot be empty');
    }
    if (!_openAIToolNamePattern.hasMatch(this.id)) {
      throw ArgumentError.value(
        id,
        'id',
        'id must match OpenAI function naming rules: [a-zA-Z0-9_-]{1,64}',
      );
    }
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'name cannot be empty');
    }
    if (this.triggerWord.isEmpty) {
      throw ArgumentError.value(
        triggerWord,
        'triggerWord',
        'triggerWord cannot be empty',
      );
    }
    if (this.systemPrompt.isEmpty) {
      throw ArgumentError.value(
        systemPrompt,
        'systemPrompt',
        'systemPrompt cannot be empty',
      );
    }

    final undefinedRequiredInputs = this
        .requiredInputs
        .where((key) => !this.inputProperties.containsKey(key))
        .toList(growable: false);
    if (undefinedRequiredInputs.isNotEmpty) {
      throw ArgumentError.value(
        requiredInputs,
        'requiredInputs',
        'requiredInputs must exist in inputProperties: '
            '${undefinedRequiredInputs.join(', ')}',
      );
    }
  }

  /// 将当前技能映射为 OpenAI tool calling 的 JSON Schema 结构。
  ///
  /// - 固定使用 `type: function`
  /// - 固定开启 `strict: true`
  /// - 参数 schema 使用 `additionalProperties: false`，以满足结构化输出要求
  Map<String, Object?> toOpenAITool() {
    final required = requiredInputs.isEmpty
        ? inputProperties.keys.toList(growable: false)
        : requiredInputs;
    final resolvedDescription = (description?.trim().isNotEmpty ?? false)
        ? description!.trim()
        : '$name (trigger: $triggerWord)';

    return {
      'type': 'function',
      'function': {
        'name': id,
        'description': resolvedDescription,
        'strict': true,
        'parameters': {
          'type': 'object',
          'properties': Map<String, Object?>.from(inputProperties),
          'required': required,
          'additionalProperties': false,
        },
      },
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'trigger_word': triggerWord,
      'system_prompt': systemPrompt,
      'description': description,
      'input_properties': jsonEncode(inputProperties),
      'required_inputs': jsonEncode(requiredInputs),
    };
  }

  factory AISkill.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parseProperties(dynamic val) {
      if (val is String) {
        try {
          return jsonDecode(val) as Map<String, dynamic>;
        } catch (_) {}
      } else if (val is Map) {
        return Map<String, dynamic>.from(val);
      }
      return {};
    }

    List<String> parseRequired(dynamic val) {
      if (val is String) {
        try {
          return List<String>.from(jsonDecode(val) as List);
        } catch (_) {}
      } else if (val is List) {
        return List<String>.from(val);
      }
      return [];
    }

    return AISkill(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      triggerWord: map['trigger_word'] ?? map['triggerWord'] ?? '',
      systemPrompt: map['system_prompt'] ?? map['systemPrompt'] ?? '',
      description: map['description'] as String?,
      inputProperties: parseProperties(
        map['input_properties'] ?? map['inputProperties'],
      ),
      requiredInputs: parseRequired(
        map['required_inputs'] ?? map['requiredInputs'],
      ),
    );
  }

  AISkill copyWith({
    String? id,
    String? name,
    String? triggerWord,
    String? systemPrompt,
    String? description,
    Map<String, Object?>? inputProperties,
    List<String>? requiredInputs,
  }) {
    return AISkill(
      id: id ?? this.id,
      name: name ?? this.name,
      triggerWord: triggerWord ?? this.triggerWord,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      description: description ?? this.description,
      inputProperties: inputProperties ?? this.inputProperties,
      requiredInputs: requiredInputs ?? this.requiredInputs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AISkill) return false;
    return other.id == id &&
        other.name == name &&
        other.triggerWord == triggerWord &&
        other.systemPrompt == systemPrompt &&
        other.description == description &&
        const MapEquality().equals(other.inputProperties, inputProperties) &&
        const ListEquality().equals(other.requiredInputs, requiredInputs);
  }

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      triggerWord.hashCode ^
      systemPrompt.hashCode ^
      description.hashCode ^
      const MapEquality().hash(inputProperties) ^
      const ListEquality().hash(requiredInputs);
}

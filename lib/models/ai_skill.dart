import 'dart:convert';

/// AI Skill 数据模型
///
/// 用于描述一个可被注册到 OpenAI tool calling 的技能定义。
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
      try {
        if (val is String) {
          return jsonDecode(val) as Map<String, dynamic>;
        } else if (val is Map) {
          return val.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {
        return {};
      }
      return {};
    }

    List<String> parseRequired(dynamic val) {
      try {
        final decoded = val is String ? jsonDecode(val) : val;
        if (decoded is List) {
          return decoded
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {
        return [];
      }
      return [];
    }

    String safeString(dynamic value, String fallback) {
      final text = value is String ? value.trim() : '';
      return text.isEmpty ? fallback : text;
    }

    String safeToolName(dynamic value) {
      final text = safeString(value, 'invalid_skill')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final limited = text.length > 64 ? text.substring(0, 64) : text;
      return _openAIToolNamePattern.hasMatch(limited)
          ? limited
          : 'invalid_skill';
    }

    final id = safeToolName(map['id']);
    final properties = parseProperties(
      map['input_properties'] ?? map['inputProperties'],
    );
    final requiredInputs = parseRequired(
      map['required_inputs'] ?? map['requiredInputs'],
    ).where(properties.containsKey).toList(growable: false);

    return AISkill(
      id: id,
      name: safeString(map['name'], id),
      triggerWord: safeString(map['trigger_word'] ?? map['triggerWord'], id),
      systemPrompt: safeString(
        map['system_prompt'] ?? map['systemPrompt'],
        'Execute $id',
      ),
      description: map['description'] is String
          ? (map['description'] as String).trim()
          : null,
      inputProperties: properties,
      requiredInputs: requiredInputs,
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
    return identical(this, other) || (other is AISkill && other.id == id);
  }

  @override
  int get hashCode => id.hashCode;
}

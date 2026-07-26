/// 工具参数的轻量校验器。
///
/// 目标不是完整实现 JSON Schema，而是把模型最常犯的三类错误
/// （缺失必填字段 / 未知字段 / 类型不匹配）**聚合成一条人话错误**，
/// 让模型一次就能改对，而不是靠多轮试错。
library;

/// 校验工具参数；通过返回 null，失败返回一条可执行的中文错误。
String? validateToolArguments({
  required String toolName,
  required Map<String, Object?> schema,
  required Map<String, Object?> arguments,
}) {
  final rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    return null;
  }
  final properties = rawProperties.map(
    (key, value) => MapEntry(key.toString(), value),
  );
  final required = (schema['required'] as List?)
          ?.map((item) => item.toString())
          .toList(growable: false) ??
      const <String>[];

  final missing = <String>[];
  for (final key in required) {
    final value = arguments[key];
    if (value == null || (value is String && value.trim().isEmpty)) {
      missing.add(key);
    }
  }

  final unknown = arguments.keys
      .where((key) => !properties.containsKey(key))
      .toList(growable: false);

  final mismatched = <String>[];
  for (final entry in arguments.entries) {
    final definition = properties[entry.key];
    final value = entry.value;
    if (definition is! Map || value == null) {
      continue;
    }
    final expectedType = definition['type']?.toString();
    if (expectedType != null && !_matchesType(value, expectedType)) {
      mismatched.add(
        '${entry.key}（应为 ${_typeLabel(expectedType)}，实际是 ${_valueLabel(value)}）',
      );
      continue;
    }
    final allowed = definition['enum'];
    if (allowed is List && !allowed.map((e) => e.toString()).contains('$value')) {
      mismatched.add(
        '${entry.key}（只能是 ${allowed.join('、')} 之一，实际是 $value）',
      );
    }
  }

  if (missing.isEmpty && unknown.isEmpty && mismatched.isEmpty) {
    return null;
  }

  final parts = <String>[
    if (missing.isNotEmpty) '缺少必填参数：${missing.join('、')}',
    if (unknown.isNotEmpty)
      '不支持的参数：${unknown.join('、')}（请删除；本工具只接受：${properties.keys.join('、')}）',
    if (mismatched.isNotEmpty) '类型不匹配：${mismatched.join('、')}',
  ];
  return '$toolName 的参数不符合要求。${parts.join('；')}。'
      '请按工具说明修正参数后重新调用，不要凭空构造字段。';
}

bool _matchesType(Object? value, String type) => switch (type) {
      'string' => value is String,
      'integer' => value is int || (value is double && value == value.roundToDouble()),
      'number' => value is num,
      'boolean' => value is bool,
      'array' => value is List,
      'object' => value is Map,
      _ => true,
    };

String _typeLabel(String type) => switch (type) {
      'string' => '字符串',
      'integer' => '整数',
      'number' => '数字',
      'boolean' => '布尔值',
      'array' => '数组',
      'object' => '对象',
      _ => type,
    };

String _valueLabel(Object? value) => switch (value) {
      String() => '字符串',
      bool() => '布尔值',
      int() => '整数',
      double() => '小数',
      List() => '数组',
      Map() => '对象',
      _ => '未知类型',
    };

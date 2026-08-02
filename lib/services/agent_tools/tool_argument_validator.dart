/// 工具参数的轻量校验器。
///
/// 目标不是完整实现 JSON Schema，而是把模型最常犯的三类错误
/// （缺失必填字段 / 未知字段 / 类型不匹配）**聚合成一条人话错误**，
/// 让模型一次就能改对，而不是靠多轮试错。
///
/// 校验会下钻到数组元素与嵌套对象：模型最常见的填错就发生在
/// `operations[0]` 这种层级里，只看顶层等于这些 schema 白写——错误会拖到
/// 深处才以内部异常的形式漏出去，模型读不懂也就改不对。
library;

/// 校验工具参数；通过返回 null，失败返回一条可执行的中文错误。
String? validateToolArguments({
  required String toolName,
  required Map<String, Object?> schema,
  required Map<String, Object?> arguments,
}) {
  final problems = _Problems();
  _validateObject(
    schema: schema,
    value: arguments,
    path: '',
    problems: problems,
    isRoot: true,
  );
  return problems.isEmpty ? null : problems.render(toolName);
}

/// 按类别聚合的问题，保证错误信息的结构与改法一一对应。
class _Problems {
  final List<String> missing = [];
  final List<String> unknown = [];
  final List<String> mismatched = [];
  String? rootAllowedKeys;

  bool get isEmpty => missing.isEmpty && unknown.isEmpty && mismatched.isEmpty;

  String render(String toolName) {
    final parts = <String>[
      if (missing.isNotEmpty) '缺少必填参数：${missing.join('、')}',
      if (unknown.isNotEmpty)
        '不支持的参数：${unknown.join('、')}'
            '${rootAllowedKeys == null ? '' : '（请删除；本工具只接受：$rootAllowedKeys）'}',
      if (mismatched.isNotEmpty) '类型不匹配：${mismatched.join('、')}',
    ];
    return '$toolName 的参数不符合要求。${parts.join('；')}。'
        '请按工具说明修正参数后重新调用，不要凭空构造字段。';
  }
}

String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

void _validateObject({
  required Map<String, Object?> schema,
  required Map<String, Object?> value,
  required String path,
  required _Problems problems,
  bool isRoot = false,
}) {
  final rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    // 未声明属性的自由对象不做约束。
    return;
  }
  final properties = rawProperties.map(
    (key, definition) => MapEntry(key.toString(), definition),
  );
  if (isRoot) {
    problems.rootAllowedKeys = properties.keys.join('、');
  }

  final required = (schema['required'] as List?)
          ?.map((item) => item.toString())
          .toList(growable: false) ??
      const <String>[];
  for (final key in required) {
    final field = value[key];
    if (field == null || (field is String && field.trim().isEmpty)) {
      problems.missing.add(_join(path, key));
    }
  }

  for (final entry in value.entries) {
    final key = entry.key;
    if (!properties.containsKey(key)) {
      // 顶层的可选字段在末尾统一列出；嵌套层必须就地说明，
      // 否则模型只知道自己写错了、不知道这一层该写什么。
      problems.unknown.add(
        isRoot
            ? key
            : '${_join(path, key)}（该层只接受：${properties.keys.join('、')}）',
      );
      continue;
    }
    final definition = properties[key];
    if (definition is Map && entry.value != null) {
      _validateValue(
        schema: definition.map(
          (schemaKey, schemaValue) =>
              MapEntry(schemaKey.toString(), schemaValue),
        ),
        value: entry.value,
        path: _join(path, key),
        problems: problems,
      );
    }
  }
}

void _validateValue({
  required Map<String, Object?> schema,
  required Object? value,
  required String path,
  required _Problems problems,
}) {
  if (value == null) return;

  final expectedType = schema['type']?.toString();
  if (expectedType != null && !_matchesType(value, expectedType)) {
    problems.mismatched.add(
      '$path（应为 ${_typeLabel(expectedType)}，实际是 ${_valueLabel(value)}）',
    );
    return;
  }

  final allowed = schema['enum'];
  if (allowed is List && !allowed.map((e) => e.toString()).contains('$value')) {
    problems.mismatched.add(
      '$path（只能是 ${allowed.join('、')} 之一，实际是 $value）',
    );
    return;
  }

  if (value is Map) {
    _validateObject(
      schema: schema,
      value: value.map((key, item) => MapEntry(key.toString(), item)),
      path: path,
      problems: problems,
    );
    return;
  }

  if (value is List) {
    final items = schema['items'];
    if (items is! Map) return;
    final itemSchema = items.map(
      (key, definition) => MapEntry(key.toString(), definition),
    );
    for (var index = 0; index < value.length; index++) {
      _validateValue(
        schema: itemSchema,
        value: value[index],
        path: '$path[$index]',
        problems: problems,
      );
    }
  }
}

bool _matchesType(Object? value, String type) => switch (type) {
      'string' => value is String,
      'integer' =>
        value is int || (value is double && value == value.roundToDouble()),
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

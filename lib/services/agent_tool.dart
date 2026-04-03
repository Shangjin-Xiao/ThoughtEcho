abstract class AgentTool {
  const AgentTool();

  String get name;

  String get description;

  Map<String, Object?> get parametersSchema;

  Future<ToolResult> execute(ToolCall toolCall);
}

class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  ToolCall copyWith({
    String? id,
    String? name,
    Map<String, Object?>? arguments,
  }) {
    return ToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
    );
  }

  @override
  String toString() {
    return 'ToolCall(id: $id, name: $name, arguments: $arguments)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ToolCall &&
        other.id == id &&
        other.name == name &&
        _mapEquals(other.arguments, arguments);
  }

  @override
  int get hashCode {
    return Object.hash(id, name, _mapHash(arguments));
  }
}

class ToolResult {
  const ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });

  final String toolCallId;
  final String content;
  final bool isError;

  ToolResult copyWith({
    String? toolCallId,
    String? content,
    bool? isError,
  }) {
    return ToolResult(
      toolCallId: toolCallId ?? this.toolCallId,
      content: content ?? this.content,
      isError: isError ?? this.isError,
    );
  }

  @override
  String toString() {
    return 'ToolResult(toolCallId: $toolCallId, isError: $isError, content: $content)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ToolResult &&
        other.toolCallId == toolCallId &&
        other.content == content &&
        other.isError == isError;
  }

  @override
  int get hashCode {
    return Object.hash(toolCallId, content, isError);
  }
}

class AgentResponse {
  const AgentResponse({
    required this.content,
    this.toolCalls = const <ToolCall>[],
    this.reachedMaxRounds = false,
  });

  final String content;
  final List<ToolCall> toolCalls;
  final bool reachedMaxRounds;

  AgentResponse copyWith({
    String? content,
    List<ToolCall>? toolCalls,
    bool? reachedMaxRounds,
  }) {
    return AgentResponse(
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      reachedMaxRounds: reachedMaxRounds ?? this.reachedMaxRounds,
    );
  }

  @override
  String toString() {
    return 'AgentResponse(content: $content, toolCalls: $toolCalls, reachedMaxRounds: $reachedMaxRounds)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AgentResponse &&
        other.content == content &&
        _listEquals(other.toolCalls, toolCalls) &&
        other.reachedMaxRounds == reachedMaxRounds;
  }

  @override
  int get hashCode {
    return Object.hash(content, _listHash(toolCalls), reachedMaxRounds);
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

int _listHash<T>(List<T> list) {
  return Object.hashAll(list);
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> map) {
  final keys = map.keys.toList()..sort((a, b) => '$a'.compareTo('$b'));
  return Object.hashAll(
    keys.map((key) => Object.hash(key, map[key])),
  );
}

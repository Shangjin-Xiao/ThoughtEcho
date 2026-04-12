import "package:flutter/foundation.dart";
import "package:thoughtecho/services/unified_log_service.dart";
import 'dart:collection';

abstract class AgentTool {
  const AgentTool();

  String get name;

  String get description;

  Map<String, Object?> get parametersSchema;

  Future<ToolResult> execute(ToolCall toolCall);
}

class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    required Map<String, Object?> arguments,
  }) : arguments = _deepFreezeMap(arguments);

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
        _deepEquals(other.arguments, arguments);
  }

  @override
  int get hashCode {
    return Object.hash(id, name, _deepHash(arguments));
  }
}

extension ToolCallExtensions on ToolCall {
  /// Safely gets a string argument.
  String getString(String key, {String defaultValue = ''}) {
    final value = arguments[key];
    if (value is String) return value;
    return value?.toString() ?? defaultValue;
  }

  /// Safely gets an integer argument, handling num and string inputs from LLM.
  int getInt(String key, {int defaultValue = 0}) {
    final value = arguments[key];
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Safely gets a boolean argument.
  bool getBool(String key, {bool defaultValue = false}) {
    final value = arguments[key];
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return defaultValue;
  }

  /// Logs a tool-related error to UnifiedLogService.
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    try {
      // We use string-based lookup to avoid hard dependency if possible,
      // but here we know it exists.
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Tool[$name]: $message',
        error: error,
        stackTrace: stackTrace,
        source: 'AgentTool',
      );
    } catch (e) {
      // Fallback to debugPrint if service is not available
      debugPrint('Failed to log tool error: $e');
      debugPrint('Original error: $message $error');
    }
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
  AgentResponse({
    required this.content,
    List<ToolCall> toolCalls = const <ToolCall>[],
    this.reachedMaxRounds = false,
  }) : toolCalls = List<ToolCall>.unmodifiable(toolCalls);

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

Map<String, Object?> _deepFreezeMap(Map<String, Object?> map) {
  final frozen = <String, Object?>{};
  for (final entry in map.entries) {
    frozen[entry.key] = _deepFreezeValue(entry.value);
  }
  return UnmodifiableMapView<String, Object?>(frozen);
}

Object? _deepFreezeValue(Object? value) {
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      frozen[entry.key.toString()] = _deepFreezeValue(entry.value);
    }
    return UnmodifiableMapView<String, Object?>(frozen);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepFreezeValue));
  }
  return value;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return Object.hashAll(
      keys.map((key) => Object.hash(key, _deepHash(value[key]))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

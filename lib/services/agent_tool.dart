import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/note_proposal_artifact.dart';

abstract class AgentTool {
  const AgentTool();

  String get name;

  String get description;

  /// 只读工具只获取信息，不直接产生持久化修改。
  bool get isReadOnly => false;

  /// 并发安全工具可在同一轮中与其他只读工具并发执行。
  bool get isConcurrencySafe => false;

  Map<String, Object?> get parametersSchema;

  Future<ToolResult> execute(ToolCall toolCall);
}

/// Stable categories for an Agent request failure that are safe to present in
/// the UI without exposing provider responses or credentials.
enum AgentFailureType {
  noProvider,
  missingApiKey,
  unsupportedProvider,
  timeout,
  cancelled,
  toolExecutionFailed,
  unknown,
}

/// An Agent failure with only the safe context required for user feedback.
class AgentRequestException implements Exception {
  const AgentRequestException(
    this.failureType, {
    this.providerName,
  });

  final AgentFailureType failureType;
  final String? providerName;

  @override
  String toString() => 'AgentRequestException($failureType)';
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

  /// 获取字符串参数
  String getString(String key, {String defaultValue = ''}) {
    final value = arguments[key];
    if (value is String) return value;
    return defaultValue;
  }

  /// 获取整数参数
  int getInt(String key, {int defaultValue = 0}) {
    final value = arguments[key];
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        logError('Failed to parse int from "$value"', error: e);
        return defaultValue;
      }
    }
    return defaultValue;
  }

  /// 记录错误日志
  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      print('[$name] $message');
      if (error != null) print('  Error: $error');
      if (stackTrace != null) print('  Stack: $stackTrace');
    }
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

class ToolResult {
  const ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
    this.retryable = false,
    this.failureType,
    this.artifact,
  });

  final String toolCallId;
  final String content;
  final bool isError;
  final bool retryable;
  final AgentFailureType? failureType;
  final AgentArtifact? artifact;

  ToolResult copyWith({
    String? toolCallId,
    String? content,
    bool? isError,
    bool? retryable,
    AgentFailureType? failureType,
    AgentArtifact? artifact,
  }) {
    return ToolResult(
      toolCallId: toolCallId ?? this.toolCallId,
      content: content ?? this.content,
      isError: isError ?? this.isError,
      retryable: retryable ?? this.retryable,
      failureType: failureType ?? this.failureType,
      artifact: artifact ?? this.artifact,
    );
  }

  @override
  String toString() {
    return 'ToolResult(toolCallId: $toolCallId, isError: $isError, retryable: $retryable, failureType: $failureType, content: $content)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ToolResult &&
        other.toolCallId == toolCallId &&
        other.content == content &&
        other.isError == isError &&
        other.retryable == retryable &&
        other.failureType == failureType;
  }

  @override
  int get hashCode {
    return Object.hash(toolCallId, content, isError, retryable, failureType);
  }
}

class ToolExecution {
  const ToolExecution({required this.call, required this.result});

  final ToolCall call;
  final ToolResult result;
}

class AgentResponse {
  AgentResponse({
    required this.content,
    List<ToolCall> toolCalls = const <ToolCall>[],
    List<ToolExecution> toolExecutions = const <ToolExecution>[],
    this.reachedMaxRounds = false,
  })  : toolCalls = List<ToolCall>.unmodifiable(toolCalls),
        toolExecutions = List<ToolExecution>.unmodifiable(toolExecutions);

  final String content;
  final List<ToolCall> toolCalls;
  final List<ToolExecution> toolExecutions;

  List<AgentArtifact> get artifacts => toolExecutions
      .map((execution) => execution.result.artifact)
      .whereType<AgentArtifact>()
      .toList(growable: false);
  final bool reachedMaxRounds;

  AgentResponse copyWith({
    String? content,
    List<ToolCall>? toolCalls,
    List<ToolExecution>? toolExecutions,
    bool? reachedMaxRounds,
  }) {
    return AgentResponse(
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      toolExecutions: toolExecutions ?? this.toolExecutions,
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

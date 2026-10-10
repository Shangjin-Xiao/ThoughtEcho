import 'dart:convert';
import 'package:thoughtecho/utils/app_logger.dart';

/// 消息状态枚举 - 追踪消息的生成过程
enum MessageState {
  pending, // 等待中
  thinking, // AI思考中
  responding, // AI生成回复中
  toolCalling, // 工具调用中
  complete, // 完成
  error, // 错误
}

/// 聊天消息模型 — 单一定义源（Single Source of Truth）
///
/// 支持多种角色（user/assistant/system/tool），
/// 同时保留 [isUser] 布尔值用于向后兼容 UI 层。
/// 扩展功能：支持流式增量更新和思考过程追踪。
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final String role; // 'user' | 'assistant' | 'system' | 'tool'
  final DateTime timestamp;
  final bool isLoading;
  final bool includedInContext; // 是否纳入 AI 上下文
  final String? metaJson; // 扩展元数据（Phase 2 tool_call 等）

  bool _isMetaParsed = false;
  Map<String, dynamic>? _parsedMeta;

  /// 缓存反序列化后的元数据 Map，避免列表滚动刷新时重复 jsonDecode
  Map<String, dynamic>? get parsedMeta {
    if (!_isMetaParsed && metaJson != null && metaJson!.isNotEmpty) {
      _isMetaParsed = true;
      try {
        final decoded = jsonDecode(metaJson!);
        if (decoded is Map<String, dynamic>) {
          _parsedMeta = decoded;
        } else if (decoded is Map) {
          _parsedMeta = decoded.map((k, v) => MapEntry(k.toString(), v));
        } else {
          AppLogger.w(
            'ChatMessage.parsedMeta 反序列化 metaJson 结果非 Map: ${decoded.runtimeType}',
            source: 'ChatMessage',
          );
        }
      } catch (e, stackTrace) {
        AppLogger.w(
          'ChatMessage.parsedMeta 反序列化 metaJson 失败 (${e.runtimeType})',
          error: e,
          stackTrace: stackTrace,
          source: 'ChatMessage',
        );
      }
    }
    return _parsedMeta;
  }

  // 流式传输相关字段（SOTA 实时显示）
  final MessageState state; // 消息当前状态
  final List<String> thinkingChunks; // 思考过程增量（每个thinking块一项）
  final List<String> responseChunks; // 回复增量（每个response块一项）

  // 格式化相关字段（支持富文本内容）
  final String? contentFormat; // 'plain' | 'delta' - 内容格式
  final String? deltaJson; // Delta JSON 字符串 - 富文本数据

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    String? role,
    required this.timestamp,
    this.isLoading = false,
    this.includedInContext = true,
    this.metaJson,
    this.state = MessageState.complete,
    this.thinkingChunks = const [],
    this.responseChunks = const [],
    this.contentFormat,
    this.deltaJson,
  }) : role = role ?? (isUser ? 'user' : 'assistant');

  /// 从 SQLite 行映射构建
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('ChatMessage.fromMap: id 不能为空');
    }
    final role = map['role']?.toString();
    final effectiveRole = (role != null && role.isNotEmpty) ? role : 'user';
    return ChatMessage(
      id: id,
      content: map['content']?.toString() ?? '',
      isUser: effectiveRole == 'user',
      role: effectiveRole,
      timestamp: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      includedInContext:
          _parseBool(map['included_in_context'], defaultValue: true),
      metaJson: _parseString(map['meta_json']),
      contentFormat: map['content_format']?.toString(),
      deltaJson: _parseString(map['delta_json']),
    );
  }

  /// 序列化为 SQLite 行映射
  Map<String, dynamic> toMap(String sessionId) {
    return {
      'id': id,
      'session_id': sessionId,
      'role': role,
      'content': content,
      'created_at': timestamp.toIso8601String(),
      'included_in_context': includedInContext ? 1 : 0,
      'meta_json': metaJson,
      'content_format': contentFormat,
      'delta_json': deltaJson,
    };
  }

  /// JSON 序列化（备份/同步）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUser': isUser,
      'role': role,
      'timestamp': timestamp.toIso8601String(),
      'includedInContext': includedInContext,
      'metaJson': metaJson,
      'state': state.name,
      'thinkingChunks': thinkingChunks,
      'responseChunks': responseChunks,
      'contentFormat': contentFormat,
      'deltaJson': deltaJson,
    };
  }

  /// 从 JSON 反序列化（备份/同步）
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role']?.toString();
    final isUser = _parseBool(json['isUser'], defaultValue: true);
    final role = (rawRole != null && rawRole.isNotEmpty)
        ? rawRole
        : (isUser ? 'user' : 'assistant');

    // 安全解析state枚举
    MessageState state = MessageState.complete;
    final stateStr = json['state']?.toString();
    if (stateStr != null && stateStr.isNotEmpty) {
      try {
        state = MessageState.values.byName(stateStr);
      } catch (_) {
        state = MessageState.complete;
      }
    }

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      isUser: role == 'user',
      role: role,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      includedInContext:
          _parseBool(json['includedInContext'], defaultValue: true),
      metaJson: _parseString(json['metaJson']),
      state: state,
      thinkingChunks: _toStringList(json['thinkingChunks']),
      responseChunks: _toStringList(json['responseChunks']),
      contentFormat: json['contentFormat']?.toString(),
      deltaJson: _parseString(json['deltaJson']),
    );
  }

  /// 辅助方法：安全转换为 String 列表
  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// 辅助方法：安全转换为 bool
  static bool _parseBool(dynamic val, {bool defaultValue = true}) {
    if (val is bool) return val;
    if (val is num) return val == 1;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return defaultValue;
  }

  /// 辅助方法：安全转换为 String（支持 Map/List 转化为 JSON 字符串）
  static String? _parseString(dynamic val) {
    if (val == null) return null;
    if (val is String) return val;
    if (val is Map) {
      try {
        final stringKeyMap = val.map((k, v) => MapEntry(k.toString(), v));
        return jsonEncode(stringKeyMap);
      } catch (_) {
        return val.toString();
      }
    }
    if (val is List) {
      try {
        return jsonEncode(val);
      } catch (_) {
        return val.toString();
      }
    }
    return val.toString();
  }

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    String? role,
    DateTime? timestamp,
    bool? isLoading,
    bool? includedInContext,
    String? metaJson,
    MessageState? state,
    List<String>? thinkingChunks,
    List<String>? responseChunks,
    String? contentFormat,
    String? deltaJson,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      includedInContext: includedInContext ?? this.includedInContext,
      metaJson: metaJson ?? this.metaJson,
      state: state ?? this.state,
      thinkingChunks: thinkingChunks ?? this.thinkingChunks,
      responseChunks: responseChunks ?? this.responseChunks,
      contentFormat: contentFormat ?? this.contentFormat,
      deltaJson: deltaJson ?? this.deltaJson,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

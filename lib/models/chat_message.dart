/// 消息状态枚举 - 追踪消息的生成过程
enum MessageState {
  pending,       // 等待中
  thinking,      // AI思考中
  responding,    // AI生成回复中
  toolCalling,   // 工具调用中
  complete,      // 完成
  error,         // 错误
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

  // 流式传输相关字段（SOTA 实时显示）
  final MessageState state;              // 消息当前状态
  final List<String> thinkingChunks;     // 思考过程增量（每个thinking块一项）
  final List<String> responseChunks;     // 回复增量（每个response块一项）

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
  }) : role = role ?? (isUser ? 'user' : 'assistant');

  /// 从 SQLite 行映射构建
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final role = map['role'] as String? ?? 'user';
    return ChatMessage(
      id: map['id'] as String,
      content: map['content'] as String? ?? '',
      isUser: role == 'user',
      role: role,
      timestamp: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      includedInContext: (map['included_in_context'] as int? ?? 1) == 1,
      metaJson: map['meta_json'] as String?,
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
    };
  }

  /// 从 JSON 反序列化（备份/同步）
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ??
        ((json['isUser'] as bool? ?? true) ? 'user' : 'assistant');

    // 安全解析state枚举
    MessageState state = MessageState.complete;
    final stateStr = json['state'] as String?;
    if (stateStr != null) {
      try {
        state = MessageState.values.byName(stateStr);
      } catch (_) {
        state = MessageState.complete;
      }
    }

    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      isUser: role == 'user',
      role: role,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      includedInContext: json['includedInContext'] as bool? ?? true,
      metaJson: json['metaJson'] as String?,
      state: state,
      thinkingChunks: _toStringList(json['thinkingChunks']),
      responseChunks: _toStringList(json['responseChunks']),
    );
  }

  /// 辅助方法：安全转换为String列表
  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

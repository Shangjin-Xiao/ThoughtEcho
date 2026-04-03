/// 聊天消息模型 — 单一定义源（Single Source of Truth）
///
/// 支持多种角色（user/assistant/system/tool），
/// 同时保留 [isUser] 布尔值用于向后兼容 UI 层。
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final String role; // 'user' | 'assistant' | 'system' | 'tool'
  final DateTime timestamp;
  final bool isLoading;
  final bool includedInContext; // 是否纳入 AI 上下文
  final String? metaJson; // 扩展元数据（Phase 2 tool_call 等）

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    String? role,
    required this.timestamp,
    this.isLoading = false,
    this.includedInContext = true,
    this.metaJson,
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
    };
  }

  /// 从 JSON 反序列化（备份/同步）
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ??
        ((json['isUser'] as bool? ?? true) ? 'user' : 'assistant');
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      isUser: role == 'user',
      role: role,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      includedInContext: json['includedInContext'] as bool? ?? true,
      metaJson: json['metaJson'] as String?,
    );
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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

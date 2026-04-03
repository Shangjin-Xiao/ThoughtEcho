import 'chat_message.dart';

/// 聊天会话模型
///
/// [sessionType] 区分笔记对话 (`'note'`) 和 Agent 对话 (`'agent'`)。
/// [noteId] 仅对 `note` 类型会话有值，Agent 会话为 null。
class ChatSession {
  final String id;
  final String sessionType; // 'note' | 'agent'
  final String? noteId; // 可空，Agent 会话为 null
  final String title;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final List<ChatMessage> messages;
  final bool isPinned;

  const ChatSession({
    required this.id,
    required this.sessionType,
    this.noteId,
    required this.title,
    required this.createdAt,
    required this.lastActiveAt,
    this.messages = const [],
    this.isPinned = false,
  });

  /// 从 SQLite 行映射构建（不含 messages，需单独查询）
  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'] as String,
      sessionType: map['session_type'] as String? ?? 'note',
      noteId: map['note_id'] as String?,
      title: map['title'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      lastActiveAt: DateTime.tryParse(map['last_active_at'] as String? ?? '') ??
          DateTime.now(),
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
    );
  }

  /// 序列化为 SQLite 行映射
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_type': sessionType,
      'note_id': noteId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'last_active_at': lastActiveAt.toIso8601String(),
      'is_pinned': isPinned ? 1 : 0,
    };
  }

  /// JSON 序列化（备份/同步）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionType': sessionType,
      'noteId': noteId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'isPinned': isPinned,
    };
  }

  /// 从 JSON 反序列化（备份/同步）
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      sessionType: json['sessionType'] as String? ?? 'note',
      noteId: json['noteId'] as String?,
      title: json['title'] as String? ?? json['noteTitle'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastActiveAt: DateTime.tryParse(json['lastActiveAt'] as String? ?? '') ??
          DateTime.now(),
      messages: (json['messages'] as List?)
              ?.map(
                (m) => ChatMessage.fromJson(m as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }

  ChatSession copyWith({
    String? id,
    String? sessionType,
    String? noteId,
    String? title,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    List<ChatMessage>? messages,
    bool? isPinned,
  }) {
    return ChatSession(
      id: id ?? this.id,
      sessionType: sessionType ?? this.sessionType,
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      messages: messages ?? this.messages,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatSession && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// 聊天会话模型
class ChatSession {
  final String id;
  final String noteId;
  final String noteTitle;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final List<ChatMessage> messages;
  final bool isPinned;

  ChatSession({
    required this.id,
    required this.noteId,
    required this.noteTitle,
    required this.createdAt,
    required this.lastActiveAt,
    required this.messages,
    this.isPinned = false,
  });

  ChatSession copyWith({
    String? id,
    String? noteId,
    String? noteTitle,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    List<ChatMessage>? messages,
    bool? isPinned,
  }) {
    return ChatSession(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      noteTitle: noteTitle ?? this.noteTitle,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      messages: messages ?? this.messages,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'noteTitle': noteTitle,
      'createdAt': createdAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'messages':
          messages
              .map(
                (m) => {
                  'id': m.id,
                  'content': m.content,
                  'isUser': m.isUser,
                  'timestamp': m.timestamp.toIso8601String(),
                },
              )
              .toList(),
      'isPinned': isPinned,
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      noteId: json['noteId'],
      noteTitle: json['noteTitle'],
      createdAt: DateTime.parse(json['createdAt']),
      lastActiveAt: DateTime.parse(json['lastActiveAt']),
      messages:
          (json['messages'] as List)
              .map(
                (m) => ChatMessage(
                  id: m['id'],
                  content: m['content'],
                  isUser: m['isUser'],
                  timestamp: DateTime.parse(m['timestamp']),
                ),
              )
              .toList(),
      isPinned: json['isPinned'] ?? false,
    );
  }
}

/// 聊天消息模型
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
  });

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    bool? isLoading,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

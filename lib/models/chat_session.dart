import 'chat_message.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('ChatSession.fromMap: id 不能为空');
    }
    return ChatSession(
      id: id,
      sessionType: map['session_type']?.toString() ?? 'note',
      noteId: map['note_id']?.toString(),
      title: map['title']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      lastActiveAt:
          DateTime.tryParse(map['last_active_at']?.toString() ?? '') ??
              DateTime.now(),
      isPinned: _parseBool(map['is_pinned'], defaultValue: false),
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
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map) {
          try {
            final stringKeyMap = item.map(
              (k, v) => MapEntry(k.toString(), v),
            );
            messages.add(ChatMessage.fromJson(stringKeyMap));
          } catch (e, stackTrace) {
            AppLogger.w(
              'ChatSession.fromJson 跳过解析失败的 ChatMessage 条目 (${e.runtimeType})',
              error: e,
              stackTrace: stackTrace,
              source: 'ChatSession',
            );
          }
        } else if (item != null) {
          AppLogger.w(
            'ChatSession.fromJson 跳过非 Map 类型的 ChatMessage 条目 (${item.runtimeType})',
            source: 'ChatSession',
          );
        }
      }
    }

    return ChatSession(
      id: json['id']?.toString() ?? '',
      sessionType: json['sessionType']?.toString() ?? 'note',
      noteId: json['noteId']?.toString(),
      title: json['title']?.toString() ?? json['noteTitle']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastActiveAt: DateTime.tryParse(json['lastActiveAt']?.toString() ?? '') ??
          DateTime.now(),
      messages: messages,
      isPinned: _parseBool(json['isPinned'], defaultValue: false),
    );
  }

  /// 辅助方法：安全转换为 bool
  static bool _parseBool(dynamic val, {bool defaultValue = false}) {
    if (val is bool) return val;
    if (val is num) return val == 1;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return defaultValue;
  }

  ChatSession copyWith({
    String? id,
    String? sessionType,
    String? noteId,
    bool clearNoteId = false,
    String? title,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    List<ChatMessage>? messages,
    bool? isPinned,
  }) {
    return ChatSession(
      id: id ?? this.id,
      sessionType: sessionType ?? this.sessionType,
      noteId: clearNoteId ? null : (noteId ?? this.noteId),
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

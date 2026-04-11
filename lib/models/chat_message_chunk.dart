/// 流式消息数据块 - 用于实时推送AI回复和思考过程
///
/// 每当AI生成新的内容块时，立即推送到流中，支持以下类型：
/// - thinking: AI思考过程
/// - response: AI回复内容
/// - toolCalling: 工具调用信息
/// - error: 错误信息
class ChatMessageChunk {
  /// 数据块类型
  final String type; // 'thinking' | 'response' | 'toolCalling' | 'error'

  /// 数据块内容（单个字符或一句话）
  final String content;

  /// 序号（用于排序和追踪）
  final int index;

  /// 是否为最后一个块
  final bool isLast;

  /// 完整内容累积（仅在isLast=true时有值）
  final String? fullContent;

  ChatMessageChunk({
    required this.type,
    required this.content,
    this.index = 0,
    this.isLast = false,
    this.fullContent,
  });

  /// 创建一个thinking块
  factory ChatMessageChunk.thinking(
    String content, {
    int index = 0,
    bool isLast = false,
  }) =>
      ChatMessageChunk(
        type: 'thinking',
        content: content,
        index: index,
        isLast: isLast,
      );

  /// 创建一个response块
  factory ChatMessageChunk.response(
    String content, {
    int index = 0,
    bool isLast = false,
    String? fullContent,
  }) =>
      ChatMessageChunk(
        type: 'response',
        content: content,
        index: index,
        isLast: isLast,
        fullContent: fullContent,
      );

  /// 创建一个toolCalling块
  factory ChatMessageChunk.toolCalling(
    String content, {
    int index = 0,
  }) =>
      ChatMessageChunk(
        type: 'toolCalling',
        content: content,
        index: index,
      );

  /// 创建一个error块
  factory ChatMessageChunk.error(String content) => ChatMessageChunk(
        type: 'error',
        content: content,
        isLast: true,
      );

  @override
  String toString() =>
      'ChatMessageChunk(type=$type, content=$content, index=$index, isLast=$isLast)';
}

import 'dart:convert';

import '../agent_tool.dart';

/// 工具输出被截断时统一附加的提示（明确告诉模型这不是失败）。
const String toolOutputTruncationNotice = '工具调用成功，但输出被截断。请用更具体的关键词或分页参数缩小范围。';

/// 注册层统一截断装饰器 —— 包住所有工具的 execute，没有工具能绕过截断。
///
/// 优先做「结构化截断」（减少返回条数而不是拦腰砍字符），保证工具结果仍是
/// 合法 JSON、分页字段不会被砍掉；只有无法结构化处理时才退化为字符截断。
class TruncatingAgentTool extends AgentTool {
  const TruncatingAgentTool(this.inner, {required this.maxChars});

  final AgentTool inner;
  final int maxChars;

  /// 错误消息的独立上限（防止 stack trace 撑爆上下文）。
  static const int maxErrorChars = 2000;

  @override
  String get name => inner.name;

  @override
  String get description => inner.description;

  @override
  bool get isReadOnly => inner.isReadOnly;

  @override
  bool get isConcurrencySafe => inner.isConcurrencySafe;

  @override
  Map<String, Object?> get parametersSchema => inner.parametersSchema;

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    final result = await inner.execute(toolCall);
    final limit = result.isError ? maxErrorChars : maxChars;
    if (result.content.length <= limit) {
      return result;
    }
    return result.copyWith(
      content: truncateToolOutput(result.content, limit),
    );
  }

  /// 结构化截断：JSON 对象优先减少最大列表字段的条数，其余退化为字符截断。
  static String truncateToolOutput(String content, int maxChars) {
    if (content.length <= maxChars) {
      return content;
    }
    final structured = _truncateJsonPayload(content, maxChars);
    if (structured != null) {
      return structured;
    }
    return '${content.substring(0, maxChars)}…\n\n[$toolOutputTruncationNotice]';
  }

  static String? _truncateJsonPayload(String content, int maxChars) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final payload =
        decoded.map((key, value) => MapEntry(key.toString(), value));

    // 找出最大的列表字段（通常是 notes / available_tags 这类结果集）。
    String? listKey;
    var listLength = 0;
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value is List && value.length > listLength) {
        listKey = entry.key;
        listLength = value.length;
      }
    }
    if (listKey == null || listLength < 2) {
      return null;
    }

    final items = List<Object?>.from(payload[listKey] as List);
    var kept = items.length;
    String encoded;
    do {
      kept--;
      final truncatedPayload = <String, Object?>{
        ...payload,
        listKey: items.take(kept).toList(growable: false),
        'truncated': true,
        'returned_count': kept,
        'omitted_count': items.length - kept,
        'truncation_notice': toolOutputTruncationNotice,
      };
      encoded = jsonEncode(truncatedPayload);
    } while (encoded.length > maxChars && kept > 1);

    if (encoded.length > maxChars) {
      return null;
    }
    return encoded;
  }
}

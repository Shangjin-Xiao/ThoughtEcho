import 'dart:convert';

import '../../models/agent_memory.dart';
import '../../utils/app_logger.dart';
import '../../utils/untrusted_text.dart';
import '../agent_memory_service.dart';
import '../agent_tool.dart';

/// 检索 Thoughter 长期记忆的事实层，并按需回带画像层条目及其 id。
///
/// 画像层本来就每轮注入，这里返回它只为一件事：拿到 id，好让 `remember` 能改能删。
class RecallTool extends AgentTool {
  const RecallTool(this._memory);

  final AgentMemoryService _memory;

  @override
  String get name => 'recall';

  @override
  String get description => '【只读】检索你记下的关于这个用户的长期记忆。\n'
      '用在：用户提到某个你可能记过的细节（地点、项目、习惯、人）；用户问"你还记得…吗"；'
      '以及你准备用 `remember` 修改或删除某条记忆、需要先拿到它的 id 时。\n'
      '不要用它检索用户写过的笔记——那归 `explore_notes`。这里只有你在对话中记下的东西。\n'
      '`query` 留空则列出全部画像条目和最重要的若干条事实。';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

  @override
  Map<String, Object?> get parametersSchema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': '检索关键词。留空则返回全部画像条目 + 最重要的事实。',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'description': '返回的事实条数上限，默认 8，最大 20。',
          },
        },
        'required': <String>[],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    if (!_memory.isEnabled) {
      return ToolResult(
        toolCallId: call.id,
        content: '用户已在设置中关闭长期记忆，没有可检索的内容。不要重试。',
        isError: true,
      );
    }

    final query = call.getString('query').trim();
    final limit = call
        .getInt('limit', defaultValue: AgentMemoryService.recallDefaultLimit)
        .clamp(1, 20);

    try {
      final now = DateTime.now();
      final profile = await _memory.activeProfile();
      final hits = await _memory.searchFacts(query, limit: limit);

      final payload = <String, Object?>{
        'query': query,
        'profile': profile
            .map(
              (entry) => <String, Object?>{
                'id': entry.id,
                'kind': entry.kind.storageValue,
                // 逐字段转义：绝不能对整段 jsonEncode 后的结果再转义。
                'directive': escapeUntrustedText(entry.directive),
                'observed': AgentMemoryService.describeAge(
                  entry.observedAt,
                  now,
                ),
              },
            )
            .toList(growable: false),
        'facts': hits
            .map(
              (hit) => <String, Object?>{
                'id': hit.fact.id,
                'category': hit.fact.category,
                'content': escapeUntrustedText(hit.fact.content),
                'importance': hit.fact.importance,
                'recorded': AgentMemoryService.describeAge(
                  hit.fact.createdAt,
                  now,
                ),
              },
            )
            .toList(growable: false),
        'note': '这些是过往观察，不是当前事实。与用户本轮所说冲突时以本轮为准，'
            '并用 remember 更新对应条目。',
      };

      return ToolResult(toolCallId: call.id, content: jsonEncode(payload));
    } catch (error, stackTrace) {
      logError(
        'recall 工具检索失败（query 长度 ${query.length}）',
        error: error,
        stackTrace: stackTrace,
        source: 'RecallTool',
      );
      // query 本身是用户数据，不进日志；异常原文也不回喂模型。
      return ToolResult(
        toolCallId: call.id,
        content: '记忆检索失败，这一轮拿不到记忆。不要重试，按没有记忆继续。',
        isError: true,
      );
    }
  }
}

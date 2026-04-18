import 'dart:convert';
import '../../utils/app_logger.dart';
import '../agent_tool.dart';

/// 提议编辑工具 - 让AI正式发起修改建议
///
/// 相比于让AI手写 JSON 代码块，此工具能确保输出格式 100% 正确。
/// 输出的内容会被 UI 识别为 smart_result 并渲染为功能卡片。
class ProposeEditTool extends AgentTool {
  const ProposeEditTool();

  @override
  String get name => 'propose_edit';

  @override
  String get description => '【核心工具】提议对现有笔记进行修改。'
      '当你想要润色、续写、总结或整理现有笔记内容时，必须调用此工具。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': '建议卡片的标题（如：润色建议、思路总结）',
          },
          'content': {
            'type': 'string',
            'description': '提议的具体内容（纯文本或 Markdown）',
          },
          'action': {
            'type': 'string',
            'enum': ['replace', 'append'],
            'description': '应用方式：replace=替换原文（润色常用），append=追加到末尾（续写常用）',
          },
          'note_id': {
            'type': 'string',
            'description': '可选：如果是对特定已有笔记的修改，请务必提供该笔记 ID',
          },
          'reason': {
            'type': 'string',
            'description': '可选：为什么要这样修改的简短理由',
          },
        },
        'required': ['title', 'content', 'action'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final title = call.getString('title');
    final content = call.getString('content');
    final action = call.getString('action');
    final noteId = call.getString('note_id');
    final reason = call.getString('reason');

    if (title.isEmpty || content.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '标题和内容不能为空',
        isError: true,
      );
    }

    try {
      final payload = <String, dynamic>{
        'type': 'smart_result',
        'title': title,
        'content': content,
        'action': action,
      };

      if (noteId.isNotEmpty) {
        payload['note_id'] = noteId;
      }

      if (reason.isNotEmpty) {
        payload['reason'] = reason;
      }

      // 将 payload 包装在标准的 smart_result 代码块中，以便 UI 现有逻辑能直接识别
      final resultBlock = '```smart_result\n${jsonEncode(payload)}\n```';

      return ToolResult(
        toolCallId: call.id,
        content: resultBlock,
      );
    } catch (e, stack) {
      logError('ProposeEditTool.execute 失败',
          error: e, stackTrace: stack, source: 'ProposeEditTool');
      return ToolResult(
        toolCallId: call.id,
        content: '生成编辑提议失败：$e',
        isError: true,
      );
    }
  }
}

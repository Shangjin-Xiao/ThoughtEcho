import 'dart:convert';

import '../../utils/app_logger.dart';
import '../agent_tool.dart';

/// 文本增强行动工具 - 让AI提议进行润色或续写操作
///
/// 用法：当用户请求润色/续写时，Agent 调用此工具提议一个行动
/// 工具不执行实际的处理，而是返回一个提议消息
/// UI层识别此提议并执行实际的流式润色/续写
class TextEnhancementActionTool extends AgentTool {
  const TextEnhancementActionTool();

  @override
  String get name => 'propose_text_enhancement';

  @override
  String get description => '提议对笔记进行润色或续写操作。Agent 调用此工具来告诉用户想要执行的操作及目标笔记。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['polish', 'continue_writing'],
            'description': 'polish=润色 或 continue_writing=续写',
          },
          'note_id': {
            'type': 'string',
            'description': '目标笔记的 ID',
          },
          'note_content': {
            'type': 'string',
            'description': '如果没有 note_id，可直接提供内容供润色/续写',
          },
          'reasoning': {
            'type': 'string',
            'description': '为什么选择这个笔记或内容的简短说明',
          },
        },
        'required': ['action'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final action = call.arguments['action'] as String? ?? '';
    final noteId = call.arguments['note_id'] as String?;
    final noteContent = call.arguments['note_content'] as String?;
    final reasoning = call.arguments['reasoning'] as String? ?? '';

    if (action != 'polish' && action != 'continue_writing') {
      return ToolResult(
        toolCallId: call.id,
        content: 'action 必须是 polish 或 continue_writing',
        isError: true,
      );
    }

    if ((noteId?.isEmpty ?? true) && (noteContent?.isEmpty ?? true)) {
      return ToolResult(
        toolCallId: call.id,
        content: '必须提供 note_id 或 note_content 中的至少一个',
        isError: true,
      );
    }

    try {
      final actionLabel = action == 'polish' ? '润色' : '续写';
      final hasNoteId = noteId != null && noteId.isNotEmpty;

      final response = <String, dynamic>{
        'type': 'text_enhancement_action',
        'action': action,
        'note_id': noteId,
        'has_content': noteContent != null && noteContent.isNotEmpty,
        'reasoning': reasoning,
        'message':
            hasNoteId ? '我推荐对笔记进行$actionLabel。' : '我推荐对这段内容进行$actionLabel。',
      };

      return ToolResult(
        toolCallId: call.id,
        content: jsonEncode(response),
      );
    } catch (e, stack) {
      logError('TextEnhancementActionTool.execute 失败',
          error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '提议操作时出错：$e',
        isError: true,
      );
    }
  }
}

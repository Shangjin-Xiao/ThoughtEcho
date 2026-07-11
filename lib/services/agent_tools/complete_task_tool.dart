import '../agent_tool.dart';

/// Marks an Agent task as complete after it has finished using tools.
class CompleteTaskTool extends AgentTool {
  const CompleteTaskTool();

  @override
  String get name => 'complete_task';

  @override
  String get description =>
      '当且仅当用户交付已完成时调用。result 必须是可直接展示给用户的最终答复。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'result': {
            'type': 'string',
            'description': '面向用户的最终结果，说明完成了什么及必要的结论。',
          },
        },
        'required': ['result'],
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    final result = toolCall.getString('result').trim();
    if (result.isEmpty) {
      return ToolResult(
        toolCallId: toolCall.id,
        content: 'result 不能为空；请完成任务后提供面向用户的最终结果。',
        isError: true,
        retryable: true,
      );
    }
    return ToolResult(toolCallId: toolCall.id, content: result);
  }
}

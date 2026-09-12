import 'dart:async';

import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import 'tool_argument_validator.dart';

/// 向用户提问的请求体。
class AskUserRequest {
  const AskUserRequest({
    required this.toolCallId,
    required this.question,
    this.header,
    required this.options,
    this.multiSelect = false,
  });

  final String toolCallId;
  final String question;
  final String? header;
  final List<String> options;
  final bool multiSelect;

  Map<String, Object?> toJson() => {
        'tool_call_id': toolCallId,
        'question': question,
        if (header != null && header!.isNotEmpty) 'header': header,
        'options': options,
        'multi_select': multiSelect,
      };
}

/// 用户对提问的回复。
class AskUserResponse {
  const AskUserResponse({
    this.selectedOptions = const [],
    this.customText,
    this.isCancelled = false,
  });

  final List<String> selectedOptions;
  final String? customText;
  final bool isCancelled;

  factory AskUserResponse.cancelled() =>
      const AskUserResponse(isCancelled: true);

  factory AskUserResponse.selected(List<String> options) =>
      AskUserResponse(selectedOptions: options);

  factory AskUserResponse.custom(String text) =>
      AskUserResponse(customText: text);
}

typedef AskUserPromptHandler = Future<AskUserResponse> Function(
  AskUserRequest request,
);

/// 向用户提问与选项确认工具。
///
/// 允许 Agent 在面临模糊需求、风格选择、分类确认等场景时，
/// 向用户呈现包含 2-4 个选项的交互式提问卡片。
/// 用户可以单选/多选，也可以输入自定义回复或取消。
class AskUserTool extends AgentTool {
  AskUserTool({AskUserPromptHandler? promptHandler})
      : _promptHandler = promptHandler;

  AskUserPromptHandler? _promptHandler;
  Completer<AskUserResponse>? _activeCompleter;

  void setPromptHandler(AskUserPromptHandler? handler) {
    _promptHandler = handler;
  }

  void cancelActivePrompt() {
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete(AskUserResponse.cancelled());
    }
  }

  @override
  void cancel() {
    cancelActivePrompt();
  }

  @override
  String get name => 'ask_user';

  @override
  String get description => '向用户提问并等待用户在界面上选择或输入回复。\n'
      '当需求不明确、需要用户在多个方案中确认、或需要用户做关键抉择时调用。\n'
      '必须提供 2 到 4 个候选项（options）。支持单选与多选（multi_select）。\n'
      '用户既可选择提供的选项，也可输入自定义文本，或直接取消操作。';

  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => false;

  @override
  bool get isInteractive => true;

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description': '向用户提出的问题内容，展示在卡片正文。必填且不能为空。',
          },
          'header': {
            'type': 'string',
            'description': '提问卡片顶部的分类或简短标题（可选，如「分类确认」、「风格选择」）。',
          },
          'options': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '供用户选择的选项列表，必须包含 2 到 4 个有效选项。',
          },
          'multi_select': {
            'type': 'boolean',
            'description': '是否允许多选。默认为 false（单选）。',
          },
        },
        'required': ['question', 'options'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final validationError = validateToolArguments(
      toolName: name,
      schema: parametersSchema,
      arguments: call.arguments,
    );
    if (validationError != null) {
      return _error(call, validationError);
    }

    final question = call.getString('question').trim();
    if (question.isEmpty) {
      return _error(call, 'question 不能为空。');
    }

    final rawOptions = call.arguments['options'];
    if (rawOptions is! List) {
      return _error(call, 'options 必须为数组。');
    }
    final options = rawOptions
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    if (options.length < 2 || options.length > 4) {
      return _error(call, 'options 必须包含 2 到 4 个有效选项。');
    }

    if (options.toSet().length != options.length) {
      return _error(call, 'options 选项不能重复。');
    }

    final header = call.getString('header').trim();
    final multiSelect = call.arguments['multi_select'] == true;

    final handler = _promptHandler;
    if (handler == null) {
      return ToolResult(
        toolCallId: call.id,
        content: '当前环境未配置用户交互处理程序，无法向用户提问。',
        isError: true,
        retryable: false,
      );
    }

    final request = AskUserRequest(
      toolCallId: call.id,
      question: question,
      header: header.isNotEmpty ? header : null,
      options: options,
      multiSelect: multiSelect,
    );

    cancelActivePrompt();

    final completer = Completer<AskUserResponse>();
    _activeCompleter = completer;

    handler(request).then((response) {
      if (!completer.isCompleted) {
        completer.complete(response);
      }
    }).catchError((error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    });

    try {
      final response = await completer.future;
      if (response.isCancelled) {
        return ToolResult(
          toolCallId: call.id,
          content: '用户取消了本次选择。',
        );
      }

      final custom = response.customText?.trim();
      if (custom != null && custom.isNotEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '用户输入了自定义回复：$custom',
        );
      }

      if (response.selectedOptions.isNotEmpty) {
        return ToolResult(
          toolCallId: call.id,
          content: '用户选择了：${response.selectedOptions.join('、')}',
        );
      }

      return ToolResult(
        toolCallId: call.id,
        content: '用户已确认，但未选择具体选项。',
      );
    } catch (e, stack) {
      logError('AskUserTool 执行失败', error: e, stackTrace: stack);
      return _error(call, '用户交互处理异常: $e');
    } finally {
      if (identical(_activeCompleter, completer)) {
        _activeCompleter = null;
      }
    }
  }

  ToolResult _error(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
        retryable: true,
      );
}

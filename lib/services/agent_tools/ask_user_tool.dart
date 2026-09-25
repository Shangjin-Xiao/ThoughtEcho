import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import 'tool_argument_validator.dart';

/// 提问选项：短标签 + 一句说明。
///
/// 对齐 Claude Code `AskUserQuestion` 的 option 形态：`label` 是 1–5 个词的
/// 短标题，`description` 解释该选项的含义或取舍。UI 上竖向排列，
/// 每行展示 `label`，有说明时在其下方展示 `description`。
/// 为兼容历史调用，纯字符串也会被解析为只有 `label` 的选项。
class AskUserOption {
  const AskUserOption({
    required this.label,
    this.description = '',
  });

  final String label;
  final String description;

  /// 解析字符串或 `{label, description}` 两种形态；非法返回 null。
  static AskUserOption? tryParse(dynamic raw) {
    if (raw is String) {
      final label = raw.trim();
      if (label.isEmpty) return null;
      return AskUserOption(label: label);
    }
    if (raw is Map) {
      final label = raw['label']?.toString().trim() ?? '';
      if (label.isEmpty) return null;
      final description = raw['description']?.toString().trim() ?? '';
      return AskUserOption(label: label, description: description);
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'label': label,
        if (description.isNotEmpty) 'description': description,
      };

  @override
  String toString() =>
      'AskUserOption(label: $label, description: $description)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AskUserOption &&
          other.label == label &&
          other.description == description;

  @override
  int get hashCode => Object.hash(label, description);
}

/// 一次提问中的单个问题。
class AskUserQuestion {
  const AskUserQuestion({
    required this.question,
    this.header,
    required this.options,
    this.multiSelect = false,
  });

  final String question;
  final String? header;
  final List<AskUserOption> options;
  final bool multiSelect;

  /// 选项短标签列表，兼容只关心标签的调用方。
  List<String> get optionLabels =>
      options.map((option) => option.label).toList(growable: false);

  Map<String, Object?> toJson() => {
        'question': question,
        if (header != null && header!.isNotEmpty) 'header': header,
        'options': [for (final option in options) option.toJson()],
        'multi_select': multiSelect,
      };

  @override
  String toString() =>
      'AskUserQuestion(question: $question, header: $header, options: $options, multiSelect: $multiSelect)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AskUserQuestion &&
          other.question == question &&
          other.header == header &&
          other.multiSelect == multiSelect &&
          listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(
        question,
        header,
        multiSelect,
        Object.hashAll(options),
      );
}

/// 向用户提问的请求体：一次可携带 1–4 个问题。
class AskUserRequest {
  const AskUserRequest({
    required this.toolCallId,
    required this.questions,
  });

  final String toolCallId;
  final List<AskUserQuestion> questions;

  /// 单问题快捷构造（兼容历史调用与测试）。
  factory AskUserRequest.single({
    required String toolCallId,
    required String question,
    String? header,
    required List<String> options,
    bool multiSelect = false,
  }) {
    return AskUserRequest(
      toolCallId: toolCallId,
      questions: [
        AskUserQuestion(
          question: question,
          header: header,
          options: [
            for (final label in options) AskUserOption(label: label),
          ],
          multiSelect: multiSelect,
        ),
      ],
    );
  }

  /// 首个问题全文；单问题场景下等价于历史 `question` 字段。
  String get question => questions.first.question;

  String? get header => questions.first.header;

  /// 首个问题的选项短标签；单问题场景下等价于历史 `options` 字段。
  List<String> get options => questions.first.optionLabels;

  bool get multiSelect => questions.first.multiSelect;

  Map<String, Object?> toJson() => {
        'tool_call_id': toolCallId,
        'questions': [for (final item in questions) item.toJson()],
      };

  @override
  String toString() =>
      'AskUserRequest(toolCallId: $toolCallId, questions: $questions)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AskUserRequest &&
          other.toolCallId == toolCallId &&
          listEquals(other.questions, questions);

  @override
  int get hashCode => Object.hash(
        toolCallId,
        Object.hashAll(questions),
      );
}

/// 单个问题的回答：选项选择与自定义文本互斥，自定义优先。
class AskUserAnswer {
  const AskUserAnswer({
    this.selectedOptions = const [],
    this.customText,
  });

  final List<String> selectedOptions;
  final String? customText;

  /// 有效的自定义文本（去首尾空白后非空）。
  String? get effectiveCustomText {
    final text = customText?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Map<String, Object?> toJson() => {
        'selectedOptions': selectedOptions,
        if (customText != null) 'customText': customText,
      };

  @override
  String toString() =>
      'AskUserAnswer(selectedOptions: $selectedOptions, customText: $customText)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AskUserAnswer &&
          other.customText == customText &&
          listEquals(other.selectedOptions, selectedOptions);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selectedOptions),
        customText,
      );
}

/// 用户对提问的回复：与请求中的 `questions` 一一对应。
class AskUserResponse {
  const AskUserResponse({
    this.answers = const [],
    this.isCancelled = false,
  });

  final List<AskUserAnswer> answers;
  final bool isCancelled;

  factory AskUserResponse.cancelled() =>
      const AskUserResponse(isCancelled: true);

  /// 单问题场景：选择选项。
  factory AskUserResponse.selected(List<String> options) =>
      AskUserResponse(answers: [AskUserAnswer(selectedOptions: options)]);

  /// 单问题场景：自定义回复。
  factory AskUserResponse.custom(String text) =>
      AskUserResponse(answers: [AskUserAnswer(customText: text)]);

  /// 首个回答的选项；兼容单问题调用方。
  List<String> get selectedOptions =>
      answers.isEmpty ? const [] : answers.first.selectedOptions;

  /// 首个回答的自定义文本；兼容单问题调用方。
  String? get customText => answers.isEmpty ? null : answers.first.customText;

  @override
  String toString() =>
      'AskUserResponse(answers: $answers, isCancelled: $isCancelled)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AskUserResponse &&
          other.isCancelled == isCancelled &&
          listEquals(other.answers, answers);

  @override
  int get hashCode => Object.hash(
        isCancelled,
        Object.hashAll(answers),
      );
}

typedef AskUserPromptHandler = Future<AskUserResponse> Function(
  AskUserRequest request,
);

/// 向用户提问与选项确认工具（对齐 Claude Code `AskUserQuestion`）。
///
/// 一次调用可携带 1–4 个问题，每个问题 2–4 个选项（`label` + `description`），
/// 支持单选/多选。自定义输入由界面自动提供，模型禁止在 `options` 里手写
/// "Other/其他" 类兜底选项；用户要么选选项、要么写自定义，两者互斥。
class AskUserTool extends AgentTool {
  AskUserTool({AskUserPromptHandler? promptHandler})
      : _promptHandler = promptHandler;

  /// 单次调用最多携带的问题数（与 Claude Code 一致）。
  static const int maxQuestions = 4;

  /// 每个问题最少/最多选项数（与 Claude Code 一致）。
  static const int minOptions = 2;
  static const int maxOptions = 4;

  /// header 短标签最大字符数（与 Claude Code 的 chip 宽度一致）。
  static const int maxHeaderLength = 12;

  /// 界面自动提供的自定义输入入口，模型禁止手写这些兜底选项。
  static const Set<String> reservedOptionLabels = {
    'other',
    '其他',
    '自定义',
  };

  AskUserPromptHandler? _promptHandler;
  Completer<AskUserResponse>? _activeCompleter;

  void setPromptHandler(AskUserPromptHandler? handler) {
    _promptHandler = handler;
  }

  bool get hasActivePrompt =>
      _activeCompleter != null && !_activeCompleter!.isCompleted;

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
      '一次可携带 1 到 $maxQuestions 个问题（questions），每个问题必须提供 '
      '$minOptions 到 $maxOptions 个候选项（options），支持单选与多选（multi_select）。\n'
      '每个选项用 label（1–5 个词的短标题）+ description（一句说明）描述。\n'
      '不要在 options 里加 "Other/其他/自定义" 兜底选项：界面会自动提供自定义输入入口，'
      '用户要么选择选项、要么输入自定义回复，两者互斥。\n'
      '兼容旧写法：单问题时也可直接传 question + options（字符串数组）。';

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
          'questions': {
            'type': 'array',
            'description': '问题列表，1 到 4 个。每个问题包含 question（必填）、'
                'header（短标签，最多 12 个字符）、options（2 到 4 个选项，'
                '每个选项为 label + description 对象）与 multi_select（默认 false）。',
          },
          'question': {
            'type': 'string',
            'description': '单问题兼容写法：向用户提出的问题内容，展示在卡片正文。与 questions 二选一。',
          },
          'header': {
            'type': 'string',
            'description': '单问题兼容写法：提问卡片顶部的分类或简短标题（可选，如「分类确认」、「风格选择」）。',
          },
          'options': {
            'type': 'array',
            'description':
                '单问题兼容写法：供用户选择的选项列表（字符串，或 label + description 对象），2 到 4 个有效选项。',
          },
          'multi_select': {
            'type': 'boolean',
            'description': '单问题兼容写法：是否允许多选。默认为 false（单选）。',
          },
        },
        'required': [],
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

    final questions = _parseQuestions(call);
    if (questions == null) {
      return _error(
        call,
        '缺少必填参数：questions（1 到 4 个问题）或 question + options（单问题兼容写法）。',
      );
    }
    final questionsError = _validateQuestions(questions);
    if (questionsError != null) {
      return _error(call, questionsError);
    }

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
      questions: questions,
    );

    cancelActivePrompt();

    final completer = Completer<AskUserResponse>();
    _activeCompleter = completer;

    Future.sync(() => handler(request)).then((response) {
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

      final answersError = _validateAnswers(questions, response);
      if (answersError != null) {
        return _error(call, answersError);
      }

      return ToolResult(
        toolCallId: call.id,
        content: _formatResult(questions, response),
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

  /// 解析 `questions` 数组；缺失时回退到单问题兼容写法；都缺失返回 null。
  List<AskUserQuestion>? _parseQuestions(ToolCall call) {
    final rawQuestions = call.arguments['questions'];
    if (rawQuestions is List && rawQuestions.isNotEmpty) {
      final parsed = <AskUserQuestion>[];
      for (final item in rawQuestions) {
        final question = _parseSingleQuestion(
          item is Map ? item.map((key, value) => MapEntry('$key', value)) : {},
        );
        if (question == null) return <AskUserQuestion>[];
        parsed.add(question);
      }
      return parsed;
    }

    final hasLegacyQuestion =
        call.arguments['question'] != null || call.arguments['options'] != null;
    if (!hasLegacyQuestion) return null;
    final question = _parseSingleQuestion(call.arguments);
    if (question == null) return <AskUserQuestion>[];
    return [question];
  }

  /// 解析单个问题（questions 数组元素或顶层兼容字段）；非法返回 null。
  AskUserQuestion? _parseSingleQuestion(Map<String, Object?> arguments) {
    final rawQuestion = arguments['question'];
    if (rawQuestion is! String || rawQuestion.trim().isEmpty) return null;
    final rawOptions = arguments['options'];
    if (rawOptions is! List) return null;

    final options = <AskUserOption>[];
    var hasMalformedOption = false;
    for (final raw in rawOptions) {
      final option = AskUserOption.tryParse(raw);
      if (option == null) {
        hasMalformedOption = true;
        continue;
      }
      options.add(option);
    }
    if (options.isEmpty && hasMalformedOption) return null;

    final rawHeader = arguments['header'];
    final header = rawHeader is String && rawHeader.trim().isNotEmpty
        ? rawHeader.trim()
        : null;
    final multiSelect =
        arguments['multi_select'] == true || arguments['multiSelect'] == true;

    return AskUserQuestion(
      question: rawQuestion.trim(),
      header: header,
      options: options,
      multiSelect: multiSelect,
    );
  }

  /// 校验问题列表；通过返回 null，否则返回人话错误。
  String? _validateQuestions(List<AskUserQuestion> questions) {
    if (questions.isEmpty) {
      return 'question 不能为空，options 必须为包含 2 到 4 个有效选项的数组。';
    }
    if (questions.length > maxQuestions) {
      return 'questions 最多包含 $maxQuestions 个问题，当前为 ${questions.length} 个。';
    }
    final seenQuestions = <String>{};
    for (var index = 0; index < questions.length; index++) {
      final item = questions[index];
      final prefix = questions.length == 1 ? '' : '第 ${index + 1} 个问题';
      if (item.question.isEmpty) {
        return '${prefix}question 不能为空。';
      }
      if (!seenQuestions.add(item.question)) {
        return 'questions 中存在重复的问题：「${item.question}」。';
      }
      if (item.header != null && item.header!.length > maxHeaderLength) {
        return '${prefix}header 最多 $maxHeaderLength 个字符，当前为 ${item.header!.length} 个。';
      }
      if (item.options.length < minOptions ||
          item.options.length > maxOptions) {
        return questions.length == 1
            ? 'options 必须包含 $minOptions 到 $maxOptions 个有效选项。'
            : '$prefix的 options 必须包含 $minOptions 到 $maxOptions 个有效选项。';
      }
      final seenLabels = <String>{};
      for (final option in item.options) {
        if (reservedOptionLabels.contains(option.label.toLowerCase())) {
          return '$prefix的 options 里不要加“${option.label}”兜底选项：'
              '界面会自动提供自定义输入入口。';
        }
        if (!seenLabels.add(option.label)) {
          return '$prefix的 options 选项不能重复：「${option.label}」。';
        }
      }
    }
    return null;
  }

  /// 校验用户回答与问题是否对应；通过返回 null，否则返回人话错误。
  String? _validateAnswers(
    List<AskUserQuestion> questions,
    AskUserResponse response,
  ) {
    if (response.answers.length > questions.length) {
      return '回答数量（${response.answers.length}）超过了问题数量（${questions.length}）。';
    }
    final count = response.answers.length < questions.length
        ? response.answers.length
        : questions.length;
    for (var index = 0; index < count; index++) {
      final item = questions[index];
      final answer = response.answers[index];
      final prefix = questions.length == 1 ? '' : '第 ${index + 1} 个问题';
      final validLabels = item.options.map((option) => option.label).toSet();
      final seen = <String>{};
      for (final selected in answer.selectedOptions) {
        if (!validLabels.contains(selected)) {
          return '$prefix选择结果包含无效选项：$selected';
        }
        if (!seen.add(selected)) {
          return '$prefix选择结果包含重复选项：$selected';
        }
      }
      if (!item.multiSelect && answer.selectedOptions.length > 1) {
        return questions.length == 1
            ? '单选模式下不能选择多个选项。'
            : '$prefix为单选模式，不能选择多个选项。';
      }
    }
    return null;
  }

  /// 把用户回答格式化为喂给模型的文本。
  ///
  /// 自定义文本与选项互斥：同一问题两者同时存在时采用自定义回复。
  String _formatResult(
    List<AskUserQuestion> questions,
    AskUserResponse response,
  ) {
    final lines = <String>[];
    final count = questions.length;
    for (var index = 0; index < count; index++) {
      final item = questions[index];
      final answer = index < response.answers.length
          ? response.answers[index]
          : const AskUserAnswer();
      final custom = answer.effectiveCustomText;
      final selected = answer.selectedOptions;
      final resolved = custom != null
          ? '回复：$custom'
          : selected.isNotEmpty
              ? '选择了：${selected.join('、')}'
              : '未作答';
      if (count == 1) {
        if (custom != null) return '用户输入了自定义回复：$custom';
        if (selected.isNotEmpty) return '用户选择了：${selected.join('、')}';
        return '用户未做出有效选择。';
      }
      lines.add('${index + 1}. 「${item.question}」→$resolved');
    }
    return '用户回答了 $count 个问题：\n${lines.join('\n')}';
  }

  ToolResult _error(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
        retryable: true,
      );
}

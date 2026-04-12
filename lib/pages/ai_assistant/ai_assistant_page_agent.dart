part of '../ai_assistant_page.dart';

extension _AIAssistantPageAgent on _AIAssistantPageState {
  Future<void> _askAgent(String text) async {
    final l10n = AppLocalizations.of(context);
    final history = _messages.where((m) => m.includedInContext).toList();

    // 用于追踪内联工具调用进度消息的 ID
    String? toolProgressMsgId;
    final toolItems = <ToolProgressItem>[];

    // 先订阅事件流，再启动 runAgent
    _agentEventSubscription?.cancel();
    final eventStream = _agentService.events;
    _agentEventSubscription = eventStream.listen((event) {
      if (!mounted) return;

      switch (event) {
        case AgentThinkingEvent():
          // 如果还没有工具进度消息，不做特殊处理（UI 已有 loading 状态）
          break;

        case AgentToolCallStartEvent():
          // 添加工具项并创建/更新内联工具进度消息
          toolItems.add(
            ToolProgressItem(
              toolName: event.toolName,
              description: _formatToolArgs(event.arguments),
              status: ToolProgressStatus.running,
            ),
          );
          if (toolProgressMsgId == null) {
            toolProgressMsgId = _uuid.v4();
            _appendMessage(
              app_chat.ChatMessage(
                id: toolProgressMsgId!,
                content: '',
                isUser: false,
                role: 'assistant',
                timestamp: DateTime.now(),
                includedInContext: false,
                metaJson: jsonEncode(<String, dynamic>{
                  'type': 'tool_progress',
                  'items': toolItems
                      .map((i) => {
                            'toolName': i.toolName,
                            'description': i.description ?? '',
                            'status': i.status.name,
                            'result': i.result ?? '',
                          })
                      .toList(),
                  'inProgress': true,
                }),
              ),
            );
          } else {
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: true,
            );
          }

        case AgentToolCallResultEvent():
          // 更新对应工具项状态为完成
          final idx = toolItems.lastIndexWhere(
            (item) =>
                item.toolName == event.toolName &&
                item.status == ToolProgressStatus.running,
          );
          if (idx != -1) {
            toolItems[idx] = toolItems[idx].copyWith(
              status: event.isError
                  ? ToolProgressStatus.failed
                  : ToolProgressStatus.completed,
              result: _truncateToolResult(event.result),
            );
          }
          if (toolProgressMsgId != null) {
            // 检查是否还有正在运行的工具
            final stillRunning = toolItems
                .any((item) => item.status == ToolProgressStatus.running);
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: stillRunning,
            );
          }

        case AgentResponseEvent():
          // 标记工具进度为完成
          if (toolProgressMsgId != null) {
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: false,
            );
          }

        case AgentErrorEvent():
          // 标记工具进度为完成
          if (toolProgressMsgId != null) {
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: false,
            );
          }
      }
    });

    try {
      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
        noteContext: _hasBoundNote ? widget.quote!.content : null,
      );

      final parsed = _parseAgentSmartResult(response.content, l10n);

      if (parsed.displayText.isNotEmpty) {
        _appendMessage(
          app_chat.ChatMessage(
            id: _uuid.v4(),
            content: parsed.displayText,
            isUser: false,
            role: 'assistant',
            timestamp: DateTime.now(),
          ),
          persist: true,
        );
      }

      if (parsed.smartResult != null) {
        if (_hasBoundNote) {
          _appendMessage(
            app_chat.ChatMessage(
              id: _uuid.v4(),
              content: parsed.smartResult!.content,
              isUser: false,
              role: 'assistant',
              timestamp: DateTime.now(),
              metaJson: jsonEncode(<String, dynamic>{
                'type': 'smart_result',
                'title': parsed.smartResult!.title,
                'replaceButtonText': l10n.replaceOriginalNote,
                'appendButtonText': l10n.appendToEnd,
              }),
            ),
            persist: true,
          );
        } else {
          _appendMessage(
            app_chat.ChatMessage(
              id: _uuid.v4(),
              content: parsed.smartResult!.content,
              isUser: false,
              role: 'assistant',
              timestamp: DateTime.now(),
            ),
            persist: true,
          );
        }
      }

      if (parsed.displayText.isEmpty && parsed.smartResult == null) {
        _appendMessage(
          app_chat.ChatMessage(
            id: _uuid.v4(),
            content: l10n.aiMisunderstoodQuestion,
            isUser: false,
            role: 'assistant',
            timestamp: DateTime.now(),
          ),
          persist: true,
        );
      }
      _finishLoading();
    } catch (e) {
      _finishLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiResponseError(e.toString()))),
      );
    } finally {
      _agentEventSubscription?.cancel();
      _agentEventSubscription = null;
    }
  }

  /// 更新内联工具进度消息
  void _updateToolProgressMessage(
    String msgId,
    List<ToolProgressItem> items, {
    required bool inProgress,
  }) {
    _setState(() {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx == -1) return;
      _messages[idx] = _messages[idx].copyWith(
        metaJson: jsonEncode(<String, dynamic>{
          'type': 'tool_progress',
          'items': items
              .map((i) => {
                    'toolName': i.toolName,
                    'description': i.description ?? '',
                    'status': i.status.name,
                    'result': i.result ?? '',
                  })
              .toList(),
          'inProgress': inProgress,
        }),
      );
    });
    _scrollToBottom();
  }

  /// 格式化工具参数为简短摘要
  String _formatToolArgs(Map<String, Object?> args) {
    if (args.isEmpty) return '';
    return args.entries.take(3).map((e) {
      final val = e.value is String
          ? (e.value as String).length > 50
              ? '${(e.value as String).substring(0, 50)}...'
              : e.value
          : e.value;
      return '${e.key}: $val';
    }).join(', ');
  }

  /// 截断工具结果用于进度面板显示
  String _truncateToolResult(String result) {
    if (result.length <= 200) return result;
    return '${result.substring(0, 200)}…';
  }

  _AgentSmartResultParseResult _parseAgentSmartResult(
    String rawContent,
    AppLocalizations l10n,
  ) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return const _AgentSmartResultParseResult(displayText: '');
    }

    for (final match
        in _AIAssistantPageState._agentCodeBlockPattern.allMatches(trimmed)) {
      final language = (match.group(1) ?? '').trim().toLowerCase();
      final payloadText = (match.group(2) ?? '').trim();
      if (payloadText.isEmpty) {
        continue;
      }

      final decoded = _tryDecodeJsonMap(payloadText);
      if (decoded == null) {
        continue;
      }

      final isSmartResultFence =
          language == 'smart_result' || language == 'smart-result';
      final type = decoded['type']?.toString().trim().toLowerCase();
      if (!isSmartResultFence && type != 'smart_result') {
        continue;
      }

      final smartContent =
          (decoded['content'] ?? decoded['text'])?.toString().trim();
      if (smartContent == null || smartContent.isEmpty) {
        continue;
      }

      final titleText = decoded['title']?.toString().trim();
      final title = titleText != null && titleText.isNotEmpty
          ? titleText
          : l10n.analysisResult;
      final displayText = trimmed.replaceFirst(match.group(0) ?? '', '').trim();

      return _AgentSmartResultParseResult(
        displayText: displayText,
        smartResult: _AgentSmartResultPayload(
          title: title,
          content: smartContent,
        ),
      );
    }

    return _AgentSmartResultParseResult(displayText: trimmed);
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String payloadText) {
    try {
      final decoded = jsonDecode(payloadText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _AgentSmartResultParseResult {
  const _AgentSmartResultParseResult({
    required this.displayText,
    this.smartResult,
  });

  final String displayText;
  final _AgentSmartResultPayload? smartResult;
}

class _AgentSmartResultPayload {
  const _AgentSmartResultPayload({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

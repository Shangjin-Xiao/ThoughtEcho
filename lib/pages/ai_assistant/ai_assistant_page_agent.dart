part of '../ai_assistant_page.dart';

extension _AIAssistantPageAgent on _AIAssistantPageState {
  Future<void> _askAgent(String text) async {
    final l10n = AppLocalizations.of(context);

    var history = _messages
        .where((m) => m.role != 'system' && m.metaJson == null)
        .toList();

    if (history.isNotEmpty &&
        history.last.isUser &&
        history.last.content == text) {
      history = history.sublist(0, history.length - 1);
    }

    _setState(() {
      _isLoading = true;
    });
    _scrollToBottom();

    String? toolProgressMsgId;
    final toolItems = <ToolProgressItem>[];
    String? streamingMsgId;
    var streamingText = '';

    try {
      final eventSub = _agentService.events.listen((event) {
        if (!mounted) return;
        switch (event) {
          case AgentThinkingEvent():
            streamingMsgId = null;
            streamingText = '';
          case AgentTextDeltaEvent():
            if (streamingMsgId == null) {
              streamingMsgId = _uuid.v4();
              _setState(() {
                _messages.add(app_chat.ChatMessage(
                  id: streamingMsgId!,
                  role: 'assistant',
                  isUser: false,
                  content: '',
                  timestamp: DateTime.now(),
                  isLoading: true,
                ));
              });
            }
            streamingText += event.delta;
            _updateMessage(streamingMsgId!, streamingText, isLoading: true);

          case AgentToolCallStartEvent():
            if (streamingMsgId != null) {
              _setState(() {
                _messages.removeWhere((m) => m.id == streamingMsgId);
              });
              streamingMsgId = null;
              streamingText = '';
            }
            if (toolProgressMsgId == null) {
              toolProgressMsgId = const Uuid().v4();
              final msg = app_chat.ChatMessage(
                id: toolProgressMsgId!,
                role: 'assistant',
                isUser: false,
                content: '',
                timestamp: DateTime.now(),
                metaJson: jsonEncode({
                  'type': 'tool_progress',
                  'items': [],
                  'inProgress': true,
                }),
              );
              _setState(() => _messages.add(msg));
              _scrollToBottom();
            }

            final newItem = ToolProgressItem(
              toolCallId: event.toolCallId,
              toolName: event.toolName,
              status: ToolProgressStatus.running,
              description: _formatToolArgs(event.toolName, event.arguments),
            );
            toolItems.add(newItem);
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: true,
            );

          case AgentToolCallResultEvent():
            final idx = toolItems.indexWhere(
              (i) => i.toolCallId == event.toolCallId,
            );
            if (idx != -1) {
              toolItems[idx] = toolItems[idx].copyWith(
                status: event.isError
                    ? ToolProgressStatus.failed
                    : ToolProgressStatus.completed,
                result: event.result,
              );
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: true,
              );
            }

          case AgentResponseEvent():
            if (toolProgressMsgId != null) {
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
              );
            }

          case AgentErrorEvent():
            if (streamingMsgId != null) {
              _setState(() {
                _messages.removeWhere((m) => m.id == streamingMsgId);
              });
              streamingMsgId = null;
              streamingText = '';
            }
            if (toolProgressMsgId != null) {
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
              );
            }
        }
      });

      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
        noteContext: _hasBoundNote ? widget.quote!.content : null,
      );

      await eventSub.cancel();

      if (!mounted) return;

      final parsed = _parseAgentSmartResult(response, l10n);

      if (parsed.displayText.isNotEmpty) {
        if (streamingMsgId != null) {
          final idx = _messages.indexWhere((m) => m.id == streamingMsgId);
          if (idx != -1) {
            _updateMessage(streamingMsgId!, parsed.displayText,
                isLoading: false);
          } else {
            _appendMessage(
              app_chat.ChatMessage(
                id: _uuid.v4(),
                role: 'assistant',
                isUser: false,
                content: parsed.displayText,
                timestamp: DateTime.now(),
              ),
              persist: true,
            );
          }
        } else {
          _appendMessage(
            app_chat.ChatMessage(
              id: _uuid.v4(),
              role: 'assistant',
              isUser: false,
              content: parsed.displayText,
              timestamp: DateTime.now(),
            ),
            persist: true,
          );
        }
      } else if (streamingMsgId != null) {
        _setState(() {
          _messages.removeWhere((m) => m.id == streamingMsgId);
        });
      }

      if (parsed.smartResult != null) {
        final cardMsg = app_chat.ChatMessage(
          id: _uuid.v4(),
          role: 'assistant',
          isUser: false,
          content: parsed.smartResult!.content,
          timestamp: DateTime.now(),
          metaJson: jsonEncode({
            'type': 'smart_result',
            'title': parsed.smartResult!.title,
            'note_id': parsed.smartResult!.noteId,
            'action': parsed.smartResult!.action,
            'tag_ids': parsed.smartResult!.tagIds,
            'include_location': parsed.smartResult!.includeLocation,
            'include_weather': parsed.smartResult!.includeWeather,
          }),
        );
        _setState(() => _messages.add(cardMsg));
        await _chatSessionService.addMessage(_currentSessionId!, cardMsg);
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiResponseError(e.toString()))),
      );
    } finally {
      if (mounted) {
        if (toolProgressMsgId != null) {
          _updateToolProgressMessage(
            toolProgressMsgId!,
            toolItems,
            inProgress: false,
          );
        }
        _finishLoading();
      }
    }
  }

  void _updateToolProgressMessage(
    String msgId,
    List<ToolProgressItem> items, {
    required bool inProgress,
  }) {
    _setState(() {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx == -1) return;
      final updatedMsg = _messages[idx].copyWith(
        isLoading: inProgress,
        metaJson: jsonEncode(<String, dynamic>{
          'type': 'tool_progress',
          'items': items
              .map((i) => {
                    'toolCallId': i.toolCallId ?? '',
                    'toolName': i.toolName,
                    'description': i.description ?? '',
                    'status': i.status.name,
                    'result': i.result ?? '',
                  })
              .toList(),
          'inProgress': inProgress,
        }),
      );
      _messages[idx] = updatedMsg;

      // 保存到数据库（完成时持久化最终状态）
      if (!inProgress && _currentSessionId != null) {
        _chatSessionService.addMessage(_currentSessionId!, updatedMsg);
      }
    });
    _scrollToBottom();
  }

  /// 格式化工具参数为简短摘要
  String _formatToolArgs(String toolName, Map<String, dynamic> args) {
    if (toolName == 'explore_notes' && args.containsKey('query')) {
      return '搜索: ${args['query']}';
    }
    if (toolName == 'get_tags') {
      return '读取标签列表';
    }
    if (toolName == 'get_location_weather') {
      return '读取位置与天气';
    }
    if (toolName == 'propose_new_note') {
      return '新建笔记建议: ${args['title'] ?? ''}';
    }
    if (toolName == 'web_search' && args.containsKey('query')) {
      return '联网搜索: ${args['query']}';
    }
    if (toolName == 'web_fetch' && args.containsKey('url')) {
      return '抓取网页: ${args['url']}';
    }
    if (args.isEmpty) return '';
    return args.toString();
  }

  /// 解析 Agent 回复中的 Smart Result 代码块或工具调用结果
  _AgentSmartResultParseResult _parseAgentSmartResult(
    AgentResponse response,
    AppLocalizations l10n,
  ) {
    final trimmed = response.content.trim();

    // 首先检查结构化提议工具调用 (propose_edit 或 propose_new_note)
    final smartResultCalls = response.toolCalls
        .where((c) => c.name == 'propose_edit' || c.name == 'propose_new_note')
        .toList();
    if (smartResultCalls.isNotEmpty) {
      final call = smartResultCalls.last;
      try {
        return _AgentSmartResultParseResult(
          displayText: trimmed, // 显示 AI 最终的回复（解释理由）
          smartResult: _AgentSmartResultPayload(
            title: call.arguments['title']?.toString() ?? 'AI 建议',
            content: call.arguments['content']?.toString() ?? '',
            noteId: call.arguments['note_id']?.toString(),
            action: call.arguments['action']?.toString(),
            tagIds: (call.arguments['tag_ids'] as List?)
                ?.map((item) => item.toString())
                .toList(),
            includeLocation: call.arguments['include_location'] == true,
            includeWeather: call.arguments['include_weather'] == true,
          ),
        );
      } catch (_) {
        // 如果出错则回退到正则解析
      }
    }

    if (trimmed.isEmpty) {
      return const _AgentSmartResultParseResult(displayText: '');
    }

    // 回退机制：匹配 ```smart_result ... ```
    final regex = RegExp(
      r'```(?:smart_result|smart-result)\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    );

    final match = regex.firstMatch(trimmed);
    if (match == null) {
      return _AgentSmartResultParseResult(displayText: trimmed);
    }

    final jsonText = match.group(1) ?? '';
    final displayText = trimmed.replaceRange(match.start, match.end, '').trim();

    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      return _AgentSmartResultParseResult(
        displayText: displayText,
        smartResult: _AgentSmartResultPayload(
          title: data['title']?.toString() ?? 'AI 建议',
          content: data['content']?.toString() ?? '',
          noteId: data['note_id']?.toString(),
          action: data['action']?.toString(),
          tagIds: (data['tag_ids'] as List?)
              ?.map((item) => item.toString())
              .toList(),
          includeLocation: data['include_location'] == true,
          includeWeather: data['include_weather'] == true,
        ),
      );
    } catch (e) {
      return _AgentSmartResultParseResult(displayText: trimmed);
    }
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
    this.noteId,
    this.action,
    this.tagIds,
    this.includeLocation = false,
    this.includeWeather = false,
  });

  final String title;
  final String content;
  final String? noteId;
  final String? action;
  final List<String>? tagIds;
  final bool includeLocation;
  final bool includeWeather;
}

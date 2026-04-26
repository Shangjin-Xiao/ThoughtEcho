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
    String? toolThinkingText;
    // 工具组是否仍处于"采集叙述"状态：从首个 AgentToolCallStartEvent 起为 true，
    // 直到 AgentResponseEvent / AgentErrorEvent / 流程结束，期间所有
    // AgentTextDeltaEvent 都并入 tool_progress 卡片，按时间顺序穿插在工具调用之间，
    // 而非另起独立聊天气泡。
    var toolGroupOpen = false;
    // 自上一次 AgentToolCallStartEvent 之后累积的尾部叙述长度。
    // 在 AgentResponseEvent 触发时需要从最后一项 narrationText（或 thinkingText）
    // 中删除这段内容，避免最终回答既出现在工具卡片里又出现在主气泡正文中重复。
    var pendingTailNarration = '';

    try {
      await _agentEventSubscription?.cancel();
      _agentEventSubscription = _agentService.events.listen((event) {
        if (!mounted) return;
        switch (event) {
          case AgentThinkingEvent():
            streamingMsgId = null;
            streamingText = '';
          case AgentTextDeltaEvent():
            if (toolGroupOpen && toolProgressMsgId != null) {
              // 工具调用进行中：把叙述按时间穿插进工具卡片。
              pendingTailNarration += event.delta;
              if (toolItems.isEmpty) {
                // 还没产出任何工具，只能并到 thinkingText（首个工具开始前的引子）。
                toolThinkingText = (toolThinkingText ?? '') + event.delta;
              } else {
                // 追加到最后一个工具的 narrationText，让其在该工具下方按时序展示。
                final last = toolItems.last;
                final updated = (last.narrationText ?? '') + event.delta;
                toolItems[toolItems.length - 1] =
                    last.copyWith(narrationText: updated);
              }
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: true,
                thinkingText: toolThinkingText,
              );
              break;
            }
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
            if (streamingMsgId != null && streamingText.trim().isNotEmpty) {
              // 工具调用开始：把工具前的叙述并入 tool_progress 卡片的
              // thinkingText，并移除原临时气泡，让所有内容时序集中到工具卡片。
              final pendingId = streamingMsgId!;
              _setState(() {
                _messages.removeWhere((m) => m.id == pendingId);
              });
              toolThinkingText = (toolThinkingText ?? '') + streamingText;
              streamingMsgId = null;
              streamingText = '';
            }
            toolGroupOpen = true;
            // 新工具开始 = 之前积累的尾部叙述属于"工具间过渡"，应保留在原位置
            // （已通过 live update 写入），重置 pending 计数避免后续 ResponseEvent 误删。
            pendingTailNarration = '';
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
                  'thinkingText': toolThinkingText ?? '',
                }),
              );
              _setState(() => _messages.add(msg));
              _scrollToBottom();
            }

            final newItem = ToolProgressItem(
              toolCallId: event.toolCallId,
              toolName: _formatToolLabel(
                l10n,
                event.toolName,
                event.arguments,
              ),
              status: ToolProgressStatus.running,
              description: _formatToolArgs(
                l10n,
                event.toolName,
                event.arguments,
              ),
            );
            toolItems.add(newItem);
            _updateToolProgressMessage(
              toolProgressMsgId!,
              toolItems,
              inProgress: true,
              thinkingText: toolThinkingText,
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
                result: _formatToolResultSummary(
                  l10n,
                  event.toolName,
                  event.result,
                  isError: event.isError,
                ),
              );
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: true,
                thinkingText: toolThinkingText,
              );
            }

          case AgentResponseEvent():
            toolGroupOpen = false;
            // 把"最后一次工具调用之后到 ResponseEvent 之间的尾部叙述"
            // 从工具卡片中剥离——那其实是 AI 流式输出的最终回答，
            // 紧接着会作为独立主气泡呈现，避免重复。
            if (pendingTailNarration.isNotEmpty) {
              final stripLen = pendingTailNarration.length;
              if (toolItems.isNotEmpty) {
                final last = toolItems.last;
                final current = last.narrationText ?? '';
                final cut = current.length >= stripLen
                    ? current.substring(0, current.length - stripLen)
                    : '';
                toolItems[toolItems.length - 1] =
                    last.copyWith(narrationText: cut);
              } else if ((toolThinkingText ?? '').length >= stripLen) {
                final t = toolThinkingText!;
                toolThinkingText = t.substring(0, t.length - stripLen);
              }
              pendingTailNarration = '';
            }
            if (toolProgressMsgId != null) {
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
                thinkingText: toolThinkingText,
              );
            }

          case AgentErrorEvent():
            toolGroupOpen = false;
            pendingTailNarration = '';
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
                thinkingText: toolThinkingText,
              );
            }
        }
      });

      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
        noteContext: _hasBoundNote ? widget.quote!.content : null,
      );

      await _agentEventSubscription?.cancel();
      _agentEventSubscription = null;

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
        // 解析标签 ID 为可读名称，供 SmartResultCard 同步展示
        List<String> tagNames = [];
        final tagIds = parsed.smartResult!.tagIds;
        if (tagIds != null && tagIds.isNotEmpty) {
          try {
            final db = context.read<DatabaseService>();
            final allTags = await db.getCategories();
            final tagMap = <String, String>{
              for (final t in allTags) t.id: t.name,
            };
            tagNames = tagIds
                .map((id) => tagMap[id] ?? id)
                .where((name) => name.isNotEmpty)
                .toList();
          } catch (_) {
            tagNames = tagIds;
          }
        }

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
            'tag_names': tagNames,
            'author': parsed.smartResult!.author,
            'source': parsed.smartResult!.source,
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
      await _agentEventSubscription?.cancel();
      _agentEventSubscription = null;
      if (mounted) {
        if (toolProgressMsgId != null) {
          _updateToolProgressMessage(
            toolProgressMsgId!,
            toolItems,
            inProgress: false,
            thinkingText: toolThinkingText,
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
    String? thinkingText,
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
                    'narrationText': i.narrationText ?? '',
                  })
              .toList(),
          'inProgress': inProgress,
          'thinkingText': thinkingText ?? '',
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
  String _formatToolLabel(
    AppLocalizations l10n,
    String toolName,
    Map<String, Object?> args,
  ) {
    final query = _displayQuery(args['query']);
    return switch (toolName) {
      'explore_notes' || 'search_notes' => query.isEmpty
          ? l10n.agentReviewingRecentNotes
          : l10n.agentSearchingNotesForQuery(query),
      'get_tags' => l10n.agentCollectingTags,
      'get_location_weather' => l10n.agentCheckingLocationWeather,
      'propose_new_note' => l10n.agentPreparingNewNoteSuggestion,
      'propose_edit' => l10n.agentPreparingEditSuggestion,
      'web_search' => query.isEmpty
          ? l10n.agentWebSearching
          : l10n.agentSearchingWebForQuery(query),
      'web_fetch' => l10n.agentReadingWebPage,
      _ => l10n.agentToolCall(toolName),
    };
  }

  String _formatToolArgs(
    AppLocalizations l10n,
    String toolName,
    Map<String, Object?> args,
  ) {
    if ((toolName == 'explore_notes' || toolName == 'search_notes') &&
        args.containsKey('query')) {
      return '';
    }
    if (toolName == 'get_tags') {
      return '';
    }
    if (toolName == 'get_location_weather') {
      return '';
    }
    if (toolName == 'propose_new_note') {
      return args['title']?.toString() ?? '';
    }
    if (toolName == 'web_search' && args.containsKey('query')) {
      return '';
    }
    if (toolName == 'web_fetch' && args.containsKey('url')) {
      return args['url'].toString();
    }
    if (args.isEmpty) return '';
    return args.toString();
  }

  String _displayQuery(Object? rawQuery) {
    final query = rawQuery?.toString().trim() ?? '';
    if (query.isEmpty || query.length > 12 || query.contains('\n')) {
      return '';
    }
    return query;
  }

  String _formatToolResultSummary(
    AppLocalizations l10n,
    String toolName,
    String result, {
    required bool isError,
  }) {
    if (isError) {
      return l10n.agentToolStepDidNotFinish;
    }

    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      return l10n.agentToolStepFinished;
    }

    return switch (toolName) {
      'explore_notes' ||
      'search_notes' =>
        _summarizeNoteSearchResult(l10n, trimmed),
      'get_tags' => _summarizeTagResult(l10n, trimmed),
      'get_location_weather' => _summarizeLocationWeatherResult(l10n, trimmed),
      'web_search' => _summarizeWebSearchResult(l10n, trimmed),
      'web_fetch' => _summarizeWebFetchResult(l10n, trimmed),
      'propose_new_note' || 'propose_edit' => l10n.agentPreparedSuggestionCard,
      _ => l10n.agentToolStepFinished,
    };
  }

  String _summarizeNoteSearchResult(AppLocalizations l10n, String result) {
    final payload = _tryParseJsonMap(result);
    if (payload == null) {
      return l10n.agentToolStepFinished;
    }

    final notes = payload['notes'] as List<dynamic>? ?? const [];
    final pagination = payload['pagination'] as Map<String, dynamic>?;
    final totalCount = pagination?['total_count'] as int? ?? notes.length;
    final hasMore = pagination?['has_more'] == true;

    if (totalCount <= 0) {
      return l10n.agentFoundNoMatchingNotes;
    }
    if (hasMore) {
      return l10n.agentFoundMatchingNotesWithMore(totalCount);
    }
    return l10n.agentFoundMatchingNotes(totalCount);
  }

  String _summarizeTagResult(AppLocalizations l10n, String result) {
    final payload = _tryParseJsonMap(result);
    if (payload == null) {
      return l10n.agentToolStepFinished;
    }

    final tags = payload['available_tags'] as List<dynamic>? ?? const [];
    final pagination = payload['pagination'] as Map<String, dynamic>?;
    final totalCount = pagination?['total_count'] as int? ?? tags.length;
    return l10n.agentPreparedTagChoices(totalCount);
  }

  String _summarizeLocationWeatherResult(
    AppLocalizations l10n,
    String result,
  ) {
    final payload = _tryParseJsonMap(result);
    if (payload == null) {
      return l10n.agentCheckedLocationWeather;
    }

    final location = payload['location_display']?.toString().trim() ?? '';
    final weather = payload['weather_display']?.toString().trim() ?? '';
    if (location.isEmpty && weather.isEmpty) {
      return l10n.agentCheckedLocationWeather;
    }
    return l10n.agentCheckedLocationWeatherWithDetails(
      location.isEmpty ? l10n.unknown : location,
      weather.isEmpty ? l10n.unknown : weather,
    );
  }

  String _summarizeWebSearchResult(AppLocalizations l10n, String result) {
    final matches = RegExp(r'^\d+\.\s', multiLine: true).allMatches(result);
    if (matches.isEmpty) {
      return l10n.agentToolStepFinished;
    }
    return l10n.agentFoundWebSources(matches.length);
  }

  String _summarizeWebFetchResult(AppLocalizations l10n, String result) {
    return l10n.agentReadWebPageSummary(result.length);
  }

  Map<String, dynamic>? _tryParseJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
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
            author: call.arguments['author']?.toString(),
            source: call.arguments['source']?.toString(),
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
          author: data['author']?.toString(),
          source: data['source']?.toString(),
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
    this.author,
    this.source,
    this.includeLocation = false,
    this.includeWeather = false,
  });

  final String title;
  final String content;
  final String? noteId;
  final String? action;
  final List<String>? tagIds;
  final String? author;
  final String? source;
  final bool includeLocation;
  final bool includeWeather;
}

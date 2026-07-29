part of '../ai_assistant_page.dart';

extension _AIAssistantPageAgent on _AIAssistantPageState {
  Future<void> _askAgent(String text) async {
    final l10n = AppLocalizations.of(context);
    final requestGeneration = ++_agentRequestGeneration;
    StreamSubscription<AgentEvent>? eventSubscription;

    var history = _messages
        .where((m) => m.role != 'system' && m.metaJson == null)
        .toList();

    if (history.isNotEmpty &&
        history.last.isUser &&
        history.last.content == text) {
      history = history.sublist(0, history.length - 1);
    }

    final adoptionNotice = _buildProposalAdoptionNotice();
    if (adoptionNotice != null) {
      history = [...history, adoptionNotice];
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
    var toolProgressInProgress = false;
    var reachedMaxRounds = false;

    void ensureToolProgressMessage() {
      if (toolProgressMsgId != null) return;
      toolProgressMsgId = const Uuid().v4();
      toolProgressInProgress = true;
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

    void finalizeNarrationMessage(String messageId, String content) {
      _setState(() {
        final index =
            _messages.indexWhere((message) => message.id == messageId);
        if (index == -1) return;
        final finalized = _messages[index].copyWith(
          content: content,
          isLoading: false,
        );
        _messages[index] = finalized;
        if (_currentSessionId != null) {
          unawaited(
            _chatSessionService.addMessage(_currentSessionId!, finalized),
          );
        }
      });
      _scrollToBottom();
    }

    /// 出错时保留已输出内容并标记为失败状态；完全没有内容时才移除空气泡。
    void markStreamingMessageFailed(String messageId, String content) {
      _setState(() {
        final index =
            _messages.indexWhere((message) => message.id == messageId);
        if (index == -1) return;
        final resolvedContent =
            content.isNotEmpty ? content : _messages[index].content;
        if (resolvedContent.trim().isEmpty) {
          _messages.removeAt(index);
          return;
        }
        final failed = _messages[index].copyWith(
          content: resolvedContent,
          isLoading: false,
          state: app_chat.MessageState.error,
        );
        _messages[index] = failed;
        if (_currentSessionId != null) {
          unawaited(
            _chatSessionService.addMessage(_currentSessionId!, failed),
          );
        }
      });
    }

    try {
      final previousSubscription = _agentEventSubscription;
      await previousSubscription?.cancel();
      if (!mounted || requestGeneration != _agentRequestGeneration) {
        return;
      }
      eventSubscription = _agentService.events.listen((event) {
        if (!mounted || requestGeneration != _agentRequestGeneration) return;
        switch (event) {
          case AgentThinkingEvent():
            streamingText = '';
          case AgentReasoningDeltaEvent():
            ensureToolProgressMessage();
            toolProgressInProgress = true;
            toolThinkingText = '${toolThinkingText ?? ''}${event.delta}';
            _scheduleToolProgressUpdate(
              toolProgressMsgId!,
              toolItems,
              inProgress: true,
              thinkingText: toolThinkingText,
            );
          case AgentTextDeltaEvent():
            if (toolProgressMsgId != null && toolProgressInProgress) {
              toolProgressInProgress = false;
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
                thinkingText: toolThinkingText,
              );
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
            _scheduleStreamUpdate(
              streamingMsgId!,
              streamingText,
              isLoading: true,
            );

          case AgentToolCallStartEvent():
            if (streamingMsgId != null) {
              _flushStreamUpdate();
              _cancelStreamUpdate();
              final pendingId = streamingMsgId!;
              finalizeNarrationMessage(pendingId, streamingText);
              streamingMsgId = null;
              streamingText = '';
            }
            ensureToolProgressMessage();
            toolProgressInProgress = true;

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
              toolProgressInProgress = toolItems.any(
                (item) => item.status == ToolProgressStatus.running,
              );
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: toolProgressInProgress,
                thinkingText: toolThinkingText,
              );
            }

          case AgentResponseEvent():
            reachedMaxRounds = event.reachedMaxRounds;
            if (streamingMsgId != null) {
              _flushStreamUpdate();
              _cancelStreamUpdate();
            }
            if (toolProgressMsgId != null) {
              toolProgressInProgress = false;
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
                thinkingText: toolThinkingText,
              );
            }

          case AgentErrorEvent():
            if (streamingMsgId != null) {
              // 保留已经流式输出的正文，只在消息上标记错误状态，
              // 避免用户看到内容凭空消失（历史 bug：整段 removeWhere）。
              _flushStreamUpdate();
              _cancelStreamUpdate();
              markStreamingMessageFailed(streamingMsgId!, streamingText);
              streamingMsgId = null;
              streamingText = '';
            }
            if (toolProgressMsgId != null) {
              toolProgressInProgress = false;
              _updateToolProgressMessage(
                toolProgressMsgId!,
                toolItems,
                inProgress: false,
                thinkingText: toolThinkingText,
              );
            }
        }
      });
      _agentEventSubscription = eventSubscription;

      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
        noteContext: _hasBoundNote
            ? AgentNoteContext(
                noteId: _boundNoteId,
                content: widget.quote!.content,
                documentKind: ProposeNoteEditTool.kindForQuote(widget.quote!),
                documentRevision:
                    ProposeNoteEditTool.revisionForQuote(widget.quote!),
              )
            : null,
      );

      await eventSubscription.cancel();
      if (identical(_agentEventSubscription, eventSubscription)) {
        _agentEventSubscription = null;
      }

      if (!mounted || requestGeneration != _agentRequestGeneration) return;

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
        if (streamingText.trim().isNotEmpty) {
          // 被停止等情况下没有最终文本时，保留已经流式输出的内容
          finalizeNarrationMessage(streamingMsgId!, streamingText);
        } else {
          _setState(() {
            _messages.removeWhere((m) => m.id == streamingMsgId);
          });
        }
      }

      // 达到轮次上限时给用户可见提示，避免结论看起来"莫名其妙地停了"。
      if (reachedMaxRounds || response.reachedMaxRounds) {
        _appendMessage(
          app_chat.ChatMessage(
            id: _uuid.v4(),
            content: l10n.agentReachedMaxRounds,
            isUser: false,
            role: 'system',
            timestamp: DateTime.now(),
            includedInContext: false,
          ),
          persist: false,
        );
      }

      if (parsed.smartResult != null) {
        final artifact = parsed.smartResult!.artifact;

        if (!mounted || requestGeneration != _agentRequestGeneration) {
          return;
        }

        final cardMsg = app_chat.ChatMessage(
          id: _uuid.v4(),
          role: 'assistant',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          metaJson: jsonEncode({
            'type': NoteProposalArtifact.typeName,
            if (artifact != null) 'artifact': artifact.toJson(),
          }),
        );
        _setState(() => _messages.add(cardMsg));
        await _chatSessionService.addMessage(_currentSessionId!, cardMsg);
      }

      _scrollToBottom(bypassThrottle: true);
    } catch (e, stack) {
      logError(
        'AIAssistantPage Agent request failed',
        error: e is AgentRequestException ? e.failureType : e.runtimeType,
        stackTrace: stack,
      );
      if (!mounted || requestGeneration != _agentRequestGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_agentErrorMessage(l10n, e))),
      );
    } finally {
      await eventSubscription?.cancel();
      if (identical(_agentEventSubscription, eventSubscription)) {
        _agentEventSubscription = null;
      }
      if (mounted && requestGeneration == _agentRequestGeneration) {
        _cancelStreamUpdate();
        _cancelToolProgressUpdate();
        if (toolProgressMsgId != null) {
          toolProgressInProgress = false;
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

  String _agentErrorMessage(AppLocalizations l10n, Object error) {
    if (error is! AgentRequestException) {
      return l10n.agentErrorGeneric;
    }

    return switch (error.failureType) {
      AgentFailureType.noProvider => l10n.agentErrorNoProvider,
      AgentFailureType.missingApiKey =>
        l10n.agentErrorMissingApiKey(error.providerName ?? ''),
      AgentFailureType.unsupportedProvider =>
        l10n.agentErrorUnsupportedProvider,
      AgentFailureType.timeout => l10n.agentErrorTimeout,
      AgentFailureType.cancelled => l10n.agentErrorCancelled,
      AgentFailureType.toolExecutionFailed ||
      AgentFailureType.unknown =>
        l10n.agentErrorGeneric,
    };
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
      'get_note_detail' => l10n.agentReadingNoteDetail,
      'get_location_weather' => l10n.agentCheckingLocationWeather,
      'propose_new_note' => l10n.agentPreparingNewNoteSuggestion,
      'propose_edit' ||
      'propose_rich_edit' =>
        l10n.agentPreparingEditSuggestion,
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
    if (toolName == 'get_note_detail') {
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
      'get_note_detail' => _summarizeGetNoteDetailResult(l10n, trimmed),
      'get_location_weather' => _summarizeLocationWeatherResult(l10n, trimmed),
      'web_search' => _summarizeWebSearchResult(l10n, trimmed),
      'web_fetch' => _summarizeWebFetchResult(l10n, trimmed),
      'propose_new_note' ||
      'propose_edit' ||
      'propose_rich_edit' =>
        l10n.agentPreparedSuggestionCard,
      _ => l10n.agentToolStepFinished,
    };
  }

  String _summarizeGetNoteDetailResult(AppLocalizations l10n, String result) {
    final payload = _tryParseJsonMap(result);
    if (payload == null) {
      return l10n.agentToolStepFinished;
    }
    final content = payload['content']?.toString() ?? '';
    final snippet = content.trim().replaceAll('\n', ' ');
    final cleanSnippet =
        snippet.length > 15 ? '${snippet.substring(0, 15)}...' : snippet;
    return l10n.agentReadNoteDetailSummary(
        cleanSnippet.isNotEmpty ? cleanSnippet : l10n.unknown);
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

  /// 把「用户已采纳建议」这个状态补进历史。
  ///
  /// 提案卡消息带 metaJson，会被 [_askAgent] 顶部的历史过滤排除掉，而采纳状态
  /// （saved_note_id）恰恰记在那份 metaJson 里——模型因此永远看不到自己的建议
  /// 有没有被接受，会重复提同一条。这里只补一个状态位，不把提案正文塞回历史：
  /// 模型自己那句叙述（「我帮你起草了…」）本来就是普通消息，一直在历史里。
  app_chat.ChatMessage? _buildProposalAdoptionNotice() {
    final savedNoteId = AiSmartResultUtils.latestAdoptedProposalNoteId(
      _messages,
      (message) => message.parsedMeta,
    );
    if (savedNoteId == null) return null;
    return app_chat.ChatMessage(
      id: 'proposal_adoption_notice',
      role: 'assistant',
      isUser: false,
      content: AiSmartResultUtils.proposalAdoptionNotice(savedNoteId),
      timestamp: DateTime.now(),
    );
  }

  /// 解析由成功的 Agent 工具调用生成的建议卡片。
  _AgentSmartResultParseResult _parseAgentSmartResult(
    AgentResponse response,
    AppLocalizations l10n,
  ) {
    final trimmed = response.content.trim();

    final artifacts = response.artifacts.whereType<NoteProposalArtifact>();
    final artifact = artifacts.isEmpty ? null : artifacts.first;
    if (artifact != null) {
      return _AgentSmartResultParseResult(
        displayText: trimmed,
        smartResult: _AgentSmartResultPayload(artifact: artifact),
      );
    }

    if (trimmed.isEmpty) {
      return const _AgentSmartResultParseResult(displayText: '');
    }

    return _AgentSmartResultParseResult(displayText: trimmed);
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
  const _AgentSmartResultPayload({this.artifact});

  final NoteProposalArtifact? artifact;
}

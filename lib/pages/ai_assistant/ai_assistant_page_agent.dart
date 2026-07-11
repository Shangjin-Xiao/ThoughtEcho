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
    // 每轮正文在主气泡中流式显示。如果该轮随后发起工具调用，
    // 再将已显示的过渡文字移入执行过程面板。
    var pendingRoundText = '';

    void ensureToolProgressMessage() {
      if (toolProgressMsgId != null) return;
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

    void appendProcessText(String value) {
      if (value.trim().isEmpty) return;
      if (toolItems.isEmpty) {
        toolThinkingText = '${toolThinkingText ?? ''}$value';
      } else {
        final last = toolItems.last;
        toolItems[toolItems.length - 1] = last.copyWith(
          narrationText: '${last.narrationText ?? ''}$value',
        );
      }
    }

    try {
      await _agentEventSubscription?.cancel();
      _agentEventSubscription = _agentService.events.listen((event) {
        if (!mounted) return;
        switch (event) {
          case AgentThinkingEvent():
            pendingRoundText = '';
            streamingText = '';
          case AgentReasoningDeltaEvent():
            ensureToolProgressMessage();
            toolThinkingText = '${toolThinkingText ?? ''}${event.delta}';
            _scheduleToolProgressUpdate(
              toolProgressMsgId!,
              toolItems,
              inProgress: true,
              thinkingText: toolThinkingText,
            );
          case AgentTextDeltaEvent():
            pendingRoundText += event.delta;
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
              _setState(() {
                _messages.removeWhere((message) => message.id == pendingId);
              });
              streamingMsgId = null;
              streamingText = '';
            }
            ensureToolProgressMessage();
            appendProcessText(pendingRoundText);
            pendingRoundText = '';

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
            pendingRoundText = '';
            if (streamingMsgId != null) {
              _flushStreamUpdate();
              _cancelStreamUpdate();
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
            pendingRoundText = '';
            if (streamingMsgId != null) {
              _cancelStreamUpdate();
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
        // tag_ids 是权威来源；tag_names 只作为旧工具调用的展示回退。
        List<String> tagNames = const <String>[];
        List<String?> tagIconNames = const <String?>[];
        final tagIds = parsed.smartResult!.tagIds;
        final noteId = parsed.smartResult!.noteId;
        DatabaseService? db;
        if ((tagIds != null && tagIds.isNotEmpty) ||
            (noteId != null && noteId.isNotEmpty)) {
          try {
            db = context.read<DatabaseService>();
          } catch (_) {
            db = null;
          }
        }
        final fallbackTagNames =
            parsed.smartResult!.tagNames ?? const <String>[];
        if (tagIds != null && tagIds.isNotEmpty && db != null) {
          try {
            final allTags = await db.getCategories();
            final tagMap = <String, NoteCategory>{
              for (final tag in allTags) tag.id: tag,
            };
            tagNames = [
              for (var i = 0; i < tagIds.length; i++)
                tagMap[tagIds[i]]?.name ??
                    (i < fallbackTagNames.length &&
                            fallbackTagNames[i].isNotEmpty
                        ? fallbackTagNames[i]
                        : tagIds[i]),
            ].where((name) => name.isNotEmpty).toList();
            tagIconNames = [
              for (final tagId in tagIds) tagMap[tagId]?.iconName,
            ];
          } catch (_) {
            tagNames = fallbackTagNames.isNotEmpty ? fallbackTagNames : tagIds;
          }
        } else {
          tagNames = fallbackTagNames.isNotEmpty
              ? fallbackTagNames
              : (tagIds ?? const <String>[]);
        }

        Quote? originalNote;
        if (noteId != null && noteId.isNotEmpty && db != null) {
          try {
            originalNote = await db.getQuoteById(noteId);
          } catch (_) {
            originalNote = null;
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
            'tag_icon_names': tagIconNames,
            'author': parsed.smartResult!.author,
            'source': parsed.smartResult!.source,
            'include_location': parsed.smartResult!.includeLocation,
            'include_weather': parsed.smartResult!.includeWeather,
            'rich_edit': parsed.smartResult!.richEdit,
            'rich_document': parsed.smartResult!.richDocument,
            if (originalNote != null) ...{
              'original_location': originalNote.location,
              'original_has_location':
                  !LocationService.isNonDisplayMarker(originalNote.location) ||
                      (originalNote.latitude != null &&
                          originalNote.longitude != null),
              'original_weather': originalNote.weather,
              'original_temperature': originalNote.temperature,
              'original_has_weather': originalNote.weather != null,
            },
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
      _cancelStreamUpdate();
      _cancelToolProgressUpdate();
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

  /// 解析 Agent 回复中的 Smart Result 代码块或工具调用结果
  _AgentSmartResultParseResult _parseAgentSmartResult(
    AgentResponse response,
    AppLocalizations l10n,
  ) {
    final trimmed = response.content.trim();

    // 首先检查结构化提议工具调用 (propose_edit 或 propose_new_note)
    final smartResultCalls = response.toolCalls
        .where((c) =>
            c.name == 'propose_edit' ||
            c.name == 'propose_new_note' ||
            c.name == 'propose_rich_edit')
        .toList();
    if (smartResultCalls.isNotEmpty) {
      final call = smartResultCalls.last;
      try {
        return _AgentSmartResultParseResult(
          displayText: trimmed, // 显示 AI 最终的回复（解释理由）
          smartResult: _AgentSmartResultPayload(
            title: call.arguments['title']?.toString() ?? l10n.aiSuggestion,
            content: call.name == 'propose_rich_edit'
                ? _formatRichEditPreview(l10n, call.arguments)
                : call.name == 'propose_new_note' &&
                        call.arguments['blocks'] is List
                    ? _formatRichBlocksText(call.arguments['blocks'])
                    : call.arguments['content']?.toString() ?? '',
            noteId: call.arguments['note_id']?.toString(),
            action: call.arguments['action']?.toString(),
            tagIds: _parseStringList(call.arguments['tag_ids']),
            tagNames: _parseStringList(call.arguments['tag_names']),
            author: call.arguments['author']?.toString(),
            source: call.arguments['source']?.toString(),
            includeLocation: _parseOptionalBool(
              call.arguments['include_location'],
            ),
            includeWeather: _parseOptionalBool(
              call.arguments['include_weather'],
            ),
            richEdit: call.name == 'propose_rich_edit'
                ? Map<String, Object?>.from(call.arguments)
                : null,
            richDocument: call.name == 'propose_new_note' &&
                    call.arguments['blocks'] is List
                ? List<Object?>.from(call.arguments['blocks'] as List)
                : null,
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
          tagIds: _parseStringList(data['tag_ids']),
          tagNames: _parseStringList(data['tag_names']),
          author: data['author']?.toString(),
          source: data['source']?.toString(),
          includeLocation: _parseOptionalBool(data['include_location']),
          includeWeather: _parseOptionalBool(data['include_weather']),
          richEdit: data['rich_edit'] is Map
              ? Map<String, Object?>.from(data['rich_edit'] as Map)
              : null,
          richDocument: data['rich_document'] is List
              ? List<Object?>.from(data['rich_document'] as List)
              : null,
        ),
      );
    } catch (e) {
      return _AgentSmartResultParseResult(displayText: trimmed);
    }
  }

  List<String>? _parseStringList(Object? value) {
    if (value == null) return null;
    final rawItems = switch (value) {
      List() => value,
      String() => value.split(RegExp(r'[,，、]')),
      _ => const <Object?>[],
    };
    final items = rawItems
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return items.isEmpty ? null : items;
  }

  bool? _parseOptionalBool(Object? value) => value is bool ? value : null;

  String _formatRichEditPreview(
    AppLocalizations l10n,
    Map<String, Object?> arguments,
  ) {
    final operations = arguments['operations'];
    if (operations is! List) return '';
    return operations.whereType<Map>().map((operation) {
      final type = operation['type']?.toString() ?? 'replace';
      final oldText = operation['old_text']?.toString() ??
          operation['anchor_text']?.toString() ??
          '';
      final blocks = operation['blocks'];
      final newText = blocks is List
          ? blocks.whereType<Map>().map((block) {
              final children = block['children'];
              return children is List
                  ? children
                      .whereType<Map>()
                      .map((child) => child['text']?.toString() ?? '')
                      .join()
                  : '';
            }).join('\n')
          : '';
      return switch (type) {
        'insertBefore' => '${l10n.agentDiffInsertBefore}: $oldText\n$newText',
        'insertAfter' => '${l10n.agentDiffInsertAfter}: $oldText\n$newText',
        'append' => '${l10n.agentDiffAppend}:\n$newText',
        'delete' => '${l10n.agentDiffDelete}: $oldText',
        _ => '${l10n.agentDiffOriginal}: $oldText\n'
            '${l10n.agentDiffReplacement}: $newText',
      };
    }).join('\n\n');
  }

  String _formatRichBlocksText(Object? rawBlocks) {
    if (rawBlocks is! List) return '';
    return rawBlocks.whereType<Map>().map((block) {
      final children = block['children'];
      return children is List
          ? children
              .whereType<Map>()
              .map((child) => child['text']?.toString() ?? '')
              .join()
          : '';
    }).join('\n');
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
    this.tagNames,
    this.author,
    this.source,
    this.includeLocation,
    this.includeWeather,
    this.richEdit,
    this.richDocument,
  });

  final String title;
  final String content;
  final String? noteId;
  final String? action;
  final List<String>? tagIds;
  final List<String>? tagNames;
  final String? author;
  final String? source;
  final bool? includeLocation;
  final bool? includeWeather;
  final Map<String, Object?>? richEdit;
  final List<Object?>? richDocument;
}

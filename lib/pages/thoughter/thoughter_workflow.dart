part of '../thoughter_page.dart';

extension _ThoughterWorkflow on _ThoughterPageState {
  Future<void> _handleSubmitted(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    _textController.clear();
    _setAutoScrollEnabled(true);

    final userMsg = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: trimmed,
      isUser: true,
      role: 'user',
      timestamp: DateTime.now(),
    );

    _setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    await _ensureSessionCreated();
    final sessionId = _currentSessionId!;
    final shouldGenerateTitle = !(await _sessionHasUserMessages(sessionId));
    await _chatSessionService.addMessage(sessionId, userMsg);
    if (shouldGenerateTitle) {
      _generateAITitle(sessionId, trimmed);
    }

    _agentStatusDismissTimer?.cancel();
    await _askAgent(trimmed);
  }

  Future<void> _runMarkdownWorkflow({
    required String title,
    required String loadingText,
    required Stream<String> stream,
  }) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: loadingText,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        fullResponse += chunk;
        _scheduleStreamUpdate(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        _flushStreamUpdate();
        _cancelStreamUpdate();
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          metaJson: jsonEncode(<String, dynamic>{
            'type': 'markdown_result',
            'title': title,
          }),
        );
        _finishLoading();
      },
      onError: (error) {
        _flushStreamUpdate();
        _cancelStreamUpdate();
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
        _finishLoading();
      },
    );
  }

  Future<void> _runInsightsWorkflow() async {
    final l10n = AppLocalizations.of(context);
    final databaseService = _tryGetDatabaseService();
    if (databaseService == null) {
      _appendCardMessage(
        type: 'notice',
        content: l10n.aiResponseError('DatabaseService unavailable'),
        meta: <String, dynamic>{
          'title': l10n.workflowUnavailable,
          'icon': Icons.error_outline.codePoint,
        },
      );
      return;
    }

    // 洞察是「本周」的洞察，那喂进去的就该是本周的笔记。
    //
    // 原来是 getUserQuotes() 不带参数——它的默认 limit 是 10，所以模型看到的
    // 既不是本周也不是全部，而是「最近 10 条」，不管这 10 条跨了多久。改成按
    // 本周的日期范围查（周界与探索页共用 ReportPeriodUtils），条数上限交给
    // AIRequestHelper 兜底：一周通常远不到 200 条，真有极端活跃的一周也不至于
    // 把上下文冲垮。
    final week = ReportPeriodUtils.dateRange('week', DateTime.now());
    final quotes = week == null
        ? const <Quote>[]
        : await databaseService.getUserQuotes(
            dateStart: week.start.toIso8601String(),
            dateEnd: week.end.toIso8601String(),
            limit: AIRequestHelper.maxQuotesForAnalysis,
          );
    if (quotes.isEmpty) {
      _appendCardMessage(
        type: 'notice',
        content: l10n.noNotesFound,
        meta: <String, dynamic>{
          'title': l10n.commandInsight,
          'icon': Icons.info_outline.codePoint,
        },
      );
      return;
    }

    // 模板是「正在生成本{period}洞察」，要传的是「周」不是「本周」——原来传
    // l10n.thisWeek，拼出来是「正在生成本本周洞察」。
    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.generatingInsightsForPeriod(l10n.periodWeek),
      stream: _aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedInsightType,
        analysisStyle: _selectedInsightStyle,
      ),
    );
  }
}

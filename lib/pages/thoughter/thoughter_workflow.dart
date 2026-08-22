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

    final quotes = await databaseService.getUserQuotes();
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

    // 这里分析的是整个笔记库（由 AIRequestHelper 卡在最近若干条），不是某个
    // 周期。原来写 generatingInsightsForPeriod(thisWeek)：既谎称范围是本周，
    // 模板本身又是「正在生成本{period}洞察」，传进「本周」还会拼出「本本周」。
    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.analyzingAllNotes,
      stream: _aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedInsightType,
        analysisStyle: _selectedInsightStyle,
      ),
    );
  }
}

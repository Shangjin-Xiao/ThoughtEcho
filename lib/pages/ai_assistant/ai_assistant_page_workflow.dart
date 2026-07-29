part of '../ai_assistant_page.dart';

extension _AIAssistantPageWorkflow on _AIAssistantPageState {
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
      },
      onError: (error) {
        _flushStreamUpdate();
        _cancelStreamUpdate();
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
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

    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.generatingInsightsForPeriod(l10n.thisWeek),
      stream: _aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedInsightType,
        analysisStyle: _selectedInsightStyle,
      ),
    );
  }
}

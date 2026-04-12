part of '../ai_assistant_page.dart';

extension _AIAssistantPageSession on _AIAssistantPageState {
  void _initStateImpl() {
    _currentMode = _entryConfig.defaultMode;
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServicesAndLoad());
  }

  void _disposeImpl() {
    _agentStatusDismissTimer?.cancel();
    _agentEventSubscription?.cancel();
    if (_agentListenerAttached) {
      _agentService.removeListener(_onAgentServiceChanged);
    }
    _streamSubscription?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _textController.removeListener(_onTextChanged);
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
  }

  Future<void> _initServicesAndLoad() async {
    _chatSessionService = context.read<ChatSessionService>();
    _agentService = context.read<AgentService>();
    _aiService = context.read<AIService>();
    _settingsService = context.read<SettingsService>();
    if (!_agentListenerAttached) {
      _agentService.addListener(_onAgentServiceChanged);
      _agentListenerAttached = true;
    }
    _settingsReady = true;
    final restoredMode = _restoreModeFromSettings();
    if (restoredMode != _currentMode && mounted) {
      _setState(() {
        _currentMode = restoredMode;
      });
    } else {
      _currentMode = restoredMode;
    }

    // Initialize _enableThinking based on whether the current model supports thinking.
    // This is done after _settingsService is guaranteed to be initialized.
    _enableThinking = _currentModelSupportsThinking;

    if (widget.session != null) {
      await _loadSession(widget.session!.id);
    } else if (_hasBoundNote &&
        !_isAgentMode &&
        _boundNoteId != null &&
        _entrySource == AIAssistantEntrySource.note) {
      final session = await _chatSessionService.getLatestSessionForNote(
        _boundNoteId!,
      );
      if (session != null) {
        await _loadSession(session.id);
      } else {
        await _createNewSession();
      }
    } else {
      await _createNewSession();
    }

    if (!mounted) return;
    if (_messages.isEmpty) {
      _addWelcomeMessage();
    }

    if (widget.initialQuestion?.trim().isNotEmpty == true) {
      unawaited(_handleSubmitted(widget.initialQuestion!.trim()));
    }

    _onAgentServiceChanged();
  }

  AIAssistantPageMode _restoreModeFromSettings() {
    final restored = switch (_entrySource) {
      AIAssistantEntrySource.explore => _settingsService.exploreAiAssistantMode,
      AIAssistantEntrySource.note => _settingsService.noteAiAssistantMode,
    };
    return _entryConfig.resolveRestoredMode(restored);
  }

  Future<void> _persistMode(AIAssistantPageMode mode) async {
    if (_entrySource == AIAssistantEntrySource.explore) {
      await _settingsService.setExploreAiAssistantMode(mode);
    } else {
      await _settingsService.setNoteAiAssistantMode(mode);
    }
  }

  Future<void> _setMode(AIAssistantPageMode mode) async {
    if (!_entryConfig.allowsMode(mode) || _currentMode == mode) {
      return;
    }
    _setState(() {
      _currentMode = mode;
    });
    await _persistMode(mode);
  }

  Future<void> _createNewSession() async {
    final session = await _chatSessionService.createSession(
      sessionType: _sessionTypeForMode(_currentMode),
      noteId: _boundNoteId,
      title: _hasBoundNote ? _getQuotePreview() : 'AI Chat',
    );
    _currentSessionId = session.id;
  }

  String _sessionTypeForMode(AIAssistantPageMode mode) {
    return switch (mode) {
      AIAssistantPageMode.chat => 'chat',
      AIAssistantPageMode.noteChat => 'note',
      AIAssistantPageMode.agent => 'agent',
    };
  }

  Future<void> _loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    final messages = await _chatSessionService.getMessages(sessionId);
    if (!mounted) return;
    _setState(() {
      _messages
        ..clear()
        ..addAll(messages);
    });
    _scrollToBottom();
  }

  String _getQuotePreview() {
    if (!_hasBoundNote) return '';
    final content =
        StringUtils.removeObjectReplacementChar(widget.quote!.content);
    return content.length <= 100 ? content : '${content.substring(0, 100)}...';
  }

  void _addWelcomeMessage() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final String welcomeContent = _hasBoundNote
        ? l10n.aiAssistantWelcome(_getQuotePreview())
        : widget.exploreGuideSummary?.trim().isNotEmpty == true
            ? l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim())
            : l10n.aiAssistantInputHint;

    final welcomeMsg = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: welcomeContent,
      isUser: false,
      role: 'system',
      timestamp: DateTime.now(),
      includedInContext: false,
    );
    _appendMessage(welcomeMsg, persist: true);

    // Generate dynamic insight if in explore mode without explicit guide
    if (!_hasBoundNote &&
        (widget.exploreGuideSummary?.trim().isEmpty ?? true) &&
        _entrySource == AIAssistantEntrySource.explore) {
      _generateAndShowDynamicInsight();
    }
  }

  /// Generate and display a dynamic insight based on current data
  Future<void> _generateAndShowDynamicInsight() async {
    final databaseService = _tryGetDatabaseService();
    if (databaseService == null) return;

    try {
      final quotes = await databaseService.getUserQuotes();
      if (quotes.isEmpty) return;

      // Calculate simple stats
      final count = quotes.length;
      final recentCount = quotes.where((q) {
        try {
          final qDate = DateTime.parse(q.date);
          return DateTime.now().difference(qDate).inDays <= 7;
        } catch (e) {
          return false;
        }
      }).length;

      // Generate insight text
      final insightText = 'You have recorded $count thoughts, '
          'with $recentCount from the past 7 days. '
          'Share your thoughts to explore deeper insights.';

      if (!mounted) return;

      final insightMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: insightText,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(insightMsg, persist: false);
    } catch (e) {
      AppLogger.d('Failed to generate dynamic insight: $e');
    }
  }

  Future<void> _startNewChat() async {
    // Cancel any ongoing stream before starting new chat
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _isLoading = false;
    _agentStatusDismissTimer?.cancel();

    _setState(() {
      _messages.clear();
      _selectedMediaFiles.clear();
    });
    await _createNewSession();
    _addWelcomeMessage();
  }

  void _showSessionHistory() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SessionHistorySheet(
        noteId: _boundNoteId ?? '',
        currentSessionId: _currentSessionId,
        chatSessionService: _chatSessionService,
        onSelect: (id) {
          Navigator.of(ctx).pop();
          _loadSession(id);
        },
        onDelete: (id) async {
          await _chatSessionService.deleteSession(id);
          if (!mounted || !ctx.mounted) return;
          if (id == _currentSessionId) {
            Navigator.of(ctx).pop();
            await _startNewChat();
          }
        },
        onNewChat: () {
          Navigator.of(ctx).pop();
          _startNewChat();
        },
      ),
    );
  }

  DatabaseService? _tryGetDatabaseService() {
    try {
      return context.read<DatabaseService>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

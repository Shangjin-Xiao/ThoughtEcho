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

    // 清理性能优化相关的 Timer
    _cancelStreamUpdate();
    _cancelToolProgressUpdate();
    _scrollThrottleTimer?.cancel();

    // 清理空会话：如果当前会话没有任何消息，就删除它
    _cleanupEmptySession();
  }

  /// 删除空的会话（没有用户消息）
  void _cleanupEmptySession() {
    if (_currentSessionId == null) return;

    // 检查是否有任何非系统消息
    final hasUserMessages = _messages.any((msg) => msg.isUser);

    if (!hasUserMessages) {
      unawaited(
        _chatSessionService.deleteSession(_currentSessionId!).catchError(
          (e) {
            logDebug('清理空会话失败: $_currentSessionId - $e');
          },
        ),
      );
    }
  }

  Future<void> _initServicesAndLoad() async {
    try {
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

      // 按 provider 配置初始化：优先使用用户开关，其次自动推断
      final currentProvider = _settingsService.multiAISettings.currentProvider;
      _enableThinking = currentProvider?.enableThinking ??
          (currentProvider?.supportsThinking ?? false);

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
        }
        // else: leave _currentSessionId null, session created on first message
      }
      // else: leave _currentSessionId null, session created on first message

      if (!mounted) return;
      if (_messages.isEmpty) {
        _addWelcomeMessage();
      }

      if (widget.initialQuestion?.trim().isNotEmpty == true) {
        unawaited(_handleSubmitted(widget.initialQuestion!.trim()));
      }

      _onAgentServiceChanged();
    } catch (e, stack) {
      AppLogger.e('Failed to initialize AI Assistant Page services',
          error: e, stackTrace: stack);
    }
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

  Future<void> _setThinkingEnabled(bool enabled) async {
    _setState(() {
      _enableThinking = enabled;
    });
    if (!_settingsReady) {
      return;
    }

    final multiSettings = _settingsService.multiAISettings;
    final currentProvider = multiSettings.currentProvider;
    if (currentProvider == null) {
      return;
    }

    final updatedProviders = multiSettings.providers
        .map(
          (provider) => provider.id == currentProvider.id
              ? provider.copyWith(enableThinking: enabled)
              : provider,
        )
        .toList(growable: false);

    try {
      await _settingsService.saveMultiAISettings(
        multiSettings.copyWith(
          providers: updatedProviders,
          currentProviderId: currentProvider.id,
        ),
      );
    } catch (e) {
      logDebug('保存 Thinking 开关失败: $e');
    }
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

  /// 延迟创建会话，并异步生成 AI 标题
  Future<void> _ensureSessionCreated(String firstUserMessage) async {
    if (_currentSessionId != null) return;
    await _createNewSession();
    // 异步生成 AI 标题，不阻塞主流程
    unawaited(_generateAITitle(firstUserMessage));
  }

  Future<void> _generateAITitle(String firstUserMessage) async {
    if (_currentSessionId == null) return;
    try {
      final title = await _aiService.generateSessionTitle(firstUserMessage);
      if (title.isNotEmpty && title != 'Chat') {
        await _chatSessionService.updateSessionTitle(
          _currentSessionId!,
          title,
        );
      }
    } catch (e) {
      logDebug('生成会话标题失败: $e');
    }
  }

  Future<void> _loadSession(String sessionId) async {
    try {
      _currentSessionId = sessionId;
      final messages = await _chatSessionService.getMessages(sessionId);
      if (!mounted) return;
      _setState(() {
        _messages
          ..clear()
          ..addAll(messages);
      });
      _scrollToBottom();
    } catch (e, stack) {
      AppLogger.e('Failed to load chat session', error: e, stackTrace: stack);
    }
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

    // 绑定笔记模式：显示笔记欢迎信息
    if (_hasBoundNote) {
      final welcomeContent = l10n.aiAssistantWelcome(_getQuotePreview());
      final welcomeMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: welcomeContent,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(welcomeMsg, persist: false);
      return;
    }

    // Explore 模式：如果有显式总结，显示总结；否则直接生成动态洞察（不显示"输入问题"提示）
    if (widget.exploreGuideSummary?.trim().isNotEmpty == true) {
      final welcomeContent =
          l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim());
      final welcomeMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: welcomeContent,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(welcomeMsg, persist: false);
    } else if (_entrySource == AIAssistantEntrySource.explore) {
      // 无显式总结时，跳过"输入问题"提示，直接生成动态洞察
      _generateAndShowDynamicInsight();
    }
  }

  /// Generate and display a dynamic insight based on current data
  /// 复用报告页小灯泡的 buildLocalReportInsight 逻辑
  Future<void> _generateAndShowDynamicInsight() async {
    final databaseService = _tryGetDatabaseService();
    if (databaseService == null) return;

    try {
      final quotes = await databaseService.getUserQuotes();
      if (quotes.isEmpty) return;

      final noteCount = quotes.length;
      final totalWords =
          quotes.fold<int>(0, (sum, q) => sum + q.content.length);
      final activeDays =
          quotes.map((q) => q.date.substring(0, 10)).toSet().length;

      // 最常用时段
      final periodCounts = <String, int>{};
      for (final q in quotes) {
        if (q.dayPeriod != null && q.dayPeriod!.isNotEmpty) {
          periodCounts[q.dayPeriod!] = (periodCounts[q.dayPeriod!] ?? 0) + 1;
        }
      }
      final topPeriod = periodCounts.entries.isNotEmpty
          ? periodCounts.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key
          : null;

      // 最常用天气
      final weatherCounts = <String, int>{};
      for (final q in quotes) {
        if (q.weather != null && q.weather!.isNotEmpty) {
          weatherCounts[q.weather!] = (weatherCounts[q.weather!] ?? 0) + 1;
        }
      }
      final topWeather = weatherCounts.entries.isNotEmpty
          ? weatherCounts.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key
          : null;

      // 最常用标签（解析为名称）
      String? topTag;
      final tagCounts = <String, int>{};
      for (final q in quotes) {
        for (final tagId in q.tagIds) {
          tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
        }
      }
      if (tagCounts.isNotEmpty) {
        final topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final cat = await databaseService.getCategoryById(topTagId);
        topTag = cat?.name;
      }

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final insightText = _aiService.buildLocalReportInsight(
        periodLabel: l10n.thisWeek,
        mostTimePeriod: topPeriod,
        mostWeather: topWeather,
        topTag: topTag,
        activeDays: activeDays,
        noteCount: noteCount,
        totalWordCount: totalWords,
      );

      if (insightText.isEmpty) return;

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
    try {
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
    } catch (e, stack) {
      AppLogger.e('Failed to start a new chat session',
          error: e, stackTrace: stack);
    }
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

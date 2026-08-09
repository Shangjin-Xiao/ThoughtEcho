part of '../thoughter_page.dart';

extension _ThoughterSession on _ThoughterPageState {
  void _initStateImpl() {
    _currentMode = _entryConfig.defaultMode;
    _inputFocusNode.addListener(_onInputFocusChanged);
    _inputFocusNode.onKeyEvent = _handleComposerKey;
    _scrollController.addListener(_onScrollPositionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 探索摘要不依赖数据库或 AI 服务，先显示，避免初始化异常吞掉首条消息。
      if (_messages.isEmpty &&
          widget.exploreGuideSummary?.trim().isNotEmpty == true) {
        _addWelcomeMessage();
      }
      _subscribeTagMap();
      _initServicesAndLoad();
    });
  }

  /// 订阅标签表，供提案卡把 tag_ids 还原成带图标的标签。
  /// 用流而不是一次性 getTags：会话中途新建/改名/换图标的标签也能跟上。
  void _subscribeTagMap() {
    try {
      _tagSubscription = context.read<DatabaseService>().watchTags().listen(
        (tags) {
          if (!mounted) return;
          _setState(() {
            _tagMap = {for (final tag in tags) tag.id: tag};
          });
        },
        onError: (Object e) => logDebug('标签流出错，提案卡标签退回纯文字: $e'),
      );
    } catch (e) {
      // 拿不到 DatabaseService 时退回 artifact 自带的名字，不影响对话本身。
      logDebug('订阅标签表失败，提案卡标签退回纯文字: $e');
    }
  }

  void _disposeImpl() {
    _agentRequestGeneration++;
    _agentStatusDismissTimer?.cancel();
    _agentEventSubscription?.cancel();
    if (_agentListenerAttached) {
      _agentService.requestStop();
      _agentService.removeListener(_onAgentServiceChanged);
    }
    _streamSubscription?.cancel();
    _tagSubscription?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _scrollController.removeListener(_onScrollPositionChanged);
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
      await _chatSessionService.init(); // 确保数据库已初始化
      if (!mounted) return;
      if (!_agentListenerAttached) {
        _agentService.addListener(_onAgentServiceChanged);
        _agentListenerAttached = true;
      }
      _settingsReady = true;
      if (!_settingsService.dontShowAgentExperimentalNotice && mounted) {
        unawaited(showExperimentalNoticeDialog(context));
      }
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
          _boundNoteId != null &&
          _entrySource == ThoughterEntrySource.note) {
        // 这里原本还要求 !_isAgentMode，而 ThoughterEntryConfig 现在只允许
        // agent 一种模式，条件恒为假——笔记入口每次都从空白开始。默认接着上次
        // 聊，想重开由标题栏的「新建对话」明确触发。
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

  ThoughterPageMode _restoreModeFromSettings() {
    final restored = switch (_entrySource) {
      ThoughterEntrySource.explore => _settingsService.exploreAiAssistantMode,
      ThoughterEntrySource.note => _settingsService.noteAiAssistantMode,
    };
    return _entryConfig.resolveRestoredMode(restored);
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
    final l10n = AppLocalizations.of(context);
    final session = await _chatSessionService.createSession(
      sessionType: _sessionTypeForMode(_currentMode),
      noteId: _boundNoteId,
      title: _hasBoundNote ? _getQuotePreview() : l10n.aiChat,
    );
    _currentSessionId = session.id;
  }

  String _sessionTypeForMode(ThoughterPageMode mode) {
    return switch (mode) {
      ThoughterPageMode.chat => 'chat',
      ThoughterPageMode.noteChat => 'note',
      ThoughterPageMode.agent => 'agent',
    };
  }

  /// 延迟创建会话。
  Future<void> _ensureSessionCreated() async {
    if (_currentSessionId != null) return;
    await _createNewSession();
    await _flushPendingPersistMessages();
  }

  /// 补写会话建立前挂起的消息，保持它们在用户首条消息之前的顺序。
  Future<void> _flushPendingPersistMessages() async {
    if (_pendingPersistMessages.isEmpty) return;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final pending = List<app_chat.ChatMessage>.from(_pendingPersistMessages);
    _pendingPersistMessages.clear();
    for (final message in pending) {
      try {
        await _chatSessionService.addMessage(sessionId, message);
      } catch (e) {
        logDebug('补写挂起消息失败: ${message.id} - $e');
      }
    }
  }

  Future<bool> _sessionHasUserMessages(String sessionId) async {
    try {
      final messages = await _chatSessionService.getMessages(sessionId);
      return messages.any((msg) => msg.isUser);
    } catch (e) {
      logDebug('读取会话消息失败，使用内存状态判断标题生成: $e');
      return _messages.any((msg) => msg.isUser);
    }
  }

  void _generateAITitle(
    String sessionId,
    String firstUserMessage,
  ) {
    _aiService.generateSessionTitle(firstUserMessage).then((title) async {
      if (title.isNotEmpty && title != 'Chat') {
        await _chatSessionService.updateSessionTitle(
          sessionId,
          title,
        );
      }
    }).catchError((Object e) {
      logDebug('生成会话标题失败: $e');
    });
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

    // 调用方给了现成的开场白（每日提示、周期洞察）：直接用它开场，
    // 并且纳入上下文——否则模型不知道第一句说了什么。
    final opening = widget.openingMessage?.trim();
    if (opening != null && opening.isNotEmpty) {
      _appendMessage(
        app_chat.ChatMessage(
          id: _uuid.v4(),
          content: opening,
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.now(),
        ),
        persist: true,
      );
      return;
    }

    // 绑定笔记模式：显示笔记欢迎信息
    if (_hasBoundNote) {
      final welcomeContent = l10n.aiAssistantWelcome;
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
      final summary = _extractExploreInsightSummary(
        widget.exploreGuideSummary!,
        l10n,
      );
      if (summary.isEmpty) {
        return;
      }
      final welcomeContent = l10n.aiAssistantExploreWelcome(summary);
      final welcomeMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: welcomeContent,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(welcomeMsg, persist: false);
    } else if (_entrySource == ThoughterEntrySource.explore &&
        widget.initialQuestion?.trim().isNotEmpty != true) {
      // 无显式总结时，跳过"输入问题"提示，直接生成动态洞察。
      // 但调用方已经替用户问出第一句（「总结本周」这类）时不显示：
      // 这段是 buildLocalReportInsight 现拼的统计文案，既不进模型上下文，
      // 又会抢在用户的问题前面冒出来，等于答非所问。
      _generateAndShowDynamicInsight();
    }
  }

  String _extractExploreInsightSummary(
    String rawSummary,
    AppLocalizations l10n,
  ) {
    final statisticPrefixes = <String>[
      l10n.noteCount,
      l10n.totalWordCount,
      l10n.activeDays,
      l10n.commonPeriod,
      l10n.commonWeather,
      l10n.commonTag,
    ];
    return rawSummary
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !statisticPrefixes.any(
                (prefix) =>
                    line.startsWith('$prefix:') || line.startsWith('$prefix：'),
              ),
        )
        .join('\n');
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
      var totalWords = 0;
      final activeDayKeys = <String>{};
      final periodCounts = <String, int>{};
      final weatherCounts = <String, int>{};
      final tagCounts = <String, int>{};
      for (final q in quotes) {
        totalWords += q.content.length;
        activeDayKeys.add(q.date.substring(0, 10));

        final period = q.dayPeriod;
        if (period != null && period.isNotEmpty) {
          periodCounts[period] = (periodCounts[period] ?? 0) + 1;
        }

        final weather = q.weather;
        if (weather != null && weather.isNotEmpty) {
          weatherCounts[weather] = (weatherCounts[weather] ?? 0) + 1;
        }

        for (final tagId in q.tagIds) {
          tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
        }
      }

      final topPeriod = periodCounts.entries.isNotEmpty
          ? periodCounts.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key
          : null;

      final topWeather = weatherCounts.entries.isNotEmpty
          ? weatherCounts.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key
          : null;

      // 最常用标签（解析为名称）
      String? topTag;
      if (tagCounts.isNotEmpty) {
        final topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final cat = await databaseService.getTagById(topTagId);
        topTag = cat?.name;
      }

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      // 这里传 key，不要先本地化：formatLocalReportInsight 自己按
      // SettingsService.localeCode 选模板语言并翻译时段/天气。抢先用界面
      // l10n 翻一遍，界面语言和语言偏好不一致时标签会和模板语言对不上。
      final insightText = _aiService.buildLocalReportInsight(
        periodLabel: l10n.thisWeek,
        mostTimePeriod: topPeriod,
        mostWeather: topWeather,
        topTag: topTag,
        activeDays: activeDayKeys.length,
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
      _agentRequestGeneration++;
      // Cancel any ongoing stream and Agent session before starting new chat
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      await _agentEventSubscription?.cancel();
      _agentEventSubscription = null;
      _agentService.requestStop();
      if (_agentListenerAttached) {
        _agentService.removeListener(_onAgentServiceChanged);
        _agentListenerAttached = false;
      }
      _cancelStreamUpdate();
      _cancelToolProgressUpdate();
      _isLoading = false;
      _agentStatusDismissTimer?.cancel();

      _setState(() {
        _messages.clear();
      });
      await _createNewSession();
      _addWelcomeMessage();
    } catch (e, stack) {
      AppLogger.e('Failed to start a new chat session',
          error: e, stackTrace: stack);
    }
  }

  void _showSessionHistory() {
    _dropInputFocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => SessionHistoryPage(
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

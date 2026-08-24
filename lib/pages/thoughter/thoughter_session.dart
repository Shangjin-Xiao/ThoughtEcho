part of '../thoughter_page.dart';

extension _ThoughterSession on _ThoughterPageState {
  void _initStateImpl() {
    _currentMode = _entryConfig.defaultMode;
    _inputFocusNode.addListener(_onInputFocusChanged);
    _inputFocusNode.onKeyEvent = _handleComposerKey;
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
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
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    // _messages 跟得上 _currentSessionId 时，它就是最新的真相，直接用。
    if (_messagesSessionId == sessionId) {
      if (_messages.any((msg) => msg.isUser)) return;
      unawaited(
        _chatSessionService.deleteSession(sessionId).catchError((e) {
          logDebug('清理空会话失败: $sessionId - $e');
        }),
      );
      return;
    }

    // 对不上号：切会话途中，_messages 还是上一个会话的。拿别人的列表去问
    // "这个会话有没有人说过话"，答案是别人的——连着点两下历史就会走到这里。
    // 但也不能就这么放过：那一段要是真空着，跳过清理它就留在历史里了
    // （服务层的清扫要等 5 分钟，而用户翻历史就在这几秒内）。去库里问一次。
    unawaited(_deleteSessionIfEmpty(sessionId));
  }

  /// 去库里确认这个会话确实没有用户消息，然后再删。
  ///
  /// 只在内存状态不可信时走这条路。会话是 [_ensureSessionCreated] 现建的时候
  /// id 和消息一起落地，不会走到这里，所以不存在"首条消息还没写完就被删"。
  ///
  /// 这是「先读、再删」的两段异步操作，中间那段窗口要防两件事，见下面两处 return。
  Future<void> _deleteSessionIfEmpty(String sessionId) async {
    final hasUserMessages =
        await _chatSessionService.sessionHasUserMessages(sessionId);
    // null = 没读出来。读不出来不等于里面是空的——不能凭一次临时的读库失败
    // 删掉用户整段对话。留着，服务层那轮清扫会兜底。
    if (hasUserMessages != false) return;
    // 读库这段时间里用户可能又切回了这个会话并且说了话：那条消息在我们这份
    // 快照之后才落库，删下去就是刚写的第一句话跟着整段一起没。
    // 回到当前会话就不删。
    if (!mounted || _currentSessionId == sessionId) return;
    try {
      await _chatSessionService.deleteSession(sessionId);
    } catch (e) {
      logDebug('清理空会话失败: $sessionId - $e');
    }
  }

  /// 进入 Thoughter 时的一次性提示，按顺序弹完为止。
  Future<void> _showEntryNotices() async {
    if (!_settingsService.dontShowAgentExperimentalNotice && mounted) {
      await showExperimentalNoticeDialog(context);
    }
    if (!_settingsService.agentMemoryNoticeShown && mounted) {
      await showAgentMemoryNoticeDialog(context);
    }
  }

  /// 自动发起首轮请求前先等一次性提示关掉。
  ///
  /// 这一轮没人按发送键，用户还没机会表态。抢在提示前跑，用户在提示里点
  /// 「先不要记」就已经晚了——记忆在这一轮已经读写完了。
  Future<void> _sendInitialQuestion(String question) async {
    await _entryNoticesDone;
    if (!mounted) return;
    await _handleSubmitted(question);
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
      // 两条一次性提示串行弹，别叠在一起：实验性说明讲的是「AI 会出错」，
      // 记忆说明讲的是「它会记住你」，同屏出现用户一条都读不进去。
      //
      // 这里不 await：弹窗期间历史会话照常加载，用户关掉就能看到内容。只有
      // 自动发起的首轮请求需要等（见下面的 initialQuestion 分支），否则
      // 「先不要记」在首轮不生效——那一轮已经把记忆读写完了。
      _entryNoticesDone = _showEntryNotices();
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
        unawaited(_sendInitialQuestion(widget.initialQuestion!.trim()));
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
    // 会话是给手里这批消息现建的，两者天然对得上。
    _messagesSessionId = session.id;
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
    final generation = ++_sessionLoadGeneration;
    try {
      // 从一个还没说过话的会话跳到历史里的另一段：同上，那一段不留。
      // 初始化时 _currentSessionId 还是 null，_cleanupEmptySession 会直接返回。
      if (_currentSessionId != sessionId) {
        _cleanupEmptySession();
        _pendingPersistMessages.clear();
      }
      _currentSessionId = sessionId;
      // 读库这段时间里 _messages 还是上一个会话的，先声明"对不上号"，
      // 免得这期间又有人来切会话、拿这份旧列表去删新会话。
      _messagesSessionId = null;
      final messages = await _chatSessionService.getMessages(sessionId);
      // 读的过程中又切走了：这次的结果已经过期，写回去会盖掉新的那次。
      if (!mounted || generation != _sessionLoadGeneration) return;
      _setState(() {
        _messages
          ..clear()
          ..addAll(messages);
      });
      _messagesSessionId = sessionId;
      _scrollToBottom();
    } catch (e, stack) {
      AppLogger.e('Failed to load chat session', error: e, stackTrace: stack);
      // 读库失败时不能就这么走开：id 已经换成新会话，_messages 还停在上一个，
      // _messagesSessionId 停在 null。那之后界面显示的是旧会话的对话，用户
      // 接着说的话却写进新会话——看到的和落库的是两回事。
      //
      // 只有这次加载还是最新一代时才收拾，否则会踩掉后来那次正在进行的加载。
      if (mounted && generation == _sessionLoadGeneration) {
        _setState(() {
          _messages.clear();
        });
        _messagesSessionId = sessionId;
      }
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
      // 这条开场洞察打的是哪一段时间的标签，统计口径就得真是那一段。
      //
      // 原来是 getUserQuotes() 不带参数——而它的默认 limit 是 10，所以拿到的
      // 既不是全量也不是本周，是「最近 10 条」，却按这 10 条去算 activeDays /
      // noteCount / totalWords 再标上「本周」。改成按日期范围查：不分页，
      // 那段时间多少条就是多少条。周期由入口决定（[_insightPeriod] /
      // [_insightDate]），周界与探索页共用 ReportPeriodUtils（周一到周日）。
      final range = ReportPeriodUtils.dateRange(_insightPeriod, _insightDate);
      if (range == null) return;
      final quotes = await databaseService.getUserQuotes(
        dateStart: range.start.toIso8601String(),
        dateEnd: range.end.toIso8601String(),
        // 一周不可能有这么多条，给足冗余，别让分页把统计削掉一截。
        limit: 500,
      );
      if (!mounted) return;
      // 这段时间一条都没有，也要有一句开场白。
      //
      // 原来是直接 return——翻开一个空周期，Thoughter 一言不发。空白本身
      // 就是这一刻要说的事，只是不能拿统计模板去凑（那会拼出一句全是「—」
      // 的洞察），所以走的是不吃统计的空周期文案。
      if (quotes.isEmpty) {
        await _showEmptyPeriodOpening(databaseService, range);
        return;
      }

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
        periodLabel:
            ReportPeriodLabels.label(l10n, _insightPeriod, _insightDate),
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

  /// 所选周期一条笔记都没有时的开场白。
  ///
  /// 用本地模板而不是流式调 AI：这是页面刚打开时的一句引子，不是用户点了
  /// 「生成洞察」——为一句话先转两秒圈，比直接说出来更打断人。用户真想要
  /// AI 写的那句，点洞察工作流即可（见 `_runInsightsWorkflow`）。
  Future<void> _showEmptyPeriodOpening(
    DatabaseService databaseService,
    ({DateTime start, DateTime end}) range,
  ) async {
    // "上一次落笔多久前"：只有最近那条确实早于这个周期时才提得上。用户翻到
    // 一个更早的空周期时，最近那条可能在它之后，说"距上次 N 天"就是错的。
    DateTime? lastNoteDate;
    var everWroteAnything = false;
    try {
      final recent = await databaseService.getUserQuotes(limit: 1);
      if (recent.isNotEmpty) {
        everWroteAnything = true;
        lastNoteDate = DateTime.tryParse(recent.first.date);
      }
    } catch (e) {
      AppLogger.d('Failed to look up last note for empty opening: $e');
    }
    if (!mounted) return;

    final daysSinceLastNote = emptyPeriodGapDays(
      lastNoteDate: lastNoteDate,
      range: range,
      period: _insightPeriod,
      date: _insightDate,
    );

    final l10n = AppLocalizations.of(context);
    final text = _aiService.buildLocalEmptyPeriodInsight(
      periodLabel: ReportPeriodLabels.label(l10n, _insightPeriod, _insightDate),
      daysSinceLastNote: daysSinceLastNote,
      everWroteAnything: everWroteAnything,
    );
    if (text.isEmpty) return;

    _appendMessage(
      app_chat.ChatMessage(
        id: _uuid.v4(),
        content: text,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      ),
      persist: false,
    );
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

      // 走之前先把上一段收拾掉：一直没说过话的会话不该留在历史里。
      _cleanupEmptySession();
      // 上一段挂起的开场白跟着那个会话一起作废，留着会补写进新会话，
      // 变成开头两句一模一样的问候。
      _pendingPersistMessages.clear();
      // 有正在读库的历史会话就让它作废，否则它晚一步返回会把刚清空的
      // 对话区又填回去。
      _sessionLoadGeneration++;

      _setState(() {
        _messages.clear();
      });
      // 这里原来直接建会话——于是"点一下新建对话"本身就往历史里写了一条空
      // 记录，用户只是想开个新话题、结果还没开口就已经被记了一笔。
      // 改成跟入口那条路一样留 null，等首条用户消息发出去时由
      // _ensureSessionCreated 顺手建；开场白先挂起，建完按原顺序补写。
      _currentSessionId = null;
      _messagesSessionId = null;
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

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

  /// 跑一条只出 Markdown 正文的工作流（洞察、来源分析这类）。
  ///
  /// [buildStream] 而不是直接收 `Stream<String>`：思考回调得在建流的时候
  /// 就交给服务层。不交的话，推理模型那几十秒里界面上一个字都不会动——
  /// 用户盯着"正在生成…"，正文憋到最后突然出现一大段。思考显示出来，
  /// 等待才有形状。
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

    // 这里不接 onThinking：洞察是一段成品文案，不是对话，模型的草稿对读者
    // 没有意义。而且这条路径本来就不开思考（见 AIService 那几处
    // `enableThinking: false`），压根不会有推理内容可显示。
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        fullResponse += chunk;
        _scheduleStreamUpdate(
          aiMsgId,
          fullResponse,
          isLoading: true,
          state: app_chat.MessageState.responding,
        );
      },
      onDone: () {
        _flushStreamUpdate();
        _cancelStreamUpdate();
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          state: app_chat.MessageState.complete,
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
            isLoading: false, state: app_chat.MessageState.error);
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

    // 洞察是「哪一段时间」的洞察，喂进去的就该是那段时间的笔记。
    //
    // 原来这里写死 `dateRange('week', DateTime.now())`——用户在探索页翻到
    // 上周再点进来，读到的仍是本周的笔记，标题还写着「本周」。现在周期和
    // 基准日期由入口传进来（[_insightPeriod] / [_insightDate]），周界与
    // 探索页共用 ReportPeriodUtils。条数上限交给 AIRequestHelper 兜底：
    // 一周通常远不到 200 条，真有极端活跃的一周也不至于把上下文冲垮。
    final range = ReportPeriodUtils.dateRange(_insightPeriod, _insightDate);
    final periodLabel = ReportPeriodLabels.label(
      l10n,
      _insightPeriod,
      _insightDate,
    );
    final quotes = range == null
        ? const <Quote>[]
        : await databaseService.getUserQuotes(
            dateStart: range.start.toIso8601String(),
            dateEnd: range.end.toIso8601String(),
            limit: AIRequestHelper.maxQuotesForAnalysis,
          );
    if (quotes.isEmpty) {
      // 这段时间一条都没写，也照样给一句话。
      //
      // 原来这里是一张「没有找到笔记，请先添加一些笔记」的通知卡——用户点的
      // 是「生成洞察」，拿到的却是一句使用说明。空周期没有内容可分析，但
      // "这一段是空的"本身就是这一刻唯一要说的事，交给不吃统计的空周期文案。
      await _runEmptyPeriodInsight(
        range: range,
        periodLabel: periodLabel,
        databaseService: databaseService,
      );
      return;
    }

    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.generatingInsightsForRange(periodLabel),
      stream: _aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedInsightType,
        analysisStyle: _selectedInsightStyle,
        rangeStart: range?.start,
        rangeEnd: range?.end,
        periodLabel: periodLabel,
      ),
    );
  }

  /// 所选周期一条笔记都没有时的洞察：只说时间，不编内容。
  Future<void> _runEmptyPeriodInsight({
    required ({DateTime start, DateTime end})? range,
    required String periodLabel,
    required DatabaseService databaseService,
  }) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

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
      AppLogger.d('Failed to look up last note for empty insight: $e');
    }
    if (!mounted) return;

    int? daysSinceLastNote;
    if (lastNoteDate != null &&
        range != null &&
        lastNoteDate.isBefore(range.start)) {
      final days = now.difference(lastNoteDate).inDays;
      if (days >= 1) daysSinceLastNote = days;
    }

    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.generatingInsightsForRange(periodLabel),
      stream: _aiService.streamEmptyPeriodInsight(
        periodLabel: periodLabel,
        now: now,
        rangeStart: range?.start,
        rangeEnd: range?.end,
        daysSinceLastNote: daysSinceLastNote,
        everWroteAnything: everWroteAnything,
      ),
    );
  }
}

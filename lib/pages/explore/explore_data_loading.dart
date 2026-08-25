part of '../explore_page.dart';

extension _ExploreDataLoading on _ExplorePageState {
  /// 加载周期数据
  ///
  /// [showLoading] 为 false 时做静默刷新：保留当前内容，不把整页换成转圈，
  /// 这样数据库连续通知时页面不会来回闪。
  Future<void> _loadPeriodData({bool showLoading = true}) async {
    final token = ++_loadToken;
    // 首次加载还没有任何内容可保留，必须显示 loading
    final shouldShowLoading = showLoading || !_hasLoadedOnce;
    if (shouldShowLoading && !_isLoadingData) {
      _updateState(() {
        _isLoadingData = true;
      });
    }

    try {
      final databaseService = context.read<DatabaseService>();

      final range = ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);

      List<Quote> quotes;
      if (range != null) {
        // 使用优化后的日期范围查询，仅返回周期报告所需字段
        quotes =
            await databaseService.getQuotesForPeriod(range.start, range.end);
      } else {
        // 获取所有笔记（排除隐藏笔记，隐藏笔记不参与AI分析统计）
        quotes = await databaseService.getAllQuotes();
      }

      // 调试：打印获取到的所有笔记数量
      AppLogger.d('getQuotes returned notes count: ${quotes.length}');
      // 打印每条笔记的日期（前10条）
      for (var i = 0; i < quotes.length && i < 10; i++) {
        AppLogger.d('  Raw note[$i]: date=${quotes[i].date}');
      }

      // 根据选择的时间范围筛选笔记 (内存中再次确认筛选，处理可能存在的跨时区或边界情况)
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      // 已有更新的加载在跑，丢弃这次的结果，避免旧数据把新数据顶掉
      if (token != _loadToken) return;

      // 更新数据版本key，触发动画
      final newDataKey =
          '${_selectedPeriod}_${_selectedDate.millisecondsSinceEpoch}';
      final dataChanged = newDataKey != _dataKey;

      _hasLoadedOnce = true;
      _updateState(() {
        _periodQuotes = filteredQuotes;
        _isLoadingData = false;
        _dataKey = newDataKey;
        // 只在数据真正变化时才播放动画
        _shouldAnimateOverview = dataChanged;
      });

      // 计算“最多”指标并触发洞察
      await _computeExtrasAndInsight(token);
    } catch (e) {
      if (token != _loadToken) return;
      _updateState(() {
        _isLoadingData = false;
      });
      AppLogger.e('Failed to load period data', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.loadDataFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _computeExtrasAndInsight(int token) async {
    if (!mounted || token != _loadToken) return;
    final l10n = AppLocalizations.of(context);

    // 计算总字数、最常见时间段、最常见天气和标签，单遍遍历完成
    var totalWords = 0;
    final Map<String, int> periodCounts = {};
    final Map<String, int> weatherCategoryCounts = {};
    final Map<String, int> tagCounts = {};
    for (final q in _periodQuotes) {
      totalWords += q.content.length;

      final p = q.dayPeriod?.trim();
      if (p != null && p.isNotEmpty) {
        periodCounts[p] = (periodCounts[p] ?? 0) + 1;
      }

      final w = q.weather?.trim();
      if (w != null && w.isNotEmpty) {
        // 先尝试通过key获取分类，如果失败则直接用原值
        String? category = WeatherService.getFilterCategoryByWeatherKey(w);
        if (category == null) {
          // 如果是中文描述，尝试反查key再获取分类
          final key = WeatherCodeMapper.getKeyByDescription(w);
          if (key != null) {
            category = WeatherService.getFilterCategoryByWeatherKey(key);
          }
        }
        final finalCategory = category ?? w; // 如果找不到分类就用原值
        weatherCategoryCounts[finalCategory] =
            (weatherCategoryCounts[finalCategory] ?? 0) + 1;
      }

      for (final tagId in q.tagIds) {
        tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
      }
    }

    // 生成数据签名（用于判断洞察能不能复用缓存）。
    //
    // 原来是「周期_本地化日期文案_笔记数_总字数」，三处都不够：
    // - 改错别字、换个等长的词，笔记数和总字数都不动，签名不变，于是永远
    //   返回旧洞察；反过来两批完全不同的笔记也可能撞签名。改成把每条笔记的
    //   id 和内容一起折进指纹，用异或合并，与查询返回的顺序无关。
    // - 日期文案是本地化字符串，切换界面语言就白白重算一遍。改用 ISO 日期。
    // - 签名不含提示词版本和模型，所以改完提示词或换了模型，老缓存照样命中，
    //   用户根本看不到变化。两样都折进来。
    var contentFingerprint = 0;
    for (final quote in _periodQuotes) {
      contentFingerprint ^= Object.hash(quote.id, quote.content);
    }

    final range = ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);
    final rangeStart = range?.start.toIso8601String().substring(0, 10);
    final rangeEnd = range?.end.toIso8601String().substring(0, 10);
    final rangeKey = range == null ? 'all' : '$rangeStart~$rangeEnd';
    final provider =
        context.read<SettingsService>().multiAISettings.currentProvider;
    final model = provider?.model ?? '-';

    final dataSignature = [
      _selectedPeriod,
      rangeKey,
      _periodQuotes.length,
      totalWords,
      contentFingerprint,
      'p${AIPromptManager.reportInsightPromptVersion}',
      model,
    ].join('_');

    final mostPeriod = periodCounts.entries.isNotEmpty
        ? periodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
        : null;

    final mostWeather = weatherCategoryCounts.entries.isNotEmpty
        ? weatherCategoryCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key
        : null;

    // 最常用标签（根据tagIds统计，然后映射为名称）
    String? topTagName;
    String? topTagId;
    dynamic topTagIcon;
    try {
      if (tagCounts.isNotEmpty) {
        topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final db = context.read<DatabaseService>();
        final cats = await db.getTags();
        final category = cats.firstWhere(
          (c) => c.id == topTagId,
          orElse: () => cats.first,
        );
        topTagName = category.name;
        topTagIcon = IconUtils.getDisplayIcon(category.iconName);
      }
    } catch (_) {
      // 如解析失败，保持null
    }

    // 笔记片段预览（最多5条，每条截断80字）
    final samples = _periodQuotes.take(5).map((q) {
      var t = q.content.trim().replaceAll('\n', ' ');
      if (t.length > 80) t = '${t.substring(0, 80)}…';
      return '- $t';
    }).join('\n');

    if (!mounted || token != _loadToken) return;

    // 处理时段显示：转换为本地化标签
    String? dayPeriodDisplay;
    IconData? dayPeriodIcon;
    if (mostPeriod != null) {
      dayPeriodDisplay = TimeUtils.getLocalizedDayPeriodLabel(
        context,
        mostPeriod,
      );
      dayPeriodIcon = TimeUtils.getDayPeriodIconByKey(mostPeriod);
    }

    // 处理天气显示：转换为中文
    String? weatherDisplay;
    IconData? weatherIcon;
    if (mostWeather != null) {
      // 如果是筛选分类key，直接使用分类标签
      if (WeatherService.filterCategoryToKeys.containsKey(mostWeather)) {
        weatherDisplay = WeatherService.getLocalizedFilterCategoryLabel(
          context,
          mostWeather,
        );
        weatherIcon = WeatherService.getFilterCategoryIcon(mostWeather);
      } else {
        // 否则按原逻辑处理
        weatherDisplay = WeatherCodeMapper.getLocalizedDescription(
          l10n,
          mostWeather,
        );
        weatherIcon = WeatherCodeMapper.getIcon(mostWeather);

        // 如果返回的是未知描述，说明mostWeather可能已经是描述
        if (weatherDisplay == l10n.weatherUnknown) {
          weatherDisplay = mostWeather;
          // 反向匹配：根据中文描述找到key以获取更准确的图标
          final key = WeatherCodeMapper.getKeyByDescription(mostWeather);
          weatherIcon =
              key != null ? WeatherCodeMapper.getIcon(key) : Icons.cloud_queue;
        }
      }
    }
    if (!mounted || token != _loadToken) return;
    _updateState(() {
      _totalWordCount = totalWords;
      _mostDayPeriod = mostPeriod;
      _mostWeather = mostWeather;
      _mostTopTag = topTagName;
      _notesPreview = samples.isEmpty ? null : samples;

      // 设置显示用的文本和图标
      _mostDayPeriodDisplay = dayPeriodDisplay;
      _mostDayPeriodIcon = dayPeriodIcon;
      _mostWeatherDisplay = weatherDisplay;
      _mostWeatherIcon = weatherIcon;
      _mostTopTagIcon = topTagIcon;
    });

    _maybeStartInsight(dataSignature);
  }

  void _maybeStartInsight(String dataSignature) async {
    if (!mounted) return;

    // 同一份数据不要重复生成：否则数据库每通知一次，洞察就清空重来，
    // 文字先消失再重新流出来，看上去就是页面在闪。
    if (dataSignature == _insightSignature &&
        (_insightLoading || _insightText.isNotEmpty)) {
      return;
    }
    _insightSignature = dataSignature;

    final l10n = AppLocalizations.of(context);
    final settings = context.read<SettingsService>();
    final useAI = settings.reportInsightsUseAI;
    // 用户翻到上周就说「上周」，翻到更早就报日期范围。原来是
    // thisPeriod(周) —— 永远的「本周」，和实际查询的日期范围对不上。
    final periodLabel = ReportPeriodLabels.label(
      l10n,
      _selectedPeriod,
      _selectedDate,
    );
    final periodRange =
        ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);
    final activeDays = _getActiveDays();
    final noteCount = _periodQuotes.length;

    _insightSub?.cancel();
    _insightFlushTimer?.cancel();
    _insightFlushTimer = null;
    _insightPending = '';

    // 1. 尝试从历史记录中查找缓存
    final insightService = context.read<InsightHistoryService>();
    final cachedInsight = insightService.getInsightBySignature(dataSignature);

    if (cachedInsight != null) {
      // 如果有缓存，直接使用缓存
      if (mounted) {
        _updateState(() {
          _insightText = cachedInsight.insight;
          _insightLoading = false;
        });
        AppLogger.d('Using cached insight for signature: $dataSignature');
      }
      return;
    }

    // 这个周期一条笔记都没有。
    //
    // 原来这里直接把 _insightText 清空返回，界面留一句灰色的「暂无洞察」——
    // 最需要被说一句话的时刻，恰恰是页面最沉默的时刻。改成照样生成一句：
    // 开了 AI 就流式写一句（提示词里钉死"没有笔记可依据，不许编造经历"），
    // 没开或失败就退回本地模板。
    if (noteCount == 0) {
      await _generateEmptyPeriodInsight(
        l10n,
        periodLabel: periodLabel,
        useAI: useAI,
      );
      return;
    }

    if (useAI) {
      _updateState(() {
        _insightText = '';
        _insightLoading = true;
      });
      final ai = context.read<AIService>();

      // 获取历史洞察上下文
      final previousInsights = insightService.getPreviousInsightsContext();

      // 准备笔记内容用于AI分析。
      //
      // 这条路径绕过了 convertQuotesToJson，所以上限要在这里自己兜住：年报
      // 周期下 _periodQuotes 可能是上千条，全量拼进一个字符串就直接把上下文
      // 顶穿。先按同一套规则挑出最近的若干条，拼完再按总字数收一次尾——日期、
      // 位置、天气、署名这些元信息也占字符，只在正文上算预算是不够的。
      final helper = AIRequestHelper();
      final notesForAnalysis = helper.selectQuotesForAnalysis(_periodQuotes);
      final fullNotesContent = notesForAnalysis.map((quote) {
        final date = DateTime.tryParse(quote.date) ?? DateTime.now();
        final dateStr = l10n.formattedDate(date.month, date.day);
        var content = AIRequestHelper.clampQuoteContent(quote.content.trim());

        // 添加位置信息（`__address_pending__` 这类内部标记不能喂给模型）
        if (!LocationService.isNonDisplayMarker(quote.location)) {
          content = l10n.noteMetaWithLocation(
            dateStr,
            quote.location!,
            content,
          );
        } else {
          content = l10n.noteMeta(dateStr, content);
        }

        // 添加天气信息（历史数据里可能残留 error/unknown，跳过）
        if (quote.weather != null &&
            quote.weather!.isNotEmpty &&
            quote.weather!.trim() != 'error' &&
            quote.weather!.trim() != 'unknown') {
          final w = quote.weather!.trim();
          // 优先把英文key映射为国际化描述
          final wDesc = WeatherCodeMapper.getLocalizedDescription(l10n, w);
          final display = wDesc == l10n.weatherUnknown ? w : wDesc;
          content += l10n.weatherInfo(display);
        }

        // 把作者/出处一并交出去。原文里没有这条线索时，模型会把摘抄来的
        // 句子当成用户的自述，洞察就开始按书里的经历编人生。
        // 语义和 Thoughter 那边一致：这是归属标注，不等于"摘录"标记
        // （填的是用户自己的名字就是原创署名），怎么解读写在系统提示里。
        final attribution = quote.source;
        if (attribution != null && attribution.trim().isNotEmpty) {
          content += l10n.noteAttribution(attribution.trim());
        }

        return content;
      }).join('\n\n');

      // 拼完再收一次尾：元信息叠上去之后总长可能又越过预算。
      final boundedNotesContent =
          fullNotesContent.length > AIRequestHelper.maxContentCharsForAnalysis
              ? fullNotesContent.substring(
                  0,
                  AIRequestHelper.maxContentCharsForAnalysis,
                )
              : fullNotesContent;

      _insightSub = ai
          .streamReportInsight(
        periodLabel: periodLabel,
        mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
        mostWeather: _mostWeatherDisplay ?? _mostWeather,
        topTag: _mostTopTag,
        activeDays: activeDays,
        noteCount: noteCount,
        totalWordCount: _totalWordCount,
        notesPreview: _notesPreview,
        fullNotesContent: boundedNotesContent, // 已按条数/字数上限收过
        previousInsights: previousInsights, // 传递历史上下文
        rangeStart: periodRange?.start,
        rangeEnd: periodRange?.end,
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          // 按帧率量级节流：逐 chunk setState 会让整页反复重排抖动
          _insightPending += chunk;
          _insightFlushTimer ??=
              Timer(_ExplorePageState._insightFlushInterval, _flushInsight);
        },
        onError: (_) {
          if (!mounted) return;
          _insightFlushTimer?.cancel();
          _insightFlushTimer = null;
          _insightPending = '';
          final local = context.read<AIService>().buildLocalReportInsight(
                periodLabel: periodLabel,
                mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
                mostWeather: _mostWeatherDisplay ?? _mostWeather,
                topTag: _mostTopTag,
                activeDays: activeDays,
                noteCount: noteCount,
                totalWordCount: _totalWordCount,
              );
          _updateState(() {
            _insightText = local;
            _insightLoading = false;
          });

          // 本地兜底生成的洞察不写进带 signature 的历史，免得下次误当成
          // 缓存好的 AI 洞察复用。
          //
          // 同时把签名清掉：签名在方法开头就记下了，兜底文本又让
          // _insightText 非空，于是 _maybeStartInsight 开头那个早退条件
          // 永远成立——网络抖一次，这个周期就钉死在本地模板上，除非用户
          // 恰好增删了笔记。清掉之后下次刷新会重新试 AI。
          _insightSignature = null;
        },
        onDone: () {
          if (!mounted) return;
          _insightFlushTimer?.cancel();
          _insightFlushTimer = null;
          final tail = _insightPending;
          _insightPending = '';
          _updateState(() {
            if (tail.isNotEmpty) _insightText += tail;
            _insightLoading = false;
          });

          // 保存洞察到历史记录
          if (_insightText.isNotEmpty) {
            _saveInsightToHistory(l10n, dataSignature: dataSignature);
          }
        },
      );
    } else {
      // ... (Local generation logic remains mostly the same, but we won't save it with signature)
      // 调试：记录本地生成洞察的参数
      AppLogger.d(
        'Start generating local insight - useAI: $useAI, periodLabel: $periodLabel, activeDays: $activeDays, noteCount: $noteCount, totalWordCount: $_totalWordCount',
      );

      final local = context.read<AIService>().buildLocalReportInsight(
            periodLabel: periodLabel,
            mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
            mostWeather: _mostWeatherDisplay ?? _mostWeather,
            topTag: _mostTopTag,
            activeDays: activeDays,
            noteCount: noteCount,
            totalWordCount: _totalWordCount,
          );

      _updateState(() {
        _insightText = local;
        _insightLoading = false;
      });

      // 本地生成的洞察通常不保存到"AI历史"中，或者保存但不用于上下文参考
      // 根据用户需求，这里我们不保存本地生成的洞察到带signature的缓存中，
      // 因为用户明确说 "只有调用ai生成的才保存"
    }
  }

  /// 这个周期一条笔记都没有时的那一句话。
  ///
  /// 没有笔记就没有统计口径，[AIService.streamReportInsight] 那一套用不上；
  /// 这里只把"哪一段时间""上次落笔多久前"交出去，剩下的靠提示词管住不编造。
  /// AI 关着、报错、或者一个字都没吐出来时，一律退回本地模板——这一格不该
  /// 因为网络抖一下就退回沉默。
  Future<void> _generateEmptyPeriodInsight(
    AppLocalizations l10n, {
    required String periodLabel,
    required bool useAI,
  }) async {
    final now = DateTime.now();
    final range = ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);

    // "上一次落笔是多久前"——只有当最近那条确实早于本周期时才提。用户翻到
    // 一个更早的空周期时，最近那条可能在它之后，那时说"距上次 N 天"是错的。
    DateTime? lastNoteDate;
    var everWroteAnything = false;
    try {
      final recent = await context.read<DatabaseService>().getUserQuotes(
            limit: 1,
          );
      if (recent.isNotEmpty) {
        everWroteAnything = true;
        lastNoteDate = DateTime.tryParse(recent.first.date);
      }
    } catch (e) {
      AppLogger.d('Failed to look up last note for empty insight: $e');
    }
    if (!mounted) return;

    final daysSinceLastNote = emptyPeriodGapDays(
      lastNoteDate: lastNoteDate,
      range: range,
      period: _selectedPeriod,
      date: _selectedDate,
    );

    String localFallback() =>
        context.read<AIService>().buildLocalEmptyPeriodInsight(
              periodLabel: periodLabel,
              daysSinceLastNote: daysSinceLastNote,
              everWroteAnything: everWroteAnything,
            );

    if (!useAI) {
      _updateState(() {
        _insightText = localFallback();
        _insightLoading = false;
      });
      return;
    }

    _updateState(() {
      _insightText = '';
      _insightLoading = true;
    });

    _insightSub = context
        .read<AIService>()
        .streamEmptyPeriodInsight(
          periodLabel: periodLabel,
          now: now,
          rangeStart: range?.start,
          rangeEnd: range?.end,
          daysSinceLastNote: daysSinceLastNote,
          everWroteAnything: everWroteAnything,
        )
        .listen(
      (chunk) {
        if (!mounted) return;
        _insightPending += chunk;
        _insightFlushTimer ??=
            Timer(_ExplorePageState._insightFlushInterval, _flushInsight);
      },
      onError: (_) {
        if (!mounted) return;
        _insightFlushTimer?.cancel();
        _insightFlushTimer = null;
        _insightPending = '';
        _updateState(() {
          _insightText = localFallback();
          _insightLoading = false;
        });
        // 同 AI 洞察的兜底：清掉签名，下次刷新重新试 AI，不要被本地模板钉死。
        _insightSignature = null;
      },
      onDone: () {
        if (!mounted) return;
        _insightFlushTimer?.cancel();
        _insightFlushTimer = null;
        final tail = _insightPending;
        _insightPending = '';
        _updateState(() {
          if (tail.isNotEmpty) _insightText += tail;
          if (_insightText.trim().isEmpty) {
            // 一个字都没吐出来（模型把整段当成思考、或被过滤空了）也要有话说。
            _insightText = localFallback();
            _insightSignature = null;
          }
          _insightLoading = false;
        });
        // 空周期的这句话不进洞察历史：它不是对内容的洞察，留在历史里
        // 只会给下一次生成塞进一串"你这周没写"的噪声。
      },
    );
  }

  /// 把节流缓冲里的流式文本刷进 UI
  void _flushInsight() {
    _insightFlushTimer = null;
    if (!mounted || _insightPending.isEmpty) return;
    final pending = _insightPending;
    _insightPending = '';
    _updateState(() {
      _insightText += pending;
    });
  }

  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    final filtered = ReportPeriodUtils.filterByCreatedPeriod(
      quotes,
      selectedPeriod: _selectedPeriod,
      selectedDate: _selectedDate,
    );

    // 调试日志
    AppLogger.d(
      'Filter conditions: period=$_selectedPeriod, selectedDate=$_selectedDate',
    );
    AppLogger.d('Total notes: ${quotes.length}');
    AppLogger.d('Filtered notes count: ${filtered.length}');
    // 打印前5条笔记的日期以便调试
    for (var i = 0; i < filtered.length && i < 5; i++) {
      AppLogger.d('  Note[$i]: ${filtered[i].date}');
    }

    return filtered;
  }

  /// 保存洞察到历史记录
  Future<void> _saveInsightToHistory(
    AppLocalizations l10n, {
    String? dataSignature,
  }) async {
    try {
      final insightService = context.read<InsightHistoryService>();

      // 存具体的日期范围，不存「本周」。这个标签只有一个消费者——
      // getPreviousInsightsContext 把它拼成「- [标签] 洞察」喂回给模型做
      // 历史参考。每一周都存成「本周」的话，模型看到的是一串一模一样的
      // 标签，既分不清先后也看不出跨度，等于白给。
      final rangeText = _getDateRangeText(l10n);
      final periodLabel = rangeText.isNotEmpty ? rangeText : _selectedPeriod;

      await insightService.addInsight(
        insight: _insightText,
        periodType: _selectedPeriod,
        periodLabel: periodLabel,
        isAiGenerated: true,
        dataSignature: dataSignature, // 传递签名
      );

      logDebug(
        'Saved insight to history: ${_insightText.substring(0, _insightText.length > 50 ? 50 : _insightText.length)}...',
        source: 'ExplorePage',
      );
    } catch (e) {
      logError(
        'Failed to save insight to history: $e',
        error: e,
        source: 'ExplorePage',
      );
    }
  }
}

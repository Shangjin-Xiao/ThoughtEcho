part of '../ai_periodic_report_page.dart';

extension _AIReportDataLoading on _AIPeriodicReportPageState {
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

    // 计算总字数
    final totalWords = _periodQuotes.fold<int>(
      0,
      (sum, q) => sum + q.content.length,
    );

    // 生成数据签名 (用于判断数据是否发生变化)
    // 签名组成: 周期类型_开始日期_结束日期_笔记数量_总字数
    final rangeText = _getDateRangeText(l10n);
    final dataSignature =
        '${_selectedPeriod}_${rangeText}_${_periodQuotes.length}_$totalWords';

    // 最常见时间段
    final Map<String, int> periodCounts = {};
    for (final q in _periodQuotes) {
      final p = q.dayPeriod?.trim();
      if (p != null && p.isNotEmpty) {
        periodCounts[p] = (periodCounts[p] ?? 0) + 1;
      }
    }
    final mostPeriod = periodCounts.entries.isNotEmpty
        ? periodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
        : null;

    // 最常见天气 - 按分类统计（小雨、大雨、雷雨归为"雨"类）
    final Map<String, int> weatherCategoryCounts = {};
    for (final q in _periodQuotes) {
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
    }
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
      final Map<String, int> tagCounts = {};
      for (final q in _periodQuotes) {
        for (final tagId in q.tagIds) {
          tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
        }
      }
      if (tagCounts.isNotEmpty) {
        topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final db = context.read<DatabaseService>();
        final cats = await db.getCategories();
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
    final periodLabel = l10n.thisPeriod(_getPeriodName(l10n));
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

    // 如果没有数据，不进行生成
    if (noteCount == 0) {
      if (mounted) {
        _updateState(() {
          _insightText = '';
          _insightLoading = false;
        });
      }
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

      // 准备完整的笔记内容用于AI分析
      final fullNotesContent = _periodQuotes.map((quote) {
        final date = DateTime.tryParse(quote.date) ?? DateTime.now();
        final dateStr = l10n.formattedDate(date.month, date.day);
        var content = quote.content.trim();

        // 添加位置信息
        if (quote.location != null && quote.location!.isNotEmpty) {
          content = l10n.noteMetaWithLocation(
            dateStr,
            quote.location!,
            content,
          );
        } else {
          content = l10n.noteMeta(dateStr, content);
        }

        // 添加天气信息
        if (quote.weather != null && quote.weather!.isNotEmpty) {
          final w = quote.weather!.trim();
          // 优先把英文key映射为国际化描述
          final wDesc = WeatherCodeMapper.getLocalizedDescription(l10n, w);
          final display = wDesc == l10n.weatherUnknown ? w : wDesc;
          content += l10n.weatherInfo(display);
        }

        return content;
      }).join('\n\n');

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
        fullNotesContent: fullNotesContent, // 传递完整内容
        previousInsights: previousInsights, // 传递历史上下文
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          // 按帧率量级节流：逐 chunk setState 会让整页反复重排抖动
          _insightPending += chunk;
          _insightFlushTimer ??= Timer(
              _AIPeriodicReportPageState._insightFlushInterval, _flushInsight);
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

          // 本地兜底生成的洞察也保存，但标记为非AI（在save方法里处理）
          // 不过由于saveInsightToHistory目前强制isAiGenerated=true，
          // 这里我们可能不想保存本地兜底的，或者保存但不带signature以避免污染？
          // 暂时策略：出错降级为本地生成后，不保存到带signature的历史，以免下次误用本地版覆盖AI版
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

      // 获取当前周期的标签
      String periodLabel = '';
      switch (_selectedPeriod) {
        case 'week':
          periodLabel = l10n.thisWeek;
          break;
        case 'month':
          periodLabel = l10n.thisMonth;
          break;
        case 'year':
          periodLabel = l10n.yearOnly(_selectedDate.year);
          break;
        default:
          periodLabel = _selectedPeriod;
      }

      await insightService.addInsight(
        insight: _insightText,
        periodType: _selectedPeriod,
        periodLabel: periodLabel,
        isAiGenerated: true,
        dataSignature: dataSignature, // 传递签名
      );

      logDebug(
        'Saved insight to history: ${_insightText.substring(0, _insightText.length > 50 ? 50 : _insightText.length)}...',
        source: 'AIPeriodicReportPage',
      );
    } catch (e) {
      logError(
        'Failed to save insight to history: $e',
        error: e,
        source: 'AIPeriodicReportPage',
      );
    }
  }
}

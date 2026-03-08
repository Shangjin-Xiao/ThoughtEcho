part of '../ai_periodic_report_page.dart';

extension AIReportDataLoading on _AIPeriodicReportPageState {
  /// 加载周期数据
  Future<void> _loadPeriodData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final databaseService = context.read<DatabaseService>();
      // 获取所有笔记（排除隐藏笔记，隐藏笔记不参与AI分析统计）
      final quotes = await databaseService.getAllQuotes();

      // 调试：打印获取到的所有笔记数量
      AppLogger.d('getAllQuotes returned notes count: ${quotes.length}');
      // 打印每条笔记的日期（前10条）
      for (var i = 0; i < quotes.length && i < 10; i++) {
        AppLogger.d('  Raw note[$i]: date=${quotes[i].date}');
      }

      // 根据选择的时间范围筛选笔记
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      // 更新数据版本key，触发动画
      final newDataKey =
          '${_selectedPeriod}_${_selectedDate.millisecondsSinceEpoch}';
      final dataChanged = newDataKey != _dataKey;

      setState(() {
        _periodQuotes = filteredQuotes;
        _isLoadingData = false;
        _dataKey = newDataKey;
        // 只在数据真正变化时才播放动画
        _shouldAnimateOverview = dataChanged;
        _shouldAnimateCards = dataChanged;
      });

      // 计算“最多”指标并触发洞察
      await _computeExtrasAndInsight();
    } catch (e) {
      setState(() {
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

  Future<void> _computeExtrasAndInsight() async {
    if (!mounted) return;
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

    if (!mounted) return;

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
            context, mostWeather);
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
    if (!mounted) return;
    setState(() {
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
    final l10n = AppLocalizations.of(context);
    final settings = context.read<SettingsService>();
    final useAI = settings.reportInsightsUseAI;
    final periodLabel = l10n.thisPeriod(_getPeriodName(l10n));
    final activeDays = _getActiveDays();
    final noteCount = _periodQuotes.length;

    _insightSub?.cancel();

    // 1. 尝试从历史记录中查找缓存
    final insightService = context.read<InsightHistoryService>();
    final cachedInsight = insightService.getInsightBySignature(dataSignature);

    if (cachedInsight != null) {
      // 如果有缓存，直接使用缓存
      if (mounted) {
        setState(() {
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
        setState(() {
          _insightText = '';
          _insightLoading = false;
        });
      }
      return;
    }

    if (useAI) {
      setState(() {
        _insightText = '';
        _insightLoading = true;
      });
      final ai = context.read<AIService>();

      // 获取历史洞察上下文
      final previousInsights = insightService.getPreviousInsightsContext();

      // 准备完整的笔记内容用于AI分析
      final fullNotesContent = _periodQuotes.map((quote) {
        final date = DateTime.parse(quote.date);
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
          // 直接更新文本，UI会立即显示新内容（真正的流式显示）
          setState(() {
            _insightText += chunk;
          });
        },
        onError: (_) {
          if (!mounted) return;
          final local = context.read<AIService>().buildLocalReportInsight(
                periodLabel: periodLabel,
                mostTimePeriod: _mostDayPeriodDisplay ?? _mostDayPeriod,
                mostWeather: _mostWeatherDisplay ?? _mostWeather,
                topTag: _mostTopTag,
                activeDays: activeDays,
                noteCount: noteCount,
                totalWordCount: _totalWordCount,
              );
          setState(() {
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
          setState(() {
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

      setState(() {
        _insightText = local;
        _insightLoading = false;
      });

      // 本地生成的洞察通常不保存到"AI历史"中，或者保存但不用于上下文参考
      // 根据用户需求，这里我们不保存本地生成的洞察到带signature的缓存中，
      // 因为用户明确说 "只有调用ai生成的才保存"
    }
  }

  /// 根据时间范围筛选笔记
  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    // 归一化选中日期为当天开始时间（去除时间分量）
    final now = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case 'week':
        // 本周（周一到周日）
        final weekday = now.weekday;
        startDate = now.subtract(Duration(days: weekday - 1));
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'month':
        // 本月
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0); // 下个月第0天 = 当月最后一天
        break;
      case 'year':
        // 本年
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      default:
        return quotes;
    }

    // 调试日志
    AppLogger.d(
      'Filter conditions: period=$_selectedPeriod, selectedDate=$_selectedDate',
    );
    AppLogger.d('Filter range: startDate=$startDate, endDate=$endDate');
    AppLogger.d('Total notes: ${quotes.length}');

    final filtered = quotes.where((quote) {
      final quoteDateTime = DateTime.parse(quote.date);
      // 归一化笔记日期为当天开始时间，只比较日期部分
      final quoteDate = DateTime(
        quoteDateTime.year,
        quoteDateTime.month,
        quoteDateTime.day,
      );
      // 使用 >= startDate 且 <= endDate 的逻辑
      final isInRange =
          !quoteDate.isBefore(startDate) && !quoteDate.isAfter(endDate);
      return isInRange;
    }).toList();

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

  /// 选择有代表性的笔记
  /// [maxCount] 根据周期类型动态调整（周=6，月=12，年=18）
  List<Quote> _selectRepresentativeQuotes(
    List<Quote> quotes, {
    int maxCount = 6,
  }) {
    // 按内容长度和多样性选择
    final sortedQuotes = List<Quote>.from(quotes);

    // 优先选择内容丰富的笔记
    sortedQuotes.sort((a, b) => b.content.length.compareTo(a.content.length));

    // 选择指定数量的笔记，确保多样性
    final selected = <Quote>[];
    final usedKeywords = <String>{};

    for (final quote in sortedQuotes) {
      if (selected.length >= maxCount) break;

      // 简单的关键词去重逻辑
      final words = quote.content.toLowerCase().split(' ');
      final hasNewKeyword = words.any(
        (word) => word.length > 3 && !usedKeywords.contains(word),
      );

      if (hasNewKeyword || selected.isEmpty) {
        selected.add(quote);
        usedKeywords.addAll(words.where((word) => word.length > 3));
      }
    }

    return selected;
  }
}

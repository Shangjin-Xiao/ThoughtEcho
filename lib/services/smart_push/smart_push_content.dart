part of '../smart_push_service.dart';

/// 内容选择 — 智能算法、候选筛选、过滤器
extension SmartPushContentSelection on SmartPushService {
  /// 智能内容选择 - SOTA 核心算法
  ///
  /// SOTA v2 策略：
  /// 1. 收集所有可用内容类型及其候选笔记
  /// 2. 使用 Thompson Sampling 选择最佳内容类型（探索-利用平衡）
  /// 3. 从选中类型中随机选择未推送的笔记
  /// 4. 返回选中内容及其类型（用于效果追踪）
  ///
  /// 笔记优先原则：智能推送的核心目标是推送用户自己的笔记，
  /// 每日一言仅作为完全无笔记时的最终兜底。
  Future<_SmartSelectResult> _smartSelectContent() async {
    final now = DateTime.now();
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 5000);

    AppLogger.i(
      '智能选择：开始内容选择 (总笔记数: ${allNotes.length})',
    );

    if (allNotes.isEmpty) {
      // 没有任何笔记时，回退到每日一言
      AppLogger.w('智能选择：数据库中无笔记，回退到每日一言');
      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote != null) {
        return _SmartSelectResult(
          note: dailyQuote,
          title: '📖 每日一言',
          isDailyQuote: true,
          contentType: 'dailyQuote',
        );
      }
      return _SmartSelectResult.empty();
    }

    // 在 Isolate 中运行纯筛选操作，释放主线程
    final filterInput = SmartPushFilterInput(
      candidates: allNotes,
      now: now,
      recentlyPushedIds: _settings.recentlyPushedNoteIds.toSet(),
    );

    SmartPushFilterResult filterResult;
    try {
      filterResult = await compute(runSmartPushFilters, filterInput);
    } catch (e) {
      // Isolate 失败时回退到主线程执行
      AppLogger.w('Isolate 筛选失败，回退到主线程: $e');
      filterResult = runSmartPushFilters(filterInput);
    }

    // 异步筛选器并行执行
    final asyncResults = await Future.wait([
      _filterSameLocation(allNotes),
      _filterSameWeather(allNotes),
    ]);
    final sameLocationNotes = asyncResults[0];
    final sameWeatherNotes = asyncResults[1];

    // 记录详细的筛选结果（诊断日志，帮助排查"为什么没推送笔记"）
    AppLogger.i(
      '智能选择筛选结果：'
      'yearAgo=${filterResult.yearAgoQuotes.length}, '
      'sameTime=${filterResult.sameTimeQuotes.length}, '
      'sameLocation=${sameLocationNotes.length}, '
      'sameWeather=${sameWeatherNotes.length}, '
      'monthAgo=${filterResult.monthAgoQuotes.length}, '
      'weekAgo=${filterResult.weekAgoQuotes.length}, '
      'random7d=${filterResult.randomQuotes.length}',
    );

    // SOTA: 收集所有可用的内容类型及其候选笔记
    final availableContent = <String, _ContentCandidate>{};

    // 1. 那年今日（最高优先级 - 有纪念意义）
    if (filterResult.selectedYearAgo != null) {
      final note = filterResult.selectedYearAgo!;
      final noteDate = DateTime.tryParse(note.date);
      final years = noteDate != null ? now.year - noteDate.year : 1;
      availableContent['yearAgoToday'] = _ContentCandidate(
        note: note,
        title: '📅 $years年前的今天',
        priority: 100, // 最高优先级
      );
    }

    // 2. 同一时刻创建的笔记（±30分钟）
    if (filterResult.selectedSameTime != null) {
      availableContent['sameTimeOfDay'] = _ContentCandidate(
        note: filterResult.selectedSameTime!,
        title: '⏰ 此刻的回忆',
        priority: 80,
      );
    }

    // 3. 相同地点的笔记
    if (sameLocationNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameLocationNotes);
      if (note != null) {
        availableContent['sameLocation'] = _ContentCandidate(
          note: note,
          title: '📍 熟悉的地方',
          priority: 70,
        );
      }
    }

    // 4. 相同天气的笔记
    if (sameWeatherNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameWeatherNotes);
      if (note != null) {
        availableContent['sameWeather'] = _ContentCandidate(
          note: note,
          title: '🌤️ 此情此景',
          priority: 60,
        );
      }
    }

    // 5. 往月今日
    if (filterResult.selectedMonthAgo != null) {
      final note = filterResult.selectedMonthAgo!;
      final noteDate = DateTime.tryParse(note.date);
      String title = '📅 往月今日';
      if (noteDate != null) {
        final monthsDiff =
            (now.year - noteDate.year) * 12 + (now.month - noteDate.month);
        if (monthsDiff > 0) {
          title = '📅 $monthsDiff个月前的今天';
        }
      }
      availableContent['monthAgoToday'] = _ContentCandidate(
        note: note,
        title: title,
        priority: 50,
      );
    }

    // 6. 上周今日
    if (filterResult.selectedWeekAgo != null) {
      availableContent['weekAgoToday'] = _ContentCandidate(
        note: filterResult.selectedWeekAgo!,
        title: '📅 一周前的今天',
        priority: 45,
      );
    }

    // 7. 随机回忆（7天前的笔记）
    if (filterResult.selectedRandom != null) {
      availableContent['randomMemory'] = _ContentCandidate(
        note: filterResult.selectedRandom!,
        title: '💭 往日回忆',
        priority: 30,
      );
    }

    // SOTA: 使用 Thompson Sampling 选择内容类型
    if (availableContent.isNotEmpty) {
      final availableTypes = availableContent.keys.toList();

      AppLogger.i(
        '智能选择：可用内容类型 $availableTypes',
      );

      // 那年今日始终优先（高纪念价值）
      if (availableContent.containsKey('yearAgoToday')) {
        final candidate = availableContent['yearAgoToday']!;
        AppLogger.i('智能选择：命中那年今日，优先推送');
        return _SmartSelectResult(
          note: candidate.note,
          title: candidate.title,
          isDailyQuote: false,
          contentType: 'yearAgoToday',
        );
      }

      // 其他类型使用 Thompson Sampling 选择
      final selectedType = await _analytics.selectContentType(availableTypes);
      final candidate = availableContent[selectedType];

      if (candidate != null) {
        AppLogger.i(
          '智能选择：Thompson Sampling 选中 $selectedType',
        );
        return _SmartSelectResult(
          note: candidate.note,
          title: candidate.title,
          isDailyQuote: false,
          contentType: selectedType,
        );
      }
    }

    // 8. 所有特定筛选器均未命中，宽泛兜底：从历史笔记中随机选取
    //    笔记优先 — 只要有历史笔记就推送笔记，不回退到每日一言
    final historyNotes = allNotes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        return !(noteDate.year == now.year &&
            noteDate.month == now.month &&
            noteDate.day == now.day);
      } catch (e) {
        return false;
      }
    }).toList();

    if (historyNotes.isNotEmpty) {
      final note = _selectUnpushedNote(historyNotes);
      if (note != null) {
        AppLogger.i(
          '智能选择：特定筛选器未命中，兜底随机选择历史笔记 '
          '(总笔记数: ${allNotes.length}, 历史笔记: ${historyNotes.length})',
        );
        return _SmartSelectResult(
          note: note,
          title: '💭 往日回忆',
          isDailyQuote: false,
          contentType: 'randomMemory',
        );
      }
    }

    // 9. 所有笔记都是今天创建的 — 完全无历史笔记，回退到每日一言
    AppLogger.w(
      '智能选择：无历史笔记可推送 '
      '(总笔记数: ${allNotes.length}, 历史笔记: ${historyNotes.length})，'
      '回退到每日一言',
    );
    final dailyQuote = await _fetchDailyQuote();
    if (dailyQuote != null) {
      return _SmartSelectResult(
        note: dailyQuote,
        title: '📖 每日一言',
        isDailyQuote: true,
        contentType: 'dailyQuote',
      );
    }

    return _SmartSelectResult.empty();
  }

  /// 从候选列表中选择未被推送过的笔记
  Quote? _selectUnpushedNote(List<Quote> candidates) {
    return selectUnpushedNote(
      candidates,
      _settings.recentlyPushedNoteIds.toSet(),
      _random,
    );
  }

  /// 生成推送标题
  String _generateTitle(Quote note) {
    final now = DateTime.now();
    final noteDate = DateTime.tryParse(note.date);

    if (noteDate != null) {
      // 那年今日
      if (noteDate.month == now.month &&
          noteDate.day == now.day &&
          noteDate.year < now.year) {
        final years = now.year - noteDate.year;
        return '📅 $years年前的今天';
      }

      // 往月今日
      if (noteDate.day == now.day &&
          noteDate.year == now.year &&
          noteDate.month < now.month) {
        final months = now.month - noteDate.month;
        return '📅 $months个月前的今天';
      }

      // 上周今日
      final weekAgo = now.subtract(const Duration(days: 7));
      if (noteDate.year == weekAgo.year &&
          noteDate.month == weekAgo.month &&
          noteDate.day == weekAgo.day) {
        return '📅 一周前的今天';
      }
    }

    // 同地点
    if (note.location != null && note.location!.isNotEmpty) {
      return '📍 熟悉的地方';
    }

    // 同天气
    if (note.weather != null && note.weather!.isNotEmpty) {
      return '🌤️ 此情此景';
    }

    return '💭 回忆时刻';
  }

  /// 截断内容
  String _truncateContent(String content) {
    if (content.length <= 100) return content;
    return '${content.substring(0, 100)}...';
  }

  /// 获取每日一言
  ///
  /// 优先使用缓存，但如果缓存内容已推送过，则请求新内容。
  Future<Quote?> _fetchDailyQuote() async {
    try {
      // 先尝试缓存
      var data = await _loadDailyQuoteData();
      if (data == null) return null;

      // 如果缓存的内容已经推送过，请求新的
      final cachedContent = data['hitokoto'] as String? ?? '';
      if (cachedContent.isNotEmpty &&
          _hasDailyQuoteContentPushed(cachedContent)) {
        AppLogger.d('缓存的每日一言已推送过，请求新内容');
        data = await _loadDailyQuoteData(preferCache: false);
        if (data == null) return null;
      }

      final fromWho = data['from_who'] as String? ?? '';
      final from = data['from'] as String? ?? '';
      return Quote(
        content: data['hitokoto'] as String,
        date: DateTime.now().toIso8601String(),
        sourceAuthor: fromWho,
        source: from.isNotEmpty ? from : null,
      );
    } catch (e) {
      AppLogger.w('获取每日一言失败', error: e);
      return null;
    }
  }

  /// 获取候选推送笔记
  Future<List<Quote>> getCandidateNotes() async {
    final typedCandidates = await getTypedCandidateNotes();
    return typedCandidates.map((candidate) => candidate.note).toList();
  }

  Future<List<TypedSmartPushCandidate>> getTypedCandidateNotes() async {
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 5000);
    if (allNotes.isEmpty) return [];

    final now = DateTime.now();
    final currentLocation = await _loadCurrentLocationForMatching();
    final currentWeather = _loadCurrentWeatherForMatching();

    return buildTypedCandidates(
      notes: allNotes,
      now: now,
      enabledPastNoteTypes: _settings.enabledPastNoteTypes,
      recentPushedIds: _settings.recentlyPushedNoteIds.toSet(),
      random: _random,
      requiredTagIds: _settings.filterTagIds,
      currentLocation: currentLocation,
      currentWeather: currentWeather,
      weatherFilters: _settings.filterWeatherTypes,
    );
  }

  /// 筛选相同地点的笔记
  Future<List<Quote>> _filterSameLocation(List<Quote> notes) async {
    try {
      final currentLocation = await _loadCurrentLocationForMatching();
      return filterSameLocationNotes(notes, DateTime.now(), currentLocation);
    } catch (e) {
      AppLogger.w('位置筛选失败: $e');
      return [];
    }
  }

  /// 筛选相同天气的笔记
  Future<List<Quote>> _filterSameWeather(List<Quote> notes) async {
    final currentWeather = _loadCurrentWeatherForMatching();
    return filterSameWeatherNotes(
      notes,
      DateTime.now(),
      currentWeather: currentWeather,
      weatherFilters: _settings.filterWeatherTypes,
    );
  }

  Future<String?> _loadCurrentLocationForMatching() async {
    final currentLocation = _locationService.getFormattedLocation();
    if (currentLocation.isNotEmpty) return currentLocation;

    await _locationService.init();
    final resolvedLocation = _locationService.getFormattedLocation();
    return resolvedLocation.isEmpty ? null : resolvedLocation;
  }

  String? _loadCurrentWeatherForMatching() {
    if (_weatherService == null) return null;
    try {
      final currentWeather = _weatherService!.currentWeather;
      if (currentWeather == null || currentWeather.isEmpty) return null;
      return currentWeather;
    } catch (e) {
      AppLogger.w('获取当前天气失败', error: e);
      return null;
    }
  }
}

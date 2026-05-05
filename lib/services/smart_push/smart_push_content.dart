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

    // 使用 warning 级别确保后台 Isolate 中也能持久化到日志数据库
    AppLogger.w('智能选择：开始查询数据库...');
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 5000);
    AppLogger.w(
      '智能选择：数据库查询完成 (总笔记数: ${allNotes.length})',
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

    // 记录详细的筛选结果（使用 warning 级别确保后台可见）
    AppLogger.w(
      '智能选择筛选结果：'
      'yearAgo=${filterResult.yearAgoQuotes.length}, '
      'sameTime=${filterResult.sameTimeQuotes.length}, '
      'sameLocation=${sameLocationNotes.length}, '
      'sameWeather=${sameWeatherNotes.length}, '
      'monthAgo=${filterResult.monthAgoQuotes.length}, '
      'weekAgo=${filterResult.weekAgoQuotes.length}',
    );

    // SOTA: 收集所有可用的内容类型及其候选笔记
    // 分为两类：高价值用户笔记类型 vs 兜底内容
    final availableContent = <String, _ContentCandidate>{};
    final fallbackContent = <String, _ContentCandidate>{};

    // 1. 那年今日（最高优先级 - 有纪念意义）
    if (filterResult.selectedYearAgo != null) {
      final note = filterResult.selectedYearAgo!;
      final noteDate = DateTime.tryParse(note.date);
      final years = noteDate != null ? now.year - noteDate.year : 1;
      availableContent['yearAgoToday'] = _ContentCandidate(
        note: note,
        title: pickYearAgoTodayTitle(_random, years),
        priority: 100, // 最高优先级
      );
    }

    // 2. 相同地点的笔记（动态 priority）
    if (sameLocationNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameLocationNotes);
      if (note != null) {
        final locationPriority = calcLocationPriority(
          sameLocationNotes.length,
          allNotes.length,
        );
        availableContent['sameLocation'] = _ContentCandidate(
          note: note,
          title: pickSameLocationTitle(_random),
          priority: locationPriority,
        );
      }
    }

    // 3. 往月今日
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
        priority: 70,
      );
    }

    // 4. 上周今日
    if (filterResult.selectedWeekAgo != null) {
      availableContent['weekAgoToday'] = _ContentCandidate(
        note: filterResult.selectedWeekAgo!,
        title: pickWeekAgoTodayTitle(_random),
        priority: 55,
      );
    }

    // 5. 相同天气的笔记
    if (sameWeatherNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameWeatherNotes);
      if (note != null) {
        availableContent['sameWeather'] = _ContentCandidate(
          note: note,
          title: '🌤️ 同样的天气',
          priority: 40,
        );
      }
    }

    // 6. 每日一言（低优先级可选推送，每天最多1条）
    // 只有今日尚未在智能推送中推送过每日一言时才加入候选
    if (!_hasDailyQuotePushedTodayInSmartPush()) {
      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote != null) {
        availableContent['dailyQuote'] = _ContentCandidate(
          note: dailyQuote,
          title: '📖 每日一言',
          priority: 30, // 低于所有用户笔记类型
          isDailyQuote: true,
        );
      }
    }

    // 7. 此时此刻（最低优先级兜底 - 仅当今日无推送且7天内无其他笔记可推时）
    if (filterResult.selectedSameTime != null) {
      final note = filterResult.selectedSameTime!;
      final noteDate = DateTime.tryParse(note.date);
      final title = noteDate != null
          ? pickSameTimeOfDayTitle(_random, noteDate, now)
          : '⏰ 此刻的回忆';
      // 放入兜底池，不直接加入 availableContent
      fallbackContent['sameTimeOfDay'] = _ContentCandidate(
        note: note,
        title: title,
        priority: 20, // 最低优先级
      );
    }

    // SOTA: 按优先级排序并选择最高价值内容
    // 核心原则：一个推送只推一条，选择价值最高的
    if (availableContent.isNotEmpty) {
      final availableTypes = availableContent.keys.toList();

      AppLogger.w(
        '智能选择：可用内容类型 $availableTypes',
      );

      // 按优先级排序所有候选内容
      final sortedCandidates = availableContent.entries.toList()
        ..sort((a, b) => b.value.priority.compareTo(a.value.priority));

      // 选择优先级最高的内容
      final bestEntry = sortedCandidates.first;
      final bestType = bestEntry.key;
      final bestCandidate = bestEntry.value;

      // 特殊处理：那年今日有纪念意义，始终优先日志提示
      if (bestType == 'yearAgoToday') {
        AppLogger.w('智能选择：命中那年今日（优先级最高），优先推送');
      } else {
        AppLogger.w(
          '智能选择：选中 $bestType（优先级 ${bestCandidate.priority}）',
        );
      }

      return _SmartSelectResult(
        note: bestCandidate.note,
        title: bestCandidate.title,
        isDailyQuote: bestCandidate.isDailyQuote,
        contentType: bestType,
      );
    }

    // 所有高价值内容均未命中，检查是否可以使用「此时此刻」兜底
    // 条件：今日尚无任何推送 + 7天内无其他用户笔记可推送
    if (fallbackContent.containsKey('sameTimeOfDay')) {
      final hasPushed = _hasPushedToday();

      // 检查 7 天内是否有可推送的用户笔记
      // 使用已有的筛选结果判断（排除 sameTimeOfDay 本身）
      final hasRecentNotes = filterResult.yearAgoQuotes.isNotEmpty ||
          filterResult.monthAgoQuotes.isNotEmpty ||
          filterResult.weekAgoQuotes.isNotEmpty ||
          sameLocationNotes.isNotEmpty ||
          sameWeatherNotes.isNotEmpty;

      if (!hasPushed && !hasRecentNotes) {
        final sameTimeCandidate = fallbackContent['sameTimeOfDay']!;
        AppLogger.w(
          '智能选择：今日无推送且无高价值笔记，使用「此时此刻」兜底',
        );
        return _SmartSelectResult(
          note: sameTimeCandidate.note,
          title: sameTimeCandidate.title,
          isDailyQuote: false,
          contentType: 'sameTimeOfDay',
        );
      } else {
        AppLogger.w(
          '智能选择：跳过「此时此刻」(今日已推送: $hasPushed, 有其他笔记可推: $hasRecentNotes)',
        );
      }
    }

    // 最终兜底：每日一言
    AppLogger.w(
      '智能选择：所有筛选器均未命中 '
      '(总笔记数: ${allNotes.length})，回退到每日一言',
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
        return pickYearAgoTodayTitle(_random, years);
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
        return pickWeekAgoTodayTitle(_random);
      }
    }

    // 同地点
    if (note.location != null && note.location!.isNotEmpty) {
      return pickSameLocationTitle(_random);
    }

    // 同天气
    if (note.weather != null && note.weather!.isNotEmpty) {
      return '🌤️ 同样的天气';
    }

    return '💭 心迹';
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

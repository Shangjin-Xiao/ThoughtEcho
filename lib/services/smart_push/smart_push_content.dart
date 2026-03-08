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
  Future<_SmartSelectResult> _smartSelectContent() async {
    final now = DateTime.now();
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 500);

    if (allNotes.isEmpty) {
      // 没有笔记时，返回每日一言
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

    // 6. 随机回忆（兜底）
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

      // 那年今日始终优先（高纪念价值）
      if (availableContent.containsKey('yearAgoToday')) {
        final candidate = availableContent['yearAgoToday']!;
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
        return _SmartSelectResult(
          note: candidate.note,
          title: candidate.title,
          isDailyQuote: false,
          contentType: selectedType,
        );
      }
    }

    // 7. 所有特定筛选器均未命中，尝试宽泛兜底
    if (availableContent.isEmpty && allNotes.isNotEmpty) {
      // 排除今天创建的笔记，从所有历史笔记中随机选取
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
        // 随机决定推送笔记回顾还是每日一言（各 50% 概率）
        if (_random.nextBool()) {
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
        } else {
          AppLogger.i('智能选择：特定筛选器未命中，兜底随机选择每日一言');
        }
      }
    }

    // 8. 记录诊断日志
    if (allNotes.isNotEmpty && availableContent.isEmpty) {
      AppLogger.w(
        '智能选择：回退到每日一言 '
        '(总笔记数: ${allNotes.length}, '
        'yearAgo: ${filterResult.yearAgoQuotes.length}, '
        'sameTime: ${filterResult.sameTimeQuotes.length}, '
        'sameLocation: ${sameLocationNotes.length}, '
        'sameWeather: ${sameWeatherNotes.length}, '
        'monthAgo: ${filterResult.monthAgoQuotes.length}, '
        'random7d: ${filterResult.randomQuotes.length})',
      );
    }

    // 9. 每日一言
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

  /// 筛选同一时刻（±30分钟）创建的笔记
  List<Quote> _filterSameTimeOfDay(List<Quote> notes, DateTime now) {
    return filterSameTimeOfDay(notes, now);
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
  Future<Quote?> _fetchDailyQuote() async {
    try {
      final data = await _loadDailyQuoteData();
      if (data == null) return null;

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
    final candidates = <Quote>[];
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 500);

    if (allNotes.isEmpty) return candidates;

    final now = DateTime.now();

    // 根据启用的类型筛选
    for (final noteType in _settings.enabledPastNoteTypes) {
      switch (noteType) {
        case PastNoteType.yearAgoToday:
          candidates.addAll(_filterYearAgoToday(allNotes, now));
          break;
        case PastNoteType.monthAgoToday:
          candidates.addAll(_filterMonthAgoToday(allNotes, now));
          break;
        case PastNoteType.weekAgoToday:
          candidates.addAll(_filterWeekAgoToday(allNotes, now));
          break;
        case PastNoteType.randomMemory:
          candidates.addAll(_filterRandomMemory(allNotes, now));
          break;
        case PastNoteType.sameLocation:
          candidates.addAll(await _filterSameLocation(allNotes));
          break;
        case PastNoteType.sameWeather:
          candidates.addAll(await _filterSameWeather(allNotes));
          break;
      }
    }

    // 应用标签筛选（如果配置了）
    if (_settings.filterTagIds.isNotEmpty) {
      candidates.removeWhere(
        (note) =>
            !note.tagIds.any((tagId) => _settings.filterTagIds.contains(tagId)),
      );
    }

    // 去重
    final uniqueIds = <String>{};
    candidates.removeWhere((note) {
      if (note.id == null) return true;
      if (uniqueIds.contains(note.id)) return true;
      uniqueIds.add(note.id!);
      return false;
    });

    // 打乱顺序增加随机性
    candidates.shuffle(_random);

    return candidates;
  }

  /// 筛选去年今日的笔记
  List<Quote> _filterYearAgoToday(List<Quote> notes, DateTime now) {
    return filterYearAgoToday(notes, now);
  }

  /// 筛选往月今日的笔记
  List<Quote> _filterMonthAgoToday(List<Quote> notes, DateTime now) {
    return filterMonthAgoToday(notes, now);
  }

  /// 筛选上周今日的笔记
  List<Quote> _filterWeekAgoToday(List<Quote> notes, DateTime now) {
    return filterWeekAgoToday(notes, now);
  }

  /// 筛选随机回忆（7天前的笔记）
  List<Quote> _filterRandomMemory(List<Quote> notes, DateTime now) {
    return filterRandomMemory(notes, now, _random);
  }

  /// 筛选相同地点的笔记
  Future<List<Quote>> _filterSameLocation(List<Quote> notes) async {
    try {
      final currentLocation = _locationService.getFormattedLocation();
      if (currentLocation.isEmpty) {
        await _locationService.init();
        if (_locationService.getFormattedLocation().isEmpty) return [];
      }

      final validLocation = _locationService.getFormattedLocation();
      final currentDistrict = _extractDistrict(validLocation);
      if (currentDistrict == null) return [];

      return notes.where((note) {
        if (note.location == null || note.location!.isEmpty) return false;
        final noteDistrict = _extractDistrict(note.location!);
        return noteDistrict != null &&
            noteDistrict.toLowerCase() == currentDistrict.toLowerCase();
      }).toList();
    } catch (e) {
      AppLogger.w('位置筛选失败: $e');
      return [];
    }
  }

  /// 从位置字符串提取区/城市名，用于同地点比较
  /// 支持 CSV 格式 ("国家,省份,城市,区县") 和显示格式 ("城市·区县")
  String? _extractDistrict(String location) {
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length >= 4 && parts[3].trim().isNotEmpty) {
        return parts[3].trim();
      }
      if (parts.length >= 3 && parts[2].trim().isNotEmpty) {
        return parts[2].trim();
      }
    }

    if (location.contains('·')) {
      final parts = location.split('·');
      if (parts.length >= 2) {
        return parts[1].trim();
      }
    }

    final districtMatch = RegExp(r'([^省市县]+(?:区|县|市))').firstMatch(location);
    if (districtMatch != null) {
      return districtMatch.group(1);
    }

    return location;
  }

  /// 筛选相同天气的笔记
  Future<List<Quote>> _filterSameWeather(List<Quote> notes) async {
    // 获取当前天气
    String? currentWeather;
    if (_weatherService != null) {
      try {
        currentWeather = _weatherService!.currentWeather;
      } catch (e) {
        AppLogger.w('获取当前天气失败', error: e);
      }
    }

    if (currentWeather == null || currentWeather.isEmpty) {
      // 如果没有当前天气，使用用户配置的天气筛选
      if (_settings.filterWeatherTypes.isEmpty) return [];

      final weatherKeywords = <String>[];
      for (final weatherType in _settings.filterWeatherTypes) {
        weatherKeywords.addAll(_getWeatherKeywords(weatherType));
      }

      return notes.where((note) {
        if (note.weather == null || note.weather!.isEmpty) return false;
        final lowerWeather = note.weather!.toLowerCase();
        return weatherKeywords.any(
          (keyword) => lowerWeather.contains(keyword.toLowerCase()),
        );
      }).toList();
    }

    // 基于当前天气匹配
    final currentWeatherLower = currentWeather.toLowerCase();
    return notes.where((note) {
      if (note.weather == null || note.weather!.isEmpty) return false;
      final noteWeatherLower = note.weather!.toLowerCase();
      // 简单的相似度匹配
      return _weatherMatches(currentWeatherLower, noteWeatherLower);
    }).toList();
  }

  /// 获取天气类型关键词
  List<String> _getWeatherKeywords(WeatherFilterType type) {
    switch (type) {
      case WeatherFilterType.clear:
        return ['晴', 'clear', 'sunny', '阳光'];
      case WeatherFilterType.cloudy:
        return ['多云', 'cloudy', '阴', '云'];
      case WeatherFilterType.rain:
        return ['雨', 'rain', '阵雨', '小雨', '大雨'];
      case WeatherFilterType.snow:
        return ['雪', 'snow', '小雪', '大雪'];
      case WeatherFilterType.fog:
        return ['雾', 'fog', '霾', 'haze'];
    }
  }

  /// 天气匹配
  bool _weatherMatches(String current, String target) {
    // 提取核心天气词
    final coreWeatherTerms = [
      '晴',
      '阴',
      '云',
      '雨',
      '雪',
      '雾',
      '霾',
      'clear',
      'cloudy',
      'rain',
      'snow',
      'fog',
    ];

    for (final term in coreWeatherTerms) {
      if (current.contains(term) && target.contains(term)) {
        return true;
      }
    }
    return false;
  }

}

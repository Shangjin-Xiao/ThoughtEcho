import 'dart:math';

import '../models/quote_model.dart';
import '../models/smart_push_settings.dart';

/// Input data for smart push filter computation in an isolate.
class SmartPushFilterInput {
  final List<Quote> candidates;
  final DateTime now;
  final Set<String> recentlyPushedIds;

  SmartPushFilterInput({
    required this.candidates,
    required this.now,
    required this.recentlyPushedIds,
  });
}

/// Result of smart push filter computation from an isolate.
class SmartPushFilterResult {
  final List<Quote> yearAgoQuotes;
  final List<Quote> sameTimeQuotes;
  final List<Quote> monthAgoQuotes;
  final List<Quote> weekAgoQuotes;
  final List<Quote> randomQuotes;
  final Quote? selectedYearAgo;
  final Quote? selectedSameTime;
  final Quote? selectedMonthAgo;
  final Quote? selectedWeekAgo;
  final Quote? selectedRandom;

  SmartPushFilterResult({
    required this.yearAgoQuotes,
    required this.sameTimeQuotes,
    required this.monthAgoQuotes,
    required this.weekAgoQuotes,
    required this.randomQuotes,
    this.selectedYearAgo,
    this.selectedSameTime,
    this.selectedMonthAgo,
    this.selectedWeekAgo,
    this.selectedRandom,
  });
}

class TypedSmartPushCandidate {
  final Quote note;
  final String contentType;
  final String title;
  final int priority;

  const TypedSmartPushCandidate({
    required this.note,
    required this.contentType,
    required this.title,
    required this.priority,
  });
}

/// Top-level function for compute() — runs all smart push filters in isolate.
SmartPushFilterResult runSmartPushFilters(SmartPushFilterInput input) {
  final random = Random();

  final yearAgoQuotes = filterYearAgoToday(input.candidates, input.now);
  final sameTimeQuotes = filterSameTimeOfDay(input.candidates, input.now);
  final monthAgoQuotes = filterMonthAgoToday(input.candidates, input.now);
  final weekAgoQuotes = filterWeekAgoToday(input.candidates, input.now);

  return SmartPushFilterResult(
    yearAgoQuotes: yearAgoQuotes,
    sameTimeQuotes: sameTimeQuotes,
    monthAgoQuotes: monthAgoQuotes,
    weekAgoQuotes: weekAgoQuotes,
    randomQuotes: const [],
    selectedYearAgo: selectUnpushedNote(
      yearAgoQuotes,
      input.recentlyPushedIds,
      random,
    ),
    selectedSameTime: selectUnpushedNote(
      sameTimeQuotes,
      input.recentlyPushedIds,
      random,
    ),
    selectedMonthAgo: selectUnpushedNote(
      monthAgoQuotes,
      input.recentlyPushedIds,
      random,
    ),
    selectedWeekAgo: selectUnpushedNote(
      weekAgoQuotes,
      input.recentlyPushedIds,
      random,
    ),
    selectedRandom: null,
  );
}

/// Filters quotes from same month/day but an earlier year.
List<Quote> filterYearAgoToday(List<Quote> notes, DateTime now) {
  return notes.where((note) {
    try {
      final noteDate = DateTime.parse(note.date);
      return noteDate.month == now.month &&
          noteDate.day == now.day &&
          noteDate.year < now.year;
    } catch (e) {
      return false;
    }
  }).toList();
}

/// Filters quotes created within ±30 minutes of current time, excluding today.
List<Quote> filterSameTimeOfDay(List<Quote> notes, DateTime now) {
  final currentMinutes = now.hour * 60 + now.minute;

  return notes.where((note) {
    try {
      final noteDate = DateTime.parse(note.date);
      final noteMinutes = noteDate.hour * 60 + noteDate.minute;
      final diff = (currentMinutes - noteMinutes).abs();
      return diff <= 30 &&
          !(noteDate.year == now.year &&
              noteDate.month == now.month &&
              noteDate.day == now.day);
    } catch (e) {
      return false;
    }
  }).toList();
}

/// Filters quotes from same day in previous months.
List<Quote> filterMonthAgoToday(List<Quote> notes, DateTime now) {
  return notes.where((note) {
    try {
      final noteDate = DateTime.parse(note.date);
      return noteDate.day == now.day &&
          (noteDate.year < now.year ||
              (noteDate.year == now.year && noteDate.month < now.month));
    } catch (e) {
      return false;
    }
  }).toList();
}

/// Filters quotes from exactly one week ago.
List<Quote> filterWeekAgoToday(List<Quote> notes, DateTime now) {
  final weekAgo = now.subtract(const Duration(days: 7));
  return notes.where((note) {
    try {
      final noteDate = DateTime.parse(note.date);
      return noteDate.year == weekAgo.year &&
          noteDate.month == weekAgo.month &&
          noteDate.day == weekAgo.day;
    } catch (e) {
      return false;
    }
  }).toList();
}

/// Shuffles and returns up to 5 random quotes older than 7 days.
List<Quote> filterRandomMemory(
  List<Quote> notes,
  DateTime now,
  Random random,
) {
  final sevenDaysAgo = now.subtract(const Duration(days: 7));
  final filtered = notes.where((note) {
    try {
      final noteDate = DateTime.parse(note.date);
      return noteDate.isBefore(sevenDaysAgo);
    } catch (e) {
      return false;
    }
  }).toList();

  filtered.shuffle(random);
  return filtered.take(5).toList();
}

/// Selects a note not recently pushed, or random if all were pushed.
Quote? selectUnpushedNote(
  List<Quote> candidates,
  Set<String> recentlyPushedIds,
  Random random,
) {
  final unpushed = candidates
      .where(
        (note) => note.id == null || !recentlyPushedIds.contains(note.id),
      )
      .toList();

  if (unpushed.isNotEmpty) {
    unpushed.shuffle(random);
    return unpushed.first;
  }

  if (candidates.isNotEmpty) {
    final shuffled = List<Quote>.from(candidates);
    shuffled.shuffle(random);
    return shuffled.first;
  }

  return null;
}

List<TypedSmartPushCandidate> buildTypedCandidates({
  required List<Quote> notes,
  required DateTime now,
  required Set<PastNoteType> enabledPastNoteTypes,
  required Set<String> recentPushedIds,
  required Random random,
  List<String> requiredTagIds = const [],
  String? currentLocation,
  String? currentWeather,
  Set<WeatherFilterType> weatherFilters = const {},
}) {
  final candidatesById = <String, TypedSmartPushCandidate>{};

  void addCandidate(
    String contentType,
    List<Quote> source,
    String Function(Quote note) titleBuilder,
    int priority,
  ) {
    final eligibleSource = requiredTagIds.isEmpty
        ? source
        : source
            .where((note) => note.tagIds.any(requiredTagIds.contains))
            .toList();

    final selected =
        selectUnpushedNote(eligibleSource, recentPushedIds, random);
    if (selected == null || selected.id == null) return;

    final existing = candidatesById[selected.id!];
    if (existing != null && existing.priority >= priority) {
      return;
    }

    candidatesById[selected.id!] = TypedSmartPushCandidate(
      note: selected,
      contentType: contentType,
      title: titleBuilder(selected),
      priority: priority,
    );
  }

  if (enabledPastNoteTypes.contains(PastNoteType.yearAgoToday)) {
    addCandidate(
      'yearAgoToday',
      filterYearAgoToday(notes, now),
      (note) {
        final noteDate = DateTime.tryParse(note.date);
        final years = noteDate != null ? now.year - noteDate.year : 1;
        return '📅 $years年前的今天';
      },
      100,
    );
  }

  if (enabledPastNoteTypes.contains(PastNoteType.monthAgoToday)) {
    addCandidate(
      'monthAgoToday',
      filterMonthAgoToday(notes, now),
      (note) {
        final noteDate = DateTime.tryParse(note.date);
        final monthsDiff = noteDate == null
            ? 1
            : (now.year - noteDate.year) * 12 + (now.month - noteDate.month);
        return monthsDiff > 0 ? '📅 $monthsDiff个月前的今天' : '📅 往月今日';
      },
      70, // 上调：月度回忆有仪式感
    );
  }

  if (enabledPastNoteTypes.contains(PastNoteType.weekAgoToday)) {
    addCandidate(
      'weekAgoToday',
      filterWeekAgoToday(notes, now),
      (_) => pickWeekAgoTodayTitle(random),
      55, // 上调
    );
  }

  if (enabledPastNoteTypes.contains(PastNoteType.sameLocation)) {
    final locationNotes = filterSameLocationNotes(notes, now, currentLocation);
    // 动态评分：该地点笔记占比越低（故地重游），priority 越高
    final locationPriority =
        calcLocationPriority(locationNotes.length, notes.length);
    addCandidate(
      'sameLocation',
      locationNotes,
      (_) => pickSameLocationTitle(random),
      locationPriority,
    );
  }

  if (enabledPastNoteTypes.contains(PastNoteType.sameWeather)) {
    addCandidate(
      'sameWeather',
      filterSameWeatherNotes(
        notes,
        now,
        currentWeather: currentWeather,
        weatherFilters: weatherFilters,
      ),
      (_) => '🌤️ 同样的天气',
      40, // 下调：触发率高但情境相关性弱
    );
  }

  final typedCandidates = candidatesById.values.toList()
    ..sort((a, b) => b.priority.compareTo(a.priority));
  return typedCandidates;
}

List<Quote> filterSameLocationNotes(
  List<Quote> notes,
  DateTime now,
  String? currentLocation,
) {
  if (currentLocation == null || currentLocation.trim().isEmpty) {
    return [];
  }

  final currentDistrict = extractDistrict(currentLocation);
  if (currentDistrict == null || currentDistrict.isEmpty) {
    return [];
  }

  return notes.where((note) {
    if (!_isHistoricalNote(note, now)) return false;
    if (note.location == null || note.location!.isEmpty) return false;
    final noteDistrict = extractDistrict(note.location!);
    return noteDistrict != null &&
        noteDistrict.toLowerCase() == currentDistrict.toLowerCase();
  }).toList();
}

List<Quote> filterSameWeatherNotes(
  List<Quote> notes,
  DateTime now, {
  String? currentWeather,
  Set<WeatherFilterType> weatherFilters = const {},
}) {
  final filteredByWeatherType = weatherFilters.isNotEmpty
      ? notes.where((note) {
          if (!_isHistoricalNote(note, now)) return false;
          if (note.weather == null || note.weather!.isEmpty) return false;
          final lowerWeather = note.weather!.toLowerCase();
          return weatherFilters.any((weatherType) {
            return getWeatherKeywords(weatherType).any(
              (keyword) => lowerWeather.contains(keyword.toLowerCase()),
            );
          });
        }).toList()
      : null;

  if (filteredByWeatherType != null) {
    return filteredByWeatherType;
  }

  if (currentWeather == null || currentWeather.isEmpty) {
    return [];
  }

  final currentWeatherLower = currentWeather.toLowerCase();
  return notes.where((note) {
    if (!_isHistoricalNote(note, now)) return false;
    if (note.weather == null || note.weather!.isEmpty) return false;
    return weatherMatches(currentWeatherLower, note.weather!.toLowerCase());
  }).toList();
}

String? extractDistrict(String location) {
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

List<String> getWeatherKeywords(WeatherFilterType type) {
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

bool weatherMatches(String current, String target) {
  const coreWeatherTerms = [
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

bool _isHistoricalNote(Quote note, DateTime now) {
  try {
    final noteDate = DateTime.parse(note.date);
    return !(noteDate.year == now.year &&
        noteDate.month == now.month &&
        noteDate.day == now.day);
  } catch (_) {
    return false;
  }
}

/// yearAgoToday 标题候选池（随机轮换）
String pickYearAgoTodayTitle(Random random, int years) {
  final pool = [
    '那年今日 · $years年前',
    '时光信笺，$years年前的你',
  ];
  return pool[random.nextInt(pool.length)];
}

/// weekAgoToday 标题候选池（随机轮换）
String pickWeekAgoTodayTitle(Random random) {
  final pool = [
    '七日前，你说…',
    '📅 一周前的今天',
  ];
  return pool[random.nextInt(pool.length)];
}

/// sameLocation 标题候选池（随机轮换）
String pickSameLocationTitle(Random random) {
  final pool = [
    '故地重游，旧事如新',
    '📍 你在这里写过',
    '这里，你曾留下文字',
  ];
  return pool[random.nextInt(pool.length)];
}

/// 根据相同地点笔记占比，动态计算 priority（25 ~ 75）。
///
/// 当该地点笔记占比低于低占比阈值（< 0.10）时，判断为故地重游，priority 趋向 75；
/// 当占比高于高占比阈值（> 0.40）时，判断为常驻地点，priority 趋向 25；
/// 中间区间线性插值。阈值基于百分比，不写死绝对数字。
int calcLocationPriority(int locationCount, int totalCount) {
  if (totalCount == 0 || locationCount == 0) return 50;
  final ratio = locationCount / totalCount;
  const lowThreshold = 0.10; // 低占比阈值：稀少地点（故地重游）
  const highThreshold = 0.40; // 高占比阈值：常驻地点
  if (ratio <= lowThreshold) return 75;
  if (ratio >= highThreshold) return 25;
  // 线性插值：ratio 从 0.10 → 0.40 对应 priority 75 → 25
  final t = (ratio - lowThreshold) / (highThreshold - lowThreshold);
  return (75 - t * 50).round().clamp(25, 75);
}

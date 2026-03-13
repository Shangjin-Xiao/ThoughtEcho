import 'dart:math';

import '../models/quote_model.dart';

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

/// Top-level function for compute() — runs all smart push filters in isolate.
SmartPushFilterResult runSmartPushFilters(SmartPushFilterInput input) {
  final random = Random();

  final yearAgoQuotes = filterYearAgoToday(input.candidates, input.now);
  final sameTimeQuotes = filterSameTimeOfDay(input.candidates, input.now);
  final monthAgoQuotes = filterMonthAgoToday(input.candidates, input.now);
  final weekAgoQuotes = filterWeekAgoToday(input.candidates, input.now);
  final randomQuotes = filterRandomMemory(input.candidates, input.now, random);

  return SmartPushFilterResult(
    yearAgoQuotes: yearAgoQuotes,
    sameTimeQuotes: sameTimeQuotes,
    monthAgoQuotes: monthAgoQuotes,
    weekAgoQuotes: weekAgoQuotes,
    randomQuotes: randomQuotes,
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
    selectedRandom: selectUnpushedNote(
      randomQuotes,
      input.recentlyPushedIds,
      random,
    ),
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
        (note) =>
            note.id == null || !recentlyPushedIds.contains(note.id),
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

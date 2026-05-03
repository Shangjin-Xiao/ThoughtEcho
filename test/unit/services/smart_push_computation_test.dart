library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/smart_push_computation.dart';

Quote _quote({
  required String id,
  required DateTime date,
  String? location,
  String? weather,
  List<String> tagIds = const [],
}) {
  return Quote(
    id: id,
    content: 'note-$id',
    date: date.toIso8601String(),
    location: location,
    weather: weather,
    tagIds: tagIds,
  );
}

void main() {
  group('smart push typed candidate helpers', () {
    final now = DateTime(2026, 3, 13, 9, 0);

    test(
      'buildTypedCandidates keeps strongest match reason and filters tags',
      () {
        final yearAgo = _quote(
          id: 'year',
          date: DateTime(2025, 3, 13, 9, 0),
          location: '中国,上海市,上海市,浦东新区',
          tagIds: const ['keep'],
        );
        final random = _quote(
          id: 'random',
          date: DateTime(2026, 2, 20, 9, 0),
          tagIds: const ['drop'],
        );

        final typed = buildTypedCandidates(
          notes: [yearAgo, random],
          now: now,
          enabledPastNoteTypes: const {
            PastNoteType.yearAgoToday,
            PastNoteType.randomMemory,
          },
          recentPushedIds: const {},
          random: Random(1),
          requiredTagIds: const ['keep'],
        );

        expect(typed, hasLength(1));
        expect(typed.first.note.id, 'year');
        expect(typed.first.contentType, 'yearAgoToday');
        expect(typed.first.title, '📅 1年前的今天');
      },
    );

    test('tag filtering keeps a type when another matching note exists', () {
      final matching = _quote(
        id: 'match',
        date: DateTime(2025, 3, 13, 9, 0),
        tagIds: const ['keep'],
      );
      final nonMatching = _quote(
        id: 'drop',
        date: DateTime(2025, 3, 13, 9, 1),
        tagIds: const ['drop'],
      );

      final typed = buildTypedCandidates(
        notes: [matching, nonMatching],
        now: now,
        enabledPastNoteTypes: const {PastNoteType.yearAgoToday},
        recentPushedIds: const {},
        random: Random(0),
        requiredTagIds: const ['keep'],
      );

      expect(typed, hasLength(1));
      expect(typed.single.note.id, 'match');
    });

    test(
      'same weather respects explicit weather filters even with current weather',
      () {
        final rainy = _quote(
          id: 'rain',
          date: DateTime(2026, 3, 1, 9, 0),
          weather: '大雨',
        );
        final sunny = _quote(
          id: 'sun',
          date: DateTime(2026, 3, 2, 9, 0),
          weather: '晴',
        );

        final typed = buildTypedCandidates(
          notes: [rainy, sunny],
          now: now,
          enabledPastNoteTypes: const {PastNoteType.sameWeather},
          recentPushedIds: const {},
          random: Random(2),
          currentWeather: '晴',
          weatherFilters: const {WeatherFilterType.rain},
        );

        expect(typed, hasLength(1));
        expect(typed.first.note.id, 'rain');
        expect(typed.first.contentType, 'sameWeather');
      },
    );

    test('same location and same weather exclude notes from today', () {
      final sameDayLocation = _quote(
        id: 'today-location',
        date: DateTime(2026, 3, 13, 8, 0),
        location: '中国,上海市,上海市,浦东新区',
      );
      final olderLocation = _quote(
        id: 'old-location',
        date: DateTime(2026, 3, 10, 8, 0),
        location: '中国,上海市,上海市,浦东新区',
      );
      final sameDayWeather = _quote(
        id: 'today-weather',
        date: DateTime(2026, 3, 13, 7, 0),
        weather: '晴',
      );
      final olderWeather = _quote(
        id: 'old-weather',
        date: DateTime(2026, 3, 10, 7, 0),
        weather: '晴',
      );

      final locationCandidates = buildTypedCandidates(
        notes: [sameDayLocation, olderLocation],
        now: now,
        enabledPastNoteTypes: const {PastNoteType.sameLocation},
        recentPushedIds: const {},
        random: Random(3),
        currentLocation: '中国,上海市,上海市,浦东新区',
      );
      final weatherCandidates = buildTypedCandidates(
        notes: [sameDayWeather, olderWeather],
        now: now,
        enabledPastNoteTypes: const {PastNoteType.sameWeather},
        recentPushedIds: const {},
        random: Random(4),
        currentWeather: '晴',
      );

      expect(locationCandidates.single.note.id, 'old-location');
      expect(weatherCandidates.single.note.id, 'old-weather');
    });
  });
}

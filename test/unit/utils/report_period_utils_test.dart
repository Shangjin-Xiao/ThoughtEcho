import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/report_period_utils.dart';

void main() {
  group('ReportPeriodUtils', () {
    test(
      'includes old notes favorited during the selected week',
      () {
        final selectedDate = DateTime(2026, 5, 10);
        final oldFavoritedThisWeek = Quote(
          id: 'old-favorited-this-week',
          content: 'old note favorited this week',
          date: DateTime(2026, 4, 1).toIso8601String(),
          favoriteCount: 2,
          lastModified: DateTime(2026, 5, 6).toIso8601String(),
        );
        final oldFavoritedLastWeek = Quote(
          id: 'old-favorited-last-week',
          content: 'old note favorited last week',
          date: DateTime(2026, 4, 1).toIso8601String(),
          favoriteCount: 3,
          lastModified: DateTime(2026, 4, 30).toIso8601String(),
        );
        final newNotFavorited = Quote(
          id: 'new-not-favorited',
          content: 'new note without favorites',
          date: DateTime(2026, 5, 7).toIso8601String(),
        );

        final result = ReportPeriodUtils.filterFavoritedByActivityPeriod(
          [oldFavoritedThisWeek, oldFavoritedLastWeek, newNotFavorited],
          selectedPeriod: 'week',
          selectedDate: selectedDate,
        );

        expect(result, [oldFavoritedThisWeek]);
      },
    );
  });
}

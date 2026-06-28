import '../models/quote_model.dart';

class ReportPeriodUtils {
  const ReportPeriodUtils._();

  static List<Quote> filterByCreatedPeriod(
    List<Quote> quotes, {
    required String selectedPeriod,
    required DateTime selectedDate,
  }) {
    return quotes
        .where(
          (quote) => _isInPeriod(
            quote.date,
            selectedPeriod: selectedPeriod,
            selectedDate: selectedDate,
          ),
        )
        .toList();
  }

  static List<Quote> filterFavoritedByActivityPeriod(
    List<Quote> quotes, {
    required String selectedPeriod,
    required DateTime selectedDate,
  }) {
    final favorited = quotes.where((quote) {
      if (quote.favoriteCount <= 0 || quote.isDeleted) return false;
      return _isInPeriod(
        quote.lastModified ?? quote.date,
        selectedPeriod: selectedPeriod,
        selectedDate: selectedDate,
      );
    }).toList();

    favorited.sort((a, b) {
      final favoriteCompare = b.favoriteCount.compareTo(a.favoriteCount);
      if (favoriteCompare != 0) return favoriteCompare;
      return (b.lastModified ?? b.date).compareTo(a.lastModified ?? a.date);
    });
    return favorited;
  }

  static bool _isInPeriod(
    String isoDate, {
    required String selectedPeriod,
    required DateTime selectedDate,
  }) {
    final range = dateRange(selectedPeriod, selectedDate);
    if (range == null) return true;

    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return false;

    final date = DateTime(parsed.year, parsed.month, parsed.day);
    return !date.isBefore(range.start) && !date.isAfter(range.end);
  }

  static ({DateTime start, DateTime end})? dateRange(
    String selectedPeriod,
    DateTime selectedDate,
  ) {
    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    switch (selectedPeriod) {
      case 'week':
        final start = date.subtract(Duration(days: date.weekday - 1));
        return (start: start, end: start.add(const Duration(days: 6)));
      case 'month':
        return (
          start: DateTime(date.year, date.month),
          end: DateTime(date.year, date.month + 1, 0),
        );
      case 'year':
        return (
          start: DateTime(date.year),
          end: DateTime(date.year, 12, 31),
        );
      default:
        return null;
    }
  }
}

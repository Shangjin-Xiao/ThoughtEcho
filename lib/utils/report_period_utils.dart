import '../models/quote_model.dart';

/// 选中的周期落在「现在」的哪一侧。
///
/// 探索页可以选具体日期，于是"周"未必是本周。之前 Thoughter 无视这个选择，
/// 一律按 `dateRange('week', DateTime.now())` 取本周——用户在探索页翻到上周
/// 再点「总结」，读到的却是本周的笔记，标题还写着「本周」。
enum ReportPeriodOffset {
  /// 就是现在所在的这个周期。
  current,

  /// 紧挨着的上一个周期（上周 / 上月 / 去年）。
  previous,

  /// 更早（或未来）的某个周期，没有现成的说法，只能报日期范围。
  other,
}

class ReportPeriodUtils {
  const ReportPeriodUtils._();

  /// [selectedDate] 所在的周期相对于 [now] 所在周期的位置。
  ///
  /// 无法识别的 [selectedPeriod]（`dateRange` 返回 null 的那些）按
  /// [ReportPeriodOffset.other] 处理：说不出"本/上"就别硬说。
  static ReportPeriodOffset offsetFromNow(
    String selectedPeriod,
    DateTime selectedDate, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final selected = dateRange(selectedPeriod, selectedDate);
    final currentRange = dateRange(selectedPeriod, today);
    if (selected == null || currentRange == null) {
      return ReportPeriodOffset.other;
    }
    if (selected.start == currentRange.start) {
      return ReportPeriodOffset.current;
    }

    // 上一个周期的边界同样交给 dateRange 算，不自己减天数：夏令时下
    // `subtract(7 天)` 会落到前一天 23:00，和 dateRange 算出来的
    // 00:00 比不相等，"上周"会被误判成"更早"。取一个落在上个周期内部
    // 的日子，让同一个函数去定边界。
    final anchor = switch (selectedPeriod) {
      // 周一 00:00 往前 3 天必定落在上一周之内
      'week' => currentRange.start.subtract(const Duration(days: 3)),
      'month' => DateTime(currentRange.start.year, currentRange.start.month, 0),
      'year' => DateTime(currentRange.start.year - 1, 6, 15),
      _ => null,
    };
    final previous = anchor == null ? null : dateRange(selectedPeriod, anchor);
    if (previous != null && selected.start == previous.start) {
      return ReportPeriodOffset.previous;
    }
    return ReportPeriodOffset.other;
  }

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

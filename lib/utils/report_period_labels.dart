import '../gen_l10n/app_localizations.dart';
import 'report_period_utils.dart';

/// 周期选择的人话说法。
///
/// 探索页和 Thoughter 都要说「在总结哪一段时间」，之前各说各的：探索页永远
/// 说「本周」（哪怕用户翻到了别的一周），Thoughter 干脆无视选择直接取本周。
/// 两处共用这里，标签和真正查询的日期范围才是同一件事。
class ReportPeriodLabels {
  const ReportPeriodLabels._();

  /// 完整标签：本周 / 上周 / 8月10日 - 8月16日。
  ///
  /// 说得出「本/上」就用它，说不出才退回日期范围——「更早的某一周」没有
  /// 现成的说法，硬套一个只会比日期更含糊。
  static String label(
    AppLocalizations l10n,
    String period,
    DateTime date, {
    DateTime? now,
  }) {
    switch (ReportPeriodUtils.offsetFromNow(period, date, now: now)) {
      case ReportPeriodOffset.current:
        return switch (period) {
          'week' => l10n.thisWeek,
          'month' => l10n.thisMonth,
          'year' => l10n.thisYear,
          _ => rangeText(l10n, period, date),
        };
      case ReportPeriodOffset.previous:
        return switch (period) {
          'week' => l10n.lastWeek,
          'month' => l10n.lastMonth,
          'year' => l10n.lastYear,
          _ => rangeText(l10n, period, date),
        };
      case ReportPeriodOffset.other:
        return rangeText(l10n, period, date);
    }
  }

  /// 日期范围文案：`8月10日 - 8月16日` / `2025年7月` / `2024年`。
  static String rangeText(
    AppLocalizations l10n,
    String period,
    DateTime date,
  ) {
    switch (period) {
      case 'week':
        final range = ReportPeriodUtils.dateRange('week', date);
        if (range == null) return '';
        return l10n.dateRange(
          l10n.formattedDate(range.start.month, range.start.day),
          l10n.formattedDate(range.end.month, range.end.day),
        );
      case 'month':
        return l10n.yearMonth(date.year, date.month);
      case 'year':
        return l10n.yearOnly(date.year);
      default:
        return '';
    }
  }
}

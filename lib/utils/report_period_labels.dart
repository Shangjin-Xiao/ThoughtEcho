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

/// 空周期文案里「上一次落笔是 N 天前」的那个 N，算不出来就返回 null。
///
/// 这句话里的"天前"是相对**现在**说的，所以它只在「现在这个周期」和「刚过去
/// 的那个周期」上成立。用户翻到一年前的某个空周期时，这个数字讲的是今天，
/// 而他看的是一年前那一页——两边对不上，与其给一个读者对不上号的数字，不如
/// 不提（模板里本来就有不带数字的那一版）。
///
/// [lastNoteDate] 是整库最近一条笔记的时间。它落在 [range] 之后时同样不提：
/// 那说明用户在往回翻，"上一次"根本不在这个周期之前。
int? emptyPeriodGapDays({
  required DateTime? lastNoteDate,
  required ({DateTime start, DateTime end})? range,
  required String period,
  required DateTime date,
  DateTime? now,
}) {
  if (lastNoteDate == null || range == null) return null;
  if (!lastNoteDate.isBefore(range.start)) return null;

  final offset = ReportPeriodUtils.offsetFromNow(period, date, now: now);
  if (offset == ReportPeriodOffset.other) return null;

  // 和 buildAnalysisTimeContext 一样按日历日算：跨夏令时时本地 difference
  // 会少一小时，inDays 随之少一天。
  //
  // 结果必然 >= 1，不需要再兜一次底：range.start 恒是某天的 00:00，上面的守卫
  // 又要求 lastNoteDate 早于它，所以那条笔记落在 range.start 之前的某个日历日；
  // 而 offset 为 current / previous 意味着今天不早于 range.start 那天。
  final today = now ?? DateTime.now();
  final from = DateTime.utc(today.year, today.month, today.day);
  final to = DateTime.utc(
    lastNoteDate.year,
    lastNoteDate.month,
    lastNoteDate.day,
  );
  return from.difference(to).inDays;
}

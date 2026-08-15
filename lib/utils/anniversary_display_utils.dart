/// 周年庆典的展示规则。
///
/// 一周年时这里写死了 2026 年的两个日期，两周年要复用就得改一次常量。
/// 现在按「上线日 + 第几周年」推导，之后每一届都不用再动这个文件。
library;

/// 周年庆典的一届（一周年、两周年……）。
class AnniversaryEdition {
  /// 第几周年，从 1 开始。
  final int year;

  /// 展示期开始（含）。
  final DateTime start;

  /// 展示期结束（不含）。
  final DateTime endExclusive;

  const AnniversaryEdition({
    required this.year,
    required this.start,
    required this.endExclusive,
  });

  /// 横幅副标题里的日期区间，如 `2025.3.23 - 2027.3.23`。
  String get rangeLabel {
    final launch = AnniversaryDisplayUtils.launchDate;
    return '${launch.year}.${launch.month}.${launch.day}'
        ' - '
        '${start.year}.${start.month}.${start.day}';
  }

  @override
  bool operator ==(Object other) =>
      other is AnniversaryEdition &&
      other.year == year &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(year, start, endExclusive);
}

class AnniversaryDisplayUtils {
  /// 心迹上线日，所有周年都从这天推导。
  static final DateTime launchDate = DateTime(2025, 3, 23);

  /// 展示期结束日（不含）在当年的月/日，与上线日一起框定庆典窗口。
  static const int _seasonEndMonth = 5;
  static const int _seasonEndDay = 1;

  /// 第 [year] 周年的展示期。
  static AnniversaryEdition editionForYear(int year) {
    final anniversaryYear = launchDate.year + year;
    return AnniversaryEdition(
      year: year,
      start: DateTime(anniversaryYear, launchDate.month, launchDate.day),
      endExclusive: DateTime(anniversaryYear, _seasonEndMonth, _seasonEndDay),
    );
  }

  /// 当前正在进行的那一届；不在任何展示期内返回 null。
  ///
  /// [simulatedYear] 大于 0 时无视真实日期，直接返回那一届 —— 开发者模式的
  /// 「模拟周年庆典」用它把整套展示（横幅、启动动画、老用户标记）拉到当下。
  static AnniversaryEdition? currentEdition(
    DateTime now, {
    int simulatedYear = 0,
  }) {
    if (simulatedYear > 0) {
      return editionForYear(simulatedYear);
    }
    final year = now.year - launchDate.year;
    if (year < 1) return null;
    final edition = editionForYear(year);
    if (now.isBefore(edition.start) || !now.isBefore(edition.endExclusive)) {
      return null;
    }
    return edition;
  }

  static bool isAnniversarySeason(DateTime now, {int simulatedYear = 0}) {
    return currentEdition(now, simulatedYear: simulatedYear) != null;
  }

  static bool shouldShowSettingsBanner({
    required DateTime now,
    int simulatedYear = 0,
  }) {
    return isAnniversarySeason(now, simulatedYear: simulatedYear);
  }

  /// 启动时是否自动播放庆典动画：每一届只自动播一次。
  static bool shouldAutoShowAnimation({
    required DateTime now,
    required List<int> shownYears,
    required bool anniversaryAnimationEnabled,
    int simulatedYear = 0,
  }) {
    if (!anniversaryAnimationEnabled) return false;
    final edition = currentEdition(now, simulatedYear: simulatedYear);
    if (edition == null) return false;
    return !shownYears.contains(edition.year);
  }

  /// 用户是否参与过更早的庆典（一周年老用户在两周年会看到额外的致谢）。
  static bool hasEarlierEdition({
    required List<int> shownYears,
    required int currentYear,
  }) {
    return shownYears.any((year) => year > 0 && year < currentYear);
  }

  /// 参与过的最早那一届，没有则返回 null。
  static int? earliestShownYear(List<int> shownYears) {
    final valid = shownYears.where((year) => year > 0).toList()..sort();
    return valid.isEmpty ? null : valid.first;
  }
}

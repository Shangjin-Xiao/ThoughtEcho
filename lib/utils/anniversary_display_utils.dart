class AnniversaryDisplayUtils {
  static final DateTime _bannerStartDate = DateTime(2026, 3, 23);
  static final DateTime _bannerEndExclusive = DateTime(2026, 5, 1);

  static bool isAnniversarySeason(DateTime now) {
    return !now.isBefore(_bannerStartDate) && now.isBefore(_bannerEndExclusive);
  }

  static bool shouldShowSettingsBanner({
    required DateTime now,
    required bool developerMode,
  }) {
    // 一周年开发者模式预览入口已临时关闭，保留参数便于两周年复用。
    return isAnniversarySeason(now);
  }

  static bool shouldAutoShowAnimation({
    required DateTime now,
    required bool developerMode,
    required bool anniversaryShown,
    required bool anniversaryAnimationEnabled,
  }) {
    // 一周年开发者模式预览入口已临时关闭，保留参数便于两周年复用。
    return isAnniversarySeason(now) &&
        !anniversaryShown &&
        anniversaryAnimationEnabled;
  }
}

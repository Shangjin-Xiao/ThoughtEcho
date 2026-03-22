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
    return developerMode || isAnniversarySeason(now);
  }

  static bool shouldAutoShowAnimation({
    required DateTime now,
    required bool developerMode,
    required bool anniversaryShown,
    required bool anniversaryAnimationEnabled,
  }) {
    return (developerMode || isAnniversarySeason(now)) &&
        !anniversaryShown &&
        anniversaryAnimationEnabled;
  }
}

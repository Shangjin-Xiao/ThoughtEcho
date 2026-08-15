/// 一次周年庆典的参与记录。
///
/// 只记「哪一届、什么时候看到的、当时什么版本」这三样能长期成立的事实。写作快照
/// （笔记数一类）刻意不存：那类数字之后可以重算，而且删过的笔记会让它自相矛盾。
class AnniversaryParticipation {
  /// 第几周年，从 1 开始。
  final int year;

  /// 首次看到这一届庆典动画的时间（UTC）。
  ///
  /// 一周年时只存了个 bool，迁移过来的记录没有时间，所以可空。
  final DateTime? seenAt;

  /// 当时的应用版本号，迁移记录同样可能没有。
  final String? appVersion;

  const AnniversaryParticipation({
    required this.year,
    this.seenAt,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'year': year,
        if (seenAt != null) 'seenAt': seenAt!.toUtc().toIso8601String(),
        if (appVersion != null) 'appVersion': appVersion,
      };

  static AnniversaryParticipation? fromJson(dynamic value) {
    if (value is! Map) return null;
    final rawYear = value['year'];
    final year = rawYear is num ? rawYear.toInt() : null;
    if (year == null || year <= 0) return null;
    final rawSeenAt = value['seenAt'];
    final rawVersion = value['appVersion'];
    return AnniversaryParticipation(
      year: year,
      seenAt: rawSeenAt is String ? DateTime.tryParse(rawSeenAt) : null,
      appVersion:
          rawVersion is String && rawVersion.isNotEmpty ? rawVersion : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnniversaryParticipation &&
      other.year == year &&
      other.seenAt == seenAt &&
      other.appVersion == appVersion;

  @override
  int get hashCode => Object.hash(year, seenAt, appVersion);

  @override
  String toString() => 'AnniversaryParticipation(year: $year, seenAt: $seenAt, '
      'appVersion: $appVersion)';
}

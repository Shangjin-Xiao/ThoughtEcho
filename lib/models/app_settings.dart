class AppSettings {
  final String hitokotoType;

  AppSettings({
    this.hitokotoType = 'l', // 默认为抖机灵类型（随机）
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'l',
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
    hitokotoType: 'l',
  );

  AppSettings copyWith({
    String? hitokotoType,
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
    );
  }
} 
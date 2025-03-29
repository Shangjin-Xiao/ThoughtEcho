class AppSettings {
  final String hitokotoType;

  AppSettings({
    this.hitokotoType = 'a', // 默认为动画类型
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'a',
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
    hitokotoType: 'a',
  );

  AppSettings copyWith({
    String? hitokotoType,
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
    );
  }
} 
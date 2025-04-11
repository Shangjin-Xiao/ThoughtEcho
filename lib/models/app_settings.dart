class AppSettings {
  final String hitokotoType;

  AppSettings({
    this.hitokotoType = 'a,b,c,d,e,f,g,h,i,j,k', // 默认全选所有类型
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'a,b,c,d,e,f,g,h,i,j,k',
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
    hitokotoType: 'a,b,c,d,e,f,g,h,i,j,k',
  );

  AppSettings copyWith({
    String? hitokotoType,
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
    );
  }
}
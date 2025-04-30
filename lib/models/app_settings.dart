class AppSettings {
  final String hitokotoType;
  final bool clipboardMonitoringEnabled; // 添加剪贴板监控设置
  final int defaultStartPage; // 添加默认启动页面设置，0=首页，1=记录页

  AppSettings({
    this.hitokotoType = 'a,b,c,d,e,f,g,h,i,j,k', // 默认全选所有类型
    this.clipboardMonitoringEnabled = false, // 默认不启用剪贴板监控
    this.defaultStartPage = 0, // 默认启动显示首页
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
      'clipboardMonitoringEnabled': clipboardMonitoringEnabled,
      'defaultStartPage': defaultStartPage,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'a,b,c,d,e,f,g,h,i,j,k',
      clipboardMonitoringEnabled: map['clipboardMonitoringEnabled'] ?? false,
      defaultStartPage: map['defaultStartPage'] ?? 0,
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
    hitokotoType: 'a,b,c,d,e,f,g,h,i,j,k',
    clipboardMonitoringEnabled: false,
    defaultStartPage: 0,
  );

  AppSettings copyWith({
    String? hitokotoType,
    bool? clipboardMonitoringEnabled,
    int? defaultStartPage,
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
      clipboardMonitoringEnabled:
          clipboardMonitoringEnabled ?? this.clipboardMonitoringEnabled,
      defaultStartPage: defaultStartPage ?? this.defaultStartPage,
    );
  }
}

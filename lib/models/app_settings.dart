class AppSettings {
  final String hitokotoType;
  final bool clipboardMonitoringEnabled; // 添加剪贴板监控设置
  final int defaultStartPage; // 添加默认启动页面设置，0=首页，1=记录页
  final bool hasCompletedOnboarding; // 添加是否完成引导页的标志
  final bool aiCardGenerationEnabled; // 添加AI卡片生成功能开关
  final bool reportInsightsUseAI; // 新增：周期报告洞察是否使用AI（流式）
  final bool prioritizeBoldContentInCollapse; // 新增：折叠时优先显示加粗内容
  final bool showFavoriteButton; // 新增：是否显示心形按钮

  AppSettings({
    this.hitokotoType = 'a,b,c,d,e,f,g,h,i,j,k', // 默认全选所有类型
    this.clipboardMonitoringEnabled = false, // 默认不启用剪贴板监控
    this.defaultStartPage = 0, // 默认启动显示首页
    this.hasCompletedOnboarding = false, // 默认未完成引导
    this.aiCardGenerationEnabled = true, // 默认启用AI卡片生成
    this.reportInsightsUseAI = false, // 默认关闭AI洞察，使用本地生成
    this.prioritizeBoldContentInCollapse = false, // 默认关闭优先显示加粗内容
    this.showFavoriteButton = true, // 默认显示心形按钮
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
      'clipboardMonitoringEnabled': clipboardMonitoringEnabled,
      'defaultStartPage': defaultStartPage,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'aiCardGenerationEnabled': aiCardGenerationEnabled,
      'reportInsightsUseAI': reportInsightsUseAI,
      'prioritizeBoldContentInCollapse': prioritizeBoldContentInCollapse,
      'showFavoriteButton': showFavoriteButton, // 新增
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'a,b,c,d,e,f,g,h,i,j,k',
      clipboardMonitoringEnabled: map['clipboardMonitoringEnabled'] ?? false,
      defaultStartPage: map['defaultStartPage'] ?? 0,
      hasCompletedOnboarding: map['hasCompletedOnboarding'] ?? false,
      aiCardGenerationEnabled: map['aiCardGenerationEnabled'] ?? true,
      reportInsightsUseAI: map['reportInsightsUseAI'] ?? false,
      prioritizeBoldContentInCollapse:
          map['prioritizeBoldContentInCollapse'] ?? false,
      showFavoriteButton: map['showFavoriteButton'] ?? true, // 新增
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
        hitokotoType: 'a,b,c,d,e,f,g,h,i,j,k',
        clipboardMonitoringEnabled: false,
        defaultStartPage: 0,
        hasCompletedOnboarding: false,
        aiCardGenerationEnabled: true,
        reportInsightsUseAI: false,
        prioritizeBoldContentInCollapse: false,
        showFavoriteButton: true, // 新增
      );

  AppSettings copyWith({
    String? hitokotoType,
    bool? clipboardMonitoringEnabled,
    int? defaultStartPage,
    bool? hasCompletedOnboarding,
    bool? aiCardGenerationEnabled,
    bool? reportInsightsUseAI,
    bool? prioritizeBoldContentInCollapse,
    bool? showFavoriteButton, // 新增
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
      clipboardMonitoringEnabled:
          clipboardMonitoringEnabled ?? this.clipboardMonitoringEnabled,
      defaultStartPage: defaultStartPage ?? this.defaultStartPage,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      aiCardGenerationEnabled:
          aiCardGenerationEnabled ?? this.aiCardGenerationEnabled,
      reportInsightsUseAI: reportInsightsUseAI ?? this.reportInsightsUseAI,
      prioritizeBoldContentInCollapse: prioritizeBoldContentInCollapse ??
          this.prioritizeBoldContentInCollapse,
      showFavoriteButton: showFavoriteButton ?? this.showFavoriteButton, // 新增
    );
  }
}

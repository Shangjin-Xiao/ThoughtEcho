class AppSettings {
  final String hitokotoType;
  final bool clipboardMonitoringEnabled; // 添加剪贴板监控设置
  final int defaultStartPage; // 添加默认启动页面设置，0=首页，1=记录页
  final bool hasCompletedOnboarding; // 添加是否完成引导页的标志
  final bool aiCardGenerationEnabled; // 添加AI卡片生成功能开关
  final bool reportInsightsUseAI; // 新增：周期报告洞察是否使用AI（流式）
  final bool todayThoughtsUseAI; // 新增：今日思考是否使用AI（默认开启）
  final bool prioritizeBoldContentInCollapse; // 新增：折叠时优先显示加粗内容
  final bool showFavoriteButton; // 新增：是否显示心形按钮
  final bool useLocalQuotesOnly; // 新增：仅使用本地笔记作为一言，不请求API
  final String? localeCode; // 新增：语言代码，null 表示跟随系统
  final bool showExactTime; // 新增：是否在笔记中显示精确时间（时:分）
  final bool enableHiddenNotes; // 新增：是否启用隐藏笔记功能
  final bool requireBiometricForHidden; // 新增：访问隐藏笔记是否需要生物识别验证
  final bool developerMode; // 新增：开发者模式
  final bool enableFirstOpenScrollPerfMonitor; // 新增：首次打开后首次滑动性能监测
  final bool autoAttachLocation; // 新增：添加笔记时自动勾选位置
  final bool autoAttachWeather; // 新增：添加笔记时自动勾选天气
  final String? defaultAuthor; // 新增：默认作者（自动填充）
  final String? defaultSource; // 新增：默认出处（自动填充）
  final List<String> defaultTagIds; // 新增：默认标签 ID 列表（自动填充）

  AppSettings({
    this.hitokotoType = 'a,b,c,d,e,f,g,h,i,j,k', // 默认全选所有类型
    this.clipboardMonitoringEnabled = false, // 默认不启用剪贴板监控
    this.defaultStartPage = 0, // 默认启动显示首页
    this.hasCompletedOnboarding = false, // 默认未完成引导
    this.aiCardGenerationEnabled = true, // 默认启用AI卡片生成
    this.reportInsightsUseAI = false, // 默认关闭AI洞察，使用本地生成
    this.todayThoughtsUseAI = true, // 默认开启今日思考AI
    this.prioritizeBoldContentInCollapse = false, // 默认关闭优先显示加粗内容
    this.showFavoriteButton = true, // 默认显示心形按钮
    this.useLocalQuotesOnly = false, // 默认允许请求一言API
    this.localeCode, // 默认跟随系统
    this.showExactTime = false, // 默认不显示精确时间
    this.enableHiddenNotes = false, // 默认不启用隐藏笔记功能
    this.requireBiometricForHidden = false, // 默认不需要生物识别验证
    this.developerMode = false, // 默认关闭开发者模式
    this.enableFirstOpenScrollPerfMonitor = false, // 默认关闭首次滑动性能监测
    this.autoAttachLocation = false, // 默认不自动勾选位置
    this.autoAttachWeather = false, // 默认不自动勾选天气
    this.defaultAuthor, // 默认无自动填充作者
    this.defaultSource, // 默认无自动填充出处
    this.defaultTagIds = const [], // 默认无自动填充标签
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
      'clipboardMonitoringEnabled': clipboardMonitoringEnabled,
      'defaultStartPage': defaultStartPage,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'aiCardGenerationEnabled': aiCardGenerationEnabled,
      'reportInsightsUseAI': reportInsightsUseAI,
      'todayThoughtsUseAI': todayThoughtsUseAI,
      'prioritizeBoldContentInCollapse': prioritizeBoldContentInCollapse,
      'showFavoriteButton': showFavoriteButton,
      'useLocalQuotesOnly': useLocalQuotesOnly,
      'localeCode': localeCode,
      'showExactTime': showExactTime,
      'enableHiddenNotes': enableHiddenNotes,
      'requireBiometricForHidden': requireBiometricForHidden,
      'developerMode': developerMode,
      'enableFirstOpenScrollPerfMonitor': enableFirstOpenScrollPerfMonitor,
      'autoAttachLocation': autoAttachLocation,
      'autoAttachWeather': autoAttachWeather,
      'defaultAuthor': defaultAuthor,
      'defaultSource': defaultSource,
      'defaultTagIds': defaultTagIds,
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
      todayThoughtsUseAI: map['todayThoughtsUseAI'] ?? true,
      prioritizeBoldContentInCollapse:
          map['prioritizeBoldContentInCollapse'] ?? false,
      showFavoriteButton: map['showFavoriteButton'] ?? true,
      useLocalQuotesOnly: map['useLocalQuotesOnly'] ?? false,
      localeCode: map['localeCode'] as String?,
      showExactTime: map['showExactTime'] ?? false,
      enableHiddenNotes: map['enableHiddenNotes'] ?? false,
      requireBiometricForHidden: map['requireBiometricForHidden'] ?? false,
      developerMode: map['developerMode'] ?? false,
        enableFirstOpenScrollPerfMonitor:
          map['enableFirstOpenScrollPerfMonitor'] ?? false,
      autoAttachLocation: map['autoAttachLocation'] ?? false,
      autoAttachWeather: map['autoAttachWeather'] ?? false,
      defaultAuthor: map['defaultAuthor'] as String?,
      defaultSource: map['defaultSource'] as String?,
      defaultTagIds: (map['defaultTagIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
        hitokotoType: 'a,b,c,d,e,f,g,h,i,j,k',
        clipboardMonitoringEnabled: false,
        defaultStartPage: 0,
        hasCompletedOnboarding: false,
        aiCardGenerationEnabled: true,
        reportInsightsUseAI: false,
        todayThoughtsUseAI: true,
        prioritizeBoldContentInCollapse: false,
        showFavoriteButton: true,
        useLocalQuotesOnly: false,
        localeCode: null, // 默认跟随系统
        showExactTime: false, // 默认不显示精确时间
        enableHiddenNotes: false, // 默认不启用隐藏笔记功能
        requireBiometricForHidden: false, // 默认不需要生物识别验证
        developerMode: false, // 默认关闭开发者模式
        enableFirstOpenScrollPerfMonitor: false,
        autoAttachLocation: false, // 默认不自动勾选位置
        autoAttachWeather: false, // 默认不自动勾选天气
        defaultAuthor: null,
        defaultSource: null,
        defaultTagIds: const [],
      );

  /// 使用特殊标记来区分"未指定"和"设置为null（跟随系统）"
  AppSettings copyWith({
    String? hitokotoType,
    bool? clipboardMonitoringEnabled,
    int? defaultStartPage,
    bool? hasCompletedOnboarding,
    bool? aiCardGenerationEnabled,
    bool? reportInsightsUseAI,
    bool? todayThoughtsUseAI,
    bool? prioritizeBoldContentInCollapse,
    bool? showFavoriteButton,
    bool? useLocalQuotesOnly,
    String? localeCode,
    bool clearLocale = false, // 新增：是否清除 localeCode（设置为跟随系统）
    bool? showExactTime,
    bool? enableHiddenNotes,
    bool? requireBiometricForHidden,
    bool? developerMode,
    bool? enableFirstOpenScrollPerfMonitor,
    bool? autoAttachLocation,
    bool? autoAttachWeather,
    String? defaultAuthor,
    bool clearDefaultAuthor = false,
    String? defaultSource,
    bool clearDefaultSource = false,
    List<String>? defaultTagIds,
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
      todayThoughtsUseAI: todayThoughtsUseAI ?? this.todayThoughtsUseAI,
      prioritizeBoldContentInCollapse: prioritizeBoldContentInCollapse ??
          this.prioritizeBoldContentInCollapse,
      showFavoriteButton: showFavoriteButton ?? this.showFavoriteButton,
      useLocalQuotesOnly: useLocalQuotesOnly ?? this.useLocalQuotesOnly,
      localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
      showExactTime: showExactTime ?? this.showExactTime,
      enableHiddenNotes: enableHiddenNotes ?? this.enableHiddenNotes,
      requireBiometricForHidden:
          requireBiometricForHidden ?? this.requireBiometricForHidden,
      developerMode: developerMode ?? this.developerMode,
        enableFirstOpenScrollPerfMonitor: enableFirstOpenScrollPerfMonitor ??
          this.enableFirstOpenScrollPerfMonitor,
      autoAttachLocation: autoAttachLocation ?? this.autoAttachLocation,
      autoAttachWeather: autoAttachWeather ?? this.autoAttachWeather,
      defaultAuthor: clearDefaultAuthor ? null : (defaultAuthor ?? this.defaultAuthor),
      defaultSource: clearDefaultSource ? null : (defaultSource ?? this.defaultSource),
      defaultTagIds: defaultTagIds ?? this.defaultTagIds,
    );
  }
}

class AppSettings {
  final String hitokotoType;
  final String dailyQuoteProvider;
  final List<String> apiNinjasCategories;
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
  final bool showNoteEditTime; // 新增：是否显示笔记编辑时间
  final bool enableHiddenNotes; // 新增：是否启用隐藏笔记功能
  final bool requireBiometricForHidden; // 新增：访问隐藏笔记是否需要生物识别验证
  final bool developerMode; // 新增：开发者模式
  final bool enableFirstOpenScrollPerfMonitor; // 新增：首次打开后首次滑动性能监测
  final bool autoAttachLocation; // 新增：添加笔记时自动勾选位置
  final bool autoAttachWeather; // 新增：添加笔记时自动勾选天气
  final bool excerptIntentEnabled; // 新增：允许从外部文本摘录到应用
  final String? defaultAuthor; // 新增：默认作者（自动填充）
  final String? defaultSource; // 新增：默认出处（自动填充）
  final List<String> defaultTagIds; // 新增：默认标签 ID 列表（自动填充）
  final bool anniversaryShown; // 一周年庆典动画是否已显示过
  final bool anniversaryAnimationEnabled; // 一周年庆典动画是否启用（开发者模式控制）
  final int trashRetentionDays; // 回收站保留天数（7/30/90）
  final String? trashRetentionLastModified; // 回收站保留设置更新时间（UTC ISO）
  final bool skipNonFullscreenEditor; // 新增：跳过非全屏编辑器，直接进入全屏编辑器
  final String offlineQuoteSource;

  AppSettings({
    this.hitokotoType = 'a,b,c,d,e,f,g,h,i,j,k', // 默认全选所有类型
    this.dailyQuoteProvider = 'hitokoto',
    this.apiNinjasCategories = const [],
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
    this.showNoteEditTime = false, // 默认不显示笔记编辑时间
    this.enableHiddenNotes = false, // 默认不启用隐藏笔记功能
    this.requireBiometricForHidden = false, // 默认不需要生物识别验证
    this.developerMode = false, // 默认关闭开发者模式
    this.enableFirstOpenScrollPerfMonitor = false, // 默认关闭首次滑动性能监测
    this.autoAttachLocation = false, // 默认不自动勾选位置
    this.autoAttachWeather = false, // 默认不自动勾选天气
    this.excerptIntentEnabled = true, // 默认启用外部摘录入口
    this.defaultAuthor, // 默认无自动填充作者
    this.defaultSource, // 默认无自动填充出处
    this.defaultTagIds = const [], // 默认无自动填充标签
    this.anniversaryShown = false, // 默认未显示过
    this.anniversaryAnimationEnabled = true, // 默认启用庆典动画
    this.trashRetentionDays = 30,
    this.trashRetentionLastModified,
    this.skipNonFullscreenEditor = false, // 默认不跳过非全屏编辑器
    this.offlineQuoteSource = 'tagOnly', // 默认仅展示带每日一言标签的笔记
  });

  Map<String, dynamic> toJson() {
    return {
      'hitokotoType': hitokotoType,
      'dailyQuoteProvider': dailyQuoteProvider,
      'apiNinjasCategories': apiNinjasCategories,
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
      'showNoteEditTime': showNoteEditTime,
      'enableHiddenNotes': enableHiddenNotes,
      'requireBiometricForHidden': requireBiometricForHidden,
      'developerMode': developerMode,
      'enableFirstOpenScrollPerfMonitor': enableFirstOpenScrollPerfMonitor,
      'autoAttachLocation': autoAttachLocation,
      'autoAttachWeather': autoAttachWeather,
      'excerptIntentEnabled': excerptIntentEnabled,
      'defaultAuthor': defaultAuthor,
      'defaultSource': defaultSource,
      'defaultTagIds': defaultTagIds,
      'anniversaryShown': anniversaryShown,
      'anniversaryAnimationEnabled': anniversaryAnimationEnabled,
      'trashRetentionDays': trashRetentionDays,
      'trashRetentionLastModified': trashRetentionLastModified,
      'skipNonFullscreenEditor': skipNonFullscreenEditor,
      'offlineQuoteSource': offlineQuoteSource,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> map) {
    return AppSettings(
      hitokotoType: map['hitokotoType'] ?? 'a,b,c,d,e,f,g,h,i,j,k',
      dailyQuoteProvider: map['dailyQuoteProvider'] ?? 'hitokoto',
      apiNinjasCategories:
          (map['apiNinjasCategories'] as List<dynamic>?)?.cast<String>() ??
              const [],
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
      showNoteEditTime: map['showNoteEditTime'] ?? false,
      enableHiddenNotes: map['enableHiddenNotes'] ?? false,
      requireBiometricForHidden: map['requireBiometricForHidden'] ?? false,
      developerMode: map['developerMode'] ?? false,
      enableFirstOpenScrollPerfMonitor:
          map['enableFirstOpenScrollPerfMonitor'] ?? false,
      autoAttachLocation: map['autoAttachLocation'] ?? false,
      autoAttachWeather: map['autoAttachWeather'] ?? false,
      excerptIntentEnabled: map['excerptIntentEnabled'] ?? true,
      defaultAuthor: map['defaultAuthor'] as String?,
      defaultSource: map['defaultSource'] as String?,
      defaultTagIds:
          (map['defaultTagIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      anniversaryShown: map['anniversaryShown'] ?? false,
      anniversaryAnimationEnabled: map['anniversaryAnimationEnabled'] ?? true,
      trashRetentionDays: map['trashRetentionDays'] ?? 30,
      trashRetentionLastModified: map['trashRetentionLastModified'] as String?,
      skipNonFullscreenEditor: map['skipNonFullscreenEditor'] ?? false,
      offlineQuoteSource: map['offlineQuoteSource'] ?? 'tagOnly',
    );
  }

  factory AppSettings.defaultSettings() => AppSettings(
        hitokotoType: 'a,b,c,d,e,f,g,h,i,j,k',
        dailyQuoteProvider: 'hitokoto',
        apiNinjasCategories: const [],
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
        showNoteEditTime: false, // 默认不显示笔记编辑时间
        enableHiddenNotes: false, // 默认不启用隐藏笔记功能
        requireBiometricForHidden: false, // 默认不需要生物识别验证
        developerMode: false, // 默认关闭开发者模式
        enableFirstOpenScrollPerfMonitor: false,
        autoAttachLocation: false, // 默认不自动勾选位置
        autoAttachWeather: false, // 默认不自动勾选天气
        excerptIntentEnabled: true,
        defaultAuthor: null,
        defaultSource: null,
        defaultTagIds: const [],
        anniversaryShown: false,
        anniversaryAnimationEnabled: true,
        trashRetentionDays: 30,
        trashRetentionLastModified: null,
        skipNonFullscreenEditor: false, // 默认不跳过非全屏编辑器
        offlineQuoteSource: 'tagOnly',
      );

  /// 使用特殊标记来区分"未指定"和"设置为null（跟随系统）"
  AppSettings copyWith({
    String? hitokotoType,
    String? dailyQuoteProvider,
    List<String>? apiNinjasCategories,
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
    bool? showNoteEditTime,
    bool? enableHiddenNotes,
    bool? requireBiometricForHidden,
    bool? developerMode,
    bool? enableFirstOpenScrollPerfMonitor,
    bool? autoAttachLocation,
    bool? autoAttachWeather,
    bool? excerptIntentEnabled,
    String? defaultAuthor,
    bool clearDefaultAuthor = false,
    String? defaultSource,
    bool clearDefaultSource = false,
    List<String>? defaultTagIds,
    bool? anniversaryShown,
    bool? anniversaryAnimationEnabled,
    int? trashRetentionDays,
    String? trashRetentionLastModified,
    bool? skipNonFullscreenEditor,
    String? offlineQuoteSource,
  }) {
    return AppSettings(
      hitokotoType: hitokotoType ?? this.hitokotoType,
      dailyQuoteProvider: dailyQuoteProvider ?? this.dailyQuoteProvider,
      apiNinjasCategories: apiNinjasCategories ?? this.apiNinjasCategories,
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
      showNoteEditTime: showNoteEditTime ?? this.showNoteEditTime,
      enableHiddenNotes: enableHiddenNotes ?? this.enableHiddenNotes,
      requireBiometricForHidden:
          requireBiometricForHidden ?? this.requireBiometricForHidden,
      developerMode: developerMode ?? this.developerMode,
      enableFirstOpenScrollPerfMonitor: enableFirstOpenScrollPerfMonitor ??
          this.enableFirstOpenScrollPerfMonitor,
      autoAttachLocation: autoAttachLocation ?? this.autoAttachLocation,
      autoAttachWeather: autoAttachWeather ?? this.autoAttachWeather,
      excerptIntentEnabled: excerptIntentEnabled ?? this.excerptIntentEnabled,
      defaultAuthor:
          clearDefaultAuthor ? null : (defaultAuthor ?? this.defaultAuthor),
      defaultSource:
          clearDefaultSource ? null : (defaultSource ?? this.defaultSource),
      defaultTagIds: defaultTagIds ?? this.defaultTagIds,
      anniversaryShown: anniversaryShown ?? this.anniversaryShown,
      anniversaryAnimationEnabled:
          anniversaryAnimationEnabled ?? this.anniversaryAnimationEnabled,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
      trashRetentionLastModified:
          trashRetentionLastModified ?? this.trashRetentionLastModified,
      skipNonFullscreenEditor:
          skipNonFullscreenEditor ?? this.skipNonFullscreenEditor,
      offlineQuoteSource: offlineQuoteSource ?? this.offlineQuoteSource,
    );
  }
}

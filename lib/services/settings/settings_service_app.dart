part of '../settings_service.dart';

extension _SettingsServiceAppExtension on SettingsService {
  /// 修复：加载应用设置，增加数据验证和迁移安全性
  void _loadAppSettings() {
    try {
      final String? appSettingsJson =
          _mmkv.getString(_appSettingsKey) ?? _prefs.getString(_appSettingsKey);

      if (appSettingsJson != null) {
        try {
          final jsonData = json.decode(appSettingsJson);
          _appSettings = AppSettings.fromJson(jsonData);

          // 验证设置的完整性
          if (!_validateAppSettings(_appSettings)) {
            logDebug('应用设置验证失败，重置为默认设置');
            _appSettings = AppSettings.defaultSettings();
            _saveAppSettings();
          } else {
            // 确保一言类型不为空，如果为空则设置为默认全选
            if (_appSettings.hitokotoType.isEmpty) {
              _appSettings = AppSettings.defaultSettings();
              _saveAppSettings();
              logDebug('检测到一言类型为空，已重置为默认全选值');
            }
          }
        } catch (e) {
          logDebug('解析应用设置JSON失败: $e，使用默认设置');
          _appSettings = AppSettings.defaultSettings();
          _saveAppSettings();
        }
      } else {
        _appSettings = AppSettings.defaultSettings();
        _saveAppSettings();
        logDebug('首次启动，已初始化默认一言类型设置: ${_appSettings.hitokotoType}');
      }
    } catch (e) {
      logDebug('加载应用设置失败: $e，使用默认设置');
      _appSettings = AppSettings.defaultSettings();
    }
  }

  /// 修复：验证应用设置的完整性
  bool _validateAppSettings(AppSettings settings) {
    try {
      // 验证必要字段
      if (settings.hitokotoType.isEmpty) return false;

      // 验证默认起始页面值
      if (settings.defaultStartPage < 0 || settings.defaultStartPage > 2) {
        return false;
      }

      // 验证其他关键设置
      return true;
    } catch (e) {
      logDebug('验证应用设置时出错: $e');
      return false;
    }
  }

  /// 修复：安全保存应用设置
  void _saveAppSettings() {
    try {
      _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    } catch (e) {
      logDebug('保存应用设置失败: $e');
    }
  }

  // 周期报告洞察是否使用AI（流式）
  bool get reportInsightsUseAI => _appSettings.reportInsightsUseAI;
  Future<void> setReportInsightsUseAI(bool enabled) async {
    _appSettings = _appSettings.copyWith(reportInsightsUseAI: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 今日思考是否使用AI（默认开启）
  bool get todayThoughtsUseAI => _appSettings.todayThoughtsUseAI;
  Future<void> setTodayThoughtsUseAI(bool enabled) async {
    _appSettings = _appSettings.copyWith(todayThoughtsUseAI: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 折叠时优先显示加粗内容
  bool get prioritizeBoldContentInCollapse =>
      _appSettings.prioritizeBoldContentInCollapse;
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {
    _appSettings = _appSettings.copyWith(
      prioritizeBoldContentInCollapse: enabled,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否显示心形按钮
  bool get showFavoriteButton => _appSettings.showFavoriteButton;
  Future<void> setShowFavoriteButton(bool enabled) async {
    _appSettings = _appSettings.copyWith(showFavoriteButton: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否仅使用本地笔记作为一言
  bool get useLocalQuotesOnly => _appSettings.useLocalQuotesOnly;
  Future<void> setUseLocalQuotesOnly(bool enabled) async {
    _appSettings = _appSettings.copyWith(useLocalQuotesOnly: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 无网/离线时的一言回退数据源
  String get offlineQuoteSource => _appSettings.offlineQuoteSource;
  Future<void> setOfflineQuoteSource(String source) async {
    _appSettings = _appSettings.copyWith(offlineQuoteSource: source);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否显示精确时间（时:分）
  bool get showExactTime => _appSettings.showExactTime;
  Future<void> setShowExactTime(bool enabled) async {
    _appSettings = _appSettings.copyWith(showExactTime: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者模式：首次打开后首次滑动卡顿监测开关
  bool get enableFirstOpenScrollPerfMonitor =>
      _appSettings.enableFirstOpenScrollPerfMonitor;
  Future<void> setEnableFirstOpenScrollPerfMonitor(bool enabled) async {
    _appSettings =
        _appSettings.copyWith(enableFirstOpenScrollPerfMonitor: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 语言设置：获取当前语言代码（null 表示跟随系统）
  String? get localeCode => _appSettings.localeCode;

  /// 设置语言代码，null 表示跟随系统
  Future<void> setLocale(String? localeCode) async {
    if (localeCode == null) {
      _appSettings = _appSettings.copyWith(clearLocale: true);
    } else {
      _appSettings = _appSettings.copyWith(localeCode: localeCode);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 隐藏笔记功能设置
  bool get enableHiddenNotes => _appSettings.enableHiddenNotes;
  Future<void> setEnableHiddenNotes(bool enabled) async {
    _appSettings = _appSettings.copyWith(enableHiddenNotes: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 访问隐藏笔记是否需要生物识别验证
  bool get requireBiometricForHidden => _appSettings.requireBiometricForHidden;
  Future<void> setRequireBiometricForHidden(bool enabled) async {
    _appSettings = _appSettings.copyWith(requireBiometricForHidden: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 添加笔记时自动勾选位置
  bool get autoAttachLocation => _appSettings.autoAttachLocation;
  Future<void> setAutoAttachLocation(bool enabled) async {
    _appSettings = _appSettings.copyWith(autoAttachLocation: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 添加笔记时自动勾选天气
  bool get autoAttachWeather => _appSettings.autoAttachWeather;
  Future<void> setAutoAttachWeather(bool enabled) async {
    _appSettings = _appSettings.copyWith(autoAttachWeather: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否启用从外部文本摘录到应用
  bool get excerptIntentEnabled => _appSettings.excerptIntentEnabled;
  Future<void> setExcerptIntentEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(excerptIntentEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    await _syncExcerptIntentEntryPoint();
    notifyListeners();
  }

  // 默认作者（自动填充）
  String? get defaultAuthor => _appSettings.defaultAuthor;
  Future<void> setDefaultAuthor(String? author) async {
    if (author == null || author.isEmpty) {
      _appSettings = _appSettings.copyWith(clearDefaultAuthor: true);
    } else {
      _appSettings = _appSettings.copyWith(defaultAuthor: author);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 默认出处（自动填充）
  String? get defaultSource => _appSettings.defaultSource;
  Future<void> setDefaultSource(String? source) async {
    if (source == null || source.isEmpty) {
      _appSettings = _appSettings.copyWith(clearDefaultSource: true);
    } else {
      _appSettings = _appSettings.copyWith(defaultSource: source);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 默认标签 ID 列表（自动填充）
  List<String> get defaultTagIds => _appSettings.defaultTagIds;
  Future<void> setDefaultTagIds(List<String> tagIds) async {
    _appSettings = _appSettings.copyWith(defaultTagIds: tagIds);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 一周年庆典动画是否已显示过
  bool get anniversaryShown => _appSettings.anniversaryShown;
  Future<void> setAnniversaryShown(bool shown) async {
    _appSettings = _appSettings.copyWith(anniversaryShown: shown);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 一周年庆典动画是否启用（开发者模式控制）
  bool get anniversaryAnimationEnabled =>
      _appSettings.anniversaryAnimationEnabled;
  Future<void> setAnniversaryAnimationEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(anniversaryAnimationEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 重置一周年动画已显示标记（开发者模式使用）
  Future<void> resetAnniversaryShown() async {
    _appSettings = _appSettings.copyWith(anniversaryShown: false);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 跳过非全屏编辑器，直接进入全屏编辑器
  bool get skipNonFullscreenEditor => _appSettings.skipNonFullscreenEditor;
  Future<void> setSkipNonFullscreenEditor(bool enabled) async {
    _appSettings = _appSettings.copyWith(skipNonFullscreenEditor: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 获取AI卡片生成功能是否启用
  bool get aiCardGenerationEnabled {
    return _appSettings.aiCardGenerationEnabled;
  }

  // 设置AI卡片生成功能是否启用
  Future<void> setAICardGenerationEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(aiCardGenerationEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> updateAppSettings(AppSettings settings) async {
    _appSettings = settings;
    await _mmkv.setString(_appSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 通过检查应用设置中的引导完成标志判断用户是否完成了引导
  bool hasCompletedOnboarding() {
    return _appSettings.hasCompletedOnboarding;
  }

  // 设置用户是否完成了引导流程
  Future<void> setHasCompletedOnboarding(bool completed) async {
    _appSettings = _appSettings.copyWith(hasCompletedOnboarding: completed);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> _syncExcerptIntentEntryPoint() async {
    if (kIsWeb) {
      return;
    }

    await _excerptIntentService.syncEntryPointEnabled(
      _appSettings.excerptIntentEnabled,
    );
  }
}

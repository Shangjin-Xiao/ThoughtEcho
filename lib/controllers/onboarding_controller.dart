import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/onboarding_models.dart';
import '../config/onboarding_config.dart';
import '../services/migration_service.dart';
import '../services/settings_service.dart';
import '../services/clipboard_service.dart';
import '../services/database_service.dart';
import '../services/mmkv_service.dart';
import '../services/ai_analysis_database_service.dart';
import '../utils/app_logger.dart';

/// 引导页面控制器
class OnboardingController extends ChangeNotifier {
  final PageController _pageController = PageController();
  OnboardingState _state = const OnboardingState();
  final ValueNotifier<bool>? servicesInitializedNotifier;
  
  // Services
  late final MigrationService _migrationService;
  late final SettingsService _settingsService;
  late final ClipboardService _clipboardService;
  late final AIAnalysisDatabaseService _aiAnalysisDbService;
  late final DatabaseService _databaseService;

  OnboardingController({this.servicesInitializedNotifier});

  PageController get pageController => _pageController;
  OnboardingState get state => _state;

  /// 初始化控制器
  void initialize(BuildContext context) {
    final databaseService = context.read<DatabaseService>();
    final settingsService = context.read<SettingsService>();
    final mmkvService = context.read<MMKVService>();
    final clipboardService = context.read<ClipboardService>();
    final aiAnalysisDbService = context.read<AIAnalysisDatabaseService>();

    _settingsService = settingsService;
    _clipboardService = clipboardService;
    _aiAnalysisDbService = aiAnalysisDbService;
    _databaseService = databaseService;
    _migrationService = MigrationService(
      databaseService: databaseService,
      settingsService: settingsService,
      mmkvService: mmkvService,
    );

    _initializePreferences();
  }

  /// 初始化偏好设置默认值
  void _initializePreferences() {
    final defaultPreferences = <String, dynamic>{};

    for (final preference in OnboardingConfig.preferences) {
      defaultPreferences[preference.key] = preference.defaultValue;
    }

    _state = _state.copyWith(preferences: defaultPreferences);
    _updateNavigationState();
  }

  /// 更新偏好设置
  void updatePreference(String key, dynamic value) {
    _state = _state.updatePreference(key, value);
    _updateNavigationState();
    notifyListeners();
  }

  /// 下一页
  Future<void> nextPage() async {
    if (!_state.canGoNext) return;

    if (_state.currentPageIndex < OnboardingConfig.totalPages - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      await completeOnboarding();
    }
  }

  /// 上一页
  Future<void> previousPage() async {
    if (!_state.canGoPrevious) return;

    await _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 跳到指定页面
  Future<void> goToPage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= OnboardingConfig.totalPages) return;

    await _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 页面改变回调
  void onPageChanged(int pageIndex) {
    _state = _state.copyWith(currentPageIndex: pageIndex);
    _updateNavigationState();
    notifyListeners();
  }

  /// 完成引导
  Future<void> completeOnboarding() async {
    if (_state.isCompleting) return;

    _state = _state.copyWith(isCompleting: true);
    notifyListeners();

    try {
      logInfo('开始完成引导流程');

      // 1. 执行数据迁移（包含数据库初始化）
      final migrationResult = await _migrationService.performMigration();
      if (!migrationResult.isSuccess) {
        logError(
          '数据迁移失败: ${migrationResult.errorMessage}',
          source: 'OnboardingController',
        );
        if (migrationResult.warningMessage != null) {
          logWarning(
            '迁移警告: ${migrationResult.warningMessage}',
            source: 'OnboardingController',
          );
        }
      }

      // 2. 确保数据库完全初始化并可用
      await _databaseService.safeDatabase;
      await Future.delayed(const Duration(milliseconds: 50));

      // 3. 初始化 AI 分析数据库
      try {
        await _aiAnalysisDbService.init();
        logInfo('AI分析数据库初始化完成', source: 'OnboardingController');
      } catch (aiDbError) {
        logError('AI分析数据库初始化失败: $aiDbError',
            error: aiDbError, source: 'OnboardingController');
      }

      // 4. 保存用户偏好设置
      await _saveUserPreferences();

      // 5. 标记引导完成
      await _settingsService.setHasCompletedOnboarding(true);

      // 6. 标记服务初始化完成
      servicesInitializedNotifier?.value = true;

      logInfo('引导流程完成');
    } catch (e, stackTrace) {
      logError(
        '完成引导失败',
        error: e,
        stackTrace: stackTrace,
        source: 'OnboardingController',
      );
      _state = _state.copyWith(isCompleting: false);
      notifyListeners();
      rethrow;
    }
  }

  /// 保存用户偏好设置
  Future<void> _saveUserPreferences() async {
    try {
      logDebug('开始保存用户偏好设置');

      // 获取当前应用设置
      final currentSettings = _settingsService.appSettings;

      // 构建新的设置对象
      final newSettings = currentSettings.copyWith(
        defaultStartPage: _state.getPreference<int>('defaultStartPage'),
        clipboardMonitoringEnabled: _state.getPreference<bool>(
          'clipboardMonitoring',
        ),
        hitokotoType: _state.getPreference<String>('hitokotoTypes'),
        // 新增偏好持久化
        showFavoriteButton:
            _state.getPreference<bool>('showFavoriteButton') ?? true,
        prioritizeBoldContentInCollapse:
            _state.getPreference<bool>('prioritizeBoldContent') ?? false,
        useLocalQuotesOnly: _state.getPreference<bool>('useLocalOnly') ?? false,
        aiCardGenerationEnabled:
            _state.getPreference<bool>('aiCardGenerationEnabled') ?? true,
      );

      // 更新应用设置
      await _settingsService.updateAppSettings(newSettings);

      // 应用剪贴板监控设置
      final clipboardEnabled =
          _state.getPreference<bool>('clipboardMonitoring') ?? false;
      _clipboardService.setEnableClipboardMonitoring(clipboardEnabled);

      // 应用位置服务设置
      final locationEnabled =
          _state.getPreference<bool>('locationService') ?? false;
      if (locationEnabled) {
        // 位置服务在偏好设置页面已经处理了权限申请
        // 这里只需要记录设置状态
        logInfo('位置服务已启用');
      }

      // AI相关快捷开关
      final todayAI = _state.getPreference<bool>('todayThoughtsUseAI') ?? false;
      await _settingsService.setTodayThoughtsUseAI(todayAI);
      final reportAI =
          _state.getPreference<bool>('reportInsightsUseAI') ?? false;
      await _settingsService.setReportInsightsUseAI(reportAI);

      logDebug('用户偏好设置保存完成');
    } catch (e) {
      logError('保存用户偏好设置失败', error: e, source: 'OnboardingController');
      // 不抛出异常，避免阻塞引导流程
    }
  }

  /// 更新导航状态
  void _updateNavigationState() {
    final canGoNext =
        _state.currentPageIndex < OnboardingConfig.totalPages - 1 ||
            _canCompleteOnboarding();
    final canGoPrevious = _state.currentPageIndex > 0;

    _state = _state.copyWith(
      canGoNext: canGoNext,
      canGoPrevious: canGoPrevious,
    );
  }

  /// 检查是否可以完成引导
  bool _canCompleteOnboarding() {
    // 可以在这里添加额外的验证逻辑
    return true;
  }

  /// 跳过引导
  Future<void> skipOnboarding() async {
    if (_state.isCompleting) return;

    _state = _state.copyWith(isCompleting: true);
    notifyListeners();

    try {
      logInfo('用户选择跳过引导，使用默认设置');

      // 1. 执行数据迁移（包含数据库初始化）
      final migrationResult = await _migrationService.performMigration();
      if (!migrationResult.isSuccess) {
        logWarning(
          '跳过引导时数据迁移失败: ${migrationResult.errorMessage}',
          source: 'OnboardingController',
        );
      }

      // 2. 确保数据库完全初始化并可用
      await _databaseService.safeDatabase;
      await Future.delayed(const Duration(milliseconds: 50));

      // 3. 保存默认用户偏好设置
      await _saveUserPreferences();

      // 4. 初始化 AI 分析数据库
      try {
        await _aiAnalysisDbService.init();
        logInfo('AI分析数据库初始化完成', source: 'OnboardingController');
      } catch (aiDbError) {
        logError('AI分析数据库初始化失败: $aiDbError',
            error: aiDbError, source: 'OnboardingController');
      }

      // 5. 标记引导完成
      await _settingsService.setHasCompletedOnboarding(true);

      // 6. 标记服务初始化完成
      servicesInitializedNotifier?.value = true;

      logInfo('跳过引导完成');
    } catch (e, stackTrace) {
      logError(
        '跳过引导失败',
        error: e,
        stackTrace: stackTrace,
        source: 'OnboardingController',
      );
      _state = _state.copyWith(isCompleting: false);
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

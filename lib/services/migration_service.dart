import 'package:package_info_plus/package_info_plus.dart';

import 'database_service.dart';
import 'settings_service.dart';
import 'mmkv_service.dart';
import '../utils/app_logger.dart';

/// 数据迁移服务
///
/// 负责处理版本升级时的数据迁移任务，包括：
/// - 版本检查与管理
/// - 数据库结构升级
/// - 旧数据格式转换
/// - 迁移状态追踪
class MigrationService {
  final DatabaseService _databaseService;
  final SettingsService _settingsService;
  final MMKVService _mmkvService;

  static const String _keyLastRunVersion = 'lastRunVersionBuildNumber';
  static const int _migrationNeededFromBuildNumber = 12;

  MigrationService({
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required MMKVService mmkvService,
  }) : _databaseService = databaseService,
       _settingsService = settingsService,
       _mmkvService = mmkvService;

  /// 检查是否需要执行迁移
  Future<bool> needsMigration() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      final lastRunBuildNumber =
          int.tryParse(_mmkvService.getString(_keyLastRunVersion) ?? '0') ?? 0;

      final isFirstSetup = !_settingsService.isInitialDatabaseSetupComplete();
      final isUpdateRequiringMigration =
          currentBuildNumber > lastRunBuildNumber &&
          currentBuildNumber >= _migrationNeededFromBuildNumber;

      final needsMigration = isFirstSetup || isUpdateRequiringMigration;

      logDebug(
        '迁移检查: 当前版本=$currentBuildNumber, 上次版本=$lastRunBuildNumber, '
        '首次设置=$isFirstSetup, 需要迁移=$needsMigration',
      );

      return needsMigration;
    } catch (e) {
      logError('检查迁移需求失败', error: e, source: 'MigrationService');
      return false;
    }
  }

  /// 执行完整的迁移流程
  Future<MigrationResult> performMigration() async {
    logInfo('开始执行数据迁移');

    try {
      // 1. 确保数据库已初始化
      await _databaseService.init();
      logDebug('数据库初始化完成');

      // 2. 初始化默认分类
      await _databaseService.initDefaultHitokotoCategories();
      logDebug('默认一言分类初始化完成');

      // 3. 执行数据迁移任务
      if (await needsMigration()) {
        await _executeMigrationTasks();
      }

      // 4. 更新版本记录
      await _updateVersionRecord();

      // 5. 标记迁移完成
      await _markMigrationComplete();

      logInfo('数据迁移成功完成');
      return MigrationResult.success();
    } catch (e, stackTrace) {
      logError(
        '数据迁移失败',
        error: e,
        stackTrace: stackTrace,
        source: 'MigrationService',
      );

      // 对于新用户，即使迁移失败也标记完成，避免阻塞
      if (!_settingsService.isInitialDatabaseSetupComplete()) {
        await _markMigrationComplete();
        logDebug('新用户迁移失败，已标记完成避免阻塞');
        return MigrationResult.partialSuccess('新用户设置完成，但部分迁移失败');
      }

      return MigrationResult.failure(e.toString());
    }
  }

  /// 执行具体的迁移任务
  Future<void> _executeMigrationTasks() async {
    logDebug('开始执行迁移任务');

    if (!_databaseService.isInitialized) {
      throw Exception('数据库未完全初始化，无法执行迁移');
    }

    // 任务1: 补全旧数据的dayPeriod字段
    try {
      await _databaseService.patchQuotesDayPeriod();
      logDebug('旧数据dayPeriod字段补全完成');
    } catch (e) {
      logError('补全dayPeriod字段失败', error: e, source: 'MigrationService');
    }

    // 任务2: 迁移旧weather字段为key
    try {
      await _databaseService.migrateWeatherToKey();
      logDebug('weather字段迁移完成');
    } catch (e) {
      logError('迁移weather字段失败', error: e, source: 'MigrationService');
    }

    // 任务3: 迁移旧dayPeriod字段为key
    try {
      await _databaseService.migrateDayPeriodToKey();
      logDebug('dayPeriod字段迁移完成');
    } catch (e) {
      logError('迁移dayPeriod字段失败', error: e, source: 'MigrationService');
    }

    logDebug('所有迁移任务执行完成');
  }

  /// 更新版本记录
  Future<void> _updateVersionRecord() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await _mmkvService.setString(_keyLastRunVersion, packageInfo.buildNumber);
      logDebug('版本记录已更新: ${packageInfo.buildNumber}');
    } catch (e) {
      logError('更新版本记录失败', error: e, source: 'MigrationService');
    }
  }

  /// 标记迁移完成
  Future<void> _markMigrationComplete() async {
    try {
      if (!_settingsService.isInitialDatabaseSetupComplete()) {
        await _settingsService.setInitialDatabaseSetupComplete(true);
        logDebug('数据库初始设置标记完成');
      }

      await _settingsService.setDatabaseMigrationComplete(true);
      logDebug('迁移状态标记完成');
    } catch (e) {
      logError('标记迁移完成失败', error: e, source: 'MigrationService');
    }
  }

  /// 获取当前版本信息
  Future<VersionInfo> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final lastRunVersion = _mmkvService.getString(_keyLastRunVersion) ?? '0';

      return VersionInfo(
        current: packageInfo.buildNumber,
        lastRun: lastRunVersion,
        isFirstRun: !_settingsService.isInitialDatabaseSetupComplete(),
      );
    } catch (e) {
      logError('获取版本信息失败', error: e, source: 'MigrationService');
      return VersionInfo(current: '0', lastRun: '0', isFirstRun: true);
    }
  }
}

/// 迁移结果
class MigrationResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? warningMessage;

  MigrationResult._({
    required this.isSuccess,
    this.errorMessage,
    this.warningMessage,
  });

  factory MigrationResult.success() => MigrationResult._(isSuccess: true);

  factory MigrationResult.partialSuccess(String warning) =>
      MigrationResult._(isSuccess: true, warningMessage: warning);

  factory MigrationResult.failure(String error) =>
      MigrationResult._(isSuccess: false, errorMessage: error);
}

/// 版本信息
class VersionInfo {
  final String current;
  final String lastRun;
  final bool isFirstRun;

  VersionInfo({
    required this.current,
    required this.lastRun,
    required this.isFirstRun,
  });

  bool get hasVersionChanged => current != lastRun;
}

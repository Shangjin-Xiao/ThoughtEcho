import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/migration_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class FakeMMKVService implements MMKVService {
  final Map<String, dynamic> _data = {};

  FakeMMKVService([Map<String, dynamic>? initialData]) {
    if (initialData != null) {
      _data.addAll(initialData);
    }
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    return _data[key] as String? ?? defaultValue;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsService implements SettingsService {
  bool initialDatabaseSetupComplete;
  bool databaseMigrationComplete;

  FakeSettingsService({
    this.initialDatabaseSetupComplete = true,
    this.databaseMigrationComplete = false,
  });

  @override
  bool isInitialDatabaseSetupComplete() => initialDatabaseSetupComplete;

  @override
  Future<void> setInitialDatabaseSetupComplete(bool complete) async {
    initialDatabaseSetupComplete = complete;
  }

  @override
  bool isDatabaseMigrationComplete() => databaseMigrationComplete;

  @override
  Future<void> setDatabaseMigrationComplete(bool complete) async {
    databaseMigrationComplete = complete;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDatabaseService implements DatabaseService {
  bool initialized = false;
  bool hitokotoTagsInitialized = false;
  bool patchedQuotesDayPeriod = false;
  bool migratedWeatherToKey = false;
  bool migratedDayPeriodToKey = false;
  bool shouldThrowOnPatch = false;

  @override
  bool get isInitialized => initialized;

  @override
  Future<void> init() async {
    initialized = true;
  }

  @override
  Future<void> initDefaultHitokotoTags() async {
    hitokotoTagsInitialized = true;
  }

  @override
  Future<void> patchQuotesDayPeriod() async {
    if (shouldThrowOnPatch) throw Exception('Simulated patch error');
    patchedQuotesDayPeriod = true;
  }

  @override
  Future<void> migrateWeatherToKey() async {
    migratedWeatherToKey = true;
  }

  @override
  Future<void> migrateDayPeriodToKey() async {
    migratedDayPeriodToKey = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PackageInfo createPackageInfo({
  String version = '4.1.0',
  String buildNumber = '1',
}) {
  return PackageInfo(
    appName: 'ThoughtEcho',
    packageName: 'com.shangjin.thoughtecho',
    version: version,
    buildNumber: buildNumber,
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDatabaseService dbService;
  late FakeSettingsService settingsService;
  late FakeMMKVService mmkvService;

  setUp(() {
    dbService = FakeDatabaseService();
    settingsService = FakeSettingsService(initialDatabaseSetupComplete: true);
    mmkvService = FakeMMKVService();
  });

  group('MigrationService needsMigration', () {
    test('当 packageInfo.buildNumber 为 4.0.0-beta.1 时能正确识别需要迁移', () async {
      // 场景：历史记录为旧版本 11，当前构建号采用 4.0.0-beta.1
      mmkvService = FakeMMKVService({'lastRunVersionBuildNumber': '11'});
      final packageInfo = createPackageInfo(
        version: '1.0.0',
        buildNumber: '4.0.0-beta.1',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      final needs = await migrationService.needsMigration();
      expect(needs, isTrue);

      final result = await migrationService.performMigration();
      expect(result.isSuccess, isTrue);
      expect(dbService.patchedQuotesDayPeriod, isTrue);
      expect(dbService.migratedWeatherToKey, isTrue);
      expect(dbService.migratedDayPeriodToKey, isTrue);

      // 验证 MMKV 记录更新为语义化格式
      expect(
        mmkvService.getString('lastRunVersionBuildNumber'),
        '4.0.0-beta.1',
      );

      // 再次检查无需重复迁移
      expect(await migrationService.needsMigration(), isFalse);
    });

    test('针对多种构建号格式（v4.0.0、4.0.0+12、4.0.0-beta.1、12）正确判定迁移需求', () async {
      final formats = [
        {'buildNumber': 'v4.0.0', 'version': '4.0.0', 'expected': '4.0.0'},
        {'buildNumber': '4.0.0+12', 'version': '4.0.0', 'expected': '4.0.0+12'},
        {
          'buildNumber': '4.0.0-beta.1',
          'version': '4.0.0',
          'expected': '4.0.0-beta.1'
        },
        {'buildNumber': '12', 'version': '1.0.0', 'expected': '1.0.0+12'},
      ];

      for (final item in formats) {
        final mockMmkv = FakeMMKVService({'lastRunVersionBuildNumber': '11'});
        final mockDb = FakeDatabaseService();
        final mockSettings = FakeSettingsService(
          initialDatabaseSetupComplete: true,
        );

        final packageInfo = createPackageInfo(
          version: item['version']!,
          buildNumber: item['buildNumber']!,
        );

        final service = MigrationService(
          databaseService: mockDb,
          settingsService: mockSettings,
          mmkvService: mockMmkv,
          packageInfo: packageInfo,
        );

        expect(
          await service.needsMigration(),
          isTrue,
          reason: 'Format ${item['buildNumber']} should require migration',
        );

        final result = await service.performMigration();
        expect(result.isSuccess, isTrue);
        expect(
          mockMmkv.getString('lastRunVersionBuildNumber'),
          item['expected'],
        );

        // 重启后不应重复迁移
        expect(
          await service.needsMigration(),
          isFalse,
          reason:
              'Restarting on ${item['buildNumber']} should not repeat migration',
        );
      }
    });

    test('向后兼容：已在构建号 12 运行过的用户重启时不重复迁移', () async {
      mmkvService = FakeMMKVService({'lastRunVersionBuildNumber': '12'});
      final packageInfo = createPackageInfo(
        version: '1.0.0',
        buildNumber: '12',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      expect(await migrationService.needsMigration(), isFalse);
    });

    test('向后兼容：从旧版构建号 12 升级到 4.0.0 正确触发迁移', () async {
      mmkvService = FakeMMKVService({'lastRunVersionBuildNumber': '12'});
      final packageInfo = createPackageInfo(
        version: '4.0.0',
        buildNumber: '1',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      expect(await migrationService.needsMigration(), isTrue);
    });

    test('旧版构建号低于阈值（如从 10 升级到 11）不触发迁移', () async {
      mmkvService = FakeMMKVService({'lastRunVersionBuildNumber': '10'});
      final packageInfo = createPackageInfo(
        version: '1.0.0',
        buildNumber: '11',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      expect(await migrationService.needsMigration(), isFalse);
    });

    test('预发布版本演进（4.0.0-beta.1 升级至 4.0.0-beta.2 与正式版）能正确触发迁移', () async {
      mmkvService =
          FakeMMKVService({'lastRunVersionBuildNumber': '4.0.0-beta.1'});
      final beta2Package = createPackageInfo(
        version: '4.0.0',
        buildNumber: '4.0.0-beta.2',
      );
      final serviceBeta2 = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: beta2Package,
      );

      expect(await serviceBeta2.needsMigration(), isTrue);
      await serviceBeta2.performMigration();
      expect(
        mmkvService.getString('lastRunVersionBuildNumber'),
        '4.0.0-beta.2',
      );

      // 从 beta.2 升级到 release 4.0.0
      final releasePackage = createPackageInfo(
        version: '4.0.0',
        buildNumber: '',
      );
      final serviceRelease = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: releasePackage,
      );

      expect(await serviceRelease.needsMigration(), isTrue);
      await serviceRelease.performMigration();
      expect(mmkvService.getString('lastRunVersionBuildNumber'), '4.0.0');
    });

    test('首次运行用户始终触发迁移与数据库初始化', () async {
      settingsService.initialDatabaseSetupComplete = false;
      final packageInfo = createPackageInfo(
        version: '4.1.0',
        buildNumber: '1',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      expect(await migrationService.needsMigration(), isTrue);
      final result = await migrationService.performMigration();
      expect(result.isSuccess, isTrue);
      expect(settingsService.isInitialDatabaseSetupComplete(), isTrue);
      expect(settingsService.isDatabaseMigrationComplete(), isTrue);
    });

    test('新用户迁移任务出现异常时不阻塞流程并返回 partialSuccess', () async {
      settingsService.initialDatabaseSetupComplete = false;
      dbService.shouldThrowOnPatch = true;

      final packageInfo = createPackageInfo(
        version: '4.1.0',
        buildNumber: '1',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      // performMigration 会捕获任务内部错误并正常完成，同时避免阻塞
      final result = await migrationService.performMigration();
      expect(result.isSuccess, isTrue);
      expect(settingsService.isInitialDatabaseSetupComplete(), isTrue);
    });

    test('getCurrentVersion 返回符合预期的规范化版本信息', () async {
      mmkvService = FakeMMKVService({'lastRunVersionBuildNumber': '12'});
      final packageInfo = createPackageInfo(
        version: '4.0.0',
        buildNumber: '4.0.0-beta.1',
      );
      final migrationService = MigrationService(
        databaseService: dbService,
        settingsService: settingsService,
        mmkvService: mmkvService,
        packageInfo: packageInfo,
      );

      final versionInfo = await migrationService.getCurrentVersion();
      expect(versionInfo.current, '4.0.0-beta.1');
      expect(versionInfo.lastRun, '1.0.0+12');
      expect(versionInfo.isFirstRun, isFalse);
      expect(versionInfo.hasVersionChanged, isTrue);
    });
  });
}

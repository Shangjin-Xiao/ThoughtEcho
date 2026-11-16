// 应用轻量配置 KV 存储服务与纯 Dart MMKV 迁移引擎
//
// 策略：
// 1. 主存储全面使用 SharedPreferences（内存热缓存 0ns 同步读取 + 异步持久化），
//    无任何原生 MMKV C++/FFI 依赖。
// 2. 双通道幂等迁移：
//    - 通道 1：纯 Dart `MmkvBinaryReader` 直接解析遗留 `mmkv.default` 二进制文件与 CRC 校验
//    - 通道 2：SQLite `thoughtecho.db` 启发式自愈（保障老用户绝不误触发全新安装向导）
// 3. 迁移完成后立即清理或归档遗留 `mmkv.default` 文件（含明文 API Key 时直接擦除，否则重命名为 `.migrated.bak`）。
// 4. 提供开发者设置「MMKV 迁移与解析诊断」所需的完整两方比对报告 (`MmkvDiagnosticReport`)。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;

import '../utils/app_logger.dart';
import '../utils/mmkv_binary_reader.dart';
import '../utils/platform_helper.dart';

/// 标记 KV 存储引擎已完成从 MMKV 到 SharedPreferences 主存储的迁移。
const String kKvEngineMigratedKey = 'kv_engine_migrated_v1';

/// 记录在部分失败的冷升级迁移中已成功落盘的键集合，避免重试时覆盖用户在降级期间更新的值。
const String _kKvPartialMigratedKeysKey = 'kv_engine_migrated_keys_v1';

/// 兼容旧版 SettingsService 的迁移完成标记键。
const String kLegacyMmkvMigrationCompleteKey = 'mmkv_migration_complete';

/// 标记笔记草稿已从 KV 存储迁移至独立 SQLite `drafts.db`。
const String kDraftsSqliteMigratedKey = 'drafts_sqlite_migrated_v1';

/// 标记周期洞察历史已从 KV 存储迁移至 `ai_analyses.db`。
const String kPeriodicInsightsSqliteMigratedKey =
    'periodic_insights_sqlite_migrated_v1';

/// 判断键是否已由 SQLite 接管并从 KV 存储退役。
bool isKvKeyRetiredToSqlite(
  String key, {
  required bool draftsMigrated,
  required bool periodicInsightsMigrated,
}) {
  if (draftsMigrated && key.startsWith('draft_')) {
    return true;
  }
  if (periodicInsightsMigrated && key == 'periodic_insights_history') {
    return true;
  }
  return false;
}

/// 最近一次迁移执行的统计快照。
class MmkvMigrationSnapshot {
  final DateTime migratedAt;
  final bool wasAlreadyMigrated;
  final int migratedFromBinaryCount;
  final int healedFromSqliteCount;
  final int preservedSharedPrefsOnlyCount;
  final String? primaryMmkvFilePath;
  final int migrationDurationMicroseconds;
  final List<String> warnings;

  const MmkvMigrationSnapshot({
    required this.migratedAt,
    required this.wasAlreadyMigrated,
    required this.migratedFromBinaryCount,
    required this.healedFromSqliteCount,
    required this.preservedSharedPrefsOnlyCount,
    required this.primaryMmkvFilePath,
    required this.migrationDurationMicroseconds,
    required this.warnings,
  });

  Map<String, Object?> toJson() => {
        'migratedAt': migratedAt.toIso8601String(),
        'wasAlreadyMigrated': wasAlreadyMigrated,
        'migratedFromBinaryCount': migratedFromBinaryCount,
        'healedFromSqliteCount': healedFromSqliteCount,
        'preservedSharedPrefsOnlyCount': preservedSharedPrefsOnlyCount,
        'primaryMmkvFilePath': primaryMmkvFilePath,
        'migrationDurationMicroseconds': migrationDurationMicroseconds,
        'warnings': warnings,
      };
}

/// 单个键在「纯 Dart 二进制解析器」与「SharedPreferences」两方中的比对条目。
class MmkvKeyComparisonEntry {
  final String key;
  final String valueType;
  final bool presentInBinary;
  final bool presentInSharedPrefs;
  final Object? binaryValue;
  final Object? sharedPrefsValue;
  final bool binaryMatchesSharedPrefs;
  final bool allConsistent;

  const MmkvKeyComparisonEntry({
    required this.key,
    required this.valueType,
    required this.presentInBinary,
    required this.presentInSharedPrefs,
    required this.binaryValue,
    required this.sharedPrefsValue,
    required this.binaryMatchesSharedPrefs,
    required this.allConsistent,
  });

  Map<String, Object?> toRedactedJson() => {
        'key': key,
        'valueType': valueType,
        'presentInBinary': presentInBinary,
        'presentInSharedPrefs': presentInSharedPrefs,
        'binaryValue': _redactSensitiveValue(key, binaryValue),
        'sharedPrefsValue': _redactSensitiveValue(key, sharedPrefsValue),
        'binaryMatchesSharedPrefs': binaryMatchesSharedPrefs,
        'allConsistent': allConsistent,
      };
}

/// 开发者诊断页面使用的完整两方比对与解析诊断报告。
class MmkvDiagnosticReport {
  final DateTime generatedAt;
  final String platformName;
  final int pointerBits;
  final bool is64BitProcess;
  final bool kvEngineMigrated;
  final MmkvMigrationSnapshot? migrationSnapshot;
  final MmkvParseResult primaryBinaryResult;
  final MmkvParseResult? secondaryBinaryResult;
  final List<MmkvKeyComparisonEntry> comparisons;
  final int consistentCount;
  final int diffCount;

  const MmkvDiagnosticReport({
    required this.generatedAt,
    required this.platformName,
    required this.pointerBits,
    required this.is64BitProcess,
    required this.kvEngineMigrated,
    required this.migrationSnapshot,
    required this.primaryBinaryResult,
    required this.secondaryBinaryResult,
    required this.comparisons,
    required this.consistentCount,
    required this.diffCount,
  });

  Map<String, Object?> toRedactedJson() {
    final secondary = secondaryBinaryResult;
    return {
      'generatedAt': generatedAt.toIso8601String(),
      'platformName': platformName,
      'pointerBits': pointerBits,
      'is64BitProcess': is64BitProcess,
      'kvEngineMigrated': kvEngineMigrated,
      'migrationSnapshot': migrationSnapshot?.toJson(),
      'primaryBinaryFile': {
        'fileExists': primaryBinaryResult.fileExists,
        'filePath': primaryBinaryResult.filePath,
        'fileByteLength': primaryBinaryResult.fileByteLength,
        'actualSize': primaryBinaryResult.actualSize,
        'itemSizeHolder': primaryBinaryResult.itemSizeHolder,
        'computedCrc32':
            '0x${primaryBinaryResult.computedCrc32.toRadixString(16)}',
        'crcMatched': primaryBinaryResult.crcMatched,
        'usedLastConfirmed': primaryBinaryResult.usedLastConfirmed,
        'crcMeta': primaryBinaryResult.crcMeta?.toJson(),
        'entryCount': primaryBinaryResult.entries.length,
        'totalRecordsRead': primaryBinaryResult.totalRecordsRead,
        'tombstoneRecordsRead': primaryBinaryResult.tombstoneRecordsRead,
        'parseDurationMicroseconds':
            primaryBinaryResult.parseDurationMicroseconds,
        'warnings': primaryBinaryResult.warnings,
      },
      if (secondary != null && secondary.fileExists)
        'secondaryBinaryFile': {
          'fileExists': secondary.fileExists,
          'filePath': secondary.filePath,
          'fileByteLength': secondary.fileByteLength,
          'actualSize': secondary.actualSize,
          'entryCount': secondary.entries.length,
          'crcMatched': secondary.crcMatched,
          'warnings': secondary.warnings,
        },
      'consistentCount': consistentCount,
      'diffCount': diffCount,
      'comparisons': comparisons.map((e) => e.toRedactedJson()).toList(),
    };
  }
}

Object? _redactSensitiveValue(String key, Object? value) {
  if (value == null) return null;
  final lowerKey = key.toLowerCase();
  if (lowerKey.contains('api_key') ||
      lowerKey.contains('apikey') ||
      lowerKey.contains('secret') ||
      lowerKey.contains('token') ||
      lowerKey.contains('password') ||
      lowerKey.contains('cities') ||
      key == 'recent_cities_json_v1' ||
      key == 'provider_api_keys' ||
      key == 'webdav_url' ||
      key == 'webdav_username' ||
      key == 'user_nickname' ||
      key == 'device_id_v1') {
    final len = value.toString().length;
    return '***REDACTED (len=$len)***';
  }
  if (key.startsWith('draft_') ||
      key == 'periodic_insights_history' ||
      key == 'geocode_cache') {
    final str = value.toString();
    final crc = MmkvBinaryReader.computeCrc32(
      Uint8List.fromList(utf8.encode(str)),
    );
    final hexCrc = crc.toRadixString(16);
    return '<redacted content: len=${str.length}, crc32=0x$hexCrc>';
  }
  if (value is String &&
      (key == 'ai_settings' ||
          key == 'multi_ai_settings' ||
          key == 'weather_cache' ||
          value.contains('apiKey') ||
          value.contains('api_key') ||
          value.contains('latitude') ||
          value.contains('longitude'))) {
    try {
      final decoded = json.decode(value);
      return json.encode(_redactJsonStructure(decoded));
    } catch (_) {
      return '<redacted-json (len=${value.length})>';
    }
  }
  if (value is Uint8List) {
    return '<${value.length} bytes>';
  }
  return value;
}

Object? _redactJsonStructure(Object? node) {
  if (node is Map) {
    final result = <String, Object?>{};
    for (final entry in node.entries) {
      final k = entry.key.toString();
      final lower = k.toLowerCase();
      if (lower.contains('apikey') ||
          lower.contains('api_key') ||
          lower.contains('secret') ||
          lower.contains('token') ||
          lower.contains('password') ||
          lower.contains('latitude') ||
          lower.contains('longitude') ||
          lower.contains('city') ||
          lower == 'lat' ||
          lower == 'lon' ||
          lower == 'lng') {
        final strVal = entry.value?.toString() ?? '';
        result[k] = strVal.isEmpty ? '' : '***REDACTED***';
      } else {
        result[k] = _redactJsonStructure(entry.value);
      }
    }
    return result;
  }
  if (node is List) {
    return node.map(_redactJsonStructure).toList();
  }
  return node;
}

/// 应用轻量配置 KV 存储服务（SharedPreferences 主存储 + 纯 Dart MMKV 二进制迁移引擎）
class AppPreferencesService {
  static final AppPreferencesService _instance =
      AppPreferencesService._internal();

  factory AppPreferencesService() => _instance;

  StorageAdapter? _storage;
  MmkvMigrationSnapshot? _lastMigrationSnapshot;

  bool _initialized = false;
  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  // 测试注入钩子
  StorageAdapter? _testPrimaryAdapter;
  List<String>? _testCandidateMmkvFiles;
  List<String>? _testCandidateDbPaths;

  AppPreferencesService._internal();

  /// 最近一次迁移快照（供诊断页展示）
  MmkvMigrationSnapshot? get lastMigrationSnapshot => _lastMigrationSnapshot;

  /// 当前底层存储是否已完成初始化
  bool get isInitialized => _initialized;

  /// 仅供单元测试与组件测试注入自定义适配器与文件路径。
  @visibleForTesting
  void configureForTesting({
    StorageAdapter? primaryAdapter,
    List<String>? candidateMmkvFiles,
    List<String>? candidateDbPaths,
  }) {
    _testPrimaryAdapter = primaryAdapter;
    _testCandidateMmkvFiles = candidateMmkvFiles;
    _testCandidateDbPaths = candidateDbPaths;
    _initialized = false;
    _isInitializing = false;
    _initCompleter = null;
    _storage = null;
    _lastMigrationSnapshot = null;
  }

  /// 重置测试状态。
  @visibleForTesting
  void resetForTesting() => configureForTesting();

  /// 初始化 KV 存储，增加并发控制并在首次升级时执行无损迁移。
  Future<void> init() async {
    if (_initialized) return;

    if (_isInitializing) {
      await _initCompleter?.future;
      return;
    }

    _isInitializing = true;
    final completer = Completer<void>();
    completer.future.ignore();
    _initCompleter = completer;

    try {
      if (_testPrimaryAdapter != null) {
        _storage = _testPrimaryAdapter;
        await _storage!.initialize();
      } else {
        final prefsAdapter = SharedPrefsAdapter();
        await prefsAdapter.initialize();
        _storage = prefsAdapter;
      }

      // 若尚未完成引擎迁移，执行幂等迁移（迁移异常绝不降级已就绪的 SharedPreferences）
      try {
        final storage = _storage!;
        final alreadyMigrated = storage.getBool(kKvEngineMigratedKey) == true;
        if (!alreadyMigrated) {
          await _performMigration(wasAlreadyMigrated: false);
        } else {
          final files = await PlatformHelper.resolveCandidateMmkvFiles(
            customPaths: _testCandidateMmkvFiles,
          );
          final cleanupWarnings = await _wipeResidualCredentialMmkvFiles(files);
          final primaryPath = files.isNotEmpty ? files.first : null;
          _lastMigrationSnapshot = MmkvMigrationSnapshot(
            migratedAt: DateTime.now(),
            wasAlreadyMigrated: true,
            migratedFromBinaryCount: 0,
            healedFromSqliteCount: 0,
            preservedSharedPrefsOnlyCount: storage.getKeys().length,
            primaryMmkvFilePath: primaryPath,
            migrationDurationMicroseconds: 0,
            warnings: cleanupWarnings,
          );
        }
      } catch (e, stackTrace) {
        logError(
          'AppPreferencesService: 迁移过程发生异常，保留 SharedPreferences 主存储: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }

      _initialized = true;
      _isInitializing = false;
      completer.complete();
      logDebug('AppPreferencesService 已初始化（SharedPreferences 引擎）');
    } catch (e, stackTrace) {
      _isInitializing = false;
      _storage = null;
      logError(
        '初始化 AppPreferencesService 失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'AppPreferencesService',
      );
      if (!completer.isCompleted) {
        completer.completeError(e, stackTrace);
      }
      rethrow;
    }
  }

  /// 初始化存储的兼容别名。
  Future<void> initialize() => init();

  /// 确保已初始化，支持自动初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  /// 刷新跨 Isolate 的最新持久化数据
  Future<void> reload() async {
    await _ensureInitialized();
    final storage = _storage;
    if (storage is SharedPrefsAdapter) {
      await storage.reload();
    }
  }

  /// 手动或自动执行从遗留 MMKV 二进制文件与 SQLite 自愈到 SharedPreferences 的幂等迁移。
  Future<MmkvMigrationSnapshot> runMigration({bool force = false}) async {
    await _ensureInitialized();
    final alreadyMigrated = _storage!.getBool(kKvEngineMigratedKey) == true;
    if (!force && alreadyMigrated && _lastMigrationSnapshot != null) {
      return _lastMigrationSnapshot!;
    }
    return _performMigration(wasAlreadyMigrated: alreadyMigrated);
  }

  /// 对已迁移安装，幂等擦除仍滞留磁盘且包含明文或历史凭据的遗留 `mmkv.default` / `.migrated.bak`。
  Future<List<String>> _wipeResidualCredentialMmkvFiles(
    List<String> candidateFiles,
  ) async {
    final warnings = <String>[];
    for (final path in candidateFiles) {
      final activeRes = await MmkvBinaryReader.parseFile(
        path,
        allowMigratedBackupFallback: false,
      );
      if (activeRes.fileExists && _shouldWipeMmkvFile(activeRes)) {
        final ok = await PlatformHelper.archiveOrWipeMmkvFile(
          activeRes.filePath,
          wipePlaintext: true,
        );
        if (!ok &&
            await PlatformHelper.readFileBytesIfExists(activeRes.filePath) !=
                null) {
          warnings.add(
            'Failed to wipe credential-bearing legacy MMKV file at ${activeRes.filePath}.',
          );
        }
      }

      if (!path.endsWith('.migrated.bak')) {
        final bakPath = '$path.migrated.bak';
        final bakRes = await MmkvBinaryReader.parseFile(
          bakPath,
          allowMigratedBackupFallback: false,
        );
        if (bakRes.fileExists && _shouldWipeMmkvFile(bakRes)) {
          final ok = await PlatformHelper.archiveOrWipeMmkvFile(
            bakPath,
            wipePlaintext: true,
          );
          if (!ok &&
              await PlatformHelper.readFileBytesIfExists(bakPath) != null) {
            warnings.add(
              'Failed to wipe credential-bearing backup file at $bakPath.',
            );
          }
        }
      }
    }
    return warnings;
  }

  /// 按优先级扫描候选 `mmkv.default` 文件，选择首个通过 CRC 校验且含有效数据的文件作为主二进制源。
  Future<_BinaryCandidateSelection> _selectBinaryCandidates(
    List<String> candidateFiles, {
    bool allowMigratedBackupFallback = false,
  }) async {
    if (candidateFiles.isEmpty) {
      return _BinaryCandidateSelection(
        validCandidates: const [],
        primary: MmkvParseResult.notFound('<unavailable>'),
        secondary: null,
        warnings: <String>[],
      );
    }

    final validCandidates = <MmkvParseResult>[];
    final existingInvalid = <MmkvParseResult>[];
    final warnings = <String>[];

    for (final path in candidateFiles) {
      final res = await MmkvBinaryReader.parseFile(
        path,
        allowMigratedBackupFallback: allowMigratedBackupFallback,
      );
      if (!res.fileExists) continue;
      warnings.addAll(res.warnings);

      final isValidData = res.crcMatched != false &&
          res.actualSize > 4 &&
          (res.entries.isNotEmpty || res.tombstonedKeys.isNotEmpty);
      if (isValidData) {
        validCandidates.add(res);
      } else {
        existingInvalid.add(res);
      }
    }

    if (validCandidates.isNotEmpty) {
      final primary = validCandidates.first;
      final secondary = validCandidates.length > 1
          ? validCandidates[1]
          : (existingInvalid.isNotEmpty ? existingInvalid.first : null);
      return _BinaryCandidateSelection(
        validCandidates: validCandidates,
        primary: primary,
        secondary: secondary,
        warnings: warnings,
      );
    }
    if (existingInvalid.isNotEmpty) {
      return _BinaryCandidateSelection(
        validCandidates: const [],
        primary: existingInvalid.first,
        secondary: existingInvalid.length > 1 ? existingInvalid[1] : null,
        warnings: warnings,
      );
    }
    return _BinaryCandidateSelection(
      validCandidates: const [],
      primary: MmkvParseResult.notFound(candidateFiles.first),
      secondary: null,
      warnings: warnings,
    );
  }

  Future<MmkvMigrationSnapshot> _performMigration({
    required bool wasAlreadyMigrated,
  }) async {
    final stopwatch = Stopwatch()..start();
    final storage = _storage!;
    final existingSpKeys = storage.getKeys();

    // 通道 1：纯 Dart 二进制解析器扫描候选 `mmkv.default` 文件
    final candidateFiles = await PlatformHelper.resolveCandidateMmkvFiles(
      customPaths: _testCandidateMmkvFiles,
    );
    final selected = await _selectBinaryCandidates(
      candidateFiles,
      allowMigratedBackupFallback: false,
    );
    final primaryBinary = selected.primary;
    final warnings = List<String>.from(selected.warnings);

    final binaryMergedEntries = <String, Object?>{};
    final tombstones = <String>{};
    final processedCandidates = <MmkvParseResult>[];
    String? activeMmkvPath;

    final candidatesToMerge = selected.validCandidates.isNotEmpty
        ? selected.validCandidates
        : (primaryBinary.fileExists
            ? [primaryBinary]
            : const <MmkvParseResult>[]);

    for (final candidate in candidatesToMerge) {
      if (candidate.crcMatched == false ||
          candidate.actualSize <= 4 ||
          (candidate.entries.isEmpty && candidate.tombstonedKeys.isEmpty)) {
        continue;
      }
      processedCandidates.add(candidate);
      activeMmkvPath ??= candidate.filePath;
      for (final entry in candidate.entries.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value != null &&
            !binaryMergedEntries.containsKey(key) &&
            !tombstones.contains(key)) {
          binaryMergedEntries[key] = value;
        }
      }
      tombstones.addAll(candidate.tombstonedKeys);
    }

    final draftsMigrated = storage.getBool(kDraftsSqliteMigratedKey) == true;
    final periodicInsightsMigrated =
        storage.getBool(kPeriodicInsightsSqliteMigratedKey) == true;

    final previouslyMigratedKeys = (!wasAlreadyMigrated
            ? (storage.getStringList(_kKvPartialMigratedKeysKey) ??
                const <String>[])
            : const <String>[])
        .toSet();
    final newlySucceededKeys = <String>{...previouslyMigratedKeys};

    var migratedFromBinaryCount = 0;
    var allRequiredWritesSucceeded = true;

    for (final entry in binaryMergedEntries.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;

      if (isKvKeyRetiredToSqlite(
        key,
        draftsMigrated: draftsMigrated,
        periodicInsightsMigrated: periodicInsightsMigrated,
      )) {
        continue;
      }

      // 若已完成过首次迁移，或该键在上一轮部分失败的迁移中已成功写入，则保留主存中的最新值
      if ((wasAlreadyMigrated && existingSpKeys.contains(key)) ||
          (!wasAlreadyMigrated && previouslyMigratedKeys.contains(key))) {
        continue;
      }

      final written = await _writeTypedToAdapter(storage, key, value);
      if (written) {
        migratedFromBinaryCount++;
        newlySucceededKeys.add(key);
      } else {
        allRequiredWritesSucceeded = false;
        warnings.add(
          'Failed to persist migrated key "$key" to SharedPreferences.',
        );
      }
    }

    // 应用已确认的 MMKV tombstone 删除记录，避免切换主存后已删除的键在 SharedPreferences 中复活
    if (!wasAlreadyMigrated) {
      for (final tombstoneKey in tombstones) {
        if (!binaryMergedEntries.containsKey(tombstoneKey)) {
          if (previouslyMigratedKeys.contains(tombstoneKey)) {
            continue;
          }
          final removed = await storage.remove(tombstoneKey);
          if (removed) {
            newlySucceededKeys.add(tombstoneKey);
          } else {
            allRequiredWritesSucceeded = false;
            warnings.add(
              'Failed to apply tombstone deletion for key "$tombstoneKey".',
            );
          }
        }
      }
    }

    // Channel 3：SQLite `thoughtecho.db` 启发式老用户自愈
    var healedFromSqliteCount = 0;
    final needsOnboardingHeal = storage.getBool('app_installed_v2') != true;
    if (needsOnboardingHeal) {
      final customDir = storage.getString('custom_data_directory_path');
      final dbPaths = _testCandidateDbPaths;
      final hasDb = await PlatformHelper.hasPopulatedThoughtEchoDatabase(
        customDbPaths: dbPaths,
        customDataDirectoryPath: customDir,
      );
      if (hasDb) {
        // 确保 app_settings 中的 hasCompletedOnboarding 为 true，保留已有 sentryDisclosureShown
        Map<String, Object?> appSettingsMap = {
          'hitokotoType': 'a,b,c,d,e,f,g,h,i,j,k,l',
          'dailyQuoteProvider': 'hitokoto',
          'defaultStartPage': 0,
          'hasCompletedOnboarding': true,
          'sentryDisclosureShown': true,
        };
        final existingJson = storage.getString('app_settings');
        if (existingJson != null && existingJson.isNotEmpty) {
          try {
            final decoded = json.decode(existingJson);
            if (decoded is Map) {
              final existingMap = Map<String, Object?>.from(decoded);
              final hasSentry = existingMap.containsKey(
                'sentryDisclosureShown',
              );
              appSettingsMap = {
                ...appSettingsMap,
                ...existingMap,
                'hasCompletedOnboarding': true,
                if (!hasSentry) 'sentryDisclosureShown': true,
              };
            }
          } catch (_) {}
        }
        final patchedAppSettingsJson = json.encode(appSettingsMap);

        var healedWrites = 0;
        var healSucceeded = true;
        for (final flagKey in const [
          'app_installed_v2',
          'initial_database_setup_complete',
          'database_migration_complete',
          'hasCompletedOnboarding',
        ]) {
          if (await storage.setBool(flagKey, true)) {
            healedWrites++;
          } else {
            healSucceeded = false;
          }
        }
        if (await storage.setString('app_settings', patchedAppSettingsJson)) {
          healedWrites++;
        } else {
          healSucceeded = false;
        }
        healedFromSqliteCount = healedWrites;
        if (!healSucceeded) {
          allRequiredWritesSucceeded = false;
          warnings.add('SQLite heuristic healing partially failed.');
        } else {
          logDebug(
            'AppPreferencesService: 检测到非空 thoughtecho.db，已自动自愈安装、数据库初始化与引导完成标记',
          );
        }
      }
    }

    if (allRequiredWritesSucceeded) {
      // 先归档或擦除已处理的 MMKV 二进制文件，全部完成后再写入完成水位线
      var cleanupSucceeded = true;
      for (final candidate in processedCandidates) {
        if (candidate.fileExists) {
          final wipedOrArchived = await PlatformHelper.archiveOrWipeMmkvFile(
            candidate.filePath,
            wipePlaintext: _shouldWipeMmkvFile(candidate),
          );
          if (!wipedOrArchived &&
              await PlatformHelper.readFileBytesIfExists(candidate.filePath) !=
                  null) {
            cleanupSucceeded = false;
            warnings.add(
              'Failed to archive or wipe legacy MMKV file at ${candidate.filePath}.',
            );
          }
        }
      }
      if (cleanupSucceeded) {
        await storage.remove(_kKvPartialMigratedKeysKey);
        // 标记迁移完成（同时写入新旧两个标记键，防止 SettingsService._migrateDataIfNeeded 逆向覆盖）
        final legacyMarkOk = await storage.setBool(
          kLegacyMmkvMigrationCompleteKey,
          true,
        );
        final engineMarkOk = await storage.setBool(kKvEngineMigratedKey, true);
        if (!legacyMarkOk || !engineMarkOk) {
          warnings.add('Failed to persist migration completion watermark.');
        }
      } else {
        if (!wasAlreadyMigrated && newlySucceededKeys.isNotEmpty) {
          await storage.setStringList(
            _kKvPartialMigratedKeysKey,
            newlySucceededKeys.toList()..sort(),
          );
        }
        warnings.add(
          'Skipped migration completion watermark because legacy MMKV cleanup did not finish.',
        );
      }
    } else {
      if (!wasAlreadyMigrated && newlySucceededKeys.isNotEmpty) {
        await storage.setStringList(
          _kKvPartialMigratedKeysKey,
          newlySucceededKeys.toList()..sort(),
        );
      }
      warnings.add(
        'Skipped migration completion watermark and legacy file cleanup due to partial write failure.',
      );
    }

    var preservedSpOnlyCount = 0;
    for (final k in existingSpKeys) {
      if (!binaryMergedEntries.containsKey(k)) {
        preservedSpOnlyCount++;
      }
    }

    String? fallbackPath;
    if (candidateFiles.isNotEmpty) {
      fallbackPath = candidateFiles.first;
    }
    final resolvedPrimaryPath = activeMmkvPath ?? fallbackPath;

    stopwatch.stop();
    final snapshot = MmkvMigrationSnapshot(
      migratedAt: DateTime.now(),
      wasAlreadyMigrated: wasAlreadyMigrated,
      migratedFromBinaryCount: migratedFromBinaryCount,
      healedFromSqliteCount: healedFromSqliteCount,
      preservedSharedPrefsOnlyCount: preservedSpOnlyCount,
      primaryMmkvFilePath: resolvedPrimaryPath,
      migrationDurationMicroseconds: stopwatch.elapsedMicroseconds,
      warnings: warnings,
    );
    _lastMigrationSnapshot = snapshot;
    return snapshot;
  }

  static bool _shouldWipeMmkvFile(MmkvParseResult candidate) {
    if (_containsPlaintextApiKeys(candidate.entries)) {
      return true;
    }
    if (candidate.hasHistoricalPlaintextCredentials) {
      return true;
    }
    bool isCredentialKey(String key) {
      final lower = key.toLowerCase();
      return lower == 'provider_api_keys' ||
          lower == 'ai_settings' ||
          lower == 'multi_ai_settings' ||
          lower.contains('api_key') ||
          lower.contains('apikey');
    }

    if (candidate.tombstonedKeys.any(isCredentialKey)) {
      return true;
    }
    return candidate.seenKeys.any((key) {
      final lower = key.toLowerCase();
      return lower == 'provider_api_keys' ||
          lower.contains('api_key') ||
          lower.contains('apikey');
    });
  }

  static bool _containsPlaintextApiKeys(Map<String, Object?> entries) {
    final providerApiKeys = entries['provider_api_keys'];
    if (providerApiKeys is String) {
      final trimmed = providerApiKeys.trim();
      if (trimmed.isNotEmpty && trimmed != '{}') {
        return true;
      }
    }

    for (final entry in entries.entries) {
      if (entry.key == 'provider_api_keys') {
        continue;
      }
      final lowerKey = entry.key.toLowerCase();
      if (lowerKey.contains('api_key') || lowerKey.contains('apikey')) {
        final val = entry.value;
        if (val is String && val.trim().isNotEmpty) {
          return true;
        }
      }
    }

    for (final settingsKey in const ['ai_settings', 'multi_ai_settings']) {
      final raw = entries[settingsKey];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (_jsonContainsNonEmptyApiKey(decoded)) {
            return true;
          }
        } catch (_) {}
      }
    }

    return false;
  }

  static bool _jsonContainsNonEmptyApiKey(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final k = entry.key.toString();
        if ((k == 'apiKey' || k == 'api_key') &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty) {
          return true;
        }
        if (_jsonContainsNonEmptyApiKey(entry.value)) {
          return true;
        }
      }
    } else if (node is List) {
      for (final item in node) {
        if (_jsonContainsNonEmptyApiKey(item)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 根据 `MmkvKeySchema` 或回退线索从适配器读取带类型的值。
  Object? _readTypedFromAdapter(
    StorageAdapter adapter,
    String key, {
    Object? fallbackHint,
  }) {
    final schemaType = MmkvKeySchema.typeForKey(key);
    try {
      switch (schemaType) {
        case MmkvValueType.boolValue:
          return adapter.getBool(key);
        case MmkvValueType.intValue:
          return adapter.getInt(key);
        case MmkvValueType.doubleValue:
          return adapter.getDouble(key);
        case MmkvValueType.stringList:
          return adapter.getStringList(key);
        case MmkvValueType.string:
          return adapter.getString(key);
        case MmkvValueType.rawBytes:
        case null:
          break;
      }

      if (fallbackHint is bool) return adapter.getBool(key);
      if (fallbackHint is int) return adapter.getInt(key);
      if (fallbackHint is double) return adapter.getDouble(key);
      if (fallbackHint is List<String>) return adapter.getStringList(key);
      if (fallbackHint is String) return adapter.getString(key);

      // 针对 SharedPrefsAdapter，可直接读取底层动态类型
      if (adapter is SharedPrefsAdapter) {
        return adapter.getDynamic(key);
      }

      // 针对未知键的回退读取
      final strVal = adapter.getString(key);
      if (strVal != null && strVal.isNotEmpty) {
        return strVal;
      }
      return adapter.getInt(key);
    } catch (_) {
      return null;
    }
  }

  /// 将动态值按真实类型写入目标 [StorageAdapter]。
  Future<bool> _writeTypedToAdapter(
    StorageAdapter adapter,
    String key,
    Object value,
  ) async {
    try {
      if (value is Uint8List) {
        return false;
      }
      final schemaType = MmkvKeySchema.typeForKey(key);
      if (schemaType == MmkvValueType.stringList) {
        if (value is List<String>) {
          return await adapter.setStringList(key, value);
        } else if (value is List) {
          return await adapter.setStringList(
            key,
            value.map((e) => e.toString()).toList(),
          );
        } else if (value is String) {
          try {
            final decoded = json.decode(value);
            if (decoded is List) {
              return await adapter.setStringList(
                key,
                decoded.map((e) => e.toString()).toList(),
              );
            }
          } catch (_) {}
          return await adapter.setStringList(key, <String>[value]);
        }
      }

      if (value is bool) {
        return await adapter.setBool(key, value);
      }
      if (value is int) {
        return await adapter.setInt(key, value);
      }
      if (value is double) {
        return await adapter.setDouble(key, value);
      }
      if (value is String) {
        return await adapter.setString(key, value);
      }
      if (value is List<String>) {
        return await adapter.setStringList(key, value);
      }
      if (value is List) {
        return await adapter.setStringList(
          key,
          value.map((e) => e.toString()).toList(),
        );
      }
      return false;
    } catch (e) {
      logDebug('AppPreferencesService: 写入键 "$key" 失败: $e');
      return false;
    }
  }

  /// 生成开发者设置「MMKV 迁移与解析诊断」页面的完整比对报告。
  Future<MmkvDiagnosticReport> collectDiagnosticReport() async {
    await init();
    final storage = _storage!;

    final candidateFiles = await PlatformHelper.resolveCandidateMmkvFiles(
      customPaths: _testCandidateMmkvFiles,
    );
    final selected = await _selectBinaryCandidates(
      candidateFiles,
      allowMigratedBackupFallback: true,
    );
    final primaryBinaryResult = selected.primary;
    final secondaryBinaryResult = selected.secondary;

    final binaryEntries = primaryBinaryResult.entries;
    final spKeys = storage.getKeys();
    final draftsMigrated = storage.getBool(kDraftsSqliteMigratedKey) == true;
    final periodicInsightsMigrated =
        storage.getBool(kPeriodicInsightsSqliteMigratedKey) == true;

    final allKeys = <String>{
      ...binaryEntries.keys,
      ...spKeys,
    }.where((k) => k.isNotEmpty).toList();
    allKeys.sort();

    final comparisons = <MmkvKeyComparisonEntry>[];
    var consistentCount = 0;
    var diffCount = 0;

    for (final key in allKeys) {
      final retiredToSqlite = isKvKeyRetiredToSqlite(
        key,
        draftsMigrated: draftsMigrated,
        periodicInsightsMigrated: periodicInsightsMigrated,
      );
      final presentInBinary = binaryEntries.containsKey(key);
      final binaryVal = binaryEntries[key];

      final presentInSp = spKeys.contains(key);
      Object? spVal;
      if (presentInSp) {
        spVal = _readTypedFromAdapter(storage, key, fallbackHint: binaryVal);
      }

      final sampleVal = spVal ?? binaryVal;
      final valueType = _describeValueType(key, sampleVal);

      bool binaryMatchesSp;
      if (retiredToSqlite && !presentInSp) {
        binaryMatchesSp = true;
      } else if (presentInBinary) {
        binaryMatchesSp = _valuesEqual(binaryVal, spVal);
      } else {
        binaryMatchesSp = presentInSp;
      }

      // 判断该键在两方存储源中是否一致：
      // 1. 若该键已由 SQLite 接管且已从 SP 清理，仅残留于历史只读二进制文件，视为一致；
      // 2. 若二进制文件中有该键，SharedPreferences 中必须存在且值完全相等；
      // 3. 若某键仅存在于 SharedPreferences，视为一致。
      final allConsistent = binaryMatchesSp;

      if (allConsistent) {
        consistentCount++;
      } else {
        diffCount++;
      }

      comparisons.add(
        MmkvKeyComparisonEntry(
          key: key,
          valueType: valueType,
          presentInBinary: presentInBinary,
          presentInSharedPrefs: presentInSp,
          binaryValue: binaryVal,
          sharedPrefsValue: spVal,
          binaryMatchesSharedPrefs: binaryMatchesSp,
          allConsistent: allConsistent,
        ),
      );
    }

    return MmkvDiagnosticReport(
      generatedAt: DateTime.now(),
      platformName: _currentPlatformName(),
      pointerBits: PlatformHelper.pointerBits,
      is64BitProcess: PlatformHelper.is64BitProcess,
      kvEngineMigrated: storage.getBool(kKvEngineMigratedKey) == true,
      migrationSnapshot: _lastMigrationSnapshot,
      primaryBinaryResult: primaryBinaryResult,
      secondaryBinaryResult: secondaryBinaryResult,
      comparisons: comparisons,
      consistentCount: consistentCount,
      diffCount: diffCount,
    );
  }

  static String _currentPlatformName() {
    if (kIsWeb) return 'Web';
    if (PlatformHelper.isAndroid) return 'Android';
    if (PlatformHelper.isIOS) return 'iOS';
    if (PlatformHelper.isWindows) return 'Windows';
    if (PlatformHelper.isMacOS) return 'macOS';
    if (PlatformHelper.isLinux) return 'Linux';
    return 'Unknown';
  }

  static String _describeValueType(String key, Object? sample) {
    final schemaType = MmkvKeySchema.typeForKey(key);
    switch (schemaType) {
      case MmkvValueType.boolValue:
        return 'bool';
      case MmkvValueType.intValue:
        return 'int';
      case MmkvValueType.doubleValue:
        return 'double';
      case MmkvValueType.stringList:
        return 'List<String>';
      case MmkvValueType.string:
        return 'String';
      case MmkvValueType.rawBytes:
      case null:
        break;
    }
    if (sample is bool) return 'bool';
    if (sample is int) return 'int';
    if (sample is double) return 'double';
    if (sample is List) return 'List<String>';
    if (sample is String) return 'String';
    if (sample is Uint8List) return 'bytes';
    return 'unknown';
  }

  static bool _valuesEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].toString() != b[i].toString()) return false;
      }
      return true;
    }
    if (a is List && b is String) {
      try {
        final decodedB = json.decode(b);
        if (decodedB is List) {
          return _valuesEqual(a, decodedB);
        }
      } catch (_) {}
    }
    if (a is String && b is List) {
      return _valuesEqual(b, a);
    }
    if (a is double && b is double) {
      if (a.isNaN && b.isNaN) return true;
      return (a - b).abs() < 1e-9;
    }
    if (a is num && b is num) {
      return a == b;
    }
    if (a is Uint8List && b is Uint8List) {
      return listEquals(a, b);
    }
    return a == b;
  }

  /// 带重试机制的操作执行器
  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries - 1) {
          logDebug('KV操作失败，已重试$maxRetries次: $e');
          rethrow;
        }
        logDebug('KV操作失败，第${attempt + 1}次重试: $e');
        await Future.delayed(delay * (attempt + 1));
      }
    }
    throw Exception('操作重试失败');
  }

  /// 存储字符串值，增加重试机制
  Future<bool> setString(String key, String value) async {
    await _ensureInitialized();
    return _executeWithRetry(() async {
      return await _storage!.setString(key, value);
    });
  }

  /// 获取字符串值
  String? getString(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取字符串值');
        return null;
      }
      return _storage!.getString(key);
    } catch (e) {
      logDebug('KV获取字符串失败: $e');
      return null;
    }
  }

  /// 存储布尔值
  Future<bool> setBool(String key, bool value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setBool(key, value);
    } catch (e) {
      logDebug('KV保存布尔值失败: $e');
      return false;
    }
  }

  /// 获取布尔值
  bool? getBool(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取布尔值');
        return null;
      }
      return _storage!.getBool(key);
    } catch (e) {
      logDebug('KV获取布尔值失败: $e');
      return null;
    }
  }

  /// 存储整数值
  Future<bool> setInt(String key, int value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setInt(key, value);
    } catch (e) {
      logDebug('KV保存整数值失败: $e');
      return false;
    }
  }

  /// 获取整数值
  int? getInt(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取整数值');
        return null;
      }
      return _storage!.getInt(key);
    } catch (e) {
      logDebug('KV获取整数值失败: $e');
      return null;
    }
  }

  /// 存储双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setDouble(key, value);
    } catch (e) {
      logDebug('KV保存浮点值失败: $e');
      return false;
    }
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取浮点值');
        return null;
      }
      return _storage!.getDouble(key);
    } catch (e) {
      logDebug('KV获取浮点值失败: $e');
      return null;
    }
  }

  /// 存储字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setStringList(key, value);
    } catch (e) {
      logDebug('KV保存字符串列表失败: $e');
      return false;
    }
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取字符串列表');
        return null;
      }
      return _storage!.getStringList(key);
    } catch (e) {
      logDebug('KV获取字符串列表失败: $e');
      return null;
    }
  }

  /// 存储JSON对象（Map或List）
  Future<bool> setJson(String key, dynamic value) async {
    await _ensureInitialized();
    try {
      final jsonStr = json.encode(value);
      return await setString(key, jsonStr);
    } catch (e) {
      logDebug('KV保存JSON对象失败: $e');
      return false;
    }
  }

  /// 获取JSON对象
  dynamic getJson(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取JSON对象');
        return null;
      }
      final jsonStr = getString(key);
      if (jsonStr == null) return null;
      return json.decode(jsonStr);
    } catch (e) {
      logDebug('KV获取JSON对象失败: $e');
      return null;
    }
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法检查键');
        return false;
      }
      return _storage!.containsKey(key);
    } catch (e) {
      logDebug('KV检查键失败: $e');
      return false;
    }
  }

  /// 删除指定键的值
  Future<bool> remove(String key) async {
    await _ensureInitialized();
    try {
      return await _storage!.remove(key);
    } catch (e) {
      logDebug('KV删除键失败: $e');
      return false;
    }
  }

  /// 清除所有存储的值（保留迁移完成水位线与已接管的 SQLite 迁移标记）
  Future<bool> clear() async {
    await _ensureInitialized();
    try {
      final storage = _storage!;
      final preserveDraftsMigrated =
          storage.getBool(kDraftsSqliteMigratedKey) == true;
      final preserveInsightsMigrated =
          storage.getBool(kPeriodicInsightsSqliteMigratedKey) == true;
      final result = await storage.clear();
      var restoredOk = await storage.setBool(
        kLegacyMmkvMigrationCompleteKey,
        true,
      );
      restoredOk =
          await storage.setBool(kKvEngineMigratedKey, true) && restoredOk;
      if (preserveDraftsMigrated) {
        restoredOk =
            await storage.setBool(kDraftsSqliteMigratedKey, true) && restoredOk;
      }
      if (preserveInsightsMigrated) {
        restoredOk =
            await storage.setBool(kPeriodicInsightsSqliteMigratedKey, true) &&
                restoredOk;
      }
      return result && restoredOk;
    } catch (e) {
      logDebug('KV清除所有数据失败: $e');
      return false;
    }
  }

  /// 获取所有键
  List<String> getAllKeys() {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取所有键');
        return [];
      }
      final keys = _storage!.getKeys();
      return keys.map((e) => e.toString()).toList();
    } catch (e) {
      logDebug('KV获取所有键失败: $e');
      return [];
    }
  }

  /// 获取所有键名集合
  Set<String> getKeys() {
    try {
      if (!_initialized || _storage == null) {
        logDebug('KV存储未初始化，无法获取所有键');
        return <String>{};
      }
      return _storage!.getKeys();
    } catch (e) {
      logDebug('KV获取所有键失败: $e');
      return <String>{};
    }
  }

  /// 严格获取所有键（未初始化或枚举失败时抛出异常，供迁移阶段避免把失败误判为空集合）
  List<String> getAllKeysStrict() {
    if (!_initialized || _storage == null) {
      throw StateError('KV存储未初始化，无法枚举所有键');
    }
    return _storage!.getKeys().map((e) => e.toString()).toList();
  }
}

class _BinaryCandidateSelection {
  final List<MmkvParseResult> validCandidates;
  final MmkvParseResult primary;
  final MmkvParseResult? secondary;
  final List<String> warnings;

  const _BinaryCandidateSelection({
    this.validCandidates = const [],
    required this.primary,
    required this.secondary,
    required this.warnings,
  });
}

/// 存储适配器接口
abstract class StorageAdapter {
  Future<void> initialize();
  Future<bool> setString(String key, String value);
  String? getString(String key);
  Future<bool> setInt(String key, int value);
  int? getInt(String key);
  Future<bool> setDouble(String key, double value);
  double? getDouble(String key);
  Future<bool> setBool(String key, bool value);
  bool? getBool(String key);
  Future<bool> setStringList(String key, List<String> value);
  List<String>? getStringList(String key);
  bool containsKey(String key);
  Future<bool> remove(String key);
  Future<bool> clear();
  Set<String> getKeys();
}

/// SharedPreferences 存储适配器（支持 StringList 与 JSON 数组的双向容错读取）
class SharedPrefsAdapter implements StorageAdapter {
  sp.SharedPreferences? _prefs;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await sp.SharedPreferences.getInstance();
    _initialized = true;
  }

  sp.SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError('SharedPrefsAdapter 尚未初始化');
    }
    return _prefs!;
  }

  /// 刷新跨 Isolate 的最新磁盘数据
  Future<void> reload() async {
    await prefs.reload();
  }

  /// 获取底层原始值（用于诊断和未知键迁移）
  Object? getDynamic(String key) {
    return prefs.get(key);
  }

  @override
  Future<bool> setString(String key, String value) {
    return prefs.setString(key, value);
  }

  @override
  String? getString(String key) {
    final raw = prefs.get(key);
    if (raw is List) return json.encode(raw);
    return prefs.getString(key);
  }

  @override
  Future<bool> setInt(String key, int value) {
    return prefs.setInt(key, value);
  }

  @override
  int? getInt(String key) {
    return prefs.getInt(key);
  }

  @override
  Future<bool> setDouble(String key, double value) {
    return prefs.setDouble(key, value);
  }

  @override
  double? getDouble(String key) {
    return prefs.getDouble(key);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    return prefs.setBool(key, value);
  }

  @override
  bool? getBool(String key) {
    return prefs.getBool(key);
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    return prefs.setStringList(key, value);
  }

  @override
  List<String>? getStringList(String key) {
    final raw = prefs.get(key);
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  bool containsKey(String key) {
    return prefs.containsKey(key);
  }

  @override
  Future<bool> remove(String key) {
    return prefs.remove(key);
  }

  @override
  Future<bool> clear() {
    return prefs.clear();
  }

  @override
  Set<String> getKeys() {
    return prefs.getKeys();
  }
}

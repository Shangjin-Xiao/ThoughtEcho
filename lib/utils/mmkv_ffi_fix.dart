// MMKV 包装类与 Phase 1 渐进式迁移引擎
//
// Phase 1 策略：
// 1. 主存储全面切换至 SharedPreferences（内存热缓存 0ns 同步读取 + 异步持久化），
//    消除冷启动 `getprop` 子进程阻塞并规避未来 Android 15/16 16KB Page Size 风险。
// 2. 过渡期保留原生 MMKV 依赖：在支持 MMKV 的 64 位 Android / iOS 设备上开启双写镜像，
//    确保过渡版本中 `mmkv.default` 始终保持最新。
// 3. 三通道幂等迁移：
//    - 通道 1：原生 MMKVAdapter 读取（若当前进程可用）
//    - 通道 2：纯 Dart `MmkvBinaryReader` 直接解析 `mmkv.default` 二进制文件与 CRC 校验
//    - 通道 3：SQLite `thoughtecho.db` 启发式自愈（保障老用户绝不误触发全新安装向导）
// 4. 提供开发者设置「MMKV 迁移与解析诊断」所需的完整三方比对报告 (`MmkvDiagnosticReport`)。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;
import 'package:thoughtecho/utils/app_logger.dart';
import 'mmkv_adapter.dart';
import 'mmkv_binary_reader.dart';
import 'platform_helper.dart';

/// 标记 KV 存储引擎已完成从 MMKV 到 SharedPreferences 主存储的迁移。
const String kKvEngineMigratedKey = 'kv_engine_migrated_v1';

/// 兼容旧版 SettingsService 的迁移完成标记键。
const String kLegacyMmkvMigrationCompleteKey = 'mmkv_migration_complete';

/// 最近一次迁移执行的统计快照。
class MmkvMigrationSnapshot {
  final DateTime migratedAt;
  final bool wasAlreadyMigrated;
  final bool nativeMmkvAvailable;
  final int migratedFromNativeCount;
  final int migratedFromBinaryCount;
  final int healedFromSqliteCount;
  final int preservedSharedPrefsOnlyCount;
  final String? primaryMmkvFilePath;
  final int migrationDurationMicroseconds;
  final List<String> warnings;

  const MmkvMigrationSnapshot({
    required this.migratedAt,
    required this.wasAlreadyMigrated,
    required this.nativeMmkvAvailable,
    required this.migratedFromNativeCount,
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
        'nativeMmkvAvailable': nativeMmkvAvailable,
        'migratedFromNativeCount': migratedFromNativeCount,
        'migratedFromBinaryCount': migratedFromBinaryCount,
        'healedFromSqliteCount': healedFromSqliteCount,
        'preservedSharedPrefsOnlyCount': preservedSharedPrefsOnlyCount,
        'primaryMmkvFilePath': primaryMmkvFilePath,
        'migrationDurationMicroseconds': migrationDurationMicroseconds,
        'warnings': warnings,
      };
}

/// 单个键在「原生 MMKV」「纯 Dart 二进制解析器」「SharedPreferences」三方中的比对条目。
class MmkvKeyComparisonEntry {
  final String key;
  final String valueType;
  final bool presentInNative;
  final bool presentInBinary;
  final bool presentInSharedPrefs;
  final Object? nativeValue;
  final Object? binaryValue;
  final Object? sharedPrefsValue;
  final bool nativeMatchesBinary;
  final bool binaryMatchesSharedPrefs;
  final bool allConsistent;

  const MmkvKeyComparisonEntry({
    required this.key,
    required this.valueType,
    required this.presentInNative,
    required this.presentInBinary,
    required this.presentInSharedPrefs,
    required this.nativeValue,
    required this.binaryValue,
    required this.sharedPrefsValue,
    required this.nativeMatchesBinary,
    required this.binaryMatchesSharedPrefs,
    required this.allConsistent,
  });

  Map<String, Object?> toRedactedJson() => {
        'key': key,
        'valueType': valueType,
        'presentInNative': presentInNative,
        'presentInBinary': presentInBinary,
        'presentInSharedPrefs': presentInSharedPrefs,
        'nativeValue': _redactSensitiveValue(key, nativeValue),
        'binaryValue': _redactSensitiveValue(key, binaryValue),
        'sharedPrefsValue': _redactSensitiveValue(key, sharedPrefsValue),
        'nativeMatchesBinary': nativeMatchesBinary,
        'binaryMatchesSharedPrefs': binaryMatchesSharedPrefs,
        'allConsistent': allConsistent,
      };
}

/// 开发者诊断页面使用的完整三方比对与解析诊断报告。
class MmkvDiagnosticReport {
  final DateTime generatedAt;
  final String platformName;
  final int pointerBits;
  final bool is64BitProcess;
  final bool nativeMmkvAvailable;
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
    required this.nativeMmkvAvailable,
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
      'nativeMmkvAvailable': nativeMmkvAvailable,
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
          value.contains('apiKey') ||
          value.contains('api_key'))) {
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
          lower.contains('password')) {
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

/// 安全的 KV 存储包装类（Phase 1：SharedPreferences 主存 + 原生 MMKV 镜像 + 纯 Dart 解析迁移）
class SafeMMKV {
  static final SafeMMKV _instance = SafeMMKV._internal();
  factory SafeMMKV() => _instance;
  SafeMMKV._internal();

  /// 主存储适配器（默认 SharedPrefsAdapter）
  StorageAdapter? _storage;

  /// 过渡期原生 MMKV 镜像适配器（仅在支持的 64 位 Android / iOS 或测试注入时启用）
  StorageAdapter? _legacyMmkvAdapter;

  /// 最近一次迁移快照
  MmkvMigrationSnapshot? _lastMigrationSnapshot;

  bool _initialized = false;
  bool _initializing = false;
  Completer<void>? _initCompleter;

  // 测试注入钩子
  StorageAdapter? _testPrimaryAdapter;
  StorageAdapter? _testLegacyMmkvAdapter;
  List<String>? _testCandidateMmkvFiles;
  List<String>? _testCandidateDbPaths;
  bool? _testForceNativeMmkvSupport;

  /// 最近一次迁移快照（供诊断页展示）
  MmkvMigrationSnapshot? get lastMigrationSnapshot => _lastMigrationSnapshot;

  /// 当前进程是否启用了原生 MMKV 适配器镜像
  bool get isNativeMmkvActive => _legacyMmkvAdapter != null;

  /// 仅供单元测试与组件测试注入自定义适配器与文件路径。
  @visibleForTesting
  void configureForTesting({
    StorageAdapter? primaryAdapter,
    StorageAdapter? legacyMmkvAdapter,
    List<String>? candidateMmkvFiles,
    List<String>? candidateDbPaths,
    bool? forceNativeMmkvSupport,
  }) {
    _testPrimaryAdapter = primaryAdapter;
    _testLegacyMmkvAdapter = legacyMmkvAdapter;
    _testCandidateMmkvFiles = candidateMmkvFiles;
    _testCandidateDbPaths = candidateDbPaths;
    _testForceNativeMmkvSupport = forceNativeMmkvSupport;
    _initialized = false;
    _initializing = false;
    _initCompleter = null;
    _storage = null;
    _legacyMmkvAdapter = null;
    _lastMigrationSnapshot = null;
  }

  /// 重置测试状态。
  void resetForTesting() {
    configureForTesting();
  }

  /// 初始化存储并在首次升级时执行三通道无损迁移。
  Future<void> initialize() async {
    if (_initialized) return;

    if (_initializing) {
      await _initCompleter?.future;
      return;
    }

    _initializing = true;
    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      // 1. 初始化主存储（SharedPreferences）
      if (_testPrimaryAdapter != null) {
        _storage = _testPrimaryAdapter;
        await _storage!.initialize();
      } else {
        final prefsAdapter = SharedPrefsAdapter();
        await prefsAdapter.initialize();
        _storage = prefsAdapter;
      }

      // 2. 初始化过渡期原生 MMKV 适配器（仅 64 位 Android / iOS 或测试注入）
      _legacyMmkvAdapter = null;
      if (_testLegacyMmkvAdapter != null) {
        try {
          await _testLegacyMmkvAdapter!.initialize();
          _legacyMmkvAdapter = _testLegacyMmkvAdapter;
        } catch (e) {
          logDebug('SafeMMKV: 测试注入的 MMKV 适配器初始化失败: $e');
        }
      } else if (_shouldInitNativeMmkv()) {
        try {
          final mmkvAdapter = MMKVAdapter();
          await mmkvAdapter.initialize();
          _legacyMmkvAdapter = mmkvAdapter;
          logDebug('SafeMMKV: 已挂载原生 MMKVAdapter 作为过渡期双写镜像与比对源');
        } catch (e) {
          logDebug('SafeMMKV: 原生 MMKVAdapter 挂载失败，将仅使用纯 Dart 解析器: $e');
          _legacyMmkvAdapter = null;
        }
      }

      // 3. 若尚未完成引擎迁移，执行三通道幂等迁移（迁移异常绝不降级已就绪的 SharedPreferences）
      try {
        final storage = _storage!;
        final alreadyMigrated = storage.getBool(kKvEngineMigratedKey) == true;
        if (!alreadyMigrated) {
          await _performMigration(wasAlreadyMigrated: false);
        } else {
          final files = await PlatformHelper.resolveCandidateMmkvFiles(
            customPaths: _testCandidateMmkvFiles,
          );
          String? primaryPath;
          if (files.isNotEmpty) {
            primaryPath = files.first;
          }
          _lastMigrationSnapshot = MmkvMigrationSnapshot(
            migratedAt: DateTime.now(),
            wasAlreadyMigrated: true,
            nativeMmkvAvailable: _legacyMmkvAdapter != null,
            migratedFromNativeCount: 0,
            migratedFromBinaryCount: 0,
            healedFromSqliteCount: 0,
            preservedSharedPrefsOnlyCount: storage.getKeys().length,
            primaryMmkvFilePath: primaryPath,
            migrationDurationMicroseconds: 0,
            warnings: const [],
          );
        }
      } catch (e, stackTrace) {
        logError(
          'SafeMMKV: 迁移过程发生异常，保留 SharedPreferences 主存储: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }

      _initialized = true;
      completer.complete();
    } catch (e) {
      logDebug('SafeMMKV 初始化失败: $e');
      try {
        _storage = _InMemoryStorageAdapter();
        await _storage!.initialize();
        _initialized = true;
        completer.complete();
      } catch (e2) {
        completer.completeError(e2);
        rethrow;
      }
    } finally {
      _initializing = false;
    }
  }

  bool _shouldInitNativeMmkv() {
    if (_testForceNativeMmkvSupport != null) {
      return _testForceNativeMmkvSupport!;
    }
    if (kIsWeb) return false;
    if (PlatformHelper.isIOS) return true;
    if (PlatformHelper.isAndroid && PlatformHelper.is64BitProcess) {
      return true;
    }
    return false;
  }

  /// 手动或自动执行从 MMKV（原生 + 纯 Dart 二进制解析 + SQLite 自愈）到 SharedPreferences 的幂等迁移。
  Future<MmkvMigrationSnapshot> runMigration({bool force = false}) async {
    _ensureInitialized();
    final alreadyMigrated = _storage!.getBool(kKvEngineMigratedKey) == true;
    if (!force && alreadyMigrated && _lastMigrationSnapshot != null) {
      return _lastMigrationSnapshot!;
    }
    return _performMigration(wasAlreadyMigrated: alreadyMigrated);
  }

  /// 按优先级扫描候选 `mmkv.default` 文件，选择首个通过 CRC 校验且含有效数据的文件作为主二进制源。
  Future<_BinaryCandidateSelection> _selectBinaryCandidates(
    List<String> candidateFiles,
  ) async {
    if (candidateFiles.isEmpty) {
      return _BinaryCandidateSelection(
        primary: MmkvParseResult.notFound('<unavailable>'),
        secondary: null,
        warnings: <String>[],
      );
    }

    MmkvParseResult? validPrimary;
    MmkvParseResult? secondaryExisting;
    MmkvParseResult? firstExisting;
    final warnings = <String>[];

    for (final path in candidateFiles) {
      final res = await MmkvBinaryReader.parseFile(path);
      if (!res.fileExists) continue;
      firstExisting ??= res;
      warnings.addAll(res.warnings);

      final isValidData = res.crcMatched != false &&
          res.actualSize > 4 &&
          res.entries.isNotEmpty;
      if (validPrimary == null && isValidData) {
        validPrimary = res;
      } else {
        secondaryExisting ??= res;
      }
    }

    if (validPrimary != null) {
      return _BinaryCandidateSelection(
        primary: validPrimary,
        secondary: secondaryExisting,
        warnings: warnings,
      );
    }
    if (firstExisting != null) {
      final isSame = identical(secondaryExisting, firstExisting);
      final sec = isSame ? null : secondaryExisting;
      return _BinaryCandidateSelection(
        primary: firstExisting,
        secondary: sec,
        warnings: warnings,
      );
    }
    return _BinaryCandidateSelection(
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

    // 通道 2：纯 Dart 二进制解析器扫描候选 `mmkv.default` 文件
    final candidateFiles = await PlatformHelper.resolveCandidateMmkvFiles(
      customPaths: _testCandidateMmkvFiles,
    );
    final selected = await _selectBinaryCandidates(candidateFiles);
    final primaryBinary = selected.primary;
    final warnings = List<String>.from(selected.warnings);

    final binaryMergedEntries = <String, Object?>{};
    String? activeMmkvPath;
    if (primaryBinary.fileExists) {
      activeMmkvPath = primaryBinary.filePath;
      if (primaryBinary.crcMatched != false &&
          primaryBinary.actualSize > 4 &&
          primaryBinary.entries.isNotEmpty) {
        for (final entry in primaryBinary.entries.entries) {
          if (entry.value != null) {
            binaryMergedEntries[entry.key] = entry.value;
          }
        }
      }
    }

    // 通道 1：从原生 MMKVAdapter 读取所有键（若当前设备支持）
    final nativeEntries = <String, Object?>{};
    final legacy = _legacyMmkvAdapter;
    if (legacy != null) {
      try {
        final keys = legacy.getKeys();
        for (final key in keys) {
          if (key.isEmpty) continue;
          final val = _readTypedFromAdapter(
            legacy,
            key,
            fallbackHint: binaryMergedEntries[key],
          );
          if (val != null) {
            nativeEntries[key] = val;
          }
        }
      } catch (e) {
        warnings.add('Native MMKV read failed during migration: $e');
      }
    }

    // 合并通道 2 与通道 1：
    final combinedMmkvEntries = <String, Object?>{
      ...binaryMergedEntries,
      ...nativeEntries,
    };

    var migratedFromBinaryCount = 0;
    var migratedFromNativeCount = 0;

    for (final entry in combinedMmkvEntries.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;

      // 若已完成过首次迁移（如从诊断页手动重新触发），仅回填缺失键，不覆盖主存已有新值
      if (wasAlreadyMigrated && existingSpKeys.contains(key)) {
        continue;
      }

      final written = await _writeTypedToAdapter(storage, key, value);
      if (written) {
        if (nativeEntries.containsKey(key)) {
          migratedFromNativeCount++;
        }
        if (binaryMergedEntries.containsKey(key)) {
          migratedFromBinaryCount++;
        }
      }

      // 如果过渡期原生 MMKV 中缺失了二进制解析出的键，也同步回填
      if (legacy != null && !nativeEntries.containsKey(key)) {
        try {
          await _writeTypedToAdapter(legacy, key, value);
        } catch (_) {}
      }
    }

    // 通道 3：SQLite `thoughtecho.db` 启发式老用户自愈
    var healedFromSqliteCount = 0;
    if (storage.getBool('app_installed_v2') != true) {
      final customDir = storage.getString('custom_data_directory_path');
      final dbPaths = _testCandidateDbPaths;
      final hasDb = await PlatformHelper.hasPopulatedThoughtEchoDatabase(
        customDbPaths: dbPaths,
        customDataDirectoryPath: customDir,
      );
      if (hasDb) {
        await storage.setBool('app_installed_v2', true);
        await storage.setBool('initial_database_setup_complete', true);
        await storage.setBool('database_migration_complete', true);
        await storage.setBool('hasCompletedOnboarding', true);

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
        await storage.setString('app_settings', patchedAppSettingsJson);

        if (legacy != null) {
          try {
            await legacy.setBool('app_installed_v2', true);
            await legacy.setBool('initial_database_setup_complete', true);
            await legacy.setBool('database_migration_complete', true);
            await legacy.setBool('hasCompletedOnboarding', true);
            await legacy.setString('app_settings', patchedAppSettingsJson);
          } catch (_) {}
        }
        healedFromSqliteCount = 5;
        logDebug(
          'SafeMMKV: 检测到非空 thoughtecho.db，已自动自愈安装、数据库初始化与引导完成标记',
        );
      }
    }

    // 标记迁移完成（同时写入新旧两个标记键，防止 SettingsService._migrateDataIfNeeded 逆向覆盖）
    await storage.setBool(kLegacyMmkvMigrationCompleteKey, true);
    await storage.setBool(kKvEngineMigratedKey, true);
    if (legacy != null) {
      try {
        await legacy.setBool(kLegacyMmkvMigrationCompleteKey, true);
        await legacy.setBool(kKvEngineMigratedKey, true);
      } catch (_) {}
    }

    var preservedSpOnlyCount = 0;
    for (final k in existingSpKeys) {
      if (!combinedMmkvEntries.containsKey(k)) {
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
      nativeMmkvAvailable: legacy != null,
      migratedFromNativeCount: migratedFromNativeCount,
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
      logDebug('SafeMMKV: 写入键 "$key" 失败: $e');
      return false;
    }
  }

  /// 生成开发者设置「MMKV 迁移与解析诊断」页面的完整比对报告。
  Future<MmkvDiagnosticReport> collectDiagnosticReport() async {
    await initialize();
    final storage = _storage!;

    final candidateFiles = await PlatformHelper.resolveCandidateMmkvFiles(
      customPaths: _testCandidateMmkvFiles,
    );
    final selected = await _selectBinaryCandidates(candidateFiles);
    final primaryBinaryResult = selected.primary;
    final secondaryBinaryResult = selected.secondary;

    final binaryEntries = primaryBinaryResult.entries;
    final legacy = _legacyMmkvAdapter;
    final nativeKeys = legacy != null ? legacy.getKeys() : <String>{};
    final spKeys = storage.getKeys();

    final allKeys = <String>{
      ...binaryEntries.keys,
      ...nativeKeys,
      ...spKeys,
    }.where((k) => k.isNotEmpty).toList();
    allKeys.sort();

    final comparisons = <MmkvKeyComparisonEntry>[];
    var consistentCount = 0;
    var diffCount = 0;

    for (final key in allKeys) {
      final presentInBinary = binaryEntries.containsKey(key);
      final binaryVal = binaryEntries[key];

      final presentInSp = spKeys.contains(key);
      Object? spVal;
      if (presentInSp) {
        spVal = _readTypedFromAdapter(storage, key, fallbackHint: binaryVal);
      }

      final presentInNative = legacy != null && nativeKeys.contains(key);
      Object? nativeVal;
      if (presentInNative) {
        nativeVal = _readTypedFromAdapter(
          legacy,
          key,
          fallbackHint: binaryVal ?? spVal,
        );
      }

      final sampleVal = spVal ?? binaryVal ?? nativeVal;
      final valueType = _describeValueType(key, sampleVal);

      bool binaryMatchesSp;
      if (presentInBinary) {
        binaryMatchesSp = _valuesEqual(binaryVal, spVal);
      } else {
        binaryMatchesSp = presentInSp;
      }

      bool nativeMatchesBinary;
      if (legacy != null) {
        final samePresence = presentInNative == presentInBinary;
        final valuesMatch = _valuesEqual(nativeVal, binaryVal);
        nativeMatchesBinary = samePresence && valuesMatch;
      } else {
        nativeMatchesBinary = binaryMatchesSp;
      }

      // 判断该键在所有已存在的存储源中是否一致：
      // 1. 若二进制文件中有该键，SharedPreferences 中必须存在且值完全相等；
      // 2. 若原生 MMKV 可用且包含该键，它与二进制解析器的结果也必须完全相等；
      // 3. 若某键仅存在于 SharedPreferences（例如桌面端/32位设备或仅写入 SP 的键），视为一致。
      bool allConsistent;
      if (presentInBinary) {
        final nativeOk = !presentInNative || _valuesEqual(nativeVal, binaryVal);
        allConsistent = binaryMatchesSp && nativeOk;
      } else if (presentInNative) {
        allConsistent = _valuesEqual(nativeVal, spVal);
      } else {
        allConsistent = presentInSp;
      }

      if (allConsistent) {
        consistentCount++;
      } else {
        diffCount++;
      }

      comparisons.add(
        MmkvKeyComparisonEntry(
          key: key,
          valueType: valueType,
          presentInNative: presentInNative,
          presentInBinary: presentInBinary,
          presentInSharedPrefs: presentInSp,
          nativeValue: nativeVal,
          binaryValue: binaryVal,
          sharedPrefsValue: spVal,
          nativeMatchesBinary: nativeMatchesBinary,
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
      nativeMmkvAvailable: _legacyMmkvAdapter != null,
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
        return 'bytes';
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

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized || _storage == null) {
      throw StateError('SafeMMKV 尚未初始化，请先调用 initialize() 方法');
    }
  }

  /// 跨 Isolate 刷新内存缓存
  Future<void> reload() async {
    _ensureInitialized();
    final storage = _storage;
    if (storage is SharedPrefsAdapter) {
      await storage.reload();
    }
  }

  /// 设置字符串值（主存写入 + 过渡期原生 MMKV 镜像）
  Future<bool> setString(String key, String value) async {
    _ensureInitialized();
    final result = await _storage!.setString(key, value);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.setString(key, value);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像写入 setString($key) 失败: $e');
      }
    }
    return result;
  }

  /// 获取字符串值
  String? getString(String key) {
    _ensureInitialized();
    return _storage!.getString(key);
  }

  /// 设置整数值（主存写入 + 过渡期原生 MMKV 镜像）
  Future<bool> setInt(String key, int value) async {
    _ensureInitialized();
    final result = await _storage!.setInt(key, value);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.setInt(key, value);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像写入 setInt($key) 失败: $e');
      }
    }
    return result;
  }

  /// 获取整数值
  int? getInt(String key) {
    _ensureInitialized();
    return _storage!.getInt(key);
  }

  /// 设置双精度浮点值（主存写入 + 过渡期原生 MMKV 镜像）
  Future<bool> setDouble(String key, double value) async {
    _ensureInitialized();
    final result = await _storage!.setDouble(key, value);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.setDouble(key, value);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像写入 setDouble($key) 失败: $e');
      }
    }
    return result;
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    _ensureInitialized();
    return _storage!.getDouble(key);
  }

  /// 设置布尔值（主存写入 + 过渡期原生 MMKV 镜像）
  Future<bool> setBool(String key, bool value) async {
    _ensureInitialized();
    final result = await _storage!.setBool(key, value);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.setBool(key, value);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像写入 setBool($key) 失败: $e');
      }
    }
    return result;
  }

  /// 获取布尔值
  bool? getBool(String key) {
    _ensureInitialized();
    return _storage!.getBool(key);
  }

  /// 设置字符串列表（主存写入 + 过渡期原生 MMKV 镜像）
  Future<bool> setStringList(String key, List<String> value) async {
    _ensureInitialized();
    final result = await _storage!.setStringList(key, value);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.setStringList(key, value);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像写入 setStringList($key) 失败: $e');
      }
    }
    return result;
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    _ensureInitialized();
    return _storage!.getStringList(key);
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    _ensureInitialized();
    return _storage!.containsKey(key);
  }

  /// 删除指定键的值（主存删除 + 过渡期原生 MMKV 镜像删除）
  Future<bool> remove(String key) async {
    _ensureInitialized();
    final result = await _storage!.remove(key);
    if (_legacyMmkvAdapter != null) {
      try {
        await _legacyMmkvAdapter!.remove(key);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像删除 remove($key) 失败: $e');
      }
    }
    return result;
  }

  /// 清除所有值（保留迁移完成水位线）
  Future<bool> clear() async {
    _ensureInitialized();
    final result = await _storage!.clear();
    await _storage!.setBool(kLegacyMmkvMigrationCompleteKey, true);
    await _storage!.setBool(kKvEngineMigratedKey, true);
    final legacy = _legacyMmkvAdapter;
    if (legacy != null) {
      try {
        await legacy.clear();
        await legacy.setBool(kLegacyMmkvMigrationCompleteKey, true);
        await legacy.setBool(kKvEngineMigratedKey, true);
      } catch (e) {
        logDebug('SafeMMKV: MMKV 镜像清空 clear() 失败: $e');
      }
    }
    return result;
  }

  /// 获取所有键名
  Set<String> getKeys() {
    _ensureInitialized();
    return _storage!.getKeys();
  }
}

class _BinaryCandidateSelection {
  final MmkvParseResult primary;
  final MmkvParseResult? secondary;
  final List<String> warnings;

  const _BinaryCandidateSelection({
    required this.primary,
    required this.secondary,
    required this.warnings,
  });
}

/// 内存存储适配器（作为最终回退与测试桩）
class _InMemoryStorageAdapter implements StorageAdapter {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) {
    final value = _data[key];
    return value is int ? value : null;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) {
    final value = _data[key];
    return value is double ? value : null;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) {
    final value = _data[key];
    return value is bool ? value : null;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = List<String>.from(value);
    return true;
  }

  @override
  List<String>? getStringList(String key) {
    final value = _data[key];
    return value is List<String> ? value : null;
  }

  @override
  bool containsKey(String key) {
    return _data.containsKey(key);
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Set<String> getKeys() {
    return _data.keys.toSet();
  }
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
    if (raw is String) return raw;
    if (raw is List) return json.encode(raw);
    return null;
  }

  @override
  Future<bool> setInt(String key, int value) {
    return prefs.setInt(key, value);
  }

  @override
  int? getInt(String key) {
    final raw = prefs.get(key);
    if (raw is int) return raw;
    return null;
  }

  @override
  Future<bool> setDouble(String key, double value) {
    return prefs.setDouble(key, value);
  }

  @override
  double? getDouble(String key) {
    final raw = prefs.get(key);
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    return null;
  }

  @override
  Future<bool> setBool(String key, bool value) {
    return prefs.setBool(key, value);
  }

  @override
  bool? getBool(String key) {
    final raw = prefs.get(key);
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    return null;
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

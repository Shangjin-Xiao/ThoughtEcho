import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_memory.dart';
import '../utils/app_logger.dart';
import '../utils/aptabase_helper.dart';
import '../utils/lww_utils.dart';
import '../utils/untrusted_text.dart';
import 'data_directory_service.dart';
import 'large_file_manager.dart';
import 'settings_service.dart';

part 'agent_memory_sync.dart';

/// Thoughter 的长期记忆。
///
/// 两层，职责严格分开：
/// - **画像层**（`agent_memory_profile`）：身份与表达偏好，每次对话注入，有硬预算；
/// - **事实层**（`agent_memory_facts`）：细节，不注入，靠 `recall` 工具按需检索。
///
/// 边界：记忆**存结论，不存原文**。文风、品味这类结论要扫很多篇笔记才归纳得出，
/// 缓存进记忆才划算；笔记正文本身归 `explore_notes`，对话原文归 `session_search`。
/// 三套检索各管一摊，否则模型会在几个来源之间反复横跳。
///
/// **独立数据库文件 `agent_memory.db`**，和聊天记录、日志、AI 分析一样不进主库：
/// 物理隔离保证了独立的 schema 演进与一键彻底清空，主库的 schema 版本号不必为了记忆
/// 往上走；自 schema v3 起，记忆在开关开启时通过受控 JSON 段参与手动备份/恢复、
/// LocalSend 局域网同步与 WebDAV 同步，由 [AgentMemoryService] 自管导出、合并与收敛。
///
/// 检索用 `LIKE` 而不是 FTS5：条目量级是几十到几百条，`LIKE` 取候选再在 Dart 里
/// 按 relevance × recency × importance 打分完全够用；而 FTS5 的默认分词器对中文
/// 等于不分词，要中文可用得靠 `trigram`（SQLite 3.34+），Android 上跟随系统
/// SQLite 版本，不可控。检索封在 [searchFacts] 后面，将来换实现不动调用方。
class AgentMemoryService extends ChangeNotifier {
  /// [databasePath] 仅供测试注入（可传 `inMemoryDatabasePath`）。
  AgentMemoryService({
    required SettingsService settingsService,
    String? databasePath,
  })  : _settingsService = settingsService,
        _databasePath = databasePath {
    _settingsService.setIdentityAliasesProvider(() => _cachedIdentityAliases);
    if (_databasePath != inMemoryDatabasePath) {
      unawaited(_warmUpAliases());
    }
  }

  Future<void> _warmUpAliases() async {
    try {
      await activeIdentityAliases();
      _settingsService.refreshIdentityAliases();
    } catch (_) {
      // 忽略启动预热期异常（如单元测试未初始化 db factory 等情况）
    }
  }

  SettingsService _settingsService;
  final String? _databasePath;
  final Uuid _uuid = const Uuid();

  SettingsService get settingsService => _settingsService;

  /// 原位更新依赖引用（SettingsService）。
  ///
  /// 同步且幂等，不触发额外的 notifyListeners()。
  void updateDependencies({required SettingsService settingsService}) {
    if (identical(_settingsService, settingsService)) return;
    _settingsService.setIdentityAliasesProvider(null);
    _settingsService = settingsService;
    _settingsService.setIdentityAliasesProvider(() => _cachedIdentityAliases);
  }

  Database? _database;
  Completer<Database>? _opening;

  /// 只有 [dispose] 会置位，之后这个实例彻底不可用。
  bool _disposed = false;

  static const String databaseFileName = 'agent_memory.db';

  /// 记忆库自己的 schema 版本，与主库的 `schemaVersion` 无关。
  ///
  /// v2：画像层加 `source_note_ids`（Dreaming 的来源归因），并新增近况切片表。
  /// v3：补齐同步元数据（`updated_at`、`replaces_id`、Dreaming 笔记依据、墓碑表与 `agent_memory_meta`）。
  static const int schemaVersion = 3;

  static const String profileTable = 'agent_memory_profile';
  static const String factsTable = 'agent_memory_facts';
  static const String recentSliceTable = 'agent_memory_recent_slice';
  static const String tombstonesTable = 'agent_memory_tombstones';
  static const String metaTable = 'agent_memory_meta';

  static const String metaClearedAtKey = 'cleared_at';
  static const String metaDreamingLastRunAtKey = 'dreaming_last_run_at';
  static const String metaDreamingBasisWatermarkKey =
      'dreaming_basis_watermark';
  static const String metaDreamingBasisNoteCountKey =
      'dreaming_basis_note_count';
  static const String metaProfileReplacementsKey = 'profile_replacements';
  static const int maxProfileReplacements = 500;

  /// 画像层注入预算。超出时按「最近观察优先」截断注入副本，**不删库里的条目**。
  static const int profileInjectionMaxEntries = 24;
  static const int profileInjectionMaxChars = 1200;

  /// 生成类链路（每日提示、周期洞察）可以注入的 kind。
  ///
  /// 比全集少一个 [AgentMemoryKind.taste]，这是**在注入层执行**的约束，不是
  /// 提示词里的一句话：品味只可用于共鸣与推荐，绝不可用于评价，而洞察和每日
  /// 提示恰恰是最容易写出评价口吻的两条链路。不注入，就无从误用。
  ///
  /// 对话链路走全集（[AgentMemoryKind.values]）——共鸣和推荐正是它的正当用途。
  static const Set<AgentMemoryKind> profileKindsForGeneration =
      <AgentMemoryKind>{
    AgentMemoryKind.identity,
    AgentMemoryKind.preference,
    AgentMemoryKind.style,
    AgentMemoryKind.feedback,
    AgentMemoryKind.voice,
  };

  /// 单条指令长度上限，防止模型把一整段对话当成一条偏好塞进来。
  static const int directiveMaxChars = 200;

  /// 称呼长度上限。它是画像块里的一行，不是签名档。
  static const int nicknameMaxChars = 50;

  /// 单条事实长度上限。
  static const int factMaxChars = 600;

  /// `recall` 单次返回的事实条数上限。
  static const int recallDefaultLimit = 8;

  /// 事实层容量上限。超出后由 [addFact] 淘汰得分最低的条目。
  static const int factsCapacity = 400;

  /// 相关度衰减半衰期，取自 Generative Agents 的记忆流打分。
  static const double _recencyHalfLifeDays = 30;

  List<AgentMemoryProfileEntry>? _activeProfileCache;
  Set<String> _cachedIdentityAliases = const <String>{};
  AgentMemoryBatchBasisChecker? _basisChecker;

  /// 注册可选的 Dreaming 笔记依据“看全了”批量判定器（由同步层自动挂载）。
  ///
  /// 挂载后，[compactAndPrune] 在发现多条活跃 Dreaming 画像候选，以及直接调用
  /// [mergeMemorySection] 未显式传参时，均可按与跨端同步一致的口径评估依据覆盖。
  void setBasisChecker(AgentMemoryBatchBasisChecker? checker) {
    _basisChecker = checker;
  }

  /// 仅在当前挂载的判定器仍是 [checker] 时解绑，避免新旧依赖切换时误清。
  void detachBasisChecker(AgentMemoryBatchBasisChecker checker) {
    if (identical(_basisChecker, checker)) {
      _basisChecker = null;
    }
  }

  /// 预校验备份包中 `agent_memory` 段的顶层及内部容器结构合法性。
  ///
  /// 供覆盖恢复在落盘解压媒体文件或删除主库/偏好设置数据前执行前置校验，
  /// 避免后段结构损坏导致部分覆盖数据丢失。
  static void validateMemorySectionPayload(Object? rawSection) {
    if (rawSection == null) {
      return;
    }
    if (rawSection is! Map) {
      throw const FormatException('Invalid agent_memory backup section');
    }
    _validateMemorySectionContainers(rawSection);
  }

  /// 获取当前内存中已缓存的活跃身份别名集合。
  Set<String> get cachedIdentityAliases => _cachedIdentityAliases;

  bool get isEnabled => _settingsService.agentMemoryEnabled;

  int get captureGeneration => _settingsService.agentMemoryGeneration;

  bool isCaptureCurrent(int generation) =>
      !_disposed && isEnabled && generation == captureGeneration;

  void _notifySyncListeners() {
    notifyListeners();
  }

  Future<Database> get _db async {
    final current = _database;
    if (current != null && current.isOpen) {
      return current;
    }
    final opening = _opening;
    if (opening != null) {
      return opening.future;
    }

    if (_disposed) {
      throw StateError('AgentMemoryService 已销毁');
    }
    final completer = Completer<Database>();
    _opening = completer;
    // 发起打开的这个调用方直接 await openDatabase 并 rethrow，不听
    // completer.future。没有并发调用方时这条 future 就没人听，打开失败会多出
    // 一个未捕获的异步错误。ignore() 只是兜底，不影响真正在等它的调用方。
    completer.future.ignore();
    try {
      final dbPath = _databasePath ?? await _defaultDatabasePath();
      if (dbPath != inMemoryDatabasePath) {
        await DataDirectoryService.ensureParentDirectoryForFile(dbPath);
      }
      final db = await openDatabase(
        dbPath,
        version: schemaVersion,
        onCreate: (db, version) => _ensureSchema(db),
        // 建表语句都是 IF NOT EXISTS，升级和打开都跑一遍即可自愈：
        // 记忆丢一条不致命，但表不在会让每次 Thoughter 调用都炸。
        onUpgrade: (db, oldVersion, newVersion) => _ensureSchema(db),
        onOpen: _ensureSchema,
      );
      // dispose 可能发生在打开过程中：那时 _database 还是 null，dispose 关不到
      // 任何东西，而这个连接一旦落到 _database 上就再没人管了。
      if (_disposed) {
        await db.close();
        throw StateError('AgentMemoryService 已销毁');
      }
      _database = db;
      completer.complete(db);
      return db;
    } catch (error, stackTrace) {
      _reportDatabaseError('openDatabase', error, stackTrace);
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  /// 统一记录并上报存储层异常，绝不上报用户记忆指令文本等隐私信息。
  void _reportDatabaseError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    logError(
      '$operation失败',
      error: error,
      stackTrace: stackTrace,
      source: 'AgentMemoryService',
    );
  }

  @visibleForTesting
  void reportDatabaseErrorForTesting(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    _reportDatabaseError(operation, error, stackTrace);
  }

  /// 关闭连接。仅供 [dispose]。
  Future<void> _close() async {
    final opening = _opening;
    if (opening != null) {
      // 等打开流程走完，否则它会在我们关完之后再把连接装回 _database。
      try {
        await opening.future;
      } catch (_) {
        // 打开本身失败就没有连接要关。
      }
    }
    final db = _database;
    _database = null;
    if (db == null || !db.isOpen) {
      return;
    }
    try {
      await db.close();
    } catch (error, stackTrace) {
      _reportDatabaseError('closeDatabase', error, stackTrace);
    }
  }

  /// 记忆库固定放 documents，**不跟随可自定义的数据目录**。
  ///
  /// 记忆库体量仅几百 KB（跨设备备份与同步走序列化 JSON 段而非裸拷库文件）；
  /// 用户改数据目录是为了挪主库和媒体这些大件。让它待在原地，就不必接入目录迁移的
  /// 挂起/复制/校验，也不会在旧目录留下一份没人管的画像。
  static Future<String> _defaultDatabasePath() async {
    final basePath = (await getApplicationDocumentsDirectory()).path;
    return path.join(basePath, databaseFileName);
  }

  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    // 画像层：每次对话注入，因此条目少、有硬预算。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $profileTable(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        directive TEXT NOT NULL,
        observed_at TEXT NOT NULL,
        updated_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        superseded_by TEXT,
        replaces_id TEXT,
        source TEXT,
        source_note_ids TEXT,
        basis_watermark TEXT,
        basis_note_count INTEGER
      )
    ''');
    // 事实层：不默认注入，由 `recall` 按需检索。
    // `embedding` 恒为 NULL，为将来换向量检索预留列位——现在留着，
    // 免得二期为了加一列再写一次迁移。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $factsTable(
        id TEXT PRIMARY KEY,
        category TEXT,
        content TEXT NOT NULL,
        importance INTEGER NOT NULL DEFAULT 5,
        trigger_phrases TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        last_recalled_at TEXT,
        recall_count INTEGER NOT NULL DEFAULT 0,
        source_ref TEXT,
        embedding BLOB
      )
    ''');
    // 近况切片：单行覆盖式写入，带过期时间，不占画像层预算。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $recentSliceTable(
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        observed_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        source_note_ids TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tombstonesTable(
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        PRIMARY KEY(entity_type, entity_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $metaTable(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // 增量加列：建表语句里已包含新列，升级旧库时补齐并回填。
    await _addColumnIfMissing(db, profileTable, 'source_note_ids', 'TEXT');
    await _addColumnIfMissing(db, profileTable, 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, profileTable, 'replaces_id', 'TEXT');
    await _addColumnIfMissing(db, profileTable, 'basis_watermark', 'TEXT');
    await _addColumnIfMissing(db, profileTable, 'basis_note_count', 'INTEGER');
    await _addColumnIfMissing(db, factsTable, 'updated_at', 'TEXT');

    await db.execute('''
      UPDATE $profileTable
      SET replaces_id = (
        SELECT old.id FROM $profileTable old
        WHERE old.superseded_by = $profileTable.id
        LIMIT 1
      )
      WHERE replaces_id IS NULL
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_agent_memory_profile_status '
      'ON $profileTable(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_agent_memory_facts_importance '
      'ON $factsTable(importance)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_agent_memory_facts_created_at '
      'ON $factsTable(created_at)',
    );

    // 先完成旧时间列的显式时区转换与 6 位微秒定宽补齐（同时为所有被改写列建立 *_backup 快照），
    // 再用 COALESCE 回填缺失的 updated_at，避免先把无时区列复制到 updated_at 掩盖同事件显式时区配对。
    await _normalizeLegacyMemoryTimestamps(db);

    await db.execute('''
      UPDATE $profileTable
      SET updated_at = COALESCE(NULLIF(updated_at, ''), observed_at)
      WHERE updated_at IS NULL OR updated_at = ''
    ''');
    await db.execute('''
      UPDATE $factsTable
      SET updated_at = COALESCE(NULLIF(updated_at, ''), created_at)
      WHERE updated_at IS NULL OR updated_at = ''
    ''');
  }

  static String _nonCanonicalMemoryTimeClause(
    String column, {
    bool nullable = false,
  }) {
    final notCanonical =
        "$column NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}' AND "
        "$column NOT GLOB '${LWWUtils.canonicalFixedOffsetlessGlob}'";
    if (!nullable) {
      return "$column IS NOT NULL AND $column != '' AND ($notCanonical)";
    }
    return "($column IS NOT NULL AND $column != '' AND ($notCanonical))";
  }

  static Future<void> _normalizeLegacyMemoryTimestamps(
    DatabaseExecutor db,
  ) async {
    const chunkSize = 500;

    final nonCanonicalProfiles = await db.query(
      profileTable,
      columns: const <String>['id', 'observed_at', 'updated_at'],
      where: '${_nonCanonicalMemoryTimeClause('observed_at')} OR '
          '${_nonCanonicalMemoryTimeClause('updated_at', nullable: true)}',
    );
    if (nonCanonicalProfiles.isNotEmpty) {
      await _addColumnIfMissing(
        db,
        profileTable,
        'observed_at_backup',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        profileTable,
        'updated_at_backup',
        'TEXT',
      );
    }
    for (var i = 0; i < nonCanonicalProfiles.length; i += chunkSize) {
      final end = (i + chunkSize < nonCanonicalProfiles.length)
          ? i + chunkSize
          : nonCanonicalProfiles.length;
      final batch = db.batch();
      var hasUpdates = false;
      for (var j = i; j < end; j++) {
        final row = nonCanonicalProfiles[j];
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final observedAt = _normalizeMemoryTimestampToUtcOrKeep(
          row['observed_at'],
        );
        final updatedRaw = row['updated_at'];
        final updatedAt = (updatedRaw is String && updatedRaw.trim().isNotEmpty)
            ? _normalizeMemoryTimestampToUtcOrKeep(updatedRaw)
            : observedAt;
        if (observedAt != row['observed_at'] ||
            updatedAt != row['updated_at']) {
          batch.rawUpdate(
            'UPDATE $profileTable SET '
            'observed_at_backup = COALESCE(observed_at_backup, observed_at), '
            'updated_at_backup = COALESCE(updated_at_backup, updated_at), '
            'observed_at = ?, updated_at = ? '
            'WHERE id = ?',
            <Object?>[observedAt, updatedAt, id],
          );
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit(noResult: true);
      }
    }

    final nonCanonicalFacts = await db.query(
      factsTable,
      columns: const <String>[
        'id',
        'created_at',
        'updated_at',
        'last_recalled_at',
      ],
      where: '${_nonCanonicalMemoryTimeClause('created_at')} OR '
          '${_nonCanonicalMemoryTimeClause('updated_at', nullable: true)} OR '
          '${_nonCanonicalMemoryTimeClause('last_recalled_at', nullable: true)}',
    );
    if (nonCanonicalFacts.isNotEmpty) {
      await _addColumnIfMissing(db, factsTable, 'created_at_backup', 'TEXT');
      await _addColumnIfMissing(db, factsTable, 'updated_at_backup', 'TEXT');
      await _addColumnIfMissing(
        db,
        factsTable,
        'last_recalled_at_backup',
        'TEXT',
      );
    }
    for (var i = 0; i < nonCanonicalFacts.length; i += chunkSize) {
      final end = (i + chunkSize < nonCanonicalFacts.length)
          ? i + chunkSize
          : nonCanonicalFacts.length;
      final batch = db.batch();
      var hasUpdates = false;
      for (var j = i; j < end; j++) {
        final row = nonCanonicalFacts[j];
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final createdAt = _normalizeMemoryTimestampToUtcOrKeep(
          row['created_at'],
        );
        final updatedRaw = row['updated_at'];
        final updatedAt = (updatedRaw is String && updatedRaw.trim().isNotEmpty)
            ? _normalizeMemoryTimestampToUtcOrKeep(updatedRaw)
            : createdAt;
        final recalledRaw = row['last_recalled_at'];
        final lastRecalledAt =
            (recalledRaw is String && recalledRaw.trim().isNotEmpty)
                ? _normalizeMemoryTimestampToUtcOrKeep(recalledRaw)
                : recalledRaw;
        if (createdAt != row['created_at'] ||
            updatedAt != row['updated_at'] ||
            lastRecalledAt != row['last_recalled_at']) {
          batch.rawUpdate(
            'UPDATE $factsTable SET '
            'created_at_backup = COALESCE(created_at_backup, created_at), '
            'updated_at_backup = COALESCE(updated_at_backup, updated_at), '
            'last_recalled_at_backup = '
            'COALESCE(last_recalled_at_backup, last_recalled_at), '
            'created_at = ?, updated_at = ?, last_recalled_at = ? '
            'WHERE id = ?',
            <Object?>[createdAt, updatedAt, lastRecalledAt, id],
          );
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit(noResult: true);
      }
    }

    final nonCanonicalSlices = await db.query(
      recentSliceTable,
      columns: const <String>['id', 'observed_at', 'expires_at'],
      where: '${_nonCanonicalMemoryTimeClause('observed_at')} OR '
          '${_nonCanonicalMemoryTimeClause('expires_at')}',
    );
    if (nonCanonicalSlices.isNotEmpty) {
      await _addColumnIfMissing(
        db,
        recentSliceTable,
        'observed_at_backup',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        recentSliceTable,
        'expires_at_backup',
        'TEXT',
      );
    }
    for (var i = 0; i < nonCanonicalSlices.length; i += chunkSize) {
      final end = (i + chunkSize < nonCanonicalSlices.length)
          ? i + chunkSize
          : nonCanonicalSlices.length;
      final batch = db.batch();
      var hasUpdates = false;
      for (var j = i; j < end; j++) {
        final row = nonCanonicalSlices[j];
        final id = row['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final observedAt = _normalizeMemoryTimestampToUtcOrKeep(
          row['observed_at'],
        );
        final expiresAt = _normalizeMemoryTimestampToUtcOrKeep(
          row['expires_at'],
        );
        if (observedAt != row['observed_at'] ||
            expiresAt != row['expires_at']) {
          batch.rawUpdate(
            'UPDATE $recentSliceTable SET '
            'observed_at_backup = COALESCE(observed_at_backup, observed_at), '
            'expires_at_backup = COALESCE(expires_at_backup, expires_at), '
            'observed_at = ?, expires_at = ? '
            'WHERE id = ?',
            <Object?>[observedAt, expiresAt, id],
          );
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit(noResult: true);
      }
    }

    final nonCanonicalTombstones = await db.query(
      tombstonesTable,
      columns: const <String>['entity_type', 'entity_id', 'deleted_at'],
      where: _nonCanonicalMemoryTimeClause('deleted_at'),
    );
    if (nonCanonicalTombstones.isNotEmpty) {
      await _addColumnIfMissing(
        db,
        tombstonesTable,
        'deleted_at_backup',
        'TEXT',
      );
    }
    for (var i = 0; i < nonCanonicalTombstones.length; i += chunkSize) {
      final end = (i + chunkSize < nonCanonicalTombstones.length)
          ? i + chunkSize
          : nonCanonicalTombstones.length;
      final batch = db.batch();
      var hasUpdates = false;
      for (var j = i; j < end; j++) {
        final row = nonCanonicalTombstones[j];
        final type = row['entity_type'] as String?;
        final id = row['entity_id'] as String?;
        if (type == null || id == null) continue;
        final deletedAt = _normalizeMemoryTimestampToUtcOrKeep(
          row['deleted_at'],
        );
        if (deletedAt != row['deleted_at']) {
          batch.rawUpdate(
            'UPDATE $tombstonesTable SET '
            'deleted_at_backup = COALESCE(deleted_at_backup, deleted_at), '
            'deleted_at = ? '
            'WHERE entity_type = ? AND entity_id = ?',
            <Object?>[deletedAt, type, id],
          );
          hasUpdates = true;
        }
      }
      if (hasUpdates) {
        await batch.commit(noResult: true);
      }
    }

    final nonCanonicalMeta = await db.query(
      metaTable,
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?) AND ${_nonCanonicalMemoryTimeClause('value')}',
      whereArgs: <Object?>[metaClearedAtKey, metaDreamingLastRunAtKey],
    );
    for (final row in nonCanonicalMeta) {
      final key = row['key'] as String?;
      if (key == null || key.isEmpty) continue;
      final normalized = _normalizeMemoryTimestampToUtcOrKeep(row['value']);
      if (normalized != row['value']) {
        await db.insert(
          metaTable,
          <String, Object?>{'key': '${key}_backup', 'value': row['value']},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.update(
          metaTable,
          <String, Object?>{'value': normalized},
          where: 'key = ?',
          whereArgs: <Object?>[key],
        );
      }
    }
  }

  static String _quoteIdentifier(String identifier) {
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(identifier)) {
      throw StateError('不安全的标识符: $identifier');
    }
    return '"$identifier"';
  }

  static void _validateColumnDefinition(String columnDefinition) {
    final trimmedDef = columnDefinition.trim();
    final parts =
        trimmedDef.split(RegExp(r'\s+DEFAULT\s+', caseSensitive: false));
    if (parts.length > 2 ||
        !RegExp(r'^[a-zA-Z0-9_ (),]+$').hasMatch(parts[0]) ||
        (parts.length == 2 &&
            !RegExp(
              r"^(?:NULL|'[a-zA-Z0-9_ -]*'|-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$",
              caseSensitive: false,
            ).hasMatch(parts[1]))) {
      throw StateError('不安全的列定义: $columnDefinition');
    }
  }

  @visibleForTesting
  static String quoteIdentifierForTesting(String identifier) =>
      _quoteIdentifier(identifier);

  @visibleForTesting
  static void validateColumnDefinitionForTesting(String definition) =>
      _validateColumnDefinition(definition);

  /// 加列，列已存在时静默跳过。
  ///
  /// SQLite 没有 `ADD COLUMN IF NOT EXISTS`，而 [_ensureSchema] 在 onCreate /
  /// onUpgrade / onOpen 三条路径上都会跑——全新安装时建表语句已经带上这一列，
  /// 再执行加列必然报 duplicate column。吞掉异常是这里的正常路径，不是兜底。
  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String columnName,
    String columnDefinition,
  ) async {
    final safeTable = _quoteIdentifier(table);
    final safeColumnName = _quoteIdentifier(columnName);
    _validateColumnDefinition(columnDefinition);

    try {
      await db.execute(
          'ALTER TABLE $safeTable ADD COLUMN $safeColumnName $columnDefinition');
    } catch (_) {
      // 列已存在。其它 DDL 失败会在后续读写时暴露，不在这里吞成静默损坏。
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _basisChecker = null;
    _settingsService.setIdentityAliasesProvider(null);
    _disposed = true;
    unawaited(_close());
    super.dispose();
  }

  // ======================== 画像层 ========================

  static final RegExp _callMeRegex = RegExp(
    r'''(?:称呼(?:用户|我)?|自称|名字|笔名|别名|叫我|我叫)\s*(?:为|是|叫|：|:)?\s*[「“"'《]?([^「」“”"'\s,，。；;！？!?《》\n（\(]{1,30})[」”"'》]?''',
  );
  static final RegExp _quoteTrimRegex = RegExp(r'''^[「“"'《]+|[」”"'》]+$''');
  static final RegExp _punctuationOrSpaceRegex =
      RegExp(r'''[\s,，。；;！？!?\n「」“”"'《》]''');
  static final RegExp _punctuationSplitRegex = RegExp(
    r'[\s,，。、；;:：!！?？"‘’“”()（）\[\]【】<>《》/\\|~`@#$%^&*+=_-]+',
  );
  static final RegExp _cjkRegex = RegExp(r'[一-鿿]');
  static final RegExp _whitespaceCollapseRegex = RegExp(r'\s+');

  /// 常用 CJK 检索停用词（结构助词、疑问代词、常见意图谓词与虚词）。
  /// 在 2-gram 滑窗与相关度打分中过滤或降权，避免噪声稀释核心概念。
  static const Set<String> cjkStopWords = <String>{
    // 结构意图与谓词
    '我想了解',
    '告诉我',
    '我想',
    '我要',
    '我会',
    '我在',
    '我的',
    '我们',
    '了解',
    '关于',
    '对于',
    '有关',
    '至于',
    '为了',
    '中的',
    '你的',
    '他的',
    '它的',
    '有的',
    '知道',
    '告诉',
    '请问',
    '请教',
    '看看',
    '觉得',
    '认为',
    '希望',
    '需要',
    '想要',
    '能否',
    '可以',
    '帮我',
    '讨论',
    '说明',
    '解释',
    '怎样',
    '如何',
    '为何',
    '什么',
    '怎么',
    '哪里',
    '哪儿',
    '哪个',
    '哪些',
    '为什么',
    '你们',
    '他们',
    '自己',
    '这个',
    '那个',
    '这些',
    '那些',
    '这样',
    '那样',
    '这么',
    '那么',
    '某个',
    '某些',
    '各个',
    '非常',
    '十分',
    '特别',
    '极其',
    '比较',
    '稍微',
    '几乎',
    '大概',
    '大约',
    '也许',
    '已经',
    '正在',
    '将要',
    '曾经',
    '一直',
    '总是',
    '常常',
    '经常',
    '还是',
    '也是',
    '都是',
    '不是',
    '就是',
    '并且',
    '而且',
    '以及',
    '或者',
    '如果',
    '但是',
    '因为',
    '所以',
    '由于',
    '因此',
    '之中',
    '之间',
    '之后',
    '之前',
    '之上',
    '之下',
    '其中',
    '里面',
    '外面',
    '上面',
    '下面',
    '这里',
    '那里',
    '一下',
    '一些',
    '一点',
    '一次',
  };

  static final RegExp _stopWordsSplitRegex = RegExp(
    (cjkStopWords.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .map(RegExp.escape)
        .join('|'),
  );

  @visibleForTesting
  static bool isStopWord(String word) => cjkStopWords.contains(word.trim());

  /// 检查画像指令文本是否包含存疑或待确认标记（如「（存疑）」、「（待确认）」）。
  static bool isDoubtfulOrUnconfirmedDirective(String directive) {
    final trimmed = directive.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.contains('（存疑') ||
        trimmed.contains('(存疑') ||
        trimmed.contains('（待确认') ||
        trimmed.contains('(待确认') ||
        trimmed.contains('待确认') ||
        trimmed.contains('存疑');
  }

  /// 从画像指令文本中提取出用户的称呼/笔名/别名。
  ///
  /// 仅在具备明确称呼/自称上下文时提取，杜绝盲目提取普通句子中用引号或书名号包裹的词汇。
  /// 默认不提取带有「（存疑）」、「（待确认）」等存疑标记的指令，确保高置信度。
  static Set<String> extractAliasesFromDirective(
    String directive, {
    bool includeUnconfirmed = false,
  }) {
    final result = <String>{};
    final trimmed = directive.trim();
    if (trimmed.isEmpty) return result;

    if (!includeUnconfirmed && isDoubtfulOrUnconfirmedDirective(trimmed)) {
      return result;
    }

    // 1. 匹配称呼句式（支持包裹引号或书名号），如 "称呼用户为「阿澈」"、"叫我“林晚”"、"笔名为《墨客》"
    for (final match in _callMeRegex.allMatches(trimmed)) {
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty && name.length <= 30) {
        result.add(name);
      }
    }

    // 2. 若前两步未提取到且整句极简（1~15 字且无任何标点与结构词），整句可能是裸名字（如 "阿澈"）
    if (result.isEmpty) {
      final clean = trimmed.replaceAll(_quoteTrimRegex, '').trim();
      if (clean.isNotEmpty &&
          clean.length <= 15 &&
          !clean.contains(_punctuationOrSpaceRegex)) {
        const structuralKeywords = [
          '用户',
          '称呼',
          '自称',
          '喜欢',
          '职业',
          '习惯',
          '偏好',
          '工作',
          '笔名',
          '名字',
          '叫我',
          '我叫',
          '存疑',
          '待确认',
        ];
        if (!structuralKeywords.any((k) => clean.contains(k))) {
          result.add(clean);
        }
      }
    }

    return result;
  }

  void _updateCachedIdentityAliases(List<AgentMemoryProfileEntry> entries) {
    final aliases = <String>{};
    for (final entry in entries) {
      if (entry.kind == AgentMemoryKind.identity) {
        aliases.addAll(extractAliasesFromDirective(entry.directive));
      }
    }
    _cachedIdentityAliases = aliases;
  }

  /// 获取所有活跃的 identity 别名集合。
  Future<Set<String>> activeIdentityAliases() async {
    final entries = await activeProfile();
    _updateCachedIdentityAliases(entries);
    return _cachedIdentityAliases;
  }

  /// 将离线推断或对话中识别出的用户别名注册进长期记忆的 identity 画像层。
  Future<bool> registerInferredAlias(
    String alias, {
    String source = 'dreaming',
    bool unconfirmed = false,
    DateTime? observedAt,
    String? basisWatermark,
    int? basisNoteCount,
  }) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) return false;

    // 若已知别名中已包含该别名（大小写不敏感），则无需重复写入
    final currentAliases = await activeIdentityAliases();
    if (currentAliases.any((a) => a.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }

    final directive =
        unconfirmed ? '待确认笔名：$trimmed（存疑，待确认）' : '称呼用户为「$trimmed」';

    if (unconfirmed) {
      final activeEntries = await activeProfile();
      if (activeEntries.any((e) =>
          e.kind == AgentMemoryKind.identity && e.directive == directive)) {
        return false;
      }
    }

    await rememberProfile(
      kind: AgentMemoryKind.identity,
      directive: directive,
      source: source,
      observedAt: observedAt,
      basisWatermark: basisWatermark,
      basisNoteCount: basisNoteCount,
    );
    return true;
  }

  /// 全部 active 画像条目，按观察时间倒序。
  Future<List<AgentMemoryProfileEntry>> activeProfile() async {
    final cached = _activeProfileCache;
    if (cached != null) {
      return cached;
    }
    try {
      final db = await _db;
      final rows = await db.query(
        profileTable,
        where: 'status = ?',
        whereArgs: <Object?>[AgentMemoryStatus.active.storageValue],
        orderBy: 'observed_at DESC, id ASC',
      );
      final mapped = rows.map(AgentMemoryProfileEntry.fromMap).toList();
      if (rows.any((r) => !(r['observed_at'] as String? ?? '').endsWith('Z'))) {
        mapped.sort((a, b) {
          final cmp = b.observedAt.toUtc().compareTo(a.observedAt.toUtc());
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
      }
      final entries = List<AgentMemoryProfileEntry>.unmodifiable(mapped);
      _activeProfileCache = entries;
      _updateCachedIdentityAliases(entries);
      return entries;
    } catch (error, stackTrace) {
      _reportDatabaseError('activeProfile', error, stackTrace);
      rethrow;
    }
  }

  /// 含已 supersede 的全部条目，供设置页与排查使用。
  Future<List<AgentMemoryProfileEntry>> allProfileEntries() async {
    try {
      final db = await _db;
      final rows = await db.query(
        profileTable,
        orderBy: 'observed_at DESC, id ASC',
      );
      final mapped = rows.map(AgentMemoryProfileEntry.fromMap).toList();
      if (rows.any((r) => !(r['observed_at'] as String? ?? '').endsWith('Z'))) {
        mapped.sort((a, b) {
          final cmp = b.observedAt.toUtc().compareTo(a.observedAt.toUtc());
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
      }
      return List<AgentMemoryProfileEntry>.unmodifiable(mapped);
    } catch (error, stackTrace) {
      _reportDatabaseError('allProfileEntries', error, stackTrace);
      rethrow;
    }
  }

  /// 仅当提取期间隐私策略未变时写入；验证与完整事务共用开关/清空的锁。
  /// 已获准的写入先完成，关闭随后生效；清空随后删除该写入。
  Future<bool> rememberProfileFromCapture({
    required int generation,
    required AgentMemoryKind kind,
    required String directive,
    String? replacesId,
    required String source,
  }) {
    return _settingsService.withAgentMemoryPolicy(() async {
      if (!isCaptureCurrent(generation)) return false;
      await rememberProfile(
        kind: kind,
        directive: directive,
        replacesId: replacesId,
        source: source,
      );
      return true;
    });
  }

  /// 写入一条画像指令。
  ///
  /// [replacesId] 非空时把旧条目原位 supersede——偏好变了就替换，绝不让两条
  /// 互相矛盾的 active 指令同时存在（模型会随机挑一条遵守）。
  ///
  /// [sourceNoteIds] 只有后台归纳会填，用来向用户交代这条结论的依据；
  /// `remember` 手动写入留空（手动记下的东西本就没有笔记来源）。
  Future<AgentMemoryProfileEntry> rememberProfile({
    required AgentMemoryKind kind,
    required String directive,
    String? replacesId,
    String source = 'thoughter',
    DateTime? observedAt,
    DateTime? updatedAt,
    List<String> sourceNoteIds = const <String>[],
    String? basisWatermark,
    int? basisNoteCount,
  }) async {
    final normalized = _normalizeDirective(directive);
    if (normalized.isEmpty) {
      throw ArgumentError.value(directive, 'directive', '指令内容为空');
    }

    final db = await _db;
    final effectiveObservedAt = (observedAt ?? DateTime.now()).toUtc();
    final effectiveUpdatedAt = (updatedAt ?? effectiveObservedAt).toUtc();
    final cleanReplacesId =
        (replacesId != null && replacesId.isNotEmpty) ? replacesId : null;
    final cleanBasisWatermark =
        (basisWatermark != null && basisWatermark.trim().isNotEmpty)
            ? basisWatermark.trim()
            : null;
    final entry = AgentMemoryProfileEntry(
      id: _uuid.v4(),
      kind: kind,
      directive: normalized,
      observedAt: effectiveObservedAt,
      updatedAt: effectiveUpdatedAt,
      replacesId: cleanReplacesId,
      source: source,
      sourceNoteIds: sourceNoteIds,
      basisWatermark: cleanBasisWatermark,
      basisNoteCount: basisNoteCount,
    );

    try {
      await db.transaction((txn) async {
        if (cleanReplacesId != null) {
          // 仅更新 status 与 superseded_by 派生状态，绝不覆盖被取代条目的原始 updated_at，
          // 以免污染跨端冲突收敛时的真实内容修订时间。
          await txn.update(
            profileTable,
            <String, Object?>{
              'status': AgentMemoryStatus.superseded.storageValue,
              'superseded_by': entry.id,
            },
            where: 'id = ?',
            whereArgs: <Object?>[cleanReplacesId],
          );
        }
        await txn.insert(
          profileTable,
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          tombstonesTable,
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>['profile', entry.id],
        );
      });
    } catch (error, stackTrace) {
      _reportDatabaseError('rememberProfile', error, stackTrace);
      rethrow;
    }

    _invalidateProfile();
    if (kind == AgentMemoryKind.identity) {
      final activeEntries = await activeProfile();
      _updateCachedIdentityAliases(activeEntries);
      _settingsService.refreshIdentityAliases();
    }
    notifyListeners();
    AptabaseHelper.trackEvent('agent_memory_remember', {
      'kind': kind.storageValue,
    });
    return entry;
  }

  /// 原位修改一条画像指令的正文。
  ///
  /// 用户直接跟 Thoughter 说「这条记错了，改成 X」时走这条路径：改的是同一条，
  /// 不产生新 id，也不留一条 superseded 的历史。
  Future<bool> editProfileDirective({
    required String id,
    required String directive,
    AgentMemoryKind? kind,
  }) async {
    final normalized = _normalizeDirective(directive);
    if (normalized.isEmpty) {
      throw ArgumentError.value(directive, 'directive', '指令内容为空');
    }
    try {
      final db = await _db;
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      final updated = await db.transaction<int>((txn) async {
        final existingRows = await txn.query(
          profileTable,
          columns: const <String>['status', 'superseded_by', 'replaces_id'],
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        if (existingRows.isEmpty) {
          return 0;
        }
        final existing = existingRows.first;
        final prevStatus = (existing['status'] as String?)?.trim() ?? '';
        final prevSupBy = (existing['superseded_by'] as String?)?.trim() ?? '';
        final prevReplacesId =
            (existing['replaces_id'] as String?)?.trim() ?? '';

        // 若用户在打开编辑弹窗期间后台同步恰好将该条目去重标为 `superseded -> P2`（或多跳终点 T），
        // 保存人工修订时必须原位恢复为 `active`，同时将此前接管它的活跃终点 T 退休指向当前条目并补记
        // `replaces_id = T`，确保本次人工纠正在本机立即生效且后续多端同步确定性胜出。
        String? terminalSuccessorId;
        if (prevStatus == AgentMemoryStatus.superseded.storageValue &&
            prevSupBy.isNotEmpty) {
          final allStatusRows = await txn.query(
            profileTable,
            columns: const <String>['id', 'status', 'superseded_by'],
          );
          final statusRowsById = <String, Map<String, Object?>>{
            for (final row in allStatusRows)
              if (row['id'] is String && (row['id'] as String).isNotEmpty)
                row['id'] as String: row,
          };
          var currId = prevSupBy;
          final visited = <String>{id};
          while (currId.isNotEmpty && visited.add(currId)) {
            final nextRow = statusRowsById[currId];
            if (nextRow == null) {
              break;
            }
            final nextStatus = (nextRow['status'] as String?)?.trim() ??
                AgentMemoryStatus.active.storageValue;
            if (nextStatus == AgentMemoryStatus.active.storageValue) {
              terminalSuccessorId = currId;
              break;
            }
            if (nextStatus != AgentMemoryStatus.superseded.storageValue) {
              break;
            }
            currId = (nextRow['superseded_by'] as String?)?.trim() ?? '';
          }
        }

        final count = await txn.update(
          profileTable,
          <String, Object?>{
            'directive': normalized,
            'observed_at': nowUtcIso,
            'updated_at': nowUtcIso,
            'status': AgentMemoryStatus.active.storageValue,
            'superseded_by': null,
            'source': 'user_edit',
            'basis_watermark': null,
            'basis_note_count': null,
            if (terminalSuccessorId != null &&
                terminalSuccessorId != id &&
                prevReplacesId.isEmpty)
              'replaces_id': terminalSuccessorId,
            if (kind != null) 'kind': kind.storageValue,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );

        if (count > 0) {
          if (terminalSuccessorId != null && terminalSuccessorId != id) {
            await txn.update(
              profileTable,
              <String, Object?>{
                'status': AgentMemoryStatus.superseded.storageValue,
                'superseded_by': id,
              },
              where: 'id = ?',
              whereArgs: <Object?>[terminalSuccessorId],
            );
          }
          await txn.delete(
            tombstonesTable,
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: <Object?>['profile', id],
          );
        }
        return count;
      });
      if (updated > 0) {
        _invalidateProfile();
        await activeIdentityAliases();
        _settingsService.refreshIdentityAliases();
        notifyListeners();
      }
      return updated > 0;
    } catch (error, stackTrace) {
      _reportDatabaseError('editProfileDirective', error, stackTrace);
      rethrow;
    }
  }

  /// 删除一条画像指令。用户说「忘掉这个」时用，是真删不是 supersede。
  Future<bool> forgetProfile(String id) async {
    try {
      final db = await _db;
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      final deleted = await db.transaction<int>((txn) async {
        final count = await txn.delete(
          profileTable,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (count > 0) {
          await txn.insert(
            tombstonesTable,
            <String, Object?>{
              'entity_type': 'profile',
              'entity_id': id,
              'deleted_at': nowUtcIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return count;
      });
      if (deleted > 0) {
        _invalidateProfile();
        await activeIdentityAliases();
        _settingsService.refreshIdentityAliases();
        notifyListeners();
      }
      return deleted > 0;
    } catch (error, stackTrace) {
      _reportDatabaseError('forgetProfile', error, stackTrace);
      rethrow;
    }
  }

  /// 渲染注入模型的画像块。记忆关闭，或没有条目且用户也未填写称呼时返回 null。
  ///
  /// 输出是一条独立的用户数据消息，不进系统提示——和绑定笔记的做法一致，
  /// 避免把「用户偏好」和「行为准则」混成同一层权限。
  ///
  /// [kinds] 限定注入哪些类别，默认全集。生成类链路应传
  /// [profileKindsForGeneration]（见该常量的说明）。
  /// 渲染注入模型的画像块。记忆关闭，或没有条目且用户也未填写称呼时返回 null。
  ///
  /// 输出是一条独立的用户数据消息，不进系统提示——和绑定笔记的做法一致，
  /// 避免把「用户偏好」和「行为准则」混成同一层权限。
  ///
  /// [kinds] 限定注入哪些类别，默认全集。生成类链路应传
  /// [profileKindsForGeneration]（见该常量的说明）。
  Future<String?> buildProfileBlock({
    Set<AgentMemoryKind> kinds = const <AgentMemoryKind>{},
  }) async {
    if (!isEnabled) {
      return null;
    }
    final allowed = kinds.isEmpty ? AgentMemoryKind.values.toSet() : kinds;
    final entries = (await activeProfile())
        .where((entry) => allowed.contains(entry.kind))
        .toList(growable: false);
    final nickname = _settingsService.userNickname;
    final now = DateTime.now();
    final slices = await activeRecentSlices(now: now);
    if (entries.isEmpty && nickname.trim().isEmpty && slices.isEmpty) {
      return null;
    }
    return renderProfileBlock(
      entries,
      now: now,
      userNickname: nickname,
      recentSlices: slices,
    );
  }

  /// [buildProfileBlock] 的降级包装：读不到就当没有画像。
  ///
  /// Agent 和每日提示/洞察都走这一个入口——记忆是增益，一次数据库异常不能把
  /// 整轮对话或每日提示打掉；降级策略只有一份，以后要加缓存或限流也只改这里。
  Future<String?> safeProfileBlock({
    required String source,
    Set<AgentMemoryKind> kinds = const <AgentMemoryKind>{},
  }) async {
    try {
      return await buildProfileBlock(kinds: kinds);
    } catch (error, stackTrace) {
      logError(
        '读取用户画像失败，本次不注入记忆',
        error: error,
        stackTrace: stackTrace,
        source: source,
      );
      return null;
    }
  }

  // ======================== 近况切片 ========================

  /// 当前未过期的最近一条近况切片；没有、已过期或内容为空时返回 null。
  Future<AgentMemoryRecentSlice?> currentRecentSlice({DateTime? now}) async {
    if (!isEnabled) {
      return null;
    }
    final slices = await activeRecentSlices(now: now, limit: 1);
    return slices.firstOrNull;
  }

  /// 获取当前所有未过期的活跃近况切片（按观察时间倒序，最多 [limit] 条）。
  Future<List<AgentMemoryRecentSlice>> activeRecentSlices({
    DateTime? now,
    int limit = AgentMemoryRecentSlice.maxRecentSlices,
  }) async {
    if (!isEnabled) {
      return const <AgentMemoryRecentSlice>[];
    }
    final currentTime = (now ?? DateTime.now()).toUtc();
    try {
      final db = await _db;
      final rows = await db.query(
        recentSliceTable,
        orderBy: 'observed_at DESC, id ASC',
      );
      final validSlices = rows
          .map(AgentMemoryRecentSlice.fromMap)
          .where((slice) =>
              slice.content.isNotEmpty && !slice.isExpiredAt(currentTime))
          .toList()
        ..sort((a, b) {
          final cmp = b.observedAt.toUtc().compareTo(a.observedAt.toUtc());
          return cmp != 0 ? cmp : a.id.compareTo(b.id);
        });
      return validSlices.take(limit).toList(growable: false);
    } catch (error, stackTrace) {
      _reportDatabaseError('activeRecentSlices', error, stackTrace);
      rethrow;
    }
  }

  /// 写入一条近况切片（支持多切片与自然时间衰减）。
  ///
  /// [ttl] 默认 [AgentMemoryRecentSlice.defaultTtl]。内容超长按上限截断而不是
  /// 拒绝——归纳出来的东西长了一点就整轮丢掉，代价不对等。
  Future<AgentMemoryRecentSlice?> saveRecentSlice({
    required String content,
    String? id,
    List<String> sourceNoteIds = const <String>[],
    Duration ttl = AgentMemoryRecentSlice.defaultTtl,
    DateTime? observedAt,
  }) async {
    final normalized = normalizeMemoryText(
      content,
      AgentMemoryRecentSlice.maxChars,
    );
    if (normalized.isEmpty) {
      return null;
    }
    final now = (observedAt ?? DateTime.now()).toUtc();
    final slice = AgentMemoryRecentSlice(
      id: id ?? AgentMemoryRecentSlice.singletonId,
      content: normalized,
      observedAt: now,
      expiresAt: now.add(ttl),
      sourceNoteIds: sourceNoteIds,
    );
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.insert(
          recentSliceTable,
          slice.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          tombstonesTable,
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>['slice', slice.id],
        );

        // 严格控制近况切片数量上限，避免切片长期积累膨胀（自动裁剪不写墓碑）
        final allSliceRows = await txn.query(
          recentSliceTable,
          columns: const <String>['id', 'observed_at', 'expires_at'],
        );
        var activeCount = 0;
        for (final row in allSliceRows) {
          final expUtc = _tryParseMemoryUtc(row['expires_at']);
          if (expUtc != null && expUtc.isAfter(now)) {
            activeCount++;
          }
        }
        if (activeCount > AgentMemoryRecentSlice.maxRecentSlices * 2) {
          final sortedSlices = List<Map<String, Object?>>.of(allSliceRows)
            ..sort((a, b) {
              final aObs = _parseMemoryRowVersionUtc(a['observed_at'], null);
              final bObs = _parseMemoryRowVersionUtc(b['observed_at'], null);
              final cmp = bObs.compareTo(aObs);
              if (cmp != 0) return cmp;
              return ((a['id'] as String?) ?? '')
                  .compareTo((b['id'] as String?) ?? '');
            });
          final overflowIds = sortedSlices
              .skip(AgentMemoryRecentSlice.maxRecentSlices)
              .map((r) => r['id'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
          if (overflowIds.isNotEmpty) {
            final placeholders =
                List<String>.filled(overflowIds.length, '?').join(', ');
            await txn.rawDelete(
              'DELETE FROM $recentSliceTable WHERE id IN ($placeholders)',
              overflowIds,
            );
          }
        }
      });

      notifyListeners();
      return slice;
    } catch (error, stackTrace) {
      _reportDatabaseError('saveRecentSlice', error, stackTrace);
      rethrow;
    }
  }

  /// 删除近况切片。若传 [id] 则删除对应切片，否则清空全部切片。
  Future<bool> clearRecentSlice({String? id}) async {
    try {
      final db = await _db;
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      final deleted = await db.transaction<int>((txn) async {
        final existingRows = await txn.query(
          recentSliceTable,
          columns: const <String>['id'],
          where: id != null ? 'id = ?' : null,
          whereArgs: id != null ? <Object?>[id] : null,
        );
        final sliceIds = existingRows
            .map((row) => row['id'])
            .whereType<String>()
            .where((sliceId) => sliceId.isNotEmpty)
            .toList(growable: false);
        if (sliceIds.isEmpty) {
          return 0;
        }
        final count = await txn.delete(
          recentSliceTable,
          where: id != null ? 'id = ?' : null,
          whereArgs: id != null ? <Object?>[id] : null,
        );
        for (final sliceId in sliceIds) {
          await txn.insert(
            tombstonesTable,
            <String, Object?>{
              'entity_type': 'slice',
              'entity_id': sliceId,
              'deleted_at': nowUtcIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return count;
      });
      if (deleted > 0) {
        notifyListeners();
      }
      return deleted > 0;
    } catch (error, stackTrace) {
      _reportDatabaseError('clearRecentSlice', error, stackTrace);
      rethrow;
    }
  }

  /// 纯函数形式的画像块渲染，便于测试预算与时效标注。
  ///
  /// [userNickname] 是用户在设置里填的称呼，钉在画像块最前：它是用户显式
  /// 声明的身份，比模型观察出的条目更权威，不参加排序、也不能被预算挤掉。
  ///
  /// [recentSlices] 支持多切片及自然时间衰减显示（例如「刚刚」、「3 天前」）。
  @visibleForTesting
  static String? renderProfileBlock(
    List<AgentMemoryProfileEntry> entries, {
    required DateTime now,
    String? userNickname,
    AgentMemoryRecentSlice? recentSlice,
    List<AgentMemoryRecentSlice> recentSlices =
        const <AgentMemoryRecentSlice>[],
  }) {
    final sorted = List<AgentMemoryProfileEntry>.of(entries)
      ..sort((left, right) => right.observedAt.compareTo(left.observedAt));

    final lines = <String>[];
    var usedChars = 0;

    final nickname = normalizeMemoryText(userNickname ?? '', nicknameMaxChars);
    if (nickname.isNotEmpty) {
      final line = '- [${_kindLabel(AgentMemoryKind.identity)}·用户填写] '
          '称呼用户为「${escapeUntrustedText(nickname)}」';
      lines.add(line);
      usedChars += line.length;
    }

    for (final entry in sorted) {
      if (lines.length >= profileInjectionMaxEntries) {
        break;
      }
      final line = '- [${_kindLabel(entry.kind)}·'
          '${describeAge(entry.observedAt, now)}] '
          '${escapeUntrustedText(entry.directive)}';
      if (usedChars + line.length > profileInjectionMaxChars) {
        break;
      }
      lines.add(line);
      usedChars += line.length;
    }

    // 合并近况切片候选：优先使用 recentSlices，若为空且 recentSlice != null 则退回单条（兼容旧测试）
    final effectiveSlices = <AgentMemoryRecentSlice>[
      if (recentSlices.isNotEmpty)
        ...recentSlices
      else if (recentSlice != null)
        recentSlice,
    ];

    if (effectiveSlices.isNotEmpty) {
      final unexpiredSlices = effectiveSlices
          .where((s) => !s.isExpiredAt(now))
          .toList()
        ..sort((a, b) => b.observedAt.compareTo(a.observedAt));

      var sliceChars = 0;
      for (final slice
          in unexpiredSlices.take(AgentMemoryRecentSlice.maxRecentSlices)) {
        final content = normalizeMemoryText(
          slice.content,
          AgentMemoryRecentSlice.maxChars,
        );
        if (content.isEmpty) continue;
        final line = '- [近况·${describeAge(slice.observedAt, now)}] '
            '${escapeUntrustedText(content)}';
        if (sliceChars + line.length >
            AgentMemoryRecentSlice.maxRecentTotalChars) {
          break;
        }
        lines.add(line);
        sliceChars += line.length;
      }
    }

    if (lines.isEmpty) {
      return null;
    }

    return wrapUserProfile(lines.join('\n'));
  }

  // ======================== 事实层 ========================

  /// 写入一条长期事实。
  ///
  /// 超过 [factsCapacity] 时淘汰当下得分最低的条目，而不是拒绝写入——
  /// 让模型在对话中处理容量问题只会浪费一轮，用户也看不懂。
  Future<AgentMemoryFact> addFact({
    required String content,
    String? category,
    int importance = 5,
    List<String> triggerPhrases = const <String>[],
    String? sourceRef,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final effectiveCreatedAt = (createdAt ?? DateTime.now()).toUtc();
    final fact = _buildFact(
      content: content,
      category: category,
      importance: importance,
      triggerPhrases: triggerPhrases,
      sourceRef: sourceRef,
      createdAt: effectiveCreatedAt,
      updatedAt: (updatedAt ?? effectiveCreatedAt).toUtc(),
    );

    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.insert(
          factsTable,
          fact.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          tombstonesTable,
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>['fact', fact.id],
        );
        await _evictOverflowFactsInTxn(txn);
      });
    } catch (error, stackTrace) {
      _reportDatabaseError('addFact', error, stackTrace);
      rethrow;
    }
    notifyListeners();
    return fact;
  }

  /// 用新内容替换一条事实。
  ///
  /// 删旧和写新在同一个事务里：分两次写的话，写新失败会让旧事实凭空消失，
  /// 而模型只看到"写入失败"，无从得知记忆已经掉了一条。
  ///
  /// 返回 null 表示 [id] 不存在。
  Future<AgentMemoryFact?> replaceFact({
    required String id,
    required String content,
    String? category,
    int importance = 5,
    List<String> triggerPhrases = const <String>[],
    String? sourceRef,
  }) async {
    try {
      final db = await _db;
      final nowUtc = DateTime.now().toUtc();
      final updated = await db.transaction<AgentMemoryFact?>((txn) async {
        final rows = await txn.query(
          factsTable,
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        if (rows.isEmpty) {
          return null;
        }
        final previous = AgentMemoryFact.fromMap(rows.first);

        // 保留 id 和这条记忆的"履历"：id 变了，模型刚从 recall 拿到的引用当场作废；
        // createdAt 重置会让一条老记忆的 recency 分被拉满；召回计数归零则等于
        // 抹掉它被用过几次。改的是内容，不是换一条新记忆。
        final next = _buildFact(
          id: previous.id,
          content: content,
          category: category,
          importance: importance,
          triggerPhrases: triggerPhrases,
          sourceRef: sourceRef ?? previous.sourceRef,
          createdAt: previous.createdAt,
          updatedAt: nowUtc,
          lastRecalledAt: previous.lastRecalledAt,
          recallCount: previous.recallCount,
        );

        await txn.insert(
          factsTable,
          next.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return next;
      });

      if (updated == null) {
        return null;
      }
      notifyListeners();
      return updated;
    } catch (error, stackTrace) {
      _reportDatabaseError('replaceFact', error, stackTrace);
      rethrow;
    }
  }

  AgentMemoryFact _buildFact({
    required String content,
    String? id,
    String? category,
    int importance = 5,
    List<String> triggerPhrases = const <String>[],
    String? sourceRef,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastRecalledAt,
    int recallCount = 0,
  }) {
    final normalized = normalizeMemoryText(content, factMaxChars);
    if (normalized.isEmpty) {
      throw ArgumentError.value(content, 'content', '事实内容为空');
    }

    final trimmedCategory = category?.trim() ?? '';
    final effectiveCreatedAt = (createdAt ?? DateTime.now()).toUtc();

    return AgentMemoryFact(
      id: id ?? _uuid.v4(),
      content: normalized,
      createdAt: effectiveCreatedAt,
      updatedAt: (updatedAt ?? effectiveCreatedAt).toUtc(),
      lastRecalledAt: lastRecalledAt?.toUtc(),
      recallCount: recallCount,
      category: trimmedCategory.isEmpty ? null : trimmedCategory,
      importance: importance.clamp(
        AgentMemoryFact.minImportance,
        AgentMemoryFact.maxImportance,
      ),
      // 逐条折叠内部空白：trigger_phrases 在库里是换行分隔的一列，
      // 留着内部换行会让一条 phrase 在往返后裂成好几条，还绕过 take(8)。
      triggerPhrases: triggerPhrases
          .map((phrase) =>
              phrase.replaceAll(_whitespaceCollapseRegex, ' ').trim())
          .where((phrase) => phrase.isNotEmpty)
          .take(8)
          .toList(growable: false),
      sourceRef: sourceRef,
    );
  }

  Future<bool> forgetFact(String id) async {
    try {
      final db = await _db;
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      final deleted = await db.transaction<int>((txn) async {
        final count = await txn.delete(
          factsTable,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (count > 0) {
          await txn.insert(
            tombstonesTable,
            <String, Object?>{
              'entity_type': 'fact',
              'entity_id': id,
              'deleted_at': nowUtcIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return count;
      });
      if (deleted > 0) {
        notifyListeners();
      }
      return deleted > 0;
    } catch (error, stackTrace) {
      _reportDatabaseError('forgetFact', error, stackTrace);
      rethrow;
    }
  }

  /// 获取所有事实层条目（供管理界面展示与检索，不触发召回计数递增）。
  Future<List<AgentMemoryFact>> allFacts({
    int limit = factsCapacity,
    String? query,
  }) async {
    try {
      final db = await _db;
      final normalized = query?.trim() ?? '';
      if (normalized.isEmpty) {
        final rows = await db.query(
          factsTable,
          orderBy: 'importance DESC, created_at DESC',
          limit: limit,
        );
        return rows.map(AgentMemoryFact.fromMap).toList(growable: false);
      }

      final keywords = extractKeywords(normalized);
      if (keywords.isEmpty) {
        final rows = await db.query(
          factsTable,
          orderBy: 'importance DESC, created_at DESC',
          limit: limit,
        );
        return rows.map(AgentMemoryFact.fromMap).toList(growable: false);
      }

      final clauses = <String>[];
      final args = <Object?>[];
      for (final keyword in keywords) {
        clauses.add(
          '(content LIKE ? OR trigger_phrases LIKE ? OR category LIKE ?)',
        );
        final pattern = '%$keyword%';
        args.addAll(<Object?>[pattern, pattern, pattern]);
      }
      final rows = await db.query(
        factsTable,
        where: clauses.join(' OR '),
        whereArgs: args,
        orderBy: 'importance DESC, created_at DESC',
        limit: limit,
      );
      return rows.map(AgentMemoryFact.fromMap).toList(growable: false);
    } catch (error, stackTrace) {
      _reportDatabaseError('allFacts', error, stackTrace);
      rethrow;
    }
  }

  /// 按关键词检索事实层。
  ///
  /// [query] 为空时按得分返回最重要的若干条（用户问「你都记得我什么」的路径）。
  Future<List<AgentMemoryFactHit>> searchFacts(
    String query, {
    int limit = recallDefaultLimit,
  }) async {
    try {
      final db = await _db;
      final keywords = extractKeywords(query);
      final now = DateTime.now();

      // 候选窗口取整个 [factsCapacity]：候选截断发生在 SQL 层，而排序在 Dart 层，
      // 两者一旦不一致，就会按 SQLite 未定义的返回顺序丢掉本该排前面的记忆。
      // 事实层本来就有 400 条硬上限，全捞出来再打分是可负担的。
      List<Map<String, Object?>> rows;
      if (keywords.isEmpty) {
        rows = await db.query(
          factsTable,
          orderBy: 'importance DESC, created_at DESC',
          limit: factsCapacity,
        );
      } else {
        // 参数绑定，关键词只作为 LIKE 的值出现，不参与 SQL 拼接。
        final clauses = <String>[];
        final args = <Object?>[];
        for (final keyword in keywords) {
          clauses.add('(content LIKE ? OR trigger_phrases LIKE ? '
              'OR category LIKE ?)');
          final pattern = '%$keyword%';
          args.addAll(<Object?>[pattern, pattern, pattern]);
        }
        rows = await db.query(
          factsTable,
          where: clauses.join(' OR '),
          whereArgs: args,
          limit: factsCapacity,
        );
      }

      final hits = rows
          .map(AgentMemoryFact.fromMap)
          .map(
            (fact) => AgentMemoryFactHit(
              fact: fact,
              score: scoreFact(fact, keywords: keywords, now: now),
            ),
          )
          .where((hit) => hit.score > 0)
          .toList()
        ..sort((left, right) => right.score.compareTo(left.score));

      final selected = hits.take(limit).toList(growable: false);
      _enqueueRecall(selected.map((hit) => hit.fact.id));
      AptabaseHelper.trackEvent('agent_memory_search_facts', {
        'hit_count': selected.length,
        'keyword_count': keywords.length,
      });
      return selected;
    } catch (error, stackTrace) {
      _reportDatabaseError('searchFacts', error, stackTrace);
      rethrow;
    }
  }

  /// relevance × recency 衰减 × importance，公式取自 Generative Agents。
  ///
  /// 查询时不做任何模型调用——排序必须是确定的，否则同一个问题两次问出不同记忆。
  /// 采用核心词与次要/停用词分级加权与完整短语匹配加成机制，避免无意义词数量膨胀稀释核心词得分。
  @visibleForTesting
  static double scoreFact(
    AgentMemoryFact fact, {
    required List<String> keywords,
    required DateTime now,
  }) {
    double relevance;
    if (keywords.isEmpty) {
      relevance = 0.5;
    } else {
      final contentLower = fact.content.toLowerCase();
      final categoryLower = fact.category?.toLowerCase();

      double matchedWeight = 0.0;
      double totalWeight = 0.0;
      final matchedKeywords = <String>[];

      for (final keyword in keywords) {
        final kwLower = keyword.toLowerCase();
        final isStop = isStopWord(kwLower);

        // 分级加权：核心词权重远高于次要/停用虚词；长词/短语基础权重更高
        double weight;
        if (isStop) {
          weight = 0.2;
        } else {
          if (kwLower.length >= 4) {
            weight = 1.5;
          } else if (kwLower.length == 3) {
            weight = 1.25;
          } else {
            weight = 1.0;
          }
        }
        totalWeight += weight;

        final isMatched = contentLower.contains(kwLower) ||
            (categoryLower != null && categoryLower.contains(kwLower)) ||
            fact.triggerPhrases
                .any((phrase) => phrase.toLowerCase().contains(kwLower));

        if (isMatched) {
          matchedWeight += weight;
          matchedKeywords.add(kwLower);
        }
      }

      if (matchedKeywords.isEmpty || matchedWeight <= 0) {
        return 0;
      }

      // 基础相关度（加权匹配占比归一化）
      double baseRelevance = matchedWeight / totalWeight;

      // 如果仅匹配了次要虚词/停用词（未命中任何核心词），大幅降低相关度上限（惩罚纯虚词召回）
      final onlyMatchedStopWords = matchedKeywords.every(isStopWord);
      if (onlyMatchedStopWords) {
        baseRelevance = math.min(baseRelevance, 0.25) * 0.5;
      }

      // 完整短语匹配加成：
      // 1. 命中了长度 >= 3 的核心短语关键词
      // 2. 或者命中的多个关键词在内容中相连拼成短语（例如 "卡片" 与 "笔记" 拼成 "卡片笔记"）
      double phraseBonus = 1.0;
      bool hasPhraseMatch = false;

      if (!onlyMatchedStopWords) {
        if (matchedKeywords.any((k) => k.length >= 3 && !isStopWord(k))) {
          hasPhraseMatch = true;
        } else if (matchedKeywords.length >= 2) {
          for (var i = 0; i < matchedKeywords.length; i++) {
            for (var j = 0; j < matchedKeywords.length; j++) {
              if (i != j) {
                final combined = matchedKeywords[i] + matchedKeywords[j];
                if (contentLower.contains(combined)) {
                  hasPhraseMatch = true;
                  break;
                }
              }
            }
            if (hasPhraseMatch) break;
          }
        }
      }

      if (hasPhraseMatch) {
        phraseBonus = 1.25;
      }

      // 为短语匹配预留得分空间（基础加权上限 0.8，短语加成乘 1.25 后达到 1.0），
      // 确保全词命中时，相连完整短语匹配能有效拉开与散落匹配的分差。
      relevance = math.min(1.0, baseRelevance * 0.8 * phraseBonus);
    }

    final ageDays = now.difference(fact.createdAt).inMinutes / (60 * 24);
    final recency = math.pow(0.5, ageDays / _recencyHalfLifeDays).toDouble();
    final importance = fact.importance / AgentMemoryFact.maxImportance;

    // recency 只做温和衰减：一条两年前的身份事实不该被上周的琐事挤掉。
    return relevance * (0.4 + 0.6 * recency) * (0.5 + 0.5 * importance);
  }

  /// 把查询切成检索关键词。
  ///
  /// 中文按「非分隔符连续片段」切，自动过滤 CJK 停用词与虚词边界噪声，再对长片段补 2 字滑窗。
  /// 保留核心短语并排除常见无意义词，召回与排序在 [scoreFact] 里收敛。
  @visibleForTesting
  static List<String> extractKeywords(String query) {
    final normalized = query.toLowerCase().trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }
    // 复用编译好的正则表达式，避免高频检索时重复创建与编译 RegExp 对象
    final segments = normalized
        .split(_punctuationSplitRegex)
        .where((segment) => segment.isNotEmpty)
        .toList();

    final keywords = <String>{};
    for (final segment in segments) {
      if (_isCjk(segment)) {
        // 先按 CJK 停用词切分，过滤虚词并杜绝跨词滑窗产生的无意义虚词 2-gram
        final cleanParts = segment
            .split(_stopWordsSplitRegex)
            .where((part) => part.isNotEmpty)
            .toList();

        for (final part in cleanParts) {
          // 保留完整片段作为短语关键词（最多 8 字；保留有意义的单字主题词与多字短语）
          if (part.length <= 8 && !isStopWord(part)) {
            keywords.add(part);
          }
          // 对于 3 字及以上的片段，切出 2 字滑窗（例如 "去杭州" 切出 "杭州"，"咖啡馆" 切出 "咖啡" 与 "啡馆"）
          if (part.length >= 3) {
            for (var i = 0; i + 2 <= part.length; i++) {
              final gram = part.substring(i, i + 2);
              if (!isStopWord(gram)) {
                keywords.add(gram);
              }
            }
          }
        }
      } else if (segment.length >= 2 && !isStopWord(segment)) {
        keywords.add(segment);
      }
    }
    return keywords.take(16).toList(growable: false);
  }

  static bool _isCjk(String value) => _cjkRegex.hasMatch(value);

  // ======================== 全局操作 ========================

  /// 清空全部记忆。**开关关闭不会走到这里**——关开关只停读写，不删数据。
  Future<void> clearAll() {
    _settingsService.invalidateAgentMemoryCaptures();
    return _settingsService.withAgentMemoryPolicy(_clearAll);
  }

  Future<void> _clearAll() async {
    try {
      final db = await _db;
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      await db.transaction((txn) async {
        await txn.delete(profileTable);
        await txn.delete(factsTable);
        await txn.delete(recentSliceTable);
        await txn.delete(tombstonesTable);
        await txn.delete(metaTable);
        await txn.insert(
          metaTable,
          <String, Object?>{
            'key': metaClearedAtKey,
            'value': nowUtcIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (error, stackTrace) {
      _reportDatabaseError('clearAll', error, stackTrace);
      rethrow;
    }
    _invalidateProfile();
    _cachedIdentityAliases = const <String>{};
    _settingsService.refreshIdentityAliases();
    if (_settingsService.lastDreamingAt != null) {
      await _settingsService.setLastDreamingAt(null);
    }
    notifyListeners();
    logDebug('已清空 Thoughter 记忆', source: 'AgentMemoryService');
    AptabaseHelper.trackEvent('agent_memory_clear_all');
  }

  /// 记录最近一轮 Dreaming 运行时间及当时的笔记依据水位与数量，供同步导出使用。
  Future<void> recordDreamingRun({
    required DateTime runAt,
    String? basisWatermark,
    int? basisNoteCount,
  }) async {
    try {
      final db = await _db;
      final runAtIso = LWWUtils.formatFixedUtcIso(runAt);
      final cleanWatermark =
          (basisWatermark != null && basisWatermark.trim().isNotEmpty)
              ? basisWatermark.trim()
              : null;
      await db.transaction((txn) async {
        await txn.insert(
          metaTable,
          <String, Object?>{
            'key': metaDreamingLastRunAtKey,
            'value': runAtIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (cleanWatermark != null) {
          await txn.insert(
            metaTable,
            <String, Object?>{
              'key': metaDreamingBasisWatermarkKey,
              'value': cleanWatermark,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.delete(
            metaTable,
            where: 'key = ?',
            whereArgs: <Object?>[metaDreamingBasisWatermarkKey],
          );
        }
        if (basisNoteCount != null) {
          await txn.insert(
            metaTable,
            <String, Object?>{
              'key': metaDreamingBasisNoteCountKey,
              'value': basisNoteCount.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.delete(
            metaTable,
            where: 'key = ?',
            whereArgs: <Object?>[metaDreamingBasisNoteCountKey],
          );
        }
      });
    } catch (error, stackTrace) {
      _reportDatabaseError('recordDreamingRun', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _clearDreamingMeta() async {
    try {
      final db = await _db;
      await db.delete(
        metaTable,
        where: 'key IN (?, ?, ?)',
        whereArgs: <Object?>[
          metaDreamingLastRunAtKey,
          metaDreamingBasisWatermarkKey,
          metaDreamingBasisNoteCountKey,
        ],
      );
    } catch (error, stackTrace) {
      _reportDatabaseError('clearDreamingMeta', error, stackTrace);
    }
  }

  /// 周期性记忆库压缩与精简（基于 OpenClaw / Mem0 实践，严格控制噪音与记忆膨胀）。
  ///
  /// 执行内容：
  /// 1. 清理已过期的近况切片（[expiresAt] <= now）；
  /// 2. 清理过旧的已废弃画像（superseded 超过 30 天，且最多保留最新 10 条审计）；
  /// 3. 淘汰衰减低价值事实（importance <= 3、recallCount == 0 且创建于 30 天之前）；
  /// 4. 去除内容完全重复的 active 画像条目。
  Future<MemoryCompactionStats> compactAndPrune({DateTime? now}) async {
    try {
      final db = await _db;
      final currentTime = (now ?? DateTime.now()).toUtc();
      final thirtyDaysAgo = currentTime.subtract(const Duration(days: 30));

      var expiredSlices = 0;
      var supersededProfiles = 0;
      var decayedFacts = 0;
      var duplicatesPruned = 0;
      var profileStateMutated = false;

      // 若已挂载依据判定器且当前存在多条活跃 Dreaming 画像条目，
      // 在开启记忆库事务前批量预评估各条目的 basis 覆盖状态，避免事务内跨库异步等待。
      bool Function(String? watermark, int? noteCount)? syncCheckCovered;
      final checker = _basisChecker;
      if (checker != null) {
        final basisRows = await db.query(
          profileTable,
          columns: const <String>[
            'source',
            'status',
            'basis_watermark',
            'basis_note_count',
          ],
        );
        var activeDreamingCount = 0;
        final basisPairs = <(String, int)>{};
        for (final row in basisRows) {
          if (!_isDreamingMemorySource(row['source'])) continue;
          if (row['status'] == AgentMemoryStatus.active.storageValue) {
            activeDreamingCount++;
          }
          final wmRaw = row['basis_watermark'];
          if (wmRaw is! String) continue;
          final wm = wmRaw.trim();
          final cnt = _parseMemoryOptionalInt(row['basis_note_count']);
          if (wm.isEmpty || cnt == null || cnt < 0) continue;
          if (_tryParseMemoryUtc(wm) == null) continue;
          basisPairs.add((wm, cnt));
        }
        if (activeDreamingCount > 1) {
          try {
            final coverageCache = basisPairs.isEmpty
                ? const <(String, int), bool>{}
                : await checker(basisPairs);
            syncCheckCovered = (String? wm, int? cnt) {
              if (wm == null || cnt == null || cnt < 0) return false;
              final trimmed = wm.trim();
              if (trimmed.isEmpty) return false;
              return coverageCache[(trimmed, cnt)] ?? false;
            };
          } catch (error) {
            logDebug(
              '压缩前预评估 Dreaming 依据覆盖失败，降级为纯时间序活跃去重 (${error.runtimeType})',
              source: 'AgentMemoryService',
            );
          }
        }
      }

      await db.transaction((txn) async {
        // 1. 清理已过期的近况切片（按实际时间解析比较，兼容无显式时区旧历史列）
        final sliceRows = await txn.query(
          recentSliceTable,
          columns: const <String>['id', 'observed_at', 'expires_at'],
        );
        final expiredSliceIds = <String>[];
        final activeSliceRows = <Map<String, Object?>>[];
        for (final row in sliceRows) {
          final id = row['id'] as String?;
          if (id == null || id.isEmpty) continue;
          final expUtc = _tryParseMemoryUtc(row['expires_at']);
          if (expUtc != null && !expUtc.isAfter(currentTime)) {
            expiredSliceIds.add(id);
          } else {
            activeSliceRows.add(row);
          }
        }
        if (expiredSliceIds.isNotEmpty) {
          final placeholders =
              List<String>.filled(expiredSliceIds.length, '?').join(', ');
          expiredSlices = await txn.rawDelete(
            'DELETE FROM $recentSliceTable WHERE id IN ($placeholders)',
            expiredSliceIds,
          );
        }

        // 2. 活跃画像分叉收敛、单例唯一性、身份别名收敛、同 kind+directive 去重，
        //    以及自愈恢复曾被后台 dreaming* 误置为 superseded 的人工/显式画像
        //    （绝不复活同步淘汰的 dreaming* 行或被用户新指令替换的历史行）
        final convergence = await _convergeProfilesInTxn(
          txn,
          includeSupersededCandidates: false,
          isBasisCovered: syncCheckCovered,
        );
        duplicatesPruned = convergence.supersededCount;
        profileStateMutated = convergence.didMutate;

        // 3. 清理超过 30 天或超出 10 条保留上限的 superseded 画像审计历史条目
        final supProfileRows = await txn.query(
          profileTable,
          columns: const <String>['id', 'observed_at'],
          where: 'status = ?',
          whereArgs: <Object?>[AgentMemoryStatus.superseded.storageValue],
        );
        if (supProfileRows.isNotEmpty) {
          final sortedSup = List<Map<String, Object?>>.of(supProfileRows)
            ..sort((a, b) {
              final aObs = _parseMemoryRowVersionUtc(a['observed_at'], null);
              final bObs = _parseMemoryRowVersionUtc(b['observed_at'], null);
              final cmp = bObs.compareTo(aObs);
              if (cmp != 0) return cmp;
              return ((a['id'] as String?) ?? '')
                  .compareTo((b['id'] as String?) ?? '');
            });
          final pruneSupIds = <String>[];
          for (var i = 0; i < sortedSup.length; i++) {
            final row = sortedSup[i];
            final id = row['id'] as String?;
            if (id == null || id.isEmpty) continue;
            final obsUtc = _parseMemoryRowVersionUtc(row['observed_at'], null);
            if (i >= 10 || obsUtc.isBefore(thirtyDaysAgo)) {
              pruneSupIds.add(id);
            }
          }
          if (pruneSupIds.isNotEmpty) {
            await _recordPrunedProfileReplacementsInTxn(txn, pruneSupIds);
            final placeholders =
                List<String>.filled(pruneSupIds.length, '?').join(', ');
            supersededProfiles = await txn.rawDelete(
              'DELETE FROM $profileTable WHERE id IN ($placeholders)',
              pruneSupIds,
            );
          }
        }

        // 4. 淘汰低价值衰减事实：重要度 <= 3、从未召回过、且创建于 30 天之前
        final candidateFactRows = await txn.query(
          factsTable,
          columns: const <String>['id', 'created_at'],
          where: 'importance <= 3 AND recall_count = 0',
        );
        final pruneFactIds = <String>[];
        for (final row in candidateFactRows) {
          final id = row['id'] as String?;
          if (id == null || id.isEmpty) continue;
          final createdUtc = _tryParseMemoryUtc(row['created_at']);
          if (createdUtc != null && createdUtc.isBefore(thirtyDaysAgo)) {
            pruneFactIds.add(id);
          }
        }
        if (pruneFactIds.isNotEmpty) {
          final placeholders =
              List<String>.filled(pruneFactIds.length, '?').join(', ');
          decayedFacts = await txn.rawDelete(
            'DELETE FROM $factsTable WHERE id IN ($placeholders)',
            pruneFactIds,
          );
        }

        // 5. 修剪超出容量的过旧近况切片（仅保留最新的 maxRecentSlices 条活跃切片）
        if (activeSliceRows.length > AgentMemoryRecentSlice.maxRecentSlices) {
          activeSliceRows.sort((a, b) {
            final aObs = _parseMemoryRowVersionUtc(a['observed_at'], null);
            final bObs = _parseMemoryRowVersionUtc(b['observed_at'], null);
            final cmp = bObs.compareTo(aObs);
            if (cmp != 0) return cmp;
            return ((a['id'] as String?) ?? '')
                .compareTo((b['id'] as String?) ?? '');
          });
          final overflowSliceIds = activeSliceRows
              .skip(AgentMemoryRecentSlice.maxRecentSlices)
              .map((r) => r['id'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
          if (overflowSliceIds.isNotEmpty) {
            final placeholders =
                List<String>.filled(overflowSliceIds.length, '?').join(', ');
            await txn.rawDelete(
              'DELETE FROM $recentSliceTable WHERE id IN ($placeholders)',
              overflowSliceIds,
            );
          }
        }
      });

      if (duplicatesPruned > 0 || profileStateMutated) {
        _invalidateProfile();
        await activeIdentityAliases();
        _settingsService.refreshIdentityAliases();
      }

      final stats = MemoryCompactionStats(
        expiredSlicesPruned: expiredSlices,
        supersededProfilesPruned: supersededProfiles,
        decayedFactsPruned: decayedFacts,
        duplicatesPruned: duplicatesPruned,
      );

      if (stats.totalPruned > 0) {
        logDebug(
          '记忆库完成压缩裁剪: 清理过期近况 $expiredSlices 条, 淘汰旧画像 $supersededProfiles 条, '
          '修剪衰减事实 $decayedFacts 条, 去重 $duplicatesPruned 条',
          source: 'AgentMemoryService',
        );
      }

      AptabaseHelper.trackEvent('agent_memory_compact', {
        'expired_slices': stats.expiredSlicesPruned,
        'superseded_profiles': stats.supersededProfilesPruned,
        'decayed_facts': stats.decayedFactsPruned,
        'duplicates_pruned': stats.duplicatesPruned,
        'total_pruned': stats.totalPruned,
      });

      return stats;
    } catch (error, stackTrace) {
      _reportDatabaseError('compactAndPrune', error, stackTrace);
      rethrow;
    }
  }

  Future<({int profileCount, int factCount})> counts() async {
    try {
      final db = await _db;
      final profileRows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $profileTable WHERE status = ?',
        <Object?>[AgentMemoryStatus.active.storageValue],
      );
      final factRows =
          await db.rawQuery('SELECT COUNT(*) AS c FROM $factsTable');
      return (
        profileCount: (profileRows.first['c'] as num?)?.toInt() ?? 0,
        factCount: (factRows.first['c'] as num?)?.toInt() ?? 0,
      );
    } catch (error, stackTrace) {
      _reportDatabaseError('counts', error, stackTrace);
      rethrow;
    }
  }

  /// 把时间点说成模型能直接用的年龄。
  ///
  /// 原始时间戳触发不了时效推理——模型对日期算术不敏感，「47 天前」才会让它
  /// 想起来先核对当前状态。
  static String describeAge(DateTime observedAt, DateTime now) {
    final gap = now.difference(observedAt);
    if (gap.inMinutes < 60) return '刚刚';
    if (gap.inHours < 24) return '${gap.inHours} 小时前';
    if (gap.inDays < 60) return '${gap.inDays} 天前';
    return '${(gap.inDays / 30).round()} 个月前';
  }

  void _invalidateProfile() {
    _activeProfileCache = null;
    notifyListeners();
  }

  final List<String> _pendingRecallIds = <String>[];
  bool _isFlushingRecallQueue = false;

  void _enqueueRecall(Iterable<String> ids) {
    if (ids.isEmpty) return;
    _pendingRecallIds.addAll(ids);
    unawaited(_flushRecallQueue());
  }

  Future<void> _flushRecallQueue() async {
    if (_isFlushingRecallQueue || _pendingRecallIds.isEmpty) return;
    _isFlushingRecallQueue = true;
    try {
      while (_pendingRecallIds.isNotEmpty) {
        if (_disposed) break;
        final batch = _pendingRecallIds.toList();
        _pendingRecallIds.clear();

        try {
          final db = await _db;
          if (!db.isOpen || _disposed) break;

          final counts = <String, int>{};
          for (final id in batch) {
            counts[id] = (counts[id] ?? 0) + 1;
          }
          final nowStr = LWWUtils.formatFixedUtcIso(DateTime.now());

          await db.transaction((txn) async {
            for (final entry in counts.entries) {
              await txn.rawUpdate(
                'UPDATE $factsTable SET recall_count = recall_count + ?, '
                'last_recalled_at = ? WHERE id = ?',
                <Object?>[entry.value, nowStr, entry.key],
              );
            }
          });
        } catch (error, stackTrace) {
          _pendingRecallIds.insertAll(0, batch);
          _reportDatabaseError('flushRecallQueue', error, stackTrace);
          break;
        }
      }
    } finally {
      _isFlushingRecallQueue = false;
      if (!_disposed && _pendingRecallIds.isNotEmpty) {
        unawaited(_rescheduleFlushQueue());
      }
    }
  }

  Future<void> _rescheduleFlushQueue() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!_disposed && _pendingRecallIds.isNotEmpty) {
      await _flushRecallQueue();
    }
  }

  static Future<void> _evictOverflowFactsInTxn(
    DatabaseExecutor db, {
    DateTime? now,
  }) async {
    final countRows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM $factsTable');
    final total = (countRows.first['c'] as num?)?.toInt() ?? 0;
    final overflowCount = total - factsCapacity;
    if (overflowCount <= 0) {
      return;
    }

    final rows = await db.query(factsTable);
    final refNow = now ?? DateTime.now();
    final scored = rows
        .map(AgentMemoryFact.fromMap)
        .map(
          (fact) => AgentMemoryFactHit(
            fact: fact,
            score: scoreFact(fact, keywords: const <String>[], now: refNow),
          ),
        )
        .toList()
      ..sort((left, right) {
        final cmp = left.score.compareTo(right.score);
        if (cmp != 0) return cmp;
        return right.fact.id.compareTo(left.fact.id);
      });

    final victims = scored
        .take(overflowCount)
        .map((hit) => hit.fact.id)
        .toList(growable: false);
    if (victims.isEmpty) {
      return;
    }
    final placeholders = List<String>.filled(victims.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM $factsTable WHERE id IN ($placeholders)',
      victims,
    );
    logDebug(
      '记忆事实层超出容量，淘汰 ${victims.length} 条',
      source: 'AgentMemoryService',
    );
  }

  String _normalizeDirective(String value) =>
      normalizeMemoryText(value, directiveMaxChars);

  /// 折叠空白并截断到 [maxChars]。静态方法：画像块渲染（纯函数）也要用。
  static String normalizeMemoryText(String value, int maxChars) {
    final collapsed = value.replaceAll(_whitespaceCollapseRegex, ' ').trim();
    if (collapsed.length <= maxChars) {
      return collapsed;
    }
    var truncated = collapsed.substring(0, maxChars);
    // substring 按 UTF-16 code unit 切，正好切在代理对中间会留下一个孤立的
    // 高代理码位，写进 SQLite 时无法合法编码成 UTF-8。丢掉这半个字符。
    if (truncated.isNotEmpty) {
      final last = truncated.codeUnitAt(truncated.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        truncated = truncated.substring(0, truncated.length - 1);
      }
    }
    return truncated.trimRight();
  }

  static String _kindLabel(AgentMemoryKind kind) {
    return switch (kind) {
      AgentMemoryKind.identity => '身份',
      AgentMemoryKind.preference => '偏好',
      AgentMemoryKind.style => '表达',
      AgentMemoryKind.feedback => '纠正',
      AgentMemoryKind.taste => '品味',
      AgentMemoryKind.voice => '文风',
    };
  }
}

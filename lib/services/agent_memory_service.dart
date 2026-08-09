import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_memory.dart';
import '../utils/app_logger.dart';
import '../utils/untrusted_text.dart';
import 'data_directory_service.dart';
import 'settings_service.dart';

/// Thoughter 的长期记忆。
///
/// 两层，职责严格分开：
/// - **画像层**（`agent_memory_profile`）：身份与表达偏好，每次对话注入，有硬预算；
/// - **事实层**（`agent_memory_facts`）：细节，不注入，靠 `recall` 工具按需检索。
///
/// 边界：记忆只存**从笔记里推导不出来**的东西。用户写过什么归 `explore_notes`，
/// 两套检索各管一摊，否则模型会在两个来源之间反复横跳。
///
/// **独立数据库文件 `agent_memory.db`**，和聊天记录、日志、AI 分析一样不进主库：
/// 记忆是对用户的行为画像，物理隔离让"不进备份、不跨设备同步、一键清干净"变成
/// 文件层面的事实，而不是"备份代码恰好没导出这两张表"的隐式约定。主库的 schema
/// 版本号也不必为了记忆往上走。
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
    activeInstance = this;
  }

  /// 当前活跃实例，供 `DataDirectoryService` 在迁移数据目录前关闭连接。
  /// 与 `ChatSessionService.activeInstance` 同一模式。
  static AgentMemoryService? activeInstance;

  final SettingsService _settingsService;
  final String? _databasePath;
  final Uuid _uuid = const Uuid();

  Database? _database;
  Completer<Database>? _opening;
  bool _closed = false;

  static const String databaseFileName = 'agent_memory.db';

  /// 记忆库自己的 schema 版本，与主库的 `schemaVersion` 无关。
  static const int schemaVersion = 1;

  static const String profileTable = 'agent_memory_profile';
  static const String factsTable = 'agent_memory_facts';

  /// 画像层注入预算。超出时按「最近观察优先」截断注入副本，**不删库里的条目**。
  static const int profileInjectionMaxEntries = 24;
  static const int profileInjectionMaxChars = 1200;

  /// 单条指令长度上限，防止模型把一整段对话当成一条偏好塞进来。
  static const int directiveMaxChars = 200;

  /// 单条事实长度上限。
  static const int factMaxChars = 600;

  /// `recall` 单次返回的事实条数上限。
  static const int recallDefaultLimit = 8;

  /// 事实层容量上限。超出后由 [addFact] 淘汰得分最低的条目。
  static const int factsCapacity = 400;

  /// 相关度衰减半衰期，取自 Generative Agents 的记忆流打分。
  static const double _recencyHalfLifeDays = 30;

  List<AgentMemoryProfileEntry>? _activeProfileCache;

  bool get isEnabled => _settingsService.agentMemoryEnabled;

  Future<Database> get _db async {
    final current = _database;
    if (current != null && current.isOpen) {
      return current;
    }
    final opening = _opening;
    if (opening != null) {
      return opening.future;
    }

    if (_closed) {
      throw StateError('AgentMemoryService 已关闭');
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
      // dispose/close 可能发生在打开过程中：那时 _database 还是 null，
      // 关不到任何东西，而这个连接一旦落到 _database 上就再没人管了。
      if (_closed) {
        await db.close();
        throw StateError('AgentMemoryService 已关闭');
      }
      _database = db;
      completer.complete(db);
      return db;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  /// 关闭连接并冲刷 WAL。
  ///
  /// 迁移数据目录前必须调用：复制的是 SQLite 文件本体，没 checkpoint 的话
  /// 最近的写入会留在旧目录的 WAL 里。
  Future<void> close() async {
    _closed = true;
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
      await db.execute('PRAGMA wal_checkpoint(FULL);');
    } catch (error, stackTrace) {
      logError(
        '记忆库 WAL checkpoint 失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
        source: 'AgentMemoryService',
      );
    }
    try {
      await db.close();
    } catch (error, stackTrace) {
      logError(
        '关闭记忆库失败',
        error: error.runtimeType,
        stackTrace: stackTrace,
        source: 'AgentMemoryService',
      );
    }
  }

  static Future<String> _defaultDatabasePath() async {
    final basePath = Platform.isWindows
        ? await DataDirectoryService.getCurrentDataDirectory()
        : (await getApplicationDocumentsDirectory()).path;
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
        status TEXT NOT NULL DEFAULT 'active',
        superseded_by TEXT,
        source TEXT
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
        last_recalled_at TEXT,
        recall_count INTEGER NOT NULL DEFAULT 0,
        source_ref TEXT,
        embedding BLOB
      )
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
  }

  @override
  void dispose() {
    if (identical(activeInstance, this)) {
      activeInstance = null;
    }
    unawaited(close());
    super.dispose();
  }

  // ======================== 画像层 ========================

  /// 全部 active 画像条目，按观察时间倒序。
  Future<List<AgentMemoryProfileEntry>> activeProfile() async {
    final cached = _activeProfileCache;
    if (cached != null) {
      return cached;
    }
    final db = await _db;
    final rows = await db.query(
      profileTable,
      where: 'status = ?',
      whereArgs: <Object?>[AgentMemoryStatus.active.storageValue],
      orderBy: 'observed_at DESC',
    );
    final entries =
        rows.map(AgentMemoryProfileEntry.fromMap).toList(growable: false);
    _activeProfileCache = entries;
    return entries;
  }

  /// 含已 supersede 的全部条目，供设置页与排查使用。
  Future<List<AgentMemoryProfileEntry>> allProfileEntries() async {
    final db = await _db;
    final rows = await db.query(profileTable, orderBy: 'observed_at DESC');
    return rows.map(AgentMemoryProfileEntry.fromMap).toList(growable: false);
  }

  /// 写入一条画像指令。
  ///
  /// [replacesId] 非空时把旧条目原位 supersede——偏好变了就替换，绝不让两条
  /// 互相矛盾的 active 指令同时存在（模型会随机挑一条遵守）。
  Future<AgentMemoryProfileEntry> rememberProfile({
    required AgentMemoryKind kind,
    required String directive,
    String? replacesId,
    String source = 'thoughter',
    DateTime? observedAt,
  }) async {
    final normalized = _normalizeDirective(directive);
    if (normalized.isEmpty) {
      throw ArgumentError.value(directive, 'directive', '指令内容为空');
    }

    final db = await _db;
    final entry = AgentMemoryProfileEntry(
      id: _uuid.v4(),
      kind: kind,
      directive: normalized,
      observedAt: observedAt ?? DateTime.now(),
      source: source,
    );

    await db.transaction((txn) async {
      if (replacesId != null && replacesId.isNotEmpty) {
        await txn.update(
          profileTable,
          <String, Object?>{
            'status': AgentMemoryStatus.superseded.storageValue,
            'superseded_by': entry.id,
          },
          where: 'id = ?',
          whereArgs: <Object?>[replacesId],
        );
      }
      await txn.insert(
        profileTable,
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _invalidateProfile();
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
    final db = await _db;
    final updated = await db.update(
      profileTable,
      <String, Object?>{
        'directive': normalized,
        'observed_at': DateTime.now().toIso8601String(),
        if (kind != null) 'kind': kind.storageValue,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updated > 0) {
      _invalidateProfile();
    }
    return updated > 0;
  }

  /// 删除一条画像指令。用户说「忘掉这个」时用，是真删不是 supersede。
  Future<bool> forgetProfile(String id) async {
    final db = await _db;
    final deleted = await db.delete(
      profileTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (deleted > 0) {
      _invalidateProfile();
    }
    return deleted > 0;
  }

  /// 渲染注入模型的画像块。记忆关闭或没有条目时返回 null。
  ///
  /// 输出是一条独立的用户数据消息，不进系统提示——和绑定笔记的做法一致，
  /// 避免把「用户偏好」和「行为准则」混成同一层权限。
  Future<String?> buildProfileBlock() async {
    if (!isEnabled) {
      return null;
    }
    final entries = await activeProfile();
    if (entries.isEmpty) {
      return null;
    }
    return renderProfileBlock(entries, now: DateTime.now());
  }

  /// [buildProfileBlock] 的降级包装：读不到就当没有画像。
  ///
  /// Agent 和每日提示/洞察都走这一个入口——记忆是增益，一次数据库异常不能把
  /// 整轮对话或每日提示打掉；降级策略只有一份，以后要加缓存或限流也只改这里。
  Future<String?> safeProfileBlock({required String source}) async {
    try {
      return await buildProfileBlock();
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

  /// 纯函数形式的画像块渲染，便于测试预算与时效标注。
  @visibleForTesting
  static String? renderProfileBlock(
    List<AgentMemoryProfileEntry> entries, {
    required DateTime now,
  }) {
    if (entries.isEmpty) {
      return null;
    }
    final sorted = List<AgentMemoryProfileEntry>.of(entries)
      ..sort((left, right) => right.observedAt.compareTo(left.observedAt));

    final lines = <String>[];
    var usedChars = 0;
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
  }) async {
    final fact = _buildFact(
      content: content,
      category: category,
      importance: importance,
      triggerPhrases: triggerPhrases,
      sourceRef: sourceRef,
      createdAt: createdAt,
    );

    final db = await _db;
    await db.insert(
      factsTable,
      fact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _evictOverflowFacts();
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
    final db = await _db;
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
  }

  AgentMemoryFact _buildFact({
    required String content,
    String? id,
    String? category,
    int importance = 5,
    List<String> triggerPhrases = const <String>[],
    String? sourceRef,
    DateTime? createdAt,
    DateTime? lastRecalledAt,
    int recallCount = 0,
  }) {
    final normalized = _normalizeText(content, factMaxChars);
    if (normalized.isEmpty) {
      throw ArgumentError.value(content, 'content', '事实内容为空');
    }

    final trimmedCategory = category?.trim() ?? '';

    return AgentMemoryFact(
      id: id ?? _uuid.v4(),
      content: normalized,
      createdAt: createdAt ?? DateTime.now(),
      lastRecalledAt: lastRecalledAt,
      recallCount: recallCount,
      category: trimmedCategory.isEmpty ? null : trimmedCategory,
      importance: importance.clamp(
        AgentMemoryFact.minImportance,
        AgentMemoryFact.maxImportance,
      ),
      // 逐条折叠内部空白：trigger_phrases 在库里是换行分隔的一列，
      // 留着内部换行会让一条 phrase 在往返后裂成好几条，还绕过 take(8)。
      triggerPhrases: triggerPhrases
          .map((phrase) => phrase.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((phrase) => phrase.isNotEmpty)
          .take(8)
          .toList(growable: false),
      sourceRef: sourceRef,
    );
  }

  Future<bool> forgetFact(String id) async {
    final db = await _db;
    final deleted = await db.delete(
      factsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (deleted > 0) {
      notifyListeners();
    }
    return deleted > 0;
  }

  /// 按关键词检索事实层。
  ///
  /// [query] 为空时按得分返回最重要的若干条（用户问「你都记得我什么」的路径）。
  Future<List<AgentMemoryFactHit>> searchFacts(
    String query, {
    int limit = recallDefaultLimit,
  }) async {
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
    await _markRecalled(selected.map((hit) => hit.fact.id));
    return selected;
  }

  /// relevance × recency 衰减 × importance，公式取自 Generative Agents。
  ///
  /// 查询时不做任何模型调用——排序必须是确定的，否则同一个问题两次问出不同记忆。
  @visibleForTesting
  static double scoreFact(
    AgentMemoryFact fact, {
    required List<String> keywords,
    required DateTime now,
  }) {
    final haystack = <String>[
      fact.content,
      fact.category ?? '',
      ...fact.triggerPhrases,
    ].join('\n').toLowerCase();

    double relevance;
    if (keywords.isEmpty) {
      relevance = 0.5;
    } else {
      final matched =
          keywords.where((keyword) => haystack.contains(keyword)).length;
      if (matched == 0) {
        return 0;
      }
      relevance = matched / keywords.length;
    }

    final ageDays = now.difference(fact.createdAt).inMinutes / (60 * 24);
    final recency = math.pow(0.5, ageDays / _recencyHalfLifeDays).toDouble();
    final importance = fact.importance / AgentMemoryFact.maxImportance;

    // recency 只做温和衰减：一条两年前的身份事实不该被上周的琐事挤掉。
    return relevance * (0.4 + 0.6 * recency) * (0.5 + 0.5 * importance);
  }

  /// 把查询切成检索关键词。
  ///
  /// 中文按「非分隔符连续片段」切，再对长片段补 2 字滑窗——没有分词器时这是
  /// 用 LIKE 捞中文候选的务实办法，召回宁多勿少，排序在 [scoreFact] 里收敛。
  @visibleForTesting
  static List<String> extractKeywords(String query) {
    final normalized = query.toLowerCase().trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }
    final segments = normalized
        .split(RegExp(r'[\s,，。、；;:：!！?？"'
            '‘’“”()（）\\[\\]【】<>《》/\\\\|~`@#\$%^&*+=_-]+'))
        .where((segment) => segment.isNotEmpty)
        .toList();

    final keywords = <String>{};
    for (final segment in segments) {
      if (_isCjk(segment)) {
        if (segment.length <= 3) {
          keywords.add(segment);
        } else {
          for (var i = 0; i + 2 <= segment.length; i++) {
            keywords.add(segment.substring(i, i + 2));
          }
        }
      } else if (segment.length >= 2) {
        keywords.add(segment);
      }
    }
    return keywords.take(12).toList(growable: false);
  }

  static bool _isCjk(String value) => RegExp(r'[一-鿿]').hasMatch(value);

  // ======================== 全局操作 ========================

  /// 清空全部记忆。**开关关闭不会走到这里**——关开关只停读写，不删数据。
  Future<void> clearAll() async {
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.delete(profileTable);
        await txn.delete(factsTable);
      });
    } catch (error, stackTrace) {
      logError(
        '清空 Thoughter 记忆失败',
        error: error,
        stackTrace: stackTrace,
        source: 'AgentMemoryService',
      );
      rethrow;
    }
    _invalidateProfile();
    logDebug('已清空 Thoughter 记忆', source: 'AgentMemoryService');
  }

  Future<({int profileCount, int factCount})> counts() async {
    final db = await _db;
    final profileRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $profileTable WHERE status = ?',
      <Object?>[AgentMemoryStatus.active.storageValue],
    );
    final factRows = await db.rawQuery('SELECT COUNT(*) AS c FROM $factsTable');
    return (
      profileCount: (profileRows.first['c'] as int?) ?? 0,
      factCount: (factRows.first['c'] as int?) ?? 0,
    );
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

  Future<void> _markRecalled(Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) {
      return;
    }
    final db = await _db;
    final placeholders = List<String>.filled(idList.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE $factsTable SET recall_count = recall_count + 1, '
      'last_recalled_at = ? WHERE id IN ($placeholders)',
      <Object?>[DateTime.now().toIso8601String(), ...idList],
    );
  }

  Future<void> _evictOverflowFacts() async {
    final db = await _db;
    final countRows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM $factsTable');
    final total = (countRows.first['c'] as int?) ?? 0;
    if (total <= factsCapacity) {
      return;
    }

    final rows = await db.query(factsTable);
    final now = DateTime.now();
    final scored = rows
        .map(AgentMemoryFact.fromMap)
        .map(
          (fact) => AgentMemoryFactHit(
            fact: fact,
            score: scoreFact(fact, keywords: const <String>[], now: now),
          ),
        )
        .toList()
      ..sort((left, right) => left.score.compareTo(right.score));

    final victims = scored
        .take(total - factsCapacity)
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
      _normalizeText(value, directiveMaxChars);

  String _normalizeText(String value, int maxChars) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
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
    };
  }
}

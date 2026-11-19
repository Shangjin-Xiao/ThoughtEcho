import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late SettingsService settingsService;
  late AgentMemoryService memory;

  setUpAll(() async {
    await TestHarness.initialize();
    await AppPreferencesService().init();
  });

  tearDownAll(TestHarness.tearDown);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agent_memory_sync_test_');
    dbPath = p.join(tempDir.path, 'agent_memory.db');
    await AppPreferencesService().clear();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settingsService = SettingsService(await SharedPreferences.getInstance());
    await settingsService.setAgentMemoryEnabled(true);
    memory = AgentMemoryService(
      settingsService: settingsService,
      databasePath: dbPath,
    );
  });

  tearDown(() async {
    memory.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    SharedPreferences.resetStatic();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<Map<String, Object?>>> queryTombstones(String path) async {
    final db = await openDatabase(path, singleInstance: true);
    return db.query(
      AgentMemoryService.tombstonesTable,
      orderBy: 'entity_type ASC, entity_id ASC',
    );
  }

  group('agent_memory.db schema v2 -> v3 迁移', () {
    test('回填 updated_at、按 superseded_by 反推回填 replaces_id 并创建墓碑与元数据表', () async {
      final legacyPath = p.join(tempDir.path, 'legacy_v2_memory.db');
      final rawV2 = await openDatabase(
        legacyPath,
        version: 2,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE agent_memory_profile (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              directive TEXT NOT NULL,
              observed_at TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'active',
              superseded_by TEXT,
              source TEXT,
              source_note_ids TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE agent_memory_facts (
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
          await db.execute('''
            CREATE TABLE agent_memory_recent_slice (
              id TEXT PRIMARY KEY,
              content TEXT NOT NULL,
              observed_at TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              source_note_ids TEXT
            )
          ''');
        },
      );

      await rawV2.insert('agent_memory_profile', <String, Object?>{
        'id': 'prof_old',
        'kind': 'style',
        'directive': '旧版长段回复指令',
        'observed_at': '2026-09-01T08:00:00.000Z',
        'status': 'superseded',
        'superseded_by': 'prof_new',
      });
      await rawV2.insert('agent_memory_profile', <String, Object?>{
        'id': 'prof_new',
        'kind': 'style',
        'directive': '新版简洁回复指令',
        'observed_at': '2026-09-10T09:30:00.000Z',
        'status': 'active',
      });
      await rawV2.insert('agent_memory_facts', <String, Object?>{
        'id': 'fact_v2',
        'category': 'project',
        'content': '用户正在构建本地优先工具',
        'importance': 7,
        'created_at': '2026-09-05T10:00:00.000Z',
        'recall_count': 3,
      });
      await rawV2.close();

      final upgraded = AgentMemoryService(
        settingsService: settingsService,
        databasePath: legacyPath,
      );
      try {
        final entries = await upgraded.allProfileEntries();
        final byId = <String, AgentMemoryProfileEntry>{
          for (final e in entries) e.id: e,
        };
        expect(
          byId['prof_old']!.updatedAt?.toUtc().toIso8601String(),
          '2026-09-01T08:00:00.000Z',
        );
        expect(
          byId['prof_new']!.updatedAt?.toUtc().toIso8601String(),
          '2026-09-10T09:30:00.000Z',
        );
        expect(byId['prof_new']!.replacesId, 'prof_old');

        final facts = await upgraded.allFacts();
        expect(facts, hasLength(1));
        expect(
          facts.single.updatedAt?.toUtc().toIso8601String(),
          '2026-09-05T10:00:00.000Z',
        );

        final inspectDb = await openDatabase(legacyPath, singleInstance: true);
        expect(await inspectDb.getVersion(), 3);
        expect(
          await inspectDb.query(AgentMemoryService.tombstonesTable),
          isEmpty,
        );
        expect(await inspectDb.query(AgentMemoryService.metaTable), isEmpty);
      } finally {
        upgraded.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
  });

  group('写入墓碑边界与 clearAll 清空屏障', () {
    test('forgetProfile / forgetFact / clearRecentSlice 写墓碑，自动淘汰与压缩不写墓碑',
        () async {
      final prof = await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '不要主动总结要点',
      );
      final fact = await memory.addFact(
        content: '用户喜欢夜间阅读技术文档',
        importance: 6,
      );
      final slice1 = (await memory.saveRecentSlice(
        id: 'slice_1',
        content: '近期整理示例归档A',
      ))!;
      final slice2 = (await memory.saveRecentSlice(
        id: 'slice_2',
        content: '近期整理示例归档B',
      ))!;

      expect(await memory.forgetProfile(prof.id), isTrue);
      expect(await memory.forgetFact(fact.id), isTrue);
      expect(await memory.clearRecentSlice(id: slice1.id), isTrue);
      expect(await memory.clearRecentSlice(), isTrue); // 清理剩余 slice2

      final tombs = await queryTombstones(dbPath);
      final tombPairs =
          tombs.map((t) => '${t['entity_type']}:${t['entity_id']}').toSet();
      expect(
        tombPairs,
        equals(<String>{
          'profile:${prof.id}',
          'fact:${fact.id}',
          'slice:${slice1.id}',
          'slice:${slice2.id}',
        }),
      );

      // 验证自动淘汰不产生新墓碑：1) compactAndPrune 清理过期切片、衰减事实、超30天 superseded
      final now = DateTime.utc(2026, 11, 15, 12, 0);
      final oldEntry = await memory.rememberProfile(
        kind: AgentMemoryKind.style,
        directive: '早期风格指令',
        observedAt: now.subtract(const Duration(days: 45)),
      );
      await memory.rememberProfile(
        kind: AgentMemoryKind.style,
        directive: '新风格指令',
        replacesId: oldEntry.id,
        observedAt: now.subtract(const Duration(days: 40)),
      );
      await memory.addFact(
        content: '一条低权重陈旧事实',
        importance: 1,
        createdAt: now.subtract(const Duration(days: 400)),
      );
      await memory.saveRecentSlice(
        id: 'expired_slice_1',
        content: '已过期切片',
        observedAt: now.subtract(const Duration(days: 20)),
      );

      final report = await memory.compactAndPrune(now: now);
      expect(report.expiredSlicesPruned, greaterThanOrEqualTo(1));
      expect(report.decayedFactsPruned, greaterThanOrEqualTo(1));
      expect(report.supersededProfilesPruned, greaterThanOrEqualTo(1));

      // 2) 容量溢出淘汰（超出 factsCapacity=400 条）同样不产生墓碑
      for (var i = 0; i < AgentMemoryService.factsCapacity + 3; i++) {
        await memory.addFact(
          content: '容量填充事实编号 $i',
          importance: (i % 5) + 4,
          createdAt: now.subtract(Duration(minutes: i)),
        );
      }
      expect(
          (await memory.counts()).factCount, AgentMemoryService.factsCapacity);

      // 墓碑集合仍只包含之前显式删除的那 4 条
      final tombsAfterPrune = await queryTombstones(dbPath);
      expect(tombsAfterPrune, hasLength(4));
    });

    test('clearAll 写入 cleared_at 屏障，拒收早于等于它的远端行，晚于它的新行正常合入', () async {
      await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '清空前的旧偏好',
        observedAt: DateTime.utc(2020, 1, 1, 10, 0),
      );
      await memory.clearAll();

      final exportedAfterClear = await memory.exportMemorySectionForTesting();
      final clearedAtIso = exportedAfterClear!['cleared_at'] as String;
      final clearMoment = DateTime.parse(clearedAtIso).toUtc();
      expect(exportedAfterClear['profile'], isEmpty);
      expect(exportedAfterClear['tombstones'], isEmpty);

      final beforeClearIso =
          clearMoment.subtract(const Duration(hours: 2)).toIso8601String();
      final afterClearIso =
          clearMoment.add(const Duration(seconds: 2)).toIso8601String();
      final futureExpiryIso =
          clearMoment.add(const Duration(days: 14)).toIso8601String();

      final stats = await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'cleared_at': beforeClearIso, // 比本地旧
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'stale_prof_equal',
            'kind': 'preference',
            'directive': '恰好等于 cleared_at 的旧偏好',
            'observed_at': clearedAtIso,
            'updated_at': clearedAtIso, // <= cleared_at -> 拒收
            'status': 'active',
          },
          <String, Object?>{
            'id': 'fresh_prof_after',
            'kind': 'preference',
            'directive': '清空后重新建立的新偏好',
            'observed_at': afterClearIso,
            'updated_at': afterClearIso, // > cleared_at -> 接收
            'status': 'active',
          },
        ],
        'facts': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'stale_fact',
            'content': '清空前的旧事实',
            'importance': 5,
            'created_at': beforeClearIso,
            'updated_at': beforeClearIso,
          },
          <String, Object?>{
            'id': 'fresh_fact',
            'content': '清空后的新事实',
            'importance': 6,
            'created_at': afterClearIso,
            'updated_at': afterClearIso,
          },
        ],
        'recent_slices': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'stale_slice',
            'content': '清空前的切片',
            'observed_at': clearedAtIso,
            'expires_at': futureExpiryIso,
          },
          <String, Object?>{
            'id': 'fresh_slice',
            'content': '清空后的新切片',
            'observed_at': afterClearIso,
            'expires_at': futureExpiryIso,
          },
        ],
        'tombstones': <Map<String, Object?>>[
          <String, Object?>{
            'entity_type': 'profile',
            'entity_id': 'old_tomb',
            'deleted_at': clearedAtIso,
          },
        ],
      });

      expect(stats.profilesAdded, 1);
      expect(stats.factsAdded, 1);
      expect(stats.slicesAdded, 1);
      expect(stats.skippedCount, greaterThanOrEqualTo(4));

      final active = await memory.activeProfile();
      expect(active.map((e) => e.id).toList(), <String>['fresh_prof_after']);
      expect(
        (await memory.allFacts()).map((f) => f.id).toList(),
        <String>['fresh_fact'],
      );
      expect(
        (await memory.activeRecentSlices(
          now: clearMoment.add(const Duration(minutes: 5)),
        ))
            .map((s) => s.id)
            .toList(),
        <String>['fresh_slice'],
      );
      expect(await queryTombstones(dbPath), isEmpty);
    });

    test('远端传来更新的 cleared_at 时清理本机早于等于该水位的旧数据', () async {
      await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '本机较早写入的偏好',
        observedAt: DateTime.utc(2026, 11, 5, 10, 0),
      );
      await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '本机在远端清空之后写入的偏好',
        observedAt: DateTime.utc(2026, 11, 12, 10, 0),
      );

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'cleared_at': '2026-11-10T00:00:00.000Z',
        'profile': const <Object?>[],
        'facts': const <Object?>[],
        'recent_slices': const <Object?>[],
        'tombstones': const <Object?>[],
      });

      final remaining = await memory.activeProfile();
      expect(remaining, hasLength(1));
      expect(remaining.single.directive, '本机在远端清空之后写入的偏好');
    });
  });

  group('事实召回不刷新 updated_at 与跨端召回履历保真', () {
    test(
        'searchFacts 更新 recall_count 与 last_recalled_at 但不刷新 updated_at，合并保留最大计数与最晚时间',
        () async {
      final createdTime = DateTime.utc(2026, 11, 1, 9, 0);
      final fact = await memory.addFact(
        content: '用户习惯使用双栏对比视图审阅文稿',
        triggerPhrases: const <String>['双栏', '审阅'],
        importance: 7,
        createdAt: createdTime,
      );
      final initialUpdatedAt = fact.updatedAt!;

      // 本地触发检索召回（异步刷盘队列）
      final hits = await memory.searchFacts('双栏 审阅');
      expect(hits, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final afterRecall = (await memory.allFacts()).single;
      expect(afterRecall.recallCount, 1);
      expect(afterRecall.lastRecalledAt, isNotNull);
      final localRecallAt = afterRecall.lastRecalledAt!.toUtc();
      // 关键断言：只读检索不得刷新 updated_at
      expect(afterRecall.updatedAt, initialUpdatedAt);

      // 远端对同一 id 修订了正文（updated_at 更新），但远端 recall_count=0、last_recalled_at 较早；
      // 合并后应采用远端新正文，同时保留本机更高的 recall_count 与更晚的 last_recalled_at。
      final earlierRemoteRecall =
          localRecallAt.subtract(const Duration(days: 30));
      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'facts': <Map<String, Object?>>[
          <String, Object?>{
            'id': fact.id,
            'category': 'workflow',
            'content': '用户习惯使用双栏对比视图与快捷键审阅文稿',
            'importance': 8,
            'trigger_phrases': '双栏\n快捷键',
            'created_at': createdTime.toIso8601String(),
            'updated_at': '2026-11-06T12:00:00.000Z',
            'recall_count': 0,
            'last_recalled_at': earlierRemoteRecall.toIso8601String(),
          },
        ],
      });

      final merged1 = (await memory.allFacts()).single;
      expect(merged1.content, '用户习惯使用双栏对比视图与快捷键审阅文稿');
      expect(merged1.recallCount, 1);
      expect(merged1.lastRecalledAt?.toUtc(), localRecallAt);

      // 反过来：远端 updated_at 较旧，但远端有更高的 recall_count=9 与更晚的 last_recalled_at
      final remoteLaterRecall = localRecallAt.add(const Duration(days: 5));
      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'facts': <Map<String, Object?>>[
          <String, Object?>{
            'id': fact.id,
            'category': 'workflow',
            'content': '过期的远端旧正文不应覆盖',
            'importance': 5,
            'created_at': createdTime.toIso8601String(),
            'updated_at': '2026-11-03T00:00:00.000Z',
            'recall_count': 9,
            'last_recalled_at': remoteLaterRecall.toIso8601String(),
          },
        ],
      });

      final merged2 = (await memory.allFacts()).single;
      expect(merged2.content, '用户习惯使用双栏对比视图与快捷键审阅文稿');
      expect(merged2.recallCount, 9);
      expect(merged2.lastRecalledAt?.toUtc(), remoteLaterRecall);
    });
  });

  group('同事务四步确定性收敛与赢家优先级', () {
    test('① 分叉收敛（同 replaces_id 多活跃）与赢家优先级（用户写入 > Dreaming）', () async {
      // 基线旧条目 base 已被本机用户纠偏替换；同时远端 Dreaming 也在离线状态替换了同一个 base（且时间更晚）
      final base = await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '允许适度延伸背景知识',
        observedAt: DateTime.utc(2026, 11, 1, 8, 0),
      );
      final userFork = await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '用户明确要求只给结论不展开背景',
        replacesId: base.id,
        source: 'thoughter',
        observedAt: DateTime.utc(2026, 11, 5, 10, 0),
      );

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'dreaming_fork_newer',
            'kind': 'preference',
            'directive': 'Dreaming 归纳的偏好分支',
            'observed_at': '2026-11-09T10:00:00.000Z',
            'updated_at': '2026-11-09T10:00:00.000Z', // 时间虽晚但来源为 dreaming
            'status': 'active',
            'replaces_id': base.id,
            'source': 'dreaming',
            'basis_watermark': '2026-11-09T09:00:00.000Z',
            'basis_note_count': 20,
          },
        ],
      });

      final active = await memory.activeProfile();
      expect(active, hasLength(1));
      expect(active.single.id, userFork.id);

      final all = await memory.allProfileEntries();
      final loser = all.firstWhere((e) => e.id == 'dreaming_fork_newer');
      expect(loser.status, AgentMemoryStatus.superseded);
      expect(loser.supersededBy, userFork.id);
    });

    test('② 单活跃类别收敛（taste / voice / style）保留唯一赢家', () async {
      // 本机有一条 Dreaming 写入的 style（时间较新），远端传来用户主动设置的 style（时间较早）
      await memory.rememberProfile(
        kind: AgentMemoryKind.style,
        directive: 'Dreaming 猜测的风格描述',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 10, 12, 0),
      );

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'user_style_1',
            'kind': 'style',
            'directive': '用户亲口指定的极简短句风格',
            'observed_at': '2026-11-04T08:00:00.000Z',
            'updated_at': '2026-11-04T08:00:00.000Z',
            'status': 'active',
            'source': 'thoughter',
          },
          <String, Object?>{
            'id': 'taste_older',
            'kind': 'taste',
            'directive': '偏好古典散文摘录',
            'observed_at': '2026-11-02T08:00:00.000Z',
            'updated_at': '2026-11-02T08:00:00.000Z',
            'status': 'active',
            'source': 'dreaming',
          },
          <String, Object?>{
            'id': 'taste_newer',
            'kind': 'taste',
            'directive': '偏好现代哲思与短诗摘录',
            'observed_at': '2026-11-08T08:00:00.000Z',
            'updated_at': '2026-11-08T08:00:00.000Z',
            'status': 'active',
            'source': 'dreaming',
          },
        ],
      });

      final active = await memory.activeProfile();
      final activeStyles =
          active.where((e) => e.kind == AgentMemoryKind.style).toList();
      final activeTastes =
          active.where((e) => e.kind == AgentMemoryKind.taste).toList();

      expect(activeStyles, hasLength(1));
      expect(activeStyles.single.id, 'user_style_1');
      expect(activeTastes, hasLength(1));
      expect(activeTastes.single.id, 'taste_newer');
    });

    test('③ 身份别名（确认覆盖存疑）与同 kind+directive 文本去重', () async {
      await memory.registerInferredAlias(
        '墨客',
        unconfirmed: true,
        observedAt: DateTime.utc(2026, 11, 2, 10, 0),
      );
      await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '回答不要使用感叹号',
        observedAt: DateTime.utc(2026, 11, 3, 10, 0),
      );

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          // 远端用户已确认笔名「墨客」，应收敛掉本机的存疑待确认条目
          <String, Object?>{
            'id': 'confirmed_alias_1',
            'kind': 'identity',
            'directive': '笔名为「墨客」',
            'observed_at': '2026-11-06T10:00:00.000Z',
            'updated_at': '2026-11-06T10:00:00.000Z',
            'status': 'active',
            'source': 'thoughter',
          },
          // 远端不同 id 但完全同文的 preference，应去重只留一条
          <String, Object?>{
            'id': 'dup_pref_remote',
            'kind': 'preference',
            'directive': '回答不要使用感叹号',
            'observed_at': '2026-11-07T10:00:00.000Z',
            'updated_at': '2026-11-07T10:00:00.000Z',
            'status': 'active',
            'source': 'thoughter',
          },
        ],
      });

      final active = await memory.activeProfile();
      final identities =
          active.where((e) => e.kind == AgentMemoryKind.identity).toList();
      final prefs =
          active.where((e) => e.kind == AgentMemoryKind.preference).toList();

      expect(identities, hasLength(1));
      expect(identities.single.id, 'confirmed_alias_1');
      expect(await memory.activeIdentityAliases(), contains('墨客'));

      expect(prefs, hasLength(1));
      expect(prefs.single.id, 'dup_pref_remote');
    });

    test('④ 事实规范化去重：两端相反导入顺序均确定性保留最早 created_at 行并合并最高召回履历', () async {
      final path1 = p.join(tempDir.path, 'dev1_mem.db');
      final path2 = p.join(tempDir.path, 'dev2_mem.db');
      final dev1 = AgentMemoryService(
        settingsService: settingsService,
        databasePath: path1,
      );
      final dev2 = AgentMemoryService(
        settingsService: settingsService,
        databasePath: path2,
      );

      final rowEarly = <String, Object?>{
        'id': 'fact_early_b',
        'category': 'habit',
        'content': '用户每周日晚上 做周复盘',
        'importance': 6,
        'created_at': '2026-11-01T20:00:00.000Z',
        'updated_at': '2026-11-01T20:00:00.000Z',
        'recall_count': 2,
        'last_recalled_at': '2026-11-03T20:00:00.000Z',
      };
      final rowLate = <String, Object?>{
        'id': 'fact_late_a',
        'category': 'habit',
        'content': '  用户每周日晚上\n  做周复盘  ', // 规范化折叠空白后同文
        'importance': 8,
        'created_at': '2026-11-05T20:00:00.000Z',
        'updated_at': '2026-11-05T20:00:00.000Z',
        'recall_count': 7,
        'last_recalled_at': '2026-11-09T20:00:00.000Z',
      };

      try {
        // 设备 1 先有 early，再合并 late
        await dev1.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'facts': <Map<String, Object?>>[rowEarly],
        });
        await dev1.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'facts': <Map<String, Object?>>[rowLate],
        });

        // 设备 2 先有 late，再合并 early
        await dev2.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'facts': <Map<String, Object?>>[rowLate],
        });
        await dev2.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'facts': <Map<String, Object?>>[rowEarly],
        });

        final facts1 = await dev1.allFacts();
        final facts2 = await dev2.allFacts();
        expect(facts1, hasLength(1));
        expect(facts2, hasLength(1));

        // 两端均确定性保留 created_at 最早的 fact_early_b，且合并了最大 recall_count=7 与最晚召回时间
        expect(facts1.single.id, 'fact_early_b');
        expect(facts2.single.id, 'fact_early_b');
        expect(facts1.single.recallCount, 7);
        expect(facts2.single.recallCount, 7);
        expect(
          facts1.single.lastRecalledAt?.toUtc().toIso8601String(),
          '2026-11-09T20:00:00.000Z',
        );
        expect(
          facts2.single.lastRecalledAt?.toUtc().toIso8601String(),
          '2026-11-09T20:00:00.000Z',
        );

        // 自动去重不得写墓碑
        expect(await queryTombstones(path1), isEmpty);
        expect(await queryTombstones(path2), isEmpty);
      } finally {
        dev1.dispose();
        dev2.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
  });

  group('记忆隐私开关边界与覆盖恢复', () {
    test('记忆开关关闭时：导出不含 agent_memory，合并跳过并标记 skippedBecauseDisabled，覆盖恢复不动',
        () async {
      final seeded = await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '开启期间写入的本地偏好',
      );

      await settingsService.setAgentMemoryEnabled(false);
      expect(memory.isEnabled, isFalse);

      // 1. 导出返回 null（流式不写任何字节）
      expect(await memory.exportMemorySectionForTesting(), isNull);

      // 2. 合并跳过并打标
      final mergeStats = await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'remote_ignored',
            'kind': 'preference',
            'directive': '远端记忆不应在关闭时合入',
            'observed_at': '2026-11-12T00:00:00.000Z',
            'updated_at': '2026-11-12T00:00:00.000Z',
            'status': 'active',
          },
        ],
      });
      expect(mergeStats.skippedBecauseDisabled, isTrue);
      expect(mergeStats.hasChanges, isFalse);

      // 3. 关闭时覆盖恢复也保持本地不动
      await memory.restoreMemorySection(<String, dynamic>{
        'format': 1,
        'profile': const <Object?>[],
      });

      // 重新打开验证原本地数据完好无损，且未混入远端条目
      await settingsService.setAgentMemoryEnabled(true);
      final activeAfterReenable = await memory.activeProfile();
      expect(
        activeAfterReenable.map((e) => e.id).toList(),
        <String>[seeded.id],
      );

      // 4. 开启状态下：旧包无 agent_memory（null）不动；有合法段时整库替换（含 cleared_at 与 dreaming）
      await memory.restoreMemorySection(null);
      expect((await memory.activeProfile()).single.id, seeded.id);

      await memory.restoreMemorySection(<String, dynamic>{
        'format': 1,
        'cleared_at': '2026-11-10T00:00:00.000Z',
        'dreaming': <String, Object?>{
          'last_run_at': '2026-11-14T06:00:00.000Z',
          'basis_watermark': '2026-11-14T05:00:00.000Z',
          'basis_note_count': 15,
        },
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'restored_prof_1',
            'kind': 'identity',
            'directive': '称呼用户为「阿澈」',
            'observed_at': '2026-11-14T06:00:00.000Z',
            'updated_at': '2026-11-14T06:00:00.000Z',
            'status': 'active',
          },
        ],
        'facts': const <Object?>[],
        'recent_slices': const <Object?>[],
        'tombstones': const <Object?>[],
      });

      final restoredActive = await memory.activeProfile();
      expect(
        restoredActive.map((e) => e.id).toList(),
        <String>['restored_prof_1'],
      );
      expect(await memory.activeIdentityAliases(), contains('阿澈'));
      expect(
        settingsService.lastDreamingAt?.toUtc().toIso8601String(),
        '2026-11-14T06:00:00.000Z',
      );
    });
  });
}

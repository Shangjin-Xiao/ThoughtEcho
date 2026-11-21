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
    }, timeout: const Timeout(Duration(minutes: 2)));

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

  group('审查回归：多端收敛防双杀、损坏容器保护、异步开关守卫与时区平局闭环', () {
    test('问题1a：设备 A/B 离线选出相反 Dreaming 赢家后双向互相同步，正反顺序均收敛到同一条非空 active 赢家',
        () async {
      Future<(String, String)> runDirection({required bool aToBFirst}) async {
        final dir = await Directory.systemTemp.createTemp('opp_dream_');
        final devA = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'dev_a.db'),
        );
        final devB = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'dev_b.db'),
        );
        try {
          // 设备 A 上 d_early 看全，d_late 因笔记尚未同步被判漏看标为 superseded
          final payloadOnA = <String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'd_early',
                'kind': 'taste',
                'directive': '早期局部归纳品味',
                'observed_at': '2026-11-10T08:00:00.000Z',
                'updated_at': '2026-11-10T08:00:00.000Z',
                'status': 'active',
                'source': 'dreaming',
                'basis_watermark': '2026-11-10T07:00:00.000Z',
                'basis_note_count': 3,
              },
              <String, Object?>{
                'id': 'd_late',
                'kind': 'taste',
                'directive': '后期完整归纳品味',
                'observed_at': '2026-11-12T08:00:00.000Z',
                'updated_at': '2026-11-12T08:00:00.000Z',
                'status': 'superseded',
                'superseded_by': 'd_early',
                'source': 'dreaming',
                'basis_watermark': '2026-11-12T07:00:00.000Z',
                'basis_note_count': 6,
              },
            ],
          };
          // 设备 B 已收齐全部笔记，d_late 看全并标 d_early 为 superseded（形成跨端互标环）
          final payloadOnB = <String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'd_early',
                'kind': 'taste',
                'directive': '早期局部归纳品味',
                'observed_at': '2026-11-10T08:00:00.000Z',
                'updated_at': '2026-11-10T08:00:00.000Z',
                'status': 'superseded',
                'superseded_by': 'd_late',
                'source': 'dreaming',
                'basis_watermark': '2026-11-10T07:00:00.000Z',
                'basis_note_count': 3,
              },
              <String, Object?>{
                'id': 'd_late',
                'kind': 'taste',
                'directive': '后期完整归纳品味',
                'observed_at': '2026-11-12T08:00:00.000Z',
                'updated_at': '2026-11-12T08:00:00.000Z',
                'status': 'active',
                'source': 'dreaming',
                'basis_watermark': '2026-11-12T07:00:00.000Z',
                'basis_note_count': 6,
              },
            ],
          };

          await devA.restoreMemorySection(payloadOnA);
          await devB.restoreMemorySection(payloadOnB);

          // 现两端主库均已补齐笔记（两个水位均看全）
          Future<bool> allCovered(String? wm, int? cnt) async => true;

          if (aToBFirst) {
            final snapA = (await devA.exportMemorySectionForTesting())!;
            await devB.mergeMemorySection(snapA, isBasisCovered: allCovered);
            final snapB = (await devB.exportMemorySectionForTesting())!;
            await devA.mergeMemorySection(snapB, isBasisCovered: allCovered);
          } else {
            final snapB = (await devB.exportMemorySectionForTesting())!;
            await devA.mergeMemorySection(snapB, isBasisCovered: allCovered);
            final snapA = (await devA.exportMemorySectionForTesting())!;
            await devB.mergeMemorySection(snapA, isBasisCovered: allCovered);
          }

          final activeA = await devA.activeProfile();
          final activeB = await devB.activeProfile();
          expect(activeA, hasLength(1));
          expect(activeB, hasLength(1));
          expect(activeA.single.supersededBy, isNull);
          expect(activeB.single.supersededBy, isNull);
          return (activeA.single.id, activeB.single.id);
        } finally {
          devA.dispose();
          devB.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }

      final (winA1, winB1) = await runDirection(aToBFirst: true);
      final (winA2, winB2) = await runDirection(aToBFirst: false);
      expect(winA1, 'd_late');
      expect(winB1, 'd_late');
      expect(winA2, 'd_late');
      expect(winB2, 'd_late');
    });

    test(
        '问题1b：P(v1) + Q(v4, replaces_id:P) + B 离线编辑 P(v5) 后 A(T6)/B(T7) 分别合入 Q 再互传快照，两端均保留 P(v5) 为唯一 active 赢家',
        () async {
      Future<void> verifyOrder({required bool pushAToBFirst}) async {
        final dir = await Directory.systemTemp.createTemp('p_q_edit_');
        final pathA = p.join(dir.path, 'a.db');
        final pathB = p.join(dir.path, 'b.db');
        final devA = AgentMemoryService(
          settingsService: settingsService,
          databasePath: pathA,
        );
        final devB = AgentMemoryService(
          settingsService: settingsService,
          databasePath: pathB,
        );
        try {
          // 1. 初始 P(v1, T1) 同步到 A、B 两端
          final pV1 = await devA.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '回答保持中等篇幅(v1)',
            observedAt: DateTime.utc(2026, 11, 1, 1, 0),
            updatedAt: DateTime.utc(2026, 11, 1, 1, 0),
          );
          await devB.mergeMemorySection(
            (await devA.exportMemorySectionForTesting())!,
          );

          // 2. 产生 Q(v4, T4, replaces_id: P.id) 的远端包（尚未被 B 看到）
          final qPayload = <String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'q_v4_id',
                'kind': 'preference',
                'directive': '回答偏详细展开(v4)',
                'observed_at': '2026-11-01T04:00:00.000Z',
                'updated_at': '2026-11-01T04:00:00.000Z',
                'status': 'active',
                'replaces_id': pV1.id,
                'source': 'thoughter',
              },
            ],
          };

          // 3. B 离线在 T5 手动编辑 P -> P(v5, T5 > T4)
          await devB.editProfileDirective(
            id: pV1.id,
            directive: '回答务必简明直给(v5)',
          );
          // 固定 P(v5) 的时间为 T5，确保严格模拟 T1 < T4 < T5 < T6 < T7
          final rawB = await openDatabase(pathB, singleInstance: true);
          await rawB.update(
            AgentMemoryService.profileTable,
            <String, Object?>{
              'observed_at': '2026-11-01T05:00:00.000Z',
              'updated_at': '2026-11-01T05:00:00.000Z',
            },
            where: 'id = ?',
            whereArgs: <Object?>[pV1.id],
          );

          // 4. A 在 T6 合入 Q（此时 A 上仍是 P(v1, T1) -> Q 取代 P，且绝不污染 P 的 updated_at）
          await devA.mergeMemorySection(qPayload);
          final rawA = await openDatabase(pathA, singleInstance: true);
          final pRowOnA = (await rawA.query(
            AgentMemoryService.profileTable,
            where: 'id = ?',
            whereArgs: <Object?>[pV1.id],
          ))
              .single;
          expect(pRowOnA['status'], 'superseded');
          expect(pRowOnA['updated_at'], '2026-11-01T01:00:00.000000Z');

          // 5. B 在 T7 合入 Q（B 上 P 为 T5 > Q(T4)，P(v5) 保持 active，Q 被标 superseded 且保留 T4）
          await devB.mergeMemorySection(qPayload);
          expect((await devB.activeProfile()).map((e) => e.id).toList(), [
            pV1.id,
          ]);

          // 6. A 与 B 双向交换完整快照
          if (pushAToBFirst) {
            await devB.mergeMemorySection(
              (await devA.exportMemorySectionForTesting())!,
            );
            await devA.mergeMemorySection(
              (await devB.exportMemorySectionForTesting())!,
            );
          } else {
            await devA.mergeMemorySection(
              (await devB.exportMemorySectionForTesting())!,
            );
            await devB.mergeMemorySection(
              (await devA.exportMemorySectionForTesting())!,
            );
          }

          final finalActiveA = await devA.activeProfile();
          final finalActiveB = await devB.activeProfile();
          expect(finalActiveA, hasLength(1));
          expect(finalActiveB, hasLength(1));
          expect(finalActiveA.single.id, pV1.id);
          expect(finalActiveA.single.directive, '回答务必简明直给(v5)');
          expect(finalActiveA.single.supersededBy, isNull);
          expect(finalActiveB.single.id, pV1.id);
          expect(finalActiveB.single.directive, '回答务必简明直给(v5)');
          expect(finalActiveB.single.supersededBy, isNull);

          final qOnA = (await rawA.query(
            AgentMemoryService.profileTable,
            where: 'id = ?',
            whereArgs: const <Object?>['q_v4_id'],
          ))
              .single;
          expect(qOnA['status'], 'superseded');
          expect(qOnA['superseded_by'], pV1.id);
        } finally {
          devA.dispose();
          devB.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }

      await verifyOrder(pushAToBFirst: true);
      await verifyOrder(pushAToBFirst: false);
    });

    test('问题1c：Y 取代 X 后调用 forgetProfile(Y.id) 产生墓碑，跨端双向同步时 X 绝不错误复活', () async {
      final dir = await Directory.systemTemp.createTemp('tomb_successor_');
      final devA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'a.db'),
      );
      final devB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'b.db'),
      );
      try {
        final x = await devA.rememberProfile(
          kind: AgentMemoryKind.feedback,
          directive: '旧反馈指令 X',
          observedAt: DateTime.utc(2026, 11, 1, 10, 0),
        );
        final y = await devA.rememberProfile(
          kind: AgentMemoryKind.feedback,
          directive: '更新后的反馈指令 Y',
          replacesId: x.id,
          observedAt: DateTime.utc(2026, 11, 2, 10, 0),
        );
        // 先同步到设备 B（B 同时持有 superseded 的 X 与 active 的 Y）
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        expect((await devB.activeProfile()).single.id, y.id);

        // 用户在设备 A 上删除了当前生效的 Y（写入 Y 的墓碑）
        await devA.forgetProfile(y.id);
        expect(await devA.activeProfile(), isEmpty);

        // A -> B 同步：B 删除 Y，且已被 Y 取代的旧 X 绝不能复活！
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        expect(await devB.activeProfile(), isEmpty);

        // B -> A 回传：A 上 X 也绝不能复活！
        await devA.mergeMemorySection(
          (await devB.exportMemorySectionForTesting())!,
        );
        expect(await devA.activeProfile(), isEmpty);
      } finally {
        devA.dispose();
        devB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        '问题3：传入损坏的 agent_memory 内部容器时，restore 与 merge 均抛 FormatException 且本地记忆毫发无损',
        () async {
      final seededProfile = await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '受保护的本机核心画像',
      );
      final seededFact = await memory.addFact(content: '受保护的本机事实记录');

      final malformedPayloads = <Map<String, dynamic>>[
        <String, dynamic>{'profile': <String, Object?>{}},
        <String, dynamic>{'facts': 'not_a_list'},
        <String, dynamic>{'recent_slices': 123},
        <String, dynamic>{'tombstones': <String, Object?>{}},
        <String, dynamic>{'dreaming': <Object?>[]},
        <String, dynamic>{'cleared_at': 'invalid-iso-timestamp'},
        <String, dynamic>{'format': 'v1'},
        <String, dynamic>{'format': 0},
      ];

      for (final bad in malformedPayloads) {
        await expectLater(
          () => memory.restoreMemorySection(bad),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          () => memory.mergeMemorySection(bad),
          throwsA(isA<FormatException>()),
        );
      }

      // 关闭记忆开关时遇到损坏容器同样先抛 FormatException，防止 WebDAV 把损坏云端包静默忽略后覆写
      await settingsService.setAgentMemoryEnabled(false);
      await expectLater(
        () => memory.mergeMemorySection(<String, dynamic>{
          'profile': <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
      await settingsService.setAgentMemoryEnabled(true);

      // 验证本地已有记忆毫发无损
      expect(
        (await memory.activeProfile()).map((e) => e.id).toList(),
        <String>[seededProfile.id],
      );
      expect(
        (await memory.allFacts()).map((f) => f.id).toList(),
        <String>[seededFact.id],
      );
    });

    test('问题4：在 isBasisCovered 异步等待期间关闭长期记忆开关，放弃写入且不改写 lastDreamingAt',
        () async {
      final initialLastDreaming = DateTime.utc(2026, 11, 5, 8, 0);
      await settingsService.setLastDreamingAt(initialLastDreaming);

      final stats = await memory.mergeMemorySection(
        <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': '2026-11-18T08:00:00.000Z',
            'basis_watermark': '2026-11-18T07:00:00.000Z',
            'basis_note_count': 10,
          },
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'race_dreaming_prof',
              'kind': 'taste',
              'directive': '异步期间被关闭开关拦截的远端画像',
              'observed_at': '2026-11-18T08:00:00.000Z',
              'updated_at': '2026-11-18T08:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-18T07:00:00.000Z',
              'basis_note_count': 10,
            },
          ],
          'facts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'race_fact_1',
              'content': '不应落库的远端事实',
              'importance': 6,
              'created_at': '2026-11-18T08:00:00.000Z',
              'updated_at': '2026-11-18T08:00:00.000Z',
            },
          ],
        },
        isBasisCovered: (wm, cnt) async {
          // 模拟主库查询期间用户在设置页关闭了长期记忆开关
          await settingsService.setAgentMemoryEnabled(false);
          return true;
        },
      );

      expect(stats.skippedBecauseDisabled, isTrue);
      expect(stats.hasChanges, isFalse);
      expect(settingsService.lastDreamingAt?.toUtc(), initialLastDreaming);

      // 重新打开记忆开关检查数据库：没有任何远端行偷跑落库
      await settingsService.setAgentMemoryEnabled(true);
      expect(await memory.activeProfile(), isEmpty);
      expect(await memory.allFacts(), isEmpty);
    });

    test(
        '问题5：editProfileDirective 将 Dreaming 画像转为 user_edit 并清除 basis_*，跨端收敛优先胜出',
        () async {
      final dreamingTaste = await memory.rememberProfile(
        kind: AgentMemoryKind.taste,
        directive: 'Dreaming 初始自动归纳品味',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 10, 8, 0),
        basisWatermark: '2026-11-10T07:00:00.000Z',
        basisNoteCount: 8,
      );

      await memory.editProfileDirective(
        id: dreamingTaste.id,
        directive: '用户亲自改写确认的品味描述',
      );

      final afterEdit = (await memory.activeProfile()).single;
      expect(afterEdit.id, dreamingTaste.id);
      expect(afterEdit.source, 'user_edit');
      expect(afterEdit.basisWatermark, isNull);
      expect(afterEdit.basisNoteCount, isNull);

      // 合入另一台设备较旧的 thoughter taste 以及另一条覆盖更多笔记的 dreaming taste，用户手动修改均必须胜出！
      await memory.mergeMemorySection(
        <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'older_thoughter_taste',
              'kind': 'taste',
              'directive': '另一台设备较早的对话记住品味',
              'observed_at': '2026-11-11T08:00:00.000Z',
              'updated_at': '2026-11-11T08:00:00.000Z',
              'status': 'active',
              'source': 'thoughter',
            },
            <String, Object?>{
              'id': 'newer_dreaming_taste',
              'kind': 'taste',
              'directive': '另一台设备全量笔记自动归纳品味',
              'observed_at': '2026-12-01T08:00:00.000Z',
              'updated_at': '2026-12-01T08:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-12-01T07:00:00.000Z',
              'basis_note_count': 50,
            },
          ],
        },
        isBasisCovered: (_, __) async => true,
      );

      final finalTastes = (await memory.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.taste)
          .toList();
      expect(finalTastes, hasLength(1));
      expect(finalTastes.single.id, dreamingTaste.id);
      expect(finalTastes.single.directive, '用户亲自改写确认的品味描述');
      expect(finalTastes.single.source, 'user_edit');
    });

    test('问题6 & 二.2：跨时区时间戳归一化、同 ID 同时间戳交换律平局决胜、以及 cleared_at 重置 lastDreamingAt',
        () async {
      // 1. 近期切片跨时区 expires_at 过滤与旧表非 Z 时间戳自动迁移
      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'recent_slices': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'slice_tz_expired',
            'content': '已过期的带偏移切片',
            'observed_at': '2026-11-18T08:00:00+08:00',
            'updated_at': '2026-11-18T08:00:00+08:00',
            // 等价于 2026-11-19T01:00:00.000Z（早于查询时刻 02:00Z，应判定已过期！）
            'expires_at': '2026-11-19T09:00:00+08:00',
          },
          <String, Object?>{
            'id': 'slice_tz_valid',
            'content': '仍有效的带偏移切片',
            'observed_at': '2026-11-18T08:00:00+08:00',
            'updated_at': '2026-11-18T08:00:00+08:00',
            // 等价于 2026-11-19T04:00:00.000Z（晚于查询时刻 02:00Z，应保留！）
            'expires_at': '2026-11-19T12:00:00+08:00',
          },
        ],
      });
      final activeSlices = await memory.activeRecentSlices(
        now: DateTime.utc(2026, 11, 19, 2, 0),
      );
      expect(
        activeSlices.map((s) => s.id).toList(),
        <String>['slice_tz_valid'],
      );

      // 2. 同 ID 且 updated_at 绝对时刻完全相等（含 +08:00 vs Z）时，A->B 与 B->A 最终结果严格一致
      final dir = await Directory.systemTemp.createTemp('tie_mem_');
      final dev1 = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, '1.db'),
      );
      final dev2 = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, '2.db'),
      );
      try {
        final variantAlpha = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'same_prof_id',
              'kind': 'preference',
              'directive': '偏好方案 Alpha',
              'observed_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
              'status': 'active',
              'source': 'thoughter',
            },
          ],
          'facts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'same_fact_id',
              'content': '事实内容 Alpha',
              'importance': 6,
              'created_at': '2026-11-19T01:00:00.000Z',
              'updated_at': '2026-11-19T01:00:00.000Z',
            },
          ],
        };
        final variantBeta = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'same_prof_id',
              'kind': 'preference',
              'directive': '偏好方案 Beta',
              'observed_at': '2026-11-19T01:00:00.000Z',
              'updated_at': '2026-11-19T01:00:00.000Z',
              'status': 'active',
              'source': 'thoughter',
            },
          ],
          'facts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'same_fact_id',
              'content': '事实内容 Beta',
              'importance': 8,
              'created_at': '2026-11-19T09:00:00+08:00',
              'updated_at': '2026-11-19T09:00:00+08:00',
            },
          ],
        };

        await dev1.mergeMemorySection(variantAlpha);
        await dev1.mergeMemorySection(variantBeta);

        await dev2.mergeMemorySection(variantBeta);
        await dev2.mergeMemorySection(variantAlpha);

        expect(
          (await dev1.activeProfile()).single.directive,
          (await dev2.activeProfile()).single.directive,
        );
        expect(
          (await dev1.allFacts()).single.content,
          (await dev2.allFacts()).single.content,
        );
      } finally {
        dev1.dispose();
        dev2.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }

      // 3. 远端传来更新的 cleared_at >= 本机 lastDreamingAt 时，同步清空 lastDreamingAt 且不再导出陈旧 last_run_at
      await settingsService.setLastDreamingAt(
        DateTime.utc(2026, 11, 18, 12, 0),
      );
      await memory.recordDreamingRun(
        runAt: DateTime.utc(2026, 11, 18, 12, 0),
        basisWatermark: '2026-11-18T11:00:00.000Z',
        basisNoteCount: 5,
      );

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'cleared_at': '2026-11-19T05:00:00.000Z',
      });

      expect(settingsService.lastDreamingAt, isNull);
      final exportedAfterRemoteClear =
          (await memory.exportMemorySectionForTesting())!;
      final exportedDreaming =
          exportedAfterRemoteClear['dreaming'] as Map<String, dynamic>?;
      expect(exportedDreaming?['last_run_at'], isNull);
    });

    test('本地 compactAndPrune 仅收敛当前 active 条目，绝不复活已被看全合并置为 superseded 的较新条目',
        () async {
      await memory.mergeMemorySection(
        <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'p_early_covered',
              'kind': 'taste',
              'directive': '看全依据的早期品味',
              'observed_at': '2026-11-10T09:00:00.000Z',
              'updated_at': '2026-11-10T09:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T08:00:00.000Z',
              'basis_note_count': 5,
            },
            <String, Object?>{
              'id': 'p_late_uncovered',
              'kind': 'taste',
              'directive': '漏看依据但时间更新的品味',
              'observed_at': '2026-11-12T09:00:00.000Z',
              'updated_at': '2026-11-12T09:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T08:00:00.000Z',
              'basis_note_count': 2,
            },
          ],
        },
        isBasisCovered: (wm, cnt) async => cnt == 5,
      );

      expect((await memory.activeProfile()).single.id, 'p_early_covered');

      // 无挂载判定器时直接调用 compactAndPrune（30 天内保留审计行），不得复活 p_late_uncovered
      final stats = await memory.compactAndPrune(
        now: DateTime.utc(2026, 11, 15, 0, 0),
      );
      expect(stats.duplicatesPruned, 0);
      expect((await memory.activeProfile()).single.id, 'p_early_covered');

      final all = await memory.allProfileEntries();
      final lateEntry = all.singleWhere((e) => e.id == 'p_late_uncovered');
      expect(lateEntry.status, AgentMemoryStatus.superseded);
      expect(lateEntry.supersededBy, 'p_early_covered');
    });

    test('本地 compactAndPrune 自愈恢复被后台 Dreaming 误置为 superseded 的人工/显式画像（含超30天条目）',
        () async {
      final now = DateTime.utc(2026, 11, 20, 10, 0);
      await memory.activeProfile();
      final rawMemDb = await openDatabase(dbPath, singleInstance: true);

      // 模拟历史旧版遗留状态：45 天前用户手动修正的 taste (user_edit) 曾被两轮后台 Dreaming 连续置为 superseded
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'manual_taste_legacy',
          'kind': 'taste',
          'directive': '用户手动修正的摘录偏好结论',
          'observed_at':
              now.subtract(const Duration(days: 45)).toIso8601String(),
          'updated_at':
              now.subtract(const Duration(days: 45)).toIso8601String(),
          'status': 'superseded',
          'superseded_by': 'dreaming_taste_mid',
          'source': 'user_edit',
        },
      );
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'dreaming_taste_mid',
          'kind': 'taste',
          'directive': '首轮后台自动覆盖的品味',
          'observed_at':
              now.subtract(const Duration(days: 14)).toIso8601String(),
          'updated_at':
              now.subtract(const Duration(days: 14)).toIso8601String(),
          'status': 'superseded',
          'replaces_id': 'manual_taste_legacy',
          'superseded_by': 'dreaming_taste_latest',
          'source': 'dreaming',
        },
      );
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'dreaming_taste_latest',
          'kind': 'taste',
          'directive': '次轮后台自动覆盖的品味',
          'observed_at':
              now.subtract(const Duration(days: 2)).toIso8601String(),
          'updated_at': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'active',
          'replaces_id': 'dreaming_taste_mid',
          'source': 'dreaming',
        },
      );

      // 对照组：被用户新显式指令替换的 45 天前旧显式条目（不应复活，且应按 >30 天清理）
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'old_explicit_voice',
          'kind': 'voice',
          'directive': '早期已废弃显式文风',
          'observed_at':
              now.subtract(const Duration(days: 45)).toIso8601String(),
          'updated_at':
              now.subtract(const Duration(days: 45)).toIso8601String(),
          'status': 'superseded',
          'superseded_by': 'new_explicit_voice',
          'source': 'thoughter',
        },
      );
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'new_explicit_voice',
          'kind': 'voice',
          'directive': '最新显式确认文风',
          'observed_at':
              now.subtract(const Duration(days: 3)).toIso8601String(),
          'updated_at': now.subtract(const Duration(days: 3)).toIso8601String(),
          'status': 'active',
          'replaces_id': 'old_explicit_voice',
          'source': 'thoughter',
        },
      );

      final stats = await memory.compactAndPrune(now: now);
      // dreaming_taste_latest 由 active 退回 superseded（1 条），old_explicit_voice 超 30 天被清理（1 条）
      expect(stats.duplicatesPruned, 1);
      expect(stats.supersededProfilesPruned, 1);

      final active = await memory.activeProfile();
      final activeTaste = active.singleWhere(
        (e) => e.kind == AgentMemoryKind.taste,
      );
      final activeVoice = active.singleWhere(
        (e) => e.kind == AgentMemoryKind.voice,
      );
      expect(activeTaste.id, 'manual_taste_legacy');
      expect(activeTaste.directive, '用户手动修正的摘录偏好结论');
      expect(activeVoice.id, 'new_explicit_voice');

      final all = await memory.allProfileEntries();
      expect(all.any((e) => e.id == 'old_explicit_voice'), isFalse);
      final retiredDreaming = all.singleWhere(
        (e) => e.id == 'dreaming_taste_latest',
      );
      expect(retiredDreaming.status, AgentMemoryStatus.superseded);
      expect(retiredDreaming.supersededBy, 'manual_taste_legacy');

      // 再次运行应完全幂等
      final secondStats = await memory.compactAndPrune(now: now);
      expect(secondStats.duplicatesPruned, 0);
      expect(
        (await memory.activeProfile())
            .singleWhere((e) => e.kind == AgentMemoryKind.taste)
            .id,
        'manual_taste_legacy',
      );
    });

    test(
        'Devin 审查回归 #21：X -> Y -> Z 多跳替换后调用 forgetProfile(Z.id)（含 X 已被发送端裁剪的场景），双向同步均彻底退休 X/Y，仅当对端晚于墓碑真实编辑 X 时才保留',
        () async {
      // 场景 A：A 上完整保留 X、Y 历史行与 Z 的删除墓碑；B 仍持有原始 active 的 X
      for (final mergeAFirst in <bool>[false, true]) {
        final dir = await Directory.systemTemp.createTemp('multihop_tomb_');
        final pathA = p.join(dir.path, 'a.db');
        final pathB = p.join(dir.path, 'b.db');
        final devA = AgentMemoryService(
          settingsService: settingsService,
          databasePath: pathA,
        );
        final devB = AgentMemoryService(
          settingsService: settingsService,
          databasePath: pathB,
        );
        try {
          final x = await devA.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '第一代偏好指令 X',
            observedAt: DateTime.utc(2026, 11, 1, 10, 0),
          );
          await devB.mergeMemorySection(
            (await devA.exportMemorySectionForTesting())!,
          );
          expect((await devB.activeProfile()).single.id, x.id);

          // A 离线执行两跳替换 X -> Y -> Z，随后忘掉 Z
          final y = await devA.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '第二代偏好指令 Y',
            replacesId: x.id,
            observedAt: DateTime.utc(2026, 11, 2, 10, 0),
          );
          final z = await devA.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '第三代偏好指令 Z',
            replacesId: y.id,
            observedAt: DateTime.utc(2026, 11, 3, 10, 0),
          );
          await devA.forgetProfile(z.id);
          expect(await devA.activeProfile(), isEmpty);

          if (mergeAFirst) {
            await devA.mergeMemorySection(
              (await devB.exportMemorySectionForTesting())!,
            );
            await devB.mergeMemorySection(
              (await devA.exportMemorySectionForTesting())!,
            );
          } else {
            await devB.mergeMemorySection(
              (await devA.exportMemorySectionForTesting())!,
            );
            await devA.mergeMemorySection(
              (await devB.exportMemorySectionForTesting())!,
            );
          }

          expect(await devA.activeProfile(), isEmpty);
          expect(await devB.activeProfile(), isEmpty);
        } finally {
          devA.dispose();
          devB.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }

      // 场景 B：发送端 A 早已压缩裁剪掉旧 X，仅剩 Y(replaces_id: X, superseded_by: Z) 与 Z 的墓碑；B 上仍有 active 的 X
      final dirPruned =
          await Directory.systemTemp.createTemp('multihop_pruned_');
      final devAPruned = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirPruned.path, 'a.db'),
      );
      final devBPruned = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirPruned.path, 'b.db'),
      );
      try {
        final x = await devBPruned.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '仅存于 B 的初代偏好 X',
          observedAt: DateTime.utc(2026, 11, 1, 10, 0),
        );
        await devAPruned.restoreMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'mid_y_id',
              'kind': 'preference',
              'directive': '中继替换偏好 Y',
              'observed_at': '2026-11-02T10:00:00.000000Z',
              'updated_at': '2026-11-02T10:00:00.000000Z',
              'status': 'superseded',
              'replaces_id': x.id,
              'superseded_by': 'deleted_z_id',
              'source': 'thoughter',
            },
          ],
          'tombstones': <Map<String, Object?>>[
            <String, Object?>{
              'entity_type': 'profile',
              'entity_id': 'deleted_z_id',
              'deleted_at': '2026-11-04T10:00:00.000000Z',
            },
          ],
        });
        await devBPruned.mergeMemorySection(
          (await devAPruned.exportMemorySectionForTesting())!,
        );
        expect(await devBPruned.activeProfile(), isEmpty);
      } finally {
        devAPruned.dispose();
        devBPruned.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dirPruned.exists()) {
          await dirPruned.delete(recursive: true);
        }
      }
    });

    test(
        'Devin 审查回归 #23：多端同正文去重淘汰 P1 -> P2 后调用 editProfileDirective(P2) 修改指令，后续与原端及第三端同步均绝不复活旧重复项 P1',
        () async {
      final dir = await Directory.systemTemp.createTemp('dedup_edit_revive_');
      final devA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'a.db'),
      );
      final devB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'b.db'),
      );
      final devC = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'c.db'),
      );
      try {
        // 1. A 与 B 各自独立记下相同偏好指令，且 C 先从 A 同步拿到 P1(active)
        final p1 = await devA.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '回复保持简短精炼',
          observedAt: DateTime.utc(2026, 11, 10, 9, 0),
        );
        await devC.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        expect((await devC.activeProfile()).map((e) => e.id).toList(), [p1.id]);
        final p2 = await devB.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '回复保持简短精炼',
          observedAt: DateTime.utc(2026, 11, 10, 10, 0),
        );

        // 2. A 与 B 互相同步：P2 时间更新胜出，P1 被去重标为 superseded -> P2.id
        await devA.mergeMemorySection(
          (await devB.exportMemorySectionForTesting())!,
        );
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        expect((await devA.activeProfile()).map((e) => e.id).toList(), [p2.id]);
        expect((await devB.activeProfile()).map((e) => e.id).toList(), [p2.id]);

        // 3. 用户在 A 上原位修改生效条目 P2 的内容为相反偏好
        await devA.editProfileDirective(
          id: p2.id,
          directive: '回复提供详尽推导过程',
        );
        expect(
          (await devA.activeProfile()).map((e) => e.directive).toList(),
          <String>['回复提供详尽推导过程'],
        );

        // 4. A 与 B 再次双向同步：曾被去重淘汰的旧 P1（“回复保持简短精炼”）绝不能借重算复活！
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        await devA.mergeMemorySection(
          (await devB.exportMemorySectionForTesting())!,
        );
        expect(
          (await devA.activeProfile()).map((e) => e.directive).toList(),
          <String>['回复提供详尽推导过程'],
        );
        expect(
          (await devB.activeProfile()).map((e) => e.directive).toList(),
          <String>['回复提供详尽推导过程'],
        );

        // 5. 与仍持有旧 P1(active) 的第三端 C 双向同步：A 与 C 也严格收敛为仅保留编辑后的 P2！
        await devC.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        await devA.mergeMemorySection(
          (await devC.exportMemorySectionForTesting())!,
        );
        expect(
          (await devC.activeProfile()).map((e) => e.directive).toList(),
          <String>['回复提供详尽推导过程'],
        );
        expect(
          (await devA.activeProfile()).map((e) => e.directive).toList(),
          <String>['回复提供详尽推导过程'],
        );
      } finally {
        devA.dispose();
        devB.dispose();
        devC.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        'Devin 审查回归 #25：agent_memory.db 旧时间归一化为显式偏移转 6 位 UTC、纯无时区保留原语义不加伪造 Z，并完整写入 *_backup 列',
        () async {
      final dir = await Directory.systemTemp.createTemp('mem_tz_backup_');
      final legacyMemPath = p.join(dir.path, 'legacy_mem.db');
      final rawLegacy = await openDatabase(
        legacyMemPath,
        version: 3,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE agent_memory_profile (
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
          await db.execute('''
            CREATE TABLE agent_memory_facts (
              id TEXT PRIMARY KEY,
              category TEXT,
              content TEXT NOT NULL,
              importance INTEGER NOT NULL DEFAULT 5,
              trigger_phrases TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT,
              last_recalled_at TEXT,
              recall_count INTEGER NOT NULL DEFAULT 0,
              source_ref TEXT
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
          await db.execute('''
            CREATE TABLE agent_memory_tombstones (
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              deleted_at TEXT NOT NULL,
              PRIMARY KEY (entity_type, entity_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE agent_memory_meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.insert('agent_memory_profile', <String, Object?>{
            'id': 'p_explicit_tz',
            'kind': 'preference',
            'directive': '带显式东八区偏移的画像',
            'observed_at': '2026-10-05T09:00:00+08:00',
            'updated_at': '2026-10-05T09:00:00+08:00',
            'status': 'active',
          });
          await db.insert('agent_memory_profile', <String, Object?>{
            'id': 'p_pure_offsetless',
            'kind': 'feedback',
            'directive': '纯无时区历史画像',
            'observed_at': '2026-10-05T09:30:00.25',
            'updated_at': null,
            'status': 'active',
          });
          await db.insert('agent_memory_profile', <String, Object?>{
            'id': 'p_edited_later_utc',
            'kind': 'preference',
            'directive': '09:00 创建、5 分钟后即 01:05Z 编辑的历史画像',
            'observed_at': '2026-10-05T09:00:00.25',
            'updated_at': '2026-10-05T01:05:00.25Z',
            'status': 'active',
          });
        },
      );
      await rawLegacy.close();

      final svc = AgentMemoryService(
        settingsService: settingsService,
        databasePath: legacyMemPath,
      );
      try {
        await svc.activeProfile();
        final inspectDb =
            await openDatabase(legacyMemPath, singleInstance: true);
        final rows = await inspectDb.query(
          AgentMemoryService.profileTable,
          orderBy: 'id ASC',
        );
        final byId = <String, Map<String, Object?>>{
          for (final r in rows) r['id'] as String: r,
        };
        expect(
          byId['p_explicit_tz']!['observed_at'],
          '2026-10-05T01:00:00.000000Z',
        );
        expect(
          byId['p_explicit_tz']!['observed_at_backup'],
          '2026-10-05T09:00:00+08:00',
        );
        expect(
          byId['p_pure_offsetless']!['observed_at'],
          '2026-10-05T09:30:00.250000',
        );
        expect(
          byId['p_pure_offsetless']!['observed_at_backup'],
          '2026-10-05T09:30:00.25',
        );
        // Greptile #76：后续编辑产生的 UTC updated_at 绝不反向篡改无偏移 observed_at
        expect(
          byId['p_edited_later_utc']!['observed_at'],
          '2026-10-05T09:00:00.250000',
        );
        expect(
          byId['p_edited_later_utc']!['observed_at_backup'],
          '2026-10-05T09:00:00.25',
        );
        expect(
          byId['p_edited_later_utc']!['updated_at'],
          '2026-10-05T01:05:00.250000Z',
        );
      } finally {
        svc.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        'Greptile 审查回归 #77：画像在同步期间被去重标为 superseded 后或离线对旧 ID 执行 editProfileDirective，本地与双向同步均保留最新人工修订并退休旧条目',
        () async {
      // 子场景 A：UI 编辑弹窗打开期间后台同步将 P1 去重为 superseded -> P2，随后用户保存 P1 编辑
      final dirA = await Directory.systemTemp.createTemp('sup_edit_ui_race_');
      final devA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirA.path, 'a.db'),
      );
      final devB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirA.path, 'b.db'),
      );
      try {
        final p1 = await devA.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '偏爱深色极简排版',
          observedAt: DateTime.utc(2026, 11, 15, 9, 0),
        );
        final p2 = await devB.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '偏爱深色极简排版',
          observedAt: DateTime.utc(2026, 11, 15, 10, 0),
        );

        // 后台同步完成：P1 在 A/B 上均被去重标为 superseded -> P2
        await devA.mergeMemorySection(
          (await devB.exportMemorySectionForTesting())!,
        );
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        expect((await devA.activeProfile()).map((e) => e.id).toList(), [p2.id]);

        // 用户在仍持有 p1.id 的编辑框中点击保存，修改为新指令
        final edited = await devA.editProfileDirective(
          id: p1.id,
          directive: '偏爱高对比暖色排版',
        );
        expect(edited, isTrue);
        expect(
          (await devA.activeProfile())
              .map((e) => '${e.id}:${e.directive}')
              .toList(),
          <String>['${p1.id}:偏爱高对比暖色排版'],
        );

        // A 与 B 再次双向同步：B 上旧 P2 也被退休，双端严格收敛到编辑后的 P1
        await devB.mergeMemorySection(
          (await devA.exportMemorySectionForTesting())!,
        );
        await devA.mergeMemorySection(
          (await devB.exportMemorySectionForTesting())!,
        );
        expect(
          (await devA.activeProfile()).map((e) => e.directive).toList(),
          <String>['偏爱高对比暖色排版'],
        );
        expect(
          (await devB.activeProfile()).map((e) => e.directive).toList(),
          <String>['偏爱高对比暖色排版'],
        );
      } finally {
        devA.dispose();
        devB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dirA.exists()) {
          await dirA.delete(recursive: true);
        }
      }

      // 子场景 B：离线并发编辑——B 已将 P1 去重指向 P2，而 A 离线不知晓 P2 并直接 editProfileDirective(P1)；无论合并顺序如何均收敛到新 P1
      for (final mergeAFirst in <bool>[true, false]) {
        final dirOffline =
            await Directory.systemTemp.createTemp('sup_edit_offline_');
        final peerA = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dirOffline.path, 'peer_a.db'),
        );
        final peerB = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dirOffline.path, 'peer_b.db'),
        );
        try {
          final p1 = await peerA.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '回答优先给出代码示例',
            observedAt: DateTime.utc(2026, 11, 16, 9, 0),
          );
          await peerB.mergeMemorySection(
            (await peerA.exportMemorySectionForTesting())!,
          );
          final p2 = await peerB.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '回答优先给出代码示例',
            observedAt: DateTime.utc(2026, 11, 16, 10, 0),
          );
          // 触发 B 本地收敛使 B 上 P1 成为 superseded -> P2
          await peerB.mergeMemorySection(
            <String, dynamic>{'format': 1, 'profile': <Object?>[]},
          );
          expect(
            (await peerB.activeProfile()).map((e) => e.id).toList(),
            <String>[p2.id],
          );

          // A 在离线状态下原位编辑仍是 active 的 P1（此时 P1.updated_at > P2.updated_at）
          await peerA.editProfileDirective(
            id: p1.id,
            directive: '回答先给出架构权衡再附代码',
          );

          if (mergeAFirst) {
            await peerA.mergeMemorySection(
              (await peerB.exportMemorySectionForTesting())!,
            );
            await peerB.mergeMemorySection(
              (await peerA.exportMemorySectionForTesting())!,
            );
          } else {
            await peerB.mergeMemorySection(
              (await peerA.exportMemorySectionForTesting())!,
            );
            await peerA.mergeMemorySection(
              (await peerB.exportMemorySectionForTesting())!,
            );
          }

          expect(
            (await peerA.activeProfile()).map((e) => e.directive).toList(),
            <String>['回答先给出架构权衡再附代码'],
          );
          expect(
            (await peerB.activeProfile()).map((e) => e.directive).toList(),
            <String>['回答先给出架构权衡再附代码'],
          );
        } finally {
          peerA.dispose();
          peerB.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dirOffline.exists()) {
            await dirOffline.delete(recursive: true);
          }
        }
      }

      // 子场景 C：远端直接传入 status='superseded' 但带更新 user_edit updated_at 的 P1 快照时，收敛器同样将其恢复为 active 并淘汰旧终点 P2
      final dirPayload =
          await Directory.systemTemp.createTemp('sup_edit_payload_');
      final receiver = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirPayload.path, 'receiver.db'),
      );
      try {
        await receiver.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'p1_sup_edited',
              'kind': 'preference',
              'directive': '最新人工纠正指令',
              'observed_at': '2026-11-21T11:00:00.000000Z',
              'updated_at': '2026-11-21T11:00:00.000000Z',
              'status': 'superseded',
              'superseded_by': 'p2_old_term',
              'replaces_id': null,
              'source': 'user_edit',
            },
            <String, Object?>{
              'id': 'p2_old_term',
              'kind': 'preference',
              'directive': '旧去重终点指令',
              'observed_at': '2026-11-21T10:00:00.000000Z',
              'updated_at': '2026-11-21T10:00:00.000000Z',
              'status': 'active',
              'superseded_by': null,
              'replaces_id': null,
              'source': 'thoughter',
            },
          ],
        });
        expect(
          (await receiver.activeProfile())
              .map((e) => '${e.id}:${e.directive}')
              .toList(),
          <String>['p1_sup_edited:最新人工纠正指令'],
        );
      } finally {
        receiver.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dirPayload.exists()) {
          await dirPayload.delete(recursive: true);
        }
      }
    });

    test('Devin 审查回归 #72（记忆对偶）：09:00 无偏移旧版记忆在 02:00Z 墓碑删除或清空后，跨时区合入旧快照绝不复活',
        () async {
      final dir = await Directory.systemTemp.createTemp('mem_legacy_del_');
      final svc = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'mem.db'),
      );
      try {
        final staleLegacyMemory = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_legacy_0900',
              'kind': 'preference',
              'directive': '东八区 09:00 无偏移旧画像',
              'observed_at': '2026-11-21T09:00:00.000',
            },
          ],
          'facts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'fact_legacy_0900',
              'content': '东八区 09:00 无偏移旧事实',
              'importance': 6,
              'created_at': '2026-11-21T09:00:00.000',
            },
          ],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        };

        await svc.mergeMemorySection(staleLegacyMemory);
        expect((await svc.activeProfile()).length, 1);
        expect((await svc.allFacts()).length, 1);

        // 模拟在 02:00Z 删除该画像与事实（早于字面 09:00Z）后再次重合并 09:00 无偏移旧快照
        await svc.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Object?>[],
          'facts': <Object?>[],
          'tombstones': <Map<String, Object?>>[
            <String, Object?>{
              'entity_type': 'profile',
              'entity_id': 'prof_legacy_0900',
              'deleted_at': '2026-11-21T02:00:00.000000Z',
            },
            <String, Object?>{
              'entity_type': 'fact',
              'entity_id': 'fact_legacy_0900',
              'deleted_at': '2026-11-21T02:00:00.000000Z',
            },
          ],
        });
        expect(await svc.activeProfile(), isEmpty);
        expect(await svc.allFacts(), isEmpty);

        await svc.mergeMemorySection(staleLegacyMemory);
        expect(await svc.activeProfile(), isEmpty);
        expect(await svc.allFacts(), isEmpty);
      } finally {
        svc.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });
  });

  group('第六轮评审回归：确认称呼保护、编辑链收敛、裁剪替换表与清空代际失效', () {
    test('已确认身份称呼与相同观测覆盖面的较新未确认 Dreaming 称呼重复合并时，已确认称呼保持唯一 active', () async {
      final dir = await Directory.systemTemp.createTemp('alias_repeat_sync_');
      final memA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'a.db'),
      );
      final memB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'b.db'),
      );
      try {
        await memA.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_confirmed_alias',
              'kind': 'identity',
              'directive': '称呼用户为「示例笔名甲」',
              'observed_at': '2026-11-20T08:00:00.000Z',
              'updated_at': '2026-11-20T08:05:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-20T08:00:00.000Z',
              'basis_note_count': 5,
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        final unconfirmedPeerSnapshot = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_dreaming_alias',
              'kind': 'identity',
              'directive': '称呼用户为「示例笔名甲」（存疑，待确认）',
              'observed_at': '2026-11-20T09:30:00.000Z',
              'updated_at': '2026-11-20T09:30:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-20T08:00:00.000Z',
              'basis_note_count': 5,
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        };
        await memB.mergeMemorySection(unconfirmedPeerSnapshot);

        // 首轮合并与重复合并旧快照：已确认称呼均不得被未确认称呼反超退役
        await memA.mergeMemorySection(unconfirmedPeerSnapshot);
        expect(
          (await memA.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_confirmed_alias'],
        );

        await memA.mergeMemorySection(unconfirmedPeerSnapshot);
        expect(
          (await memA.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_confirmed_alias'],
        );

        // 双向同步收敛验证
        await memB.mergeMemorySection(
          (await memA.exportMemorySectionForTesting())!,
        );
        await memA.mergeMemorySection(
          (await memB.exportMemorySectionForTesting())!,
        );
        expect(
          (await memA.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_confirmed_alias'],
        );
        expect(
          (await memB.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_confirmed_alias'],
        );
      } finally {
        memA.dispose();
        memB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        '中继节点 P2 自身携带 replaces_id=P1 且曾被重复项 P3 取代后在离线端编辑复活：双向合并均收敛为仅 P2 active 且保留 replaces_id=P1',
        () async {
      final dir = await Directory.systemTemp.createTemp('p1_p2_p3_edit_');
      final memWithP3 = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'with_p3.db'),
      );
      final memOfflineEditA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'offline_edit_a.db'),
      );
      final memOfflineEditB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'offline_edit_b.db'),
      );
      try {
        final baseP1P2 = <Map<String, Object?>>[
          <String, Object?>{
            'id': 'prof_chain_p1',
            'kind': 'style',
            'directive': '初代冗长回复风格',
            'observed_at': '2026-11-01T08:00:00.000Z',
            'updated_at': '2026-11-02T08:00:00.000Z',
            'status': 'superseded',
            'superseded_by': 'prof_chain_p2',
            'source': 'dreaming',
          },
          <String, Object?>{
            'id': 'prof_chain_p2',
            'kind': 'style',
            'directive': '二代精炼回复风格',
            'observed_at': '2026-11-02T08:00:00.000Z',
            'updated_at': '2026-11-02T08:00:00.000Z',
            'status': 'active',
            'replaces_id': 'prof_chain_p1',
            'source': 'dreaming',
          },
        ];
        await memOfflineEditA.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': baseP1P2,
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });
        await memOfflineEditB.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': baseP1P2,
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        await memWithP3.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            baseP1P2[0],
            <String, Object?>{
              ...baseP1P2[1],
              'status': 'superseded',
              'superseded_by': 'prof_chain_p3',
              'updated_at': '2026-11-03T08:00:00.000Z',
            },
            <String, Object?>{
              'id': 'prof_chain_p3',
              'kind': 'style',
              'directive': '三代重复提炼回复风格',
              'observed_at': '2026-11-03T08:00:00.000Z',
              'updated_at': '2026-11-03T08:00:00.000Z',
              'status': 'active',
              'replaces_id': 'prof_chain_p2',
              'source': 'dreaming',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        // 离线端手改 P2（updated_at 为当前 UTC，晚于 2026-11-03）
        await memOfflineEditA.editProfileDirective(
          id: 'prof_chain_p2',
          directive: '用户手改精炼风格',
        );
        await memOfflineEditB.editProfileDirective(
          id: 'prof_chain_p2',
          directive: '用户手改精炼风格',
        );

        final p3Snap = (await memWithP3.exportMemorySectionForTesting())!;
        final editSnap =
            (await memOfflineEditA.exportMemorySectionForTesting())!;

        // 方向一：持有 P3 的设备合入离线编辑快照
        await memWithP3.mergeMemorySection(editSnap);
        final activeOnP3Node = await memWithP3.activeProfile();
        expect(activeOnP3Node.map((e) => e.id).toList(), <String>[
          'prof_chain_p2',
        ]);
        expect(activeOnP3Node.single.directive, '用户手改精炼风格');
        final exportedAfter1 =
            (await memWithP3.exportMemorySectionForTesting())!;
        final p2Row1 = (exportedAfter1['profile'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((r) => r['id'] == 'prof_chain_p2');
        expect(p2Row1['replaces_id'], 'prof_chain_p1');

        // 方向二：离线编辑设备合入持有 P3 的快照
        await memOfflineEditB.mergeMemorySection(p3Snap);
        final activeOnEditNode = await memOfflineEditB.activeProfile();
        expect(activeOnEditNode.map((e) => e.id).toList(), <String>[
          'prof_chain_p2',
        ]);
        expect(activeOnEditNode.single.directive, '用户手改精炼风格');
        final exportedAfter2 =
            (await memOfflineEditB.exportMemorySectionForTesting())!;
        final p2Row2 = (exportedAfter2['profile'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((r) => r['id'] == 'prof_chain_p2');
        expect(p2Row2['replaces_id'], 'prof_chain_p1');
      } finally {
        memWithP3.dispose();
        memOfflineEditA.dispose();
        memOfflineEditB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('editProfileDirective 沿多跳 superseded_by 链单次批量回溯并将远端终端节点收口为 superseded',
        () async {
      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'hop_1',
            'kind': 'preference',
            'directive': '跳点一',
            'observed_at': '2026-10-01T08:00:00.000Z',
            'updated_at': '2026-10-02T08:00:00.000Z',
            'status': 'superseded',
            'superseded_by': 'hop_2',
          },
          <String, Object?>{
            'id': 'hop_2',
            'kind': 'preference',
            'directive': '跳点二',
            'observed_at': '2026-10-02T08:00:00.000Z',
            'updated_at': '2026-10-03T08:00:00.000Z',
            'status': 'superseded',
            'replaces_id': 'hop_1',
            'superseded_by': 'hop_3',
          },
          <String, Object?>{
            'id': 'hop_3',
            'kind': 'preference',
            'directive': '跳点三',
            'observed_at': '2026-10-03T08:00:00.000Z',
            'updated_at': '2026-10-04T08:00:00.000Z',
            'status': 'superseded',
            'replaces_id': 'hop_2',
            'superseded_by': 'hop_4',
          },
          <String, Object?>{
            'id': 'hop_4',
            'kind': 'preference',
            'directive': '跳点四当前生效',
            'observed_at': '2026-10-04T08:00:00.000Z',
            'updated_at': '2026-10-04T08:00:00.000Z',
            'status': 'active',
            'replaces_id': 'hop_3',
          },
        ],
        'facts': <Object?>[],
        'recent_slices': <Object?>[],
        'tombstones': <Object?>[],
      });

      final updated = await memory.editProfileDirective(
        id: 'hop_1',
        directive: '跳点一编辑复活指令',
      );
      expect(updated, isTrue);

      final active = await memory.activeProfile();
      expect(active.map((e) => e.id).toList(), <String>['hop_1']);
      expect(active.single.directive, '跳点一编辑复活指令');

      final exported = (await memory.exportMemorySectionForTesting())!;
      final hop4 = (exported['profile'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['id'] == 'hop_4');
      expect(hop4['status'], 'superseded');
      expect(hop4['superseded_by'], 'hop_1');
    });

    test(
        'compactAndPrune 裁剪超期 superseded 行后持久化 profile_replacements，离线设备旧偏好同步时被正确退役不复活',
        () async {
      final dir = await Directory.systemTemp.createTemp('prune_replacements_');
      final memA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'a.db'),
      );
      final memB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'b.db'),
      );
      try {
        // 离线设备 B 仍持有 40 天前的旧偏好 active
        await memB.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_old_pref',
              'kind': 'preference',
              'directive': '旧偏好：每句末尾附带感叹号',
              'observed_at': '2026-09-01T08:00:00.000Z',
              'updated_at': '2026-09-01T08:00:00.000Z',
              'status': 'active',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        // 设备 A 经历了 prof_old_pref -> prof_mid_pref -> prof_cur_pref 两级演进
        await memA.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_old_pref',
              'kind': 'preference',
              'directive': '旧偏好：每句末尾附带感叹号',
              'observed_at': '2026-09-01T08:00:00.000Z',
              'updated_at': '2026-09-05T08:00:00.000Z',
              'status': 'superseded',
              'superseded_by': 'prof_mid_pref',
            },
            <String, Object?>{
              'id': 'prof_mid_pref',
              'kind': 'preference',
              'directive': '过渡偏好：适度使用标点',
              'observed_at': '2026-09-05T08:00:00.000Z',
              'updated_at': '2026-11-01T08:00:00.000Z',
              'status': 'superseded',
              'replaces_id': 'prof_old_pref',
              'superseded_by': 'prof_cur_pref',
            },
            <String, Object?>{
              'id': 'prof_cur_pref',
              'kind': 'preference',
              'directive': '当前偏好：克制平实叙述',
              'observed_at': '2026-11-01T08:00:00.000Z',
              'updated_at': '2026-11-01T08:00:00.000Z',
              'status': 'active',
              'replaces_id': 'prof_mid_pref',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        // 在 2026-11-20 执行裁剪：prof_old_pref 与 prof_mid_pref 超 30 天被物理删除
        await memA.compactAndPrune(now: DateTime.utc(2026, 11, 20));
        final snapA = (await memA.exportMemorySectionForTesting())!;
        expect(
          (snapA['profile'] as List).map((e) => (e as Map)['id']).toList(),
          <String>['prof_cur_pref'],
        );
        final replacements = snapA['profile_replacements'] as List;
        expect(
          replacements.any(
            (r) =>
                (r as Map)['from_id'] == 'prof_old_pref' &&
                r['to_id'] == 'prof_cur_pref',
          ),
          isTrue,
        );

        final snapBStale = (await memB.exportMemorySectionForTesting())!;

        // A 合入 B 的旧快照：旧偏好绝不复活
        await memA.mergeMemorySection(snapBStale);
        expect(
          (await memA.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_cur_pref'],
        );

        // B 合入 A 的已裁剪快照：B 上的 prof_old_pref 被退役为 superseded
        await memB.mergeMemorySection(snapA);
        expect(
          (await memB.activeProfile()).map((e) => e.id).toList(),
          <String>['prof_cur_pref'],
        );
      } finally {
        memA.dispose();
        memB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('mergeMemorySection 应用远端更新的 cleared_at 时使进行中的提取代际失效，拦截跨清空脏写',
        () async {
      await memory.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '清空前本地偏好',
      );
      final inFlightGen = memory.captureGeneration;
      expect(memory.isCaptureCurrent(inFlightGen), isTrue);

      await memory.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'cleared_at': '2099-01-01T00:00:00.000000Z',
        'profile': <Object?>[],
        'facts': <Object?>[],
        'recent_slices': <Object?>[],
        'tombstones': <Object?>[],
      });

      expect(memory.isCaptureCurrent(inFlightGen), isFalse);
      final persisted = await memory.rememberProfileFromCapture(
        generation: inFlightGen,
        kind: AgentMemoryKind.preference,
        directive: '清空前已发起但晚返回的脏提取指令',
        source: 'dreaming',
      );
      expect(persisted, isFalse);
      expect(await memory.activeProfile(), isEmpty);
    });

    test('Dreaming 真实「待确认笔名」格式在携带等覆盖面 basisChecker、共享前驱分叉及多轮重复合并下均不退位已确认称呼',
        () async {
      final dir = await Directory.systemTemp.createTemp('dreaming_alias_real_');
      final memA = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'a.db'),
      );
      final memB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'b.db'),
      );
      try {
        await memA.registerInferredAlias(
          '示例笔名乙',
          source: 'dreaming',
          unconfirmed: false,
          observedAt: DateTime.utc(2026, 11, 20, 8, 0),
          basisWatermark: '2026-11-20T08:00:00.000000Z',
          basisNoteCount: 5,
        );
        await memB.registerInferredAlias(
          '示例笔名乙',
          source: 'dreaming_ai',
          unconfirmed: true,
          observedAt: DateTime.utc(2026, 11, 21, 9, 30),
          basisWatermark: '2026-11-20T08:00:00.000000Z',
          basisNoteCount: 5,
        );

        final unchangedUnconfirmedSnap =
            (await memB.exportMemorySectionForTesting())!;
        Future<bool> allCovered(String? wm, int? count) async => true;

        // 连续两次合入未变更的较新未确认快照（带等覆盖面 basisChecker）
        await memA.mergeMemorySection(
          unchangedUnconfirmedSnap,
          isBasisCovered: allCovered,
        );
        expect(
          await memA.activeIdentityAliases(),
          contains('示例笔名乙'),
        );
        expect(
          (await memA.activeProfile()).single.directive,
          '称呼用户为「示例笔名乙」',
        );

        await memA.mergeMemorySection(
          unchangedUnconfirmedSnap,
          isBasisCovered: allCovered,
        );
        expect(
          await memA.activeIdentityAliases(),
          contains('示例笔名乙'),
        );
        expect(
          (await memA.activeProfile()).single.directive,
          '称呼用户为「示例笔名乙」',
        );

        // 双向同步后两端均唯一保留已确认称呼
        await memB.mergeMemorySection(
          (await memA.exportMemorySectionForTesting())!,
          isBasisCovered: allCovered,
        );
        await memA.mergeMemorySection(
          (await memB.exportMemorySectionForTesting())!,
          isBasisCovered: allCovered,
        );
        expect(
          (await memA.activeProfile()).single.directive,
          '称呼用户为「示例笔名乙」',
        );
        expect(
          (await memB.activeProfile()).single.directive,
          '称呼用户为「示例笔名乙」',
        );
      } finally {
        memA.dispose();
        memB.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test(
        '非单例 preference 节点 P2（已带 replaces_id=P1）在一端被独立同文 P3 文本去重、另一端原位编辑时，正反合并顺序与前后编辑时序均不残留冲突双活偏好',
        () async {
      for (final editNewerThanDup in <bool>[true, false]) {
        final dir = await Directory.systemTemp.createTemp('pref_dedup_edit_');
        final memDedup = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'dedup.db'),
        );
        final memEditFirst = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'edit_first.db'),
        );
        final memDedupFirst = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'dedup_first.db'),
        );
        try {
          // 初始状态：P2（简短回答）显式替换了 P1（冗长回答）
          final initialP1P2 = <String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'pref_long_p1',
                'kind': 'preference',
                'directive': '请使用冗长回答',
                'observed_at': '2026-11-01T08:00:00.000000Z',
                'updated_at': '2026-11-01T08:00:00.000000Z',
                'status': 'superseded',
                'superseded_by': 'pref_short_p2',
                'source': 'thoughter',
              },
              <String, Object?>{
                'id': 'pref_short_p2',
                'kind': 'preference',
                'directive': '请使用简短回答',
                'observed_at': '2026-11-02T08:00:00.000000Z',
                'updated_at': '2026-11-02T08:00:00.000000Z',
                'status': 'active',
                'replaces_id': 'pref_long_p1',
                'source': 'thoughter',
              },
            ],
            'facts': <Object?>[],
            'recent_slices': <Object?>[],
            'tombstones': <Object?>[],
          };
          await memDedup.mergeMemorySection(initialP1P2);
          await memEditFirst.mergeMemorySection(initialP1P2);
          await memDedupFirst.mergeMemorySection(initialP1P2);

          // 一端独立新增同正文 P3（replaces_id 为空），经文本去重使 P2 -> P3
          final dupTimeIso = editNewerThanDup
              ? '2026-11-03T08:00:00.000000Z'
              : '2099-11-03T08:00:00.000000Z';
          await memDedup.mergeMemorySection(<String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'pref_short_dup_p3',
                'kind': 'preference',
                'directive': '请使用简短回答',
                'observed_at': dupTimeIso,
                'updated_at': dupTimeIso,
                'status': 'active',
                'replaces_id': null,
                'source': 'thoughter',
              },
            ],
          });
          await memDedupFirst.mergeMemorySection(
            (await memDedup.exportMemorySectionForTesting())!,
          );
          expect(
            (await memDedupFirst.activeProfile()).map((e) => e.id).toList(),
            <String>['pref_short_dup_p3'],
          );

          // 离线端原位修改 P2 为「请使用详细回答」（自身仍携带 replaces_id = pref_long_p1）
          await memEditFirst.editProfileDirective(
            id: 'pref_short_p2',
            directive: '请使用详细回答',
          );

          final snapDedup =
              (await memDedupFirst.exportMemorySectionForTesting())!;
          final snapEdit =
              (await memEditFirst.exportMemorySectionForTesting())!;

          // 合并顺序 1：文本去重端合入离线编辑快照
          await memDedupFirst.mergeMemorySection(snapEdit);
          // 合并顺序 2：离线编辑端合入文本去重快照
          await memEditFirst.mergeMemorySection(snapDedup);

          final expectedWinnerId =
              editNewerThanDup ? 'pref_short_p2' : 'pref_short_dup_p3';
          final expectedDirective = editNewerThanDup ? '请使用详细回答' : '请使用简短回答';

          for (final node in <AgentMemoryService>[
            memDedupFirst,
            memEditFirst
          ]) {
            final active = await node.activeProfile();
            expect(
                active.map((e) => e.id).toList(), <String>[expectedWinnerId]);
            expect(active.single.directive, expectedDirective);

            final exported = (await node.exportMemorySectionForTesting())!;
            final p2Row = (exported['profile'] as List)
                .cast<Map<String, dynamic>>()
                .singleWhere((r) => r['id'] == 'pref_short_p2');
            expect(p2Row['replaces_id'], 'pref_long_p1');
          }
        } finally {
          memDedup.dispose();
          memEditFirst.dispose();
          memDedupFirst.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }
    });

    test('合入较旧快照时，若其中的去重副本 D 已被本机墓碑删除或被 cleared_at 阻挡，绝不将本机已离线编辑的偏好 P 级联退役',
        () async {
      final dir = await Directory.systemTemp.createTemp('tomb_dup_edit_pref_');
      final memTombCase = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'tomb_case.db'),
      );
      final memClearedCase = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'cleared_case.db'),
      );
      try {
        // 场景 1：设备 A 在 t2 离线编辑了偏好 P，并在 t4 已墓碑删除重复项 D；
        //        随后合入来自设备 B 的旧备份（其中 P@t1 指向去重赢家 D@t3，且 t2 < t3 < t4）。
        await memTombCase.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'pref_p_edited',
              'kind': 'preference',
              'directive': '用户离线编辑后的有效偏好',
              'observed_at': '2026-11-01T08:00:00.000000Z',
              'updated_at': '2026-11-02T08:00:00.000000Z',
              'status': 'active',
              'source': 'user_edit',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Map<String, Object?>>[
            <String, Object?>{
              'entity_type': 'profile',
              'entity_id': 'pref_d_deleted_dup',
              'deleted_at': '2026-11-04T08:00:00.000000Z',
            },
          ],
        });

        await memTombCase.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'pref_p_edited',
              'kind': 'preference',
              'directive': '未编辑前的旧偏好文案',
              'observed_at': '2026-11-01T08:00:00.000000Z',
              'updated_at': '2026-11-01T08:00:00.000000Z',
              'status': 'superseded',
              'superseded_by': 'pref_d_deleted_dup',
              'source': 'thoughter',
            },
            <String, Object?>{
              'id': 'pref_d_deleted_dup',
              'kind': 'preference',
              'directive': '未编辑前的旧偏好文案',
              'observed_at': '2026-11-03T08:00:00.000000Z',
              'updated_at': '2026-11-03T08:00:00.000000Z',
              'status': 'active',
              'source': 'thoughter',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        final activeAfterTombMerge = await memTombCase.activeProfile();
        expect(
          activeAfterTombMerge.map((e) => e.id).toList(),
          <String>['pref_p_edited'],
          reason: '被墓碑拦截的重复项 D 绝不能反向生成替换边把已编辑的活跃偏好 P 退役',
        );
        expect(
          activeAfterTombMerge.single.directive,
          '用户离线编辑后的有效偏好',
        );
        final exportedTombCase =
            (await memTombCase.exportMemorySectionForTesting())!;
        expect(exportedTombCase['profile_replacements'] ?? const <Object?>[],
            isEmpty);

        // 场景 2：superseded 条目 P2 自身晚于 cleared_at（不会被入口屏障直接跳过，会进入后继链解析），
        // 但其 superseded_by 指向的高优后继 D2（source: user_edit）早于 cleared_at。
        // 若缺少后继准入屏障过滤，D2（user_edit）将击败活跃 P2（dreaming）并错误把 P2 退役。
        await memClearedCase.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'cleared_at': '2026-11-05T00:00:00.000000Z',
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'pref_p2_post_clear',
              'kind': 'preference',
              'directive': '清空后重新提炼的活跃偏好',
              'observed_at': '2026-11-06T08:00:00.000000Z',
              'updated_at': '2026-11-06T08:00:00.000000Z',
              'status': 'active',
              'source': 'dreaming',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        await memClearedCase.mergeMemorySection(<String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'pref_p2_post_clear',
              'kind': 'preference',
              'directive': '清空后但早于本机修订的已取代版本',
              'observed_at': '2026-11-05T10:00:00.000000Z',
              'updated_at': '2026-11-05T10:00:00.000000Z',
              'status': 'superseded',
              'superseded_by': 'pref_d2_pre_clear',
              'source': 'dreaming',
            },
            <String, Object?>{
              'id': 'pref_d2_pre_clear',
              'kind': 'preference',
              'directive': '清空前残留的高优先级版本',
              'observed_at': '2026-11-04T08:00:00.000000Z',
              'updated_at': '2026-11-04T08:00:00.000000Z',
              'status': 'active',
              'source': 'user_edit',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        });

        final activeAfterClearedMerge = await memClearedCase.activeProfile();
        expect(
          activeAfterClearedMerge.map((e) => e.id).toList(),
          <String>['pref_p2_post_clear'],
          reason: 'P2 晚于 cleared_at 进入后继链判定时，早于 cleared_at 的后继 D2 必须被准入过滤拦截',
        );
        final exportedClearedCase =
            (await memClearedCase.exportMemorySectionForTesting())!;
        expect(
          exportedClearedCase['profile_replacements'] ?? const <Object?>[],
          isEmpty,
        );

        // 对称合并顺序验证（cmpProf > 0 分支）：本机先持有晚于 cleared_at 的 superseded P2，
        // 远端合入 cleared_at 屏障 + 更新的活跃 dreaming P2 + 早于 cleared_at 的高优 D2
        final memClearedReverse = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'cleared_case_reverse.db'),
        );
        try {
          await memClearedReverse.mergeMemorySection(<String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'pref_p2_post_clear',
                'kind': 'preference',
                'directive': '本机先持有的已取代版本',
                'observed_at': '2026-11-05T10:00:00.000000Z',
                'updated_at': '2026-11-05T10:00:00.000000Z',
                'status': 'superseded',
                'superseded_by': 'pref_d2_pre_clear',
                'source': 'dreaming',
              },
            ],
            'facts': <Object?>[],
            'recent_slices': <Object?>[],
            'tombstones': <Object?>[],
          });

          await memClearedReverse.mergeMemorySection(<String, dynamic>{
            'format': 1,
            'cleared_at': '2026-11-05T00:00:00.000000Z',
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'pref_p2_post_clear',
                'kind': 'preference',
                'directive': '远端清空后更新的活跃偏好',
                'observed_at': '2026-11-06T08:00:00.000000Z',
                'updated_at': '2026-11-06T08:00:00.000000Z',
                'status': 'active',
                'source': 'dreaming',
              },
              <String, Object?>{
                'id': 'pref_d2_pre_clear',
                'kind': 'preference',
                'directive': '清空前残留的高优先级版本',
                'observed_at': '2026-11-04T08:00:00.000000Z',
                'updated_at': '2026-11-04T08:00:00.000000Z',
                'status': 'active',
                'source': 'user_edit',
              },
            ],
            'facts': <Object?>[],
            'recent_slices': <Object?>[],
            'tombstones': <Object?>[],
          });

          final activeReverse = await memClearedReverse.activeProfile();
          expect(
            activeReverse.map((e) => e.id).toList(),
            <String>['pref_p2_post_clear'],
          );
        } finally {
          memClearedReverse.dispose();
        }
      } finally {
        memTombCase.dispose();
        memClearedCase.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('共享同一 replaces_id 前驱的身份别名分叉（已确认称呼 vs 更新的待确认笔名）在正反合并顺序与多轮重入下均唯一保留已确认称呼',
        () async {
      final dir = await Directory.systemTemp.createTemp('alias_fork_shared_');
      final memConfFirst = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'conf_first.db'),
      );
      final memUnconfFirst = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dir.path, 'unconf_first.db'),
      );
      try {
        final predRow = <String, Object?>{
          'id': 'id_shared_pred',
          'kind': 'identity',
          'directive': '称呼用户为「旧笔名甲」',
          'observed_at': '2026-11-18T08:00:00.000000Z',
          'updated_at': '2026-11-18T08:00:00.000000Z',
          'status': 'superseded',
          'source': 'dreaming',
          'basis_watermark': '2026-11-18T08:00:00.000000Z',
          'basis_note_count': 3,
        };
        final confirmedForkSnap = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              ...predRow,
              'superseded_by': 'id_fork_confirmed',
            },
            <String, Object?>{
              'id': 'id_fork_confirmed',
              'kind': 'identity',
              'directive': '称呼用户为「示例笔名丙」',
              'observed_at': '2026-11-20T08:00:00.000000Z',
              'updated_at': '2026-11-20T08:00:00.000000Z',
              'status': 'active',
              'replaces_id': 'id_shared_pred',
              'source': 'dreaming',
              'basis_watermark': '2026-11-20T08:00:00.000000Z',
              'basis_note_count': 6,
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        };
        final unconfirmedForkSnap = <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              ...predRow,
              'superseded_by': 'id_fork_unconfirmed',
            },
            <String, Object?>{
              'id': 'id_fork_unconfirmed',
              'kind': 'identity',
              'directive': '称呼用户为「示例笔名丙」（待确认笔名）',
              'observed_at': '2026-11-21T09:30:00.000000Z',
              'updated_at': '2026-11-21T09:30:00.000000Z',
              'status': 'active',
              'replaces_id': 'id_shared_pred',
              'source': 'dreaming_ai',
              'basis_watermark': '2026-11-20T08:00:00.000000Z',
              'basis_note_count': 6,
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        };

        Future<bool> allCovered(String? wm, int? count) async => true;

        // 顺序 1：先已确认分叉，后连续两次合入时间戳更新的待确认分叉
        await memConfFirst.mergeMemorySection(
          confirmedForkSnap,
          isBasisCovered: allCovered,
        );
        await memConfFirst.mergeMemorySection(
          unconfirmedForkSnap,
          isBasisCovered: allCovered,
        );
        await memConfFirst.mergeMemorySection(
          unconfirmedForkSnap,
          isBasisCovered: allCovered,
        );

        // 顺序 2：先待确认分叉，后合入已确认分叉，再重入待确认分叉
        await memUnconfFirst.mergeMemorySection(
          unconfirmedForkSnap,
          isBasisCovered: allCovered,
        );
        await memUnconfFirst.mergeMemorySection(
          confirmedForkSnap,
          isBasisCovered: allCovered,
        );
        await memUnconfFirst.mergeMemorySection(
          unconfirmedForkSnap,
          isBasisCovered: allCovered,
        );

        for (final node in <AgentMemoryService>[memConfFirst, memUnconfFirst]) {
          final active = await node.activeProfile();
          expect(
              active.map((e) => e.id).toList(), <String>['id_fork_confirmed']);
          expect(active.single.directive, '称呼用户为「示例笔名丙」');
          expect(await node.activeIdentityAliases(), contains('示例笔名丙'));
        }
      } finally {
        memConfFirst.dispose();
        memUnconfFirst.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    });
  });
}

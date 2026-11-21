import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/assistant_data_sync_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/dreaming_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

class _CountingDatabaseService extends DatabaseService {
  _CountingDatabaseService() : super.forTesting();

  int singleWatermarkCalls = 0;
  int batchWatermarkCalls = 0;

  void resetCounters() {
    singleWatermarkCalls = 0;
    batchWatermarkCalls = 0;
  }

  @override
  Future<int> countActiveNotesUpToWatermark(String watermarkIso) {
    singleWatermarkCalls++;
    return super.countActiveNotesUpToWatermark(watermarkIso);
  }

  @override
  Future<Map<String, int>> countActiveNotesUpToWatermarks(
    Iterable<String> watermarks,
  ) {
    batchWatermarkCalls++;
    return super.countActiveNotesUpToWatermarks(watermarks);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database rawNotesDb;
  late _CountingDatabaseService databaseService;
  late SettingsService settingsService;
  late ChatSessionService chatService;
  late AgentMemoryService memoryService;
  late AssistantDataSyncService assistantSync;

  setUpAll(() async {
    await TestHarness.initialize();
    await AppPreferencesService().init();
  });

  tearDownAll(TestHarness.tearDown);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dreaming_basis_test_');
    await AppPreferencesService().clear();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settingsService = SettingsService(await SharedPreferences.getInstance());
    await settingsService.setAgentMemoryEnabled(true);

    rawNotesDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchemaManager().createTables(rawNotesDb);
    DatabaseService.setTestDatabase(rawNotesDb);
    databaseService = _CountingDatabaseService();
    await databaseService.init();

    chatService = ChatSessionService(
      databasePath: p.join(tempDir.path, 'chat.db'),
    );
    await chatService.init();

    memoryService = AgentMemoryService(
      settingsService: settingsService,
      databasePath: p.join(tempDir.path, 'agent_memory.db'),
    );

    assistantSync = AssistantDataSyncService(
      chatSessionService: chatService,
      agentMemoryService: memoryService,
      settingsService: settingsService,
      databaseService: databaseService,
    );
  });

  tearDown(() async {
    await chatService.close();
    chatService.dispose();
    memoryService.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    DatabaseService.clearTestDatabase();
    await rawNotesDb.close();
    SharedPreferences.resetStatic();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> insertNote({
    required String id,
    required String content,
    required String lastModifiedIso,
    int isDeleted = 0,
  }) async {
    await rawNotesDb.insert('quotes', <String, Object?>{
      'id': id,
      'content': content,
      'date': lastModifiedIso,
      'last_modified': lastModifiedIso,
      'is_deleted': isDeleted,
    });
  }

  List<Quote> buildSampleNotes({int count = 12}) {
    return List<Quote>.generate(count, (i) {
      final isExcerpt = i.isEven;
      return Quote(
        id: 'sample_n_$i',
        content: isExcerpt ? '合成摘录样本笔记文本 $i' : '合成原创随笔样本 $i，写于整理归档日',
        date: '2026-11-10T08:00:00.000Z',
        sourceAuthor: isExcerpt ? '示例作者' : '墨客',
        sourceWork: isExcerpt ? '示例文集' : '个人随笔',
      );
    });
  }

  group('Dreaming 依据采集与看全判定', () {
    test('Dreaming 写入画像与导出元数据时正确记录活跃笔记的 basis_watermark 与 basis_note_count',
        () async {
      // 插入 12 条有效笔记（最大水位 2026-11-10T08:00:00.000Z）+ 2 条回收站已删笔记（不计入依据）
      for (var i = 0; i < 12; i++) {
        final hour = (i % 8) + 1;
        final ts = i == 11
            ? '2026-11-10T08:00:00.000Z'
            : '2026-11-09T0$hour:00:00.000Z';
        await insertNote(
          id: 'active_n_$i',
          content: '有效笔记正文 $i',
          lastModifiedIso: ts,
        );
      }
      await insertNote(
        id: 'deleted_n_1',
        content: '已删笔记不应计入依据',
        lastModifiedIso: '2026-11-12T00:00:00.000Z',
        isDeleted: 1,
      );

      final runTime = DateTime.utc(2026, 11, 10, 9, 0);
      final dreaming = DreamingService(
        settingsService: settingsService,
        memoryService: memoryService,
        loadNotes: ({required start, required end, required limit}) async =>
            buildSampleNotes(),
        loadNotesBasis: databaseService.getActiveNotesBasis,
        complete: ({required systemPrompt, required userMessage}) async => '''
          {
            "taste": "偏好哲理短句与结构化读书摘录",
            "voice": "习惯用精炼第一人称记录观察",
            "recent": "近期正在整理同步模块设计",
            "inferred_aliases": [{"alias": "墨客", "confident": true}]
          }
        ''',
      );

      final outcome = await dreaming.run(now: runTime);
      expect(outcome, DreamingOutcome.updated);

      final active = await memoryService.activeProfile();
      expect(active.length, greaterThanOrEqualTo(3));
      for (final entry in active) {
        expect(entry.basisWatermark, '2026-11-10T08:00:00.000Z');
        expect(entry.basisNoteCount, 12);
      }

      final exported = await memoryService.exportMemorySectionForTesting();
      expect(exported, isNotNull);
      final exportedDreaming = exported!['dreaming'] as Map<String, dynamic>;
      expect(exportedDreaming['last_run_at'], '2026-11-10T09:00:00.000000Z');
      expect(
        exportedDreaming['basis_watermark'],
        '2026-11-10T08:00:00.000Z',
      );
      expect(exportedDreaming['basis_note_count'], 12);
    });

    test('看全判定：运行后新增笔记（last_modified > watermark）仍判为看全；补入更早笔记超出计数则判为漏看',
        () async {
      // 初始有 3 条 <= 2026-11-10T10:00:00.000Z 的笔记
      await insertNote(
        id: 'n1',
        content: '笔记1',
        lastModifiedIso: '2026-11-08T10:00:00.000Z',
      );
      await insertNote(
        id: 'n2',
        content: '笔记2',
        lastModifiedIso: '2026-11-09T10:00:00.000Z',
      );
      await insertNote(
        id: 'n3',
        content: '笔记3',
        lastModifiedIso: '2026-11-10T10:00:00.000Z',
      );

      // 运行后新增了 2 条晚于 watermark 的新笔记（不应使 2026-11-10T10:00:00.000Z / count=3 的结论失效）
      await insertNote(
        id: 'n_after_1',
        content: 'Dreaming 之后新写的笔记A',
        lastModifiedIso: '2026-11-11T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_after_2',
        content: 'Dreaming 之后新写的笔记B',
        lastModifiedIso: '2026-11-12T10:00:00.000Z',
      );

      // 本机有一条时间较早（11-10）、但看全了当时全部 3 条笔记的 Dreaming taste；
      // 远端传来一条时间更晚（11-12）、但只看到 2 条笔记（basis_note_count=2 < 实际水位内 3 条）的漏看 Dreaming taste。
      final localCovered = await memoryService.rememberProfile(
        kind: AgentMemoryKind.taste,
        directive: '看全全部历史笔记归纳出的品味结论',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 10, 10, 30),
        basisWatermark: '2026-11-10T10:00:00.000Z',
        basisNoteCount: 3,
      );

      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_uncovered_newer',
              'kind': 'taste',
              'directive': '未同步完整时归纳出的残缺品味结论',
              'observed_at': '2026-11-12T08:00:00.000Z',
              'updated_at': '2026-11-12T08:00:00.000Z', // 时间更新，但漏看
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T10:00:00.000Z',
              'basis_note_count': 2,
            },
          ],
        },
      });

      var activeTastes = (await memoryService.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.taste)
          .toList();
      expect(activeTastes, hasLength(1));
      expect(activeTastes.single.id, localCovered.id);

      // 现在模拟从另一台离线设备合并进一条 last_modified <= 2026-11-10T10:00:00.000Z 的旧笔记 n_offline_early，
      // 使得水位内实际活跃笔记变成 4 条（> localCovered.basisNoteCount=3），此时 localCovered 也变成“漏看”！
      await insertNote(
        id: 'n_offline_early',
        content: '离线设备补进来的早期笔记',
        lastModifiedIso: '2026-11-09T15:00:00.000Z',
      );
      expect(
        await databaseService.countActiveNotesUpToWatermark(
          '2026-11-10T10:00:00.000Z',
        ),
        4,
      );

      // 再合入一条看全了全部 4 条笔记（basis_note_count=4）的远端 Dreaming taste（哪怕时间比 localCovered 更早），看全者应胜出！
      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_now_covered',
              'kind': 'taste',
              'directive': '包含离线早期笔记后的完整品味结论',
              'observed_at': '2026-11-10T10:05:00.000Z',
              'updated_at': '2026-11-10T10:05:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T10:00:00.000Z',
              'basis_note_count': 4,
            },
          ],
        },
      });

      activeTastes = (await memoryService.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.taste)
          .toList();
      expect(activeTastes, hasLength(1));
      expect(activeTastes.single.id, 'remote_now_covered');
    });
  });

  group('Dreaming 冲突三分支与 lastDreamingAt 同步', () {
    test('均看全时取 updated_at 较新且保留 lastDreamingAt；均漏看时取较新保底并清空本机 lastDreamingAt',
        () async {
      await insertNote(
        id: 'base_1',
        content: '基础笔记1',
        lastModifiedIso: '2026-11-05T10:00:00.000Z',
      );
      await insertNote(
        id: 'base_2',
        content: '基础笔记2',
        lastModifiedIso: '2026-11-06T10:00:00.000Z',
      );

      final initialLastDreaming = DateTime.utc(2026, 11, 7, 9, 0);
      await settingsService.setLastDreamingAt(initialLastDreaming);

      // 分支 A：两条 voice 均看全（count=2 <= 2），应取 updated_at 较新者，且不清空 lastDreamingAt
      await memoryService.rememberProfile(
        kind: AgentMemoryKind.voice,
        directive: '本机较早但看全的文风归纳',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 6, 12, 0),
        basisWatermark: '2026-11-06T10:00:00.000Z',
        basisNoteCount: 2,
      );

      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'voice_both_covered_newer',
              'kind': 'voice',
              'directive': '远端更新且同样看全的文风归纳',
              'observed_at': '2026-11-07T08:00:00.000Z',
              'updated_at': '2026-11-07T08:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-06T10:00:00.000Z',
              'basis_note_count': 2,
            },
          ],
        },
      });

      final voices = (await memoryService.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.voice)
          .toList();
      expect(voices.single.id, 'voice_both_covered_newer');
      expect(settingsService.lastDreamingAt?.toUtc(), initialLastDreaming);

      // 分支 B：新增一条早期离线笔记，使双方在 taste 上均变成“漏看”（库里有 3 条 <= 水位，双方 basis_note_count 均为 1）
      await insertNote(
        id: 'base_early_3',
        content: '早期补入笔记3',
        lastModifiedIso: '2026-11-04T10:00:00.000Z',
      );

      await memoryService.rememberProfile(
        kind: AgentMemoryKind.taste,
        directive: '设备A只看到局部笔记的品味',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 6, 12, 0),
        basisWatermark: '2026-11-06T10:00:00.000Z',
        basisNoteCount: 1,
      );

      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': '2026-11-08T10:00:00.000Z',
            'basis_watermark': '2026-11-06T10:00:00.000Z',
            'basis_note_count': 1, // 同样漏看
          },
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'taste_both_uncovered_newer',
              'kind': 'taste',
              'directive': '设备B只看到另一半笔记但时间较新的品味',
              'observed_at': '2026-11-08T10:00:00.000Z',
              'updated_at': '2026-11-08T10:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-06T10:00:00.000Z',
              'basis_note_count': 1,
            },
          ],
        },
      });

      final tastes = (await memoryService.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.taste)
          .toList();
      expect(tastes, hasLength(1));
      expect(tastes.single.id, 'taste_both_uncovered_newer');
      // 关键断言：两条冲突 Dreaming 均漏看时，必须清空本机 lastDreamingAt 以触发重做！
      expect(settingsService.lastDreamingAt, isNull);
    });

    test('lastDreamingAt 同步：对端看全且更新则沿用，漏看或较旧则不沿用', () async {
      await insertNote(
        id: 'm1',
        content: '笔记A',
        lastModifiedIso: '2026-11-10T08:00:00.000Z',
      );
      await insertNote(
        id: 'm2',
        content: '笔记B',
        lastModifiedIso: '2026-11-10T09:00:00.000Z',
      );

      final localRun = DateTime.utc(2026, 11, 10, 12, 0);
      await settingsService.setLastDreamingAt(localRun);

      // 1. 对端时间虽新（11-14），但 basis_note_count=1 < 实际 2（漏看） -> 不沿用
      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': '2026-11-14T08:00:00.000Z',
            'basis_watermark': '2026-11-10T09:00:00.000Z',
            'basis_note_count': 1,
          },
        },
      });
      expect(settingsService.lastDreamingAt?.toUtc(), localRun);

      // 2. 对端看全（count=2），且时间比本机新（11-12 > 11-10） -> 沿用！
      final remoteCoveredNewer = DateTime.utc(2026, 11, 12, 18, 0);
      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': remoteCoveredNewer.toIso8601String(),
            'basis_watermark': '2026-11-10T09:00:00.000Z',
            'basis_note_count': 2,
          },
        },
      });
      expect(settingsService.lastDreamingAt?.toUtc(), remoteCoveredNewer);

      // 3. 对端看全（count=2），但时间比本机旧（11-11 < 11-12） -> 不回退本机时间
      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': '2026-11-11T08:00:00.000Z',
            'basis_watermark': '2026-11-10T09:00:00.000Z',
            'basis_note_count': 2,
          },
        },
      });
      expect(settingsService.lastDreamingAt?.toUtc(), remoteCoveredNewer);
    });

    test('批量水位查询消除 N+1：多条不同水位 Dreaming 画像与元数据合并仅查询 quotes 表一次', () async {
      await insertNote(
        id: 'batch_n1',
        content: '批量依据笔记1',
        lastModifiedIso: '2026-11-01T10:00:00.000Z',
      );
      await insertNote(
        id: 'batch_n2',
        content: '批量依据笔记2',
        lastModifiedIso: '2026-11-05T10:00:00.000Z',
      );
      await insertNote(
        id: 'batch_n3',
        content: '批量依据笔记3',
        lastModifiedIso: '2026-11-10T10:00:00.000Z',
      );

      databaseService.resetCounters();

      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'dreaming': <String, Object?>{
            'last_run_at': '2026-11-12T08:00:00.000Z',
            'basis_watermark': '2026-11-10T10:00:00.000Z',
            'basis_note_count': 3,
          },
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'prof_wm_early_uncovered',
              'kind': 'taste',
              'directive': '时间较新但漏看的品味（水位内实际 2 条 > 1）',
              'observed_at': '2026-11-12T08:00:00.000Z',
              'updated_at': '2026-11-12T08:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-05T10:00:00.000Z',
              'basis_note_count': 1,
            },
            <String, Object?>{
              'id': 'prof_wm_early_covered',
              'kind': 'taste',
              'directive': '看全全部 3 条笔记的品味（水位内实际 3 条 <= 3）',
              'observed_at': '2026-11-10T11:00:00.000Z',
              'updated_at': '2026-11-10T11:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T10:00:00.000Z',
              'basis_note_count': 3,
            },
            <String, Object?>{
              'id': 'prof_wm_voice_1',
              'kind': 'voice',
              'directive': '早期单条笔记文风（水位内实际 1 条 <= 1）',
              'observed_at': '2026-11-01T11:00:00.000Z',
              'updated_at': '2026-11-01T11:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-01T10:00:00.000Z',
              'basis_note_count': 1,
            },
            <String, Object?>{
              'id': 'prof_wm_voice_2',
              'kind': 'voice',
              'directive': '更新且看全 3 条笔记的文风',
              'observed_at': '2026-11-11T11:00:00.000Z',
              'updated_at': '2026-11-11T11:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T10:00:00.000Z',
              'basis_note_count': 3,
            },
          ],
        },
      });

      // 无论存在多少条不同水位的 Dreaming 条目，仅触发 1 次批量查询且单条查询次数为 0
      expect(databaseService.batchWatermarkCalls, 1);
      expect(databaseService.singleWatermarkCalls, 0);

      final active = await memoryService.activeProfile();
      final taste = active.singleWhere((e) => e.kind == AgentMemoryKind.taste);
      final voice = active.singleWhere((e) => e.kind == AgentMemoryKind.voice);
      expect(taste.id, 'prof_wm_early_covered');
      expect(voice.id, 'prof_wm_voice_2');
      expect(
        settingsService.lastDreamingAt?.toUtc().toIso8601String(),
        '2026-11-12T08:00:00.000Z',
      );
    });
  });

  group('回归防护：compactAndPrune 与 Dreaming 维护阶段不翻转看全收敛结果', () {
    test(
        '同步选出较早但看全的 P_full 并淘汰较新但漏看的 P_partial 后，独立或挂载同步服务的 compactAndPrune 及 AI 不可用时的 DreamingService.run 均保持 P_full 活跃、P_partial 已淘汰',
        () async {
      await insertNote(
        id: 'n_cov_1',
        content: '早期完整笔记1',
        lastModifiedIso: '2026-11-08T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_cov_2',
        content: '早期完整笔记2',
        lastModifiedIso: '2026-11-09T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_cov_3',
        content: '早期完整笔记3',
        lastModifiedIso: '2026-11-10T10:00:00.000Z',
      );

      final pFull = await memoryService.rememberProfile(
        kind: AgentMemoryKind.taste,
        directive: '基于完整笔记库归纳的品味画像',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 10, 10, 30),
        basisWatermark: '2026-11-10T10:00:00.000Z',
        basisNoteCount: 3,
      );

      await assistantSync.mergeSections(<String, dynamic>{
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'p_partial_newer',
              'kind': 'taste',
              'directive': '未同步完整时归纳的残缺品味画像',
              'observed_at': '2026-11-12T08:00:00.000Z',
              'updated_at': '2026-11-12T08:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-10T10:00:00.000Z',
              'basis_note_count': 2,
            },
          ],
        },
      });

      Future<void> verifyConvergedState() async {
        final active = (await memoryService.activeProfile())
            .where((e) => e.kind == AgentMemoryKind.taste)
            .toList();
        expect(active, hasLength(1));
        expect(active.single.id, pFull.id);

        final allEntries = await memoryService.allProfileEntries();
        final partial = allEntries.singleWhere(
          (e) => e.id == 'p_partial_newer',
        );
        expect(partial.status, AgentMemoryStatus.superseded);
        expect(partial.supersededBy, pFull.id);
      }

      await verifyConvergedState();

      // (a) 挂载 AssistantDataSyncService 时执行 compactAndPrune（30 天保留期内）
      await memoryService.compactAndPrune(
        now: DateTime.utc(2026, 11, 13, 0, 0),
      );
      await verifyConvergedState();

      // (b) 解绑同步判定器后独立调用 compactAndPrune（防御层 1：绝不把 superseded 重新纳入候选集复活）
      assistantSync.dispose();
      await memoryService.compactAndPrune(
        now: DateTime.utc(2026, 11, 13, 1, 0),
      );
      await verifyConvergedState();

      // 重新挂载同步服务后，(c) AI 不可用时运行 DreamingService.run()（内部触发 compactAndPrune）
      assistantSync.updateDependencies(
        chatSessionService: chatService,
        agentMemoryService: memoryService,
        settingsService: settingsService,
        databaseService: databaseService,
      );
      final dreaming = DreamingService(
        settingsService: settingsService,
        memoryService: memoryService,
        isAiAvailable: () async => false,
        loadNotes: ({required start, required end, required limit}) async =>
            const <Quote>[],
        complete: ({required systemPrompt, required userMessage}) async => '{}',
      );
      final outcome = await dreaming.run(now: DateTime.utc(2026, 11, 13, 2, 0));
      expect(outcome, DreamingOutcome.skipped);
      await verifyConvergedState();
    });

    test(
        '挂载 AssistantDataSyncService 后，直接调用 mergeMemorySection 或对多条活跃 Dreaming 画像执行 compactAndPrune 均自动按看全规则收敛',
        () async {
      await insertNote(
        id: 'n_mount_1',
        content: '笔记1',
        lastModifiedIso: '2026-11-08T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_mount_2',
        content: '笔记2',
        lastModifiedIso: '2026-11-09T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_mount_3',
        content: '笔记3',
        lastModifiedIso: '2026-11-10T10:00:00.000Z',
      );

      // 1. 直接调用 memoryService.mergeMemorySection（未显式传 checkBasisBatch），自动回退到挂载的判定器
      await memoryService.mergeMemorySection(<String, dynamic>{
        'format': 1,
        'profile': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'voice_early_covered',
            'kind': 'voice',
            'directive': '较早但看全 3 条笔记的表达风格',
            'observed_at': '2026-11-10T11:00:00.000Z',
            'updated_at': '2026-11-10T11:00:00.000Z',
            'status': 'active',
            'source': 'dreaming',
            'basis_watermark': '2026-11-10T10:00:00.000Z',
            'basis_note_count': 3,
          },
          <String, Object?>{
            'id': 'voice_late_uncovered',
            'kind': 'voice',
            'directive': '较新但仅看 1 条笔记的残缺表达风格',
            'observed_at': '2026-11-12T11:00:00.000Z',
            'updated_at': '2026-11-12T11:00:00.000Z',
            'status': 'active',
            'source': 'dreaming',
            'basis_watermark': '2026-11-10T10:00:00.000Z',
            'basis_note_count': 1,
          },
        ],
      });

      final activeVoice = (await memoryService.activeProfile())
          .singleWhere((e) => e.kind == AgentMemoryKind.voice);
      expect(activeVoice.id, 'voice_early_covered');

      // 2. 若库内同时存在两条 status='active' 的 Dreaming 同类画像，compactAndPrune 预评估依据后保留看全者
      final rawMemDb = await openDatabase(
        p.join(tempDir.path, 'agent_memory.db'),
        singleInstance: true,
      );
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'taste_active_covered',
          'kind': 'taste',
          'directive': '看全笔记的活跃品味',
          'observed_at': '2026-11-10T11:00:00.000Z',
          'updated_at': '2026-11-10T11:00:00.000Z',
          'status': 'active',
          'source': 'dreaming',
          'basis_watermark': '2026-11-10T10:00:00.000Z',
          'basis_note_count': 3,
        },
      );
      await rawMemDb.insert(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'id': 'taste_active_uncovered',
          'kind': 'taste',
          'directive': '更新但漏看的活跃品味',
          'observed_at': '2026-11-12T12:00:00.000Z',
          'updated_at': '2026-11-12T12:00:00.000Z',
          'status': 'active',
          'source': 'dreaming',
          'basis_watermark': '2026-11-10T10:00:00.000Z',
          'basis_note_count': 1,
        },
      );

      databaseService.resetCounters();
      final stats = await memoryService.compactAndPrune(
        now: DateTime.utc(2026, 11, 13, 0, 0),
      );
      expect(databaseService.batchWatermarkCalls, 1);
      expect(stats.duplicatesPruned, 1);

      final activeTaste = (await memoryService.activeProfile())
          .singleWhere((e) => e.kind == AgentMemoryKind.taste);
      expect(activeTaste.id, 'taste_active_covered');
    });

    test(
        'Devin 审查回归 #22：Stage 0 显式 replaces_id 链遇到非单例 Dreaming 画像（如 identity）时同样遵守看全依据优先，漏看新 Q(replaces_id: P) 绝不淘汰看全旧 P',
        () async {
      // 合并后的主库共有 4 条笔记：前 3 条 <= 10:00，第 4 条为离线设备在 10:30 补入的笔记（<= 11:30）
      await insertNote(
        id: 'n_cov_1',
        content: '早期笔记1',
        lastModifiedIso: '2026-11-10T08:00:00.000Z',
      );
      await insertNote(
        id: 'n_cov_2',
        content: '早期笔记2',
        lastModifiedIso: '2026-11-10T09:00:00.000Z',
      );
      await insertNote(
        id: 'n_cov_3',
        content: '早期笔记3',
        lastModifiedIso: '2026-11-10T10:00:00.000Z',
      );
      await insertNote(
        id: 'n_offline_1030',
        content: 'B 端 10:30 离线关键笔记（A 端 12:00 归纳时未同步到此条）',
        lastModifiedIso: '2026-11-10T10:30:00.000Z',
      );

      for (final mergeAFirst in <bool>[false, true]) {
        final dir = await Directory.systemTemp.createTemp('stage0_basis_');
        final devA = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'a.db'),
        );
        final devB = AgentMemoryService(
          settingsService: settingsService,
          databasePath: p.join(dir.path, 'b.db'),
        );
        devA.setBasisChecker((basisPairs) async {
          final watermarks = basisPairs.map((e) => e.$1).toSet();
          final counts =
              await databaseService.countActiveNotesUpToWatermarks(watermarks);
          return <(String, int), bool>{
            for (final pair in basisPairs)
              pair: (counts[pair.$1] ?? 0) <= pair.$2,
          };
        });
        devB.setBasisChecker((basisPairs) async {
          final watermarks = basisPairs.map((e) => e.$1).toSet();
          final counts =
              await databaseService.countActiveNotesUpToWatermarks(watermarks);
          return <(String, int), bool>{
            for (final pair in basisPairs)
              pair: (counts[pair.$1] ?? 0) <= pair.$2,
          };
        });

        try {
          // B 端持有较早但看全当时全部 3 条笔记（<=10:00 共 3 条）的非单例 Dreaming identity 画像 P
          final coveredP = await devB.rememberProfile(
            kind: AgentMemoryKind.identity,
            directive: '称呼用户为「林澈」',
            source: 'dreaming',
            observedAt: DateTime.utc(2026, 11, 10, 10, 5),
            basisWatermark: '2026-11-10T10:00:00.000Z',
            basisNoteCount: 3,
          );

          // A 端在未同步到 n_offline_1030 时于 12:00 运行了新一轮归纳，产生了声明 replaces_id = P.id 的漏看 Q
          // （水位 11:30 下主库实际有 4 条笔记，而 Q 的 basis_note_count 仅为 3），且 A 已裁剪掉历史 P
          await devA.restoreMemorySection(<String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'uncovered_q_id',
                'kind': 'identity',
                'directive': '待确认笔名：木子（存疑，待确认）',
                'observed_at': '2026-11-10T12:00:00.000000Z',
                'updated_at': '2026-11-10T12:00:00.000000Z',
                'status': 'active',
                'replaces_id': coveredP.id,
                'source': 'dreaming',
                'basis_watermark': '2026-11-10T11:30:00.000Z',
                'basis_note_count': 3,
              },
            ],
          });

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

          expect(
            (await devA.activeProfile()).map((e) => e.id).toList(),
            <String>[coveredP.id],
          );
          expect(
            (await devB.activeProfile()).map((e) => e.id).toList(),
            <String>[coveredP.id],
          );
        } finally {
          devA.dispose();
          devB.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      }
    });
  });
}

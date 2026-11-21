import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/assistant_data_sync_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';

import '../../test_harness.dart';

class _NoopAIAnalysisDbService extends Fake
    implements AIAnalysisDatabaseService {
  int deleteAllCalls = 0;
  int importCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> exportAnalysesPage(
    int offset,
    int limit,
  ) async =>
      <Map<String, dynamic>>[];

  @override
  Future<bool> deleteAllAnalyses() async {
    deleteAllCalls++;
    return true;
  }

  @override
  Future<int> importAnalysesFromList(List<dynamic> analyses) async {
    importCalls++;
    return analyses.length;
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {
  _LoopbackHttpOverrides(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _LoopbackHttpClient(super.createHttpClient(context), port);
}

class _LoopbackHttpClient implements HttpClient {
  _LoopbackHttpClient(this.delegate, this.port);
  final HttpClient delegate;
  final int port;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.host != 'webdav.example.invalid' || url.scheme != 'https') {
      throw StateError('Unexpected test URL: $url');
    }
    return delegate.openUrl(
      method,
      url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;
  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');

  late Directory tempDir;
  late Database rawNotesDb;
  late DatabaseService databaseService;
  late SettingsService settingsService;
  late ChatSessionService chatService;
  late AgentMemoryService memoryService;
  late AssistantDataSyncService assistantSync;
  late BackupService backupService;

  setUpAll(() async {
    await TestHarness.initialize();
    await AppPreferencesService().init();
  });

  tearDownAll(TestHarness.tearDown);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('assistant_sync_int_test_');
    await AppPreferencesService().clear();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settingsService = SettingsService(await SharedPreferences.getInstance());
    await settingsService.setAgentMemoryEnabled(true);
    await settingsService.setRequireBiometricForHidden(false);

    rawNotesDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchemaManager().createTables(rawNotesDb);
    DatabaseService.setTestDatabase(rawNotesDb);
    databaseService = DatabaseService();
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

    backupService = BackupService(
      databaseService: databaseService,
      settingsService: settingsService,
      aiAnalysisDbService: _NoopAIAnalysisDbService(),
      assistantDataSyncService: assistantSync,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      connectivityChannel,
      (_) async => <String>['mobile'],
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
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

  group('BackupService 导出、LWW 合并、覆盖恢复与旧备份兼容', () {
    test('备份导出（JSON 与 ZIP）包含 chat 与开启时的 agent_memory，记忆关闭时省略 agent_memory',
        () async {
      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'q_export_1',
        'content': '导出测试笔记',
        'date': '2026-11-10T10:00:00.000Z',
        'last_modified': '2026-11-10T10:00:00.000Z',
        'is_deleted': 0,
      });
      final session = await chatService.createSession(
        sessionType: 'agent',
        title: '导出测试会话',
      );
      await chatService.addMessage(
        session.id,
        ChatMessage(
          id: 'm_export_1',
          content: '导出测试提问',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 10, 10, 5),
        ),
      );
      await memoryService.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '导出测试记忆偏好',
      );
      await memoryService.addFact(content: '导出测试事实条目');

      // 1. 记忆开启时导出 JSON
      final jsonPath = p.join(tempDir.path, 'backup_open.json');
      await backupService.exportAllData(
        includeMediaFiles: false,
        customPath: jsonPath,
      );
      final exportedOpen = jsonDecode(await File(jsonPath).readAsString())
          as Map<String, dynamic>;
      expect(exportedOpen['chat'], isA<Map>());
      expect((exportedOpen['chat']['sessions'] as List), hasLength(1));
      expect((exportedOpen['chat']['messages'] as List), hasLength(1));
      expect(exportedOpen['agent_memory'], isA<Map>());
      expect((exportedOpen['agent_memory']['profile'] as List), hasLength(1));
      expect((exportedOpen['agent_memory']['facts'] as List), hasLength(1));

      // 2. 记忆开启时导出 ZIP，验证压缩包内 backup_data.json 同样包含两段
      final zipPath = p.join(tempDir.path, 'backup_open.zip');
      await backupService.exportAllData(
        includeMediaFiles: true,
        customPath: zipPath,
      );
      final inputStream = InputFileStream(zipPath);
      try {
        final archive = ZipDecoder().decodeStream(inputStream);
        final entry = archive.findFile('backup_data.json');
        expect(entry, isNotNull);
        final zipJson =
            jsonDecode(utf8.decode(entry!.content)) as Map<String, dynamic>;
        expect(zipJson['chat'], isA<Map>());
        expect(zipJson['agent_memory'], isA<Map>());
      } finally {
        inputStream.closeSync();
      }

      // 3. 关闭记忆开关后导出：仍含 chat，但不含 agent_memory
      await settingsService.setAgentMemoryEnabled(false);
      final closedPath = p.join(tempDir.path, 'backup_closed.json');
      await backupService.exportAllData(
        includeMediaFiles: false,
        customPath: closedPath,
      );
      final exportedClosed = jsonDecode(await File(closedPath).readAsString())
          as Map<String, dynamic>;
      expect(exportedClosed.containsKey('chat'), isTrue);
      expect(exportedClosed.containsKey('agent_memory'), isFalse);
    });

    test(
        'importDataWithLWWMerge（手动合并 & LocalSend 通道）：按笔记→对话→记忆顺序合并，产出 MergeReport.assistantStats，且绝不覆盖偏好设置',
        () async {
      // 先构造一份不同于本机的完整 settings 备份字典，用于验证 LWW 合并绝不应用它
      await settingsService.setDefaultAuthor('远端备份里的不同默认作者');
      await AppPreferencesService().setString('theme_style', 'plain');
      final remoteDiffSettings = settingsService.getAllSettingsForBackup();

      // 还原回本机预设偏好（默认作者与纸墨主题风格）+ 一条 Dreaming 漏看的本地 taste（当时本机只有 1 条笔记）
      await settingsService.setDefaultAuthor('本地保留作者');
      await AppPreferencesService().setString('theme_style', 'paper');

      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'note_local_1',
        'content': '本机已有早期笔记',
        'date': '2026-11-01T10:00:00.000Z',
        'last_modified': '2026-11-01T10:00:00.000Z',
        'is_deleted': 0,
      });
      await memoryService.rememberProfile(
        kind: AgentMemoryKind.taste,
        directive: '远端较新但漏看的品味（仅看到1条笔记）',
        source: 'dreaming',
        observedAt: DateTime.utc(2026, 11, 12, 10, 0),
        basisWatermark: '2026-11-05T10:00:00.000Z',
        basisNoteCount: 1,
      );

      // 构造备份包：包含第 2 条早期笔记 note_remote_2（合并笔记后总活跃数变为 2），
      // 同时包含一条 basis_note_count=2 的 Dreaming taste（只有在笔记先合并提交后，才会被准确判为“看全”并战胜上面时间更新的漏看条目！），
      // 且包含与本机不同的 settings（验证合并路径绝不应用 settings）。
      final incomingBackup = <String, dynamic>{
        'version': '2.0.0',
        'createdAt': '2026-11-12T12:00:00.000Z',
        'notes': <String, dynamic>{
          'categories': <Object?>[],
          'quotes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'note_remote_2',
              'content': '备份包带来的第二条早期笔记',
              'date': '2026-11-04T10:00:00.000Z',
              'last_modified': '2026-11-04T10:00:00.000Z',
              'is_deleted': 0,
            },
          ],
          'tombstones': <Object?>[],
        },
        'settings': remoteDiffSettings,
        'chat': <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'sync_s1',
              'session_type': 'agent',
              'title': '同步进来的对话',
              'created_at': '2026-11-10T09:00:00.000Z',
              'last_active_at': '2026-11-10T09:05:00.000Z',
              'updated_at': '2026-11-10T09:05:00.000Z',
              'is_pinned': 0,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'sync_m1',
              'session_id': 'sync_s1',
              'role': 'user',
              'content': '同步进来的首条消息',
              'created_at': '2026-11-10T09:05:00.000Z',
              'updated_at': '2026-11-10T09:05:00.000Z',
            },
          ],
          'tombstones': <Object?>[],
        },
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_covered_taste',
              'kind': 'taste',
              'directive': '基于完整 2 条笔记归纳出的品味',
              'observed_at': '2026-11-06T10:00:00.000Z',
              'updated_at': '2026-11-06T10:00:00.000Z',
              'status': 'active',
              'source': 'dreaming',
              'basis_watermark': '2026-11-05T10:00:00.000Z',
              'basis_note_count': 2,
            },
          ],
          'facts': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'sync_fact_1',
              'content': '同步进来的长期事实',
              'importance': 7,
              'created_at': '2026-11-10T09:00:00.000Z',
              'updated_at': '2026-11-10T09:00:00.000Z',
            },
          ],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        },
      };

      final mergeFile = File(p.join(tempDir.path, 'incoming_lww.json'));
      await mergeFile.writeAsString(jsonEncode(incomingBackup));

      final report = await backupService.importDataWithLWWMerge(mergeFile.path);

      // 1. 笔记、对话、记忆均已合并，且统计写入 MergeReport.assistantStats
      expect(report.insertedQuotes, 1);
      expect(report.assistantStats, isNotNull);
      expect(report.assistantStats!.sessionsAdded, 1);
      expect(report.assistantStats!.messagesAdded, 1);
      expect(report.assistantStats!.profilesAdded, 1);
      expect(report.assistantStats!.factsAdded, 1);
      expect(report.summary, contains('对话(新增 1 个会话/新增 1 条消息)'));
      expect(report.summary, contains('长期记忆(新增 2)'));
      expect(report.toJson()['assistantStats'], isA<Map>());

      // 2. 验证固定顺序：记忆合并时已能看到刚合入的 note_remote_2，因此 remote_covered_taste 被判“看全”并胜出
      final activeTastes = (await memoryService.activeProfile())
          .where((e) => e.kind == AgentMemoryKind.taste)
          .toList();
      expect(activeTastes.single.id, 'remote_covered_taste');
      expect(await chatService.getMessages('sync_s1'), hasLength(1));

      // 3. 偏好设置绝不被 LWW 合并覆盖
      expect(settingsService.defaultAuthor, '本地保留作者');
      expect(AppPreferencesService().getString('theme_style'), 'paper');

      // 4. 幂等再次合并同一文件：助手数据无新增改动，已有笔记计数跳过；空笔记段再次合并返回 '无变更'
      final idempotentReport =
          await backupService.importDataWithLWWMerge(mergeFile.path);
      expect(idempotentReport.assistantStats!.hasChanges, isFalse);
      expect(idempotentReport.summary, '跳过 1 条笔记');

      final assistantOnlyFile =
          File(p.join(tempDir.path, 'incoming_assistant_only.json'));
      await assistantOnlyFile.writeAsString(
        jsonEncode(<String, dynamic>{
          ...incomingBackup,
          'notes': <String, dynamic>{
            'categories': <Object?>[],
            'quotes': <Object?>[],
            'tombstones': <Object?>[],
          },
        }),
      );
      final emptyIdempotentReport =
          await backupService.importDataWithLWWMerge(assistantOnlyFile.path);
      expect(emptyIdempotentReport.summary, '无变更');

      // 5. 关闭记忆开关合并时，报告明确标注跳过原因
      await settingsService.setAgentMemoryEnabled(false);
      final disabledReport =
          await backupService.importDataWithLWWMerge(mergeFile.path);
      expect(
        disabledReport.assistantStats!.memorySkippedBecauseDisabled,
        isTrue,
      );
      expect(disabledReport.summary, contains('长期记忆因开关关闭已跳过'));
    });

    test(
        '覆盖恢复（clearExisting: true）整库还原全部数据，且旧格式备份包（无 chat/agent_memory 键）不清空本地对话与记忆',
        () async {
      final localSession = await chatService.createSession(
        sessionType: 'agent',
        title: '本地原有会话',
      );
      await chatService.addMessage(
        localSession.id,
        ChatMessage(
          id: 'local_m1',
          content: '本地原有消息',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 1, 10, 0),
        ),
      );
      final localProf = await memoryService.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '本地原有记忆指令',
      );

      // 构造合法的设置备份载荷
      await settingsService.setDefaultAuthor('旧备份恢复的默认作者');
      final legacySettingsPayload = settingsService.getAllSettingsForBackup();
      await settingsService.setDefaultAuthor('完整备份恢复默认作者');
      await AppPreferencesService().setString('theme_style', 'plain');
      final fullSettingsPayload = settingsService.getAllSettingsForBackup();
      // 重置本机初始状态再测恢复
      await settingsService.setDefaultAuthor('恢复前的本机默认作者');
      await AppPreferencesService().setString('theme_style', 'paper');

      // 1. 旧格式备份包（没有 chat 与 agent_memory 顶层键）：既使 clearExisting=true 也不得清空本地对话与记忆
      final legacyBackup = <String, dynamic>{
        'version': '1.2.0',
        'notes': <String, dynamic>{
          'categories': <Object?>[],
          'quotes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'legacy_q1',
              'content': '旧版备份里的笔记',
              'date': '2026-10-01T10:00:00.000Z',
              'last_modified': '2026-10-01T10:00:00.000Z',
              'is_deleted': 0,
            },
          ],
        },
        'settings': legacySettingsPayload,
      };
      final legacyFile = File(p.join(tempDir.path, 'legacy_backup.json'));
      await legacyFile.writeAsString(jsonEncode(legacyBackup));

      await backupService.importData(
        legacyFile.path,
        clearExisting: true,
        merge: false,
      );
      expect(settingsService.defaultAuthor, '旧备份恢复的默认作者');
      expect(await chatService.getMessages(localSession.id), hasLength(1));
      expect(
        (await memoryService.activeProfile()).map((e) => e.id).toList(),
        <String>[localProf.id],
      );

      // 2. 新格式完整备份包覆盖恢复：彻底替换笔记、设置、对话与长期记忆
      final fullRestoreBackup = <String, dynamic>{
        'version': '2.0.0',
        'notes': <String, dynamic>{
          'categories': <Object?>[],
          'quotes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'restored_q1',
              'content': '覆盖还原的笔记',
              'date': '2026-11-15T10:00:00.000Z',
              'last_modified': '2026-11-15T10:00:00.000Z',
              'is_deleted': 0,
            },
          ],
        },
        'settings': fullSettingsPayload,
        'chat': <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'restored_chat_s1',
              'session_type': 'agent',
              'title': '覆盖恢复后的唯一会话',
              'created_at': '2026-11-15T10:00:00.000Z',
              'last_active_at': '2026-11-15T10:01:00.000Z',
              'updated_at': '2026-11-15T10:01:00.000Z',
              'is_pinned': 1,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'restored_chat_m1',
              'session_id': 'restored_chat_s1',
              'role': 'user',
              'content': '覆盖恢复后的消息',
              'created_at': '2026-11-15T10:01:00.000Z',
              'updated_at': '2026-11-15T10:01:00.000Z',
            },
          ],
          'tombstones': <Object?>[],
        },
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'restored_mem_p1',
              'kind': 'style',
              'directive': '覆盖恢复后的唯一风格指令',
              'observed_at': '2026-11-15T10:00:00.000Z',
              'updated_at': '2026-11-15T10:00:00.000Z',
              'status': 'active',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        },
      };
      final fullFile = File(p.join(tempDir.path, 'full_restore.json'));
      await fullFile.writeAsString(jsonEncode(fullRestoreBackup));

      await backupService.importData(
        fullFile.path,
        clearExisting: true,
        merge: false,
      );

      expect(settingsService.defaultAuthor, '完整备份恢复默认作者');
      expect(AppPreferencesService().getString('theme_style'), 'plain');
      expect(await chatService.getMessages(localSession.id), isEmpty);
      expect(await chatService.getMessages('restored_chat_s1'), hasLength(1));
      final restoredProfiles = await memoryService.activeProfile();
      expect(
        restoredProfiles.map((e) => e.id).toList(),
        <String>['restored_mem_p1'],
      );
    });
  });

  group('SettingsService + AppTheme theme_style 覆盖恢复闭环', () {
    test('备份导出 theme_style 并覆盖恢复后调用 AppTheme.reloadFromStorage() 立即刷新内存态主题',
        () async {
      final storage = AppPreferencesService();
      await storage.setString('theme_style', 'plain');
      await settingsService.updateThemeMode(ThemeMode.dark);
      await storage.setString('theme_accent_plain', 'celadon');
      await storage.setBool('use_custom_color', true);
      await storage.setInt('custom_color', 0xFF336699);

      final exportedSettings = settingsService.getAllSettingsForBackup();
      expect(exportedSettings['theme_style'], 'plain');
      expect(exportedSettings['theme_mode'], ThemeMode.dark.index);

      // 模拟另一台处于初始默认风格 + 跟随系统模式的设备
      await storage.clear();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final targetSettings = SettingsService(
        await SharedPreferences.getInstance(),
      );
      await storage.setString('theme_style', 'paper');
      final appTheme = AppTheme();
      addTearDown(appTheme.dispose);
      await appTheme.initialize();
      expect(appTheme.themeStyle, ThemeStyle.paper);
      expect(appTheme.themeMode, ThemeMode.system);

      var notified = 0;
      appTheme.addListener(() => notified++);

      // 1) 执行覆盖恢复设置 + reloadFromStorage()
      await targetSettings.restoreAllSettingsFromBackup(exportedSettings);
      await appTheme.reloadFromStorage();

      expect(appTheme.themeStyle, ThemeStyle.plain);
      expect(appTheme.themeMode, ThemeMode.dark);
      expect(appTheme.useCustomColor, isTrue);
      expect(appTheme.customColor!.toARGB32(), 0xFF336699);
      expect(notified, greaterThanOrEqualTo(1));

      // 2) 直接修改底层存储后单独调用 reloadFromStorage()，验证不依赖 currentInstance 也即时生效并通知监听者
      final beforeDirectReload = notified;
      await storage.setString('theme_style', 'material');
      await storage.setString('theme_mode', ThemeMode.light.name);
      await appTheme.reloadFromStorage();
      expect(appTheme.themeStyle, ThemeStyle.material);
      expect(appTheme.themeMode, ThemeMode.light);
      expect(notified, greaterThan(beforeDirectReload));
    });
  });

  group('WebDAVSyncService 端到端接线与合并异常中止保护', () {
    test('拉取云端包合并笔记+对话+记忆，并向云端上传包含 chat 与 agent_memory 的新快照', () async {
      final appPrefs = AppPreferencesService();
      await appPrefs.setString(
        'webdav_last_sync_time',
        '2026-11-01T00:00:00.000Z',
      );
      await settingsService.setUserNickname('WebDAV本地称呼不外泄');

      // 本地预置一条笔记、一条会话、一条记忆事实
      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'local_q1',
        'content': '本机笔记内容',
        'date': '2026-11-10T08:00:00.000Z',
        'last_modified': '2026-11-10T08:00:00.000Z',
        'is_deleted': 0,
      });
      final localSession = await chatService.createSession(
        sessionType: 'agent',
        title: '本机聊天会话',
      );
      await chatService.addMessage(
        localSession.id,
        ChatMessage(
          id: 'local_chat_m1',
          content: '本机消息正文',
          isUser: true,
          role: 'user',
          timestamp: DateTime.utc(2026, 11, 10, 8, 5),
        ),
      );
      final localFact = await memoryService.addFact(content: '本机创建的事实条目');

      // 云端预置另一条笔记、另一条会话、另一条画像条目
      final remotePayload = <String, dynamic>{
        'categories': <Object?>[],
        'quotes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'remote_q2',
            'content': '云端同步下来的笔记',
            'date': '2026-11-11T09:00:00.000Z',
            'last_modified': '2026-11-11T09:00:00.000Z',
            'is_deleted': 0,
          },
        ],
        'tombstones': <Object?>[],
        'chat': <String, dynamic>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_chat_s2',
              'session_type': 'agent',
              'title': '云端同步会话',
              'created_at': '2026-11-11T09:00:00.000Z',
              'last_active_at': '2026-11-11T09:10:00.000Z',
              'updated_at': '2026-11-11T09:10:00.000Z',
              'is_pinned': 0,
            },
          ],
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_chat_m2',
              'session_id': 'remote_chat_s2',
              'role': 'assistant',
              'content': '云端同步回复',
              'created_at': '2026-11-11T09:10:00.000Z',
              'updated_at': '2026-11-11T09:10:00.000Z',
            },
          ],
          'tombstones': <Object?>[],
        },
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'remote_mem_p2',
              'kind': 'preference',
              'directive': '云端同步偏好指令',
              'observed_at': '2026-11-11T09:00:00.000Z',
              'updated_at': '2026-11-11T09:00:00.000Z',
              'status': 'active',
            },
          ],
          'facts': <Object?>[],
          'recent_slices': <Object?>[],
          'tombstones': <Object?>[],
        },
      };

      final remoteJsonBytes = utf8.encode(jsonEncode(remotePayload));
      final remoteZip = ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile(
              'backup_data.json',
              remoteJsonBytes.length,
              remoteJsonBytes,
            ),
          ),
      );

      List<int>? uploadedZip;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final response = request.response;
        if (request.uri.path.endsWith('thoughtecho_sync.zip')) {
          switch (request.method) {
            case 'PROPFIND':
              response.statusCode = 207;
              response.write('''
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
<d:propstat><d:prop><d:getetag>"rev-ok-1"</d:getetag>
<d:getcontentlength>${remoteZip.length}</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''');
            case 'GET':
              response.add(remoteZip);
            case 'PUT':
              uploadedZip = body;
              response.statusCode = 204;
            default:
              response.statusCode = 405;
          }
        } else {
          response.statusCode = 207;
        }
        await response.close();
      });

      final webdav = WebDAVSyncService.forTesting();
      addTearDown(webdav.dispose);
      webdav.attachAssistantDataSync(assistantSync);
      await webdav.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://webdav.example.invalid/dav/',
        username: 'test-user',
        password: 'synthetic-password',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: true,
      );

      await HttpOverrides.runWithHttpOverrides(
        () => webdav.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );

      expect(
        webdav.syncStatus,
        WebDAVSyncStatus.success,
        reason: webdav.lastSyncError,
      );
      expect(
        appPrefs.getString('webdav_last_sync_time'),
        isNot('2026-11-01T00:00:00.000Z'),
      );

      // 本地已合入云端的笔记、对话与记忆
      final localQuotes = await rawNotesDb.query('quotes');
      expect(
        localQuotes.map((q) => q['id']).toSet(),
        equals(<String>{'local_q1', 'remote_q2'}),
      );
      expect(await chatService.getMessages('remote_chat_s2'), hasLength(1));
      expect(
        (await memoryService.activeProfile()).map((p) => p.id).toList(),
        <String>['remote_mem_p2'],
      );

      // 上传的云端新快照同时包含本机与云端合并后的 quotes、chat、agent_memory，且绝不含 settings
      expect(uploadedZip, isNotNull);
      final uploadedPayload =
          WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
        uploadedZip!,
      );
      expect((uploadedPayload['quotes'] as List), hasLength(2));
      expect(uploadedPayload.containsKey('settings'), isFalse);

      final uploadedChat = uploadedPayload['chat'] as Map<String, dynamic>;
      expect(
        (uploadedChat['sessions'] as List).map((s) => (s as Map)['id']).toSet(),
        equals(<String>{localSession.id, 'remote_chat_s2'}),
      );

      final uploadedMemory =
          uploadedPayload['agent_memory'] as Map<String, dynamic>;
      expect((uploadedMemory['profile'] as List), hasLength(1));
      expect(
        (uploadedMemory['facts'] as List).single['id'],
        localFact.id,
      );
    });

    test('当对话或记忆段合并失败时：中止上传（PUT=0）、不推进同步水位，且错误信息严格脱敏', () async {
      final appPrefs = AppPreferencesService();
      const initialWatermark = '2026-11-01T00:00:00.000Z';
      await appPrefs.setString('webdav_last_sync_time', initialWatermark);

      // 云端包中 quotes 合法，但 chat.sessions 为非法结构，且带有敏感正文标记词用于验证脱敏
      const secretMarker = 'SENSITIVE_CHAT_CONTENT_DO_NOT_LEAK_9876';
      final brokenRemotePayload = <String, dynamic>{
        'categories': <Object?>[],
        'quotes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'remote_note_ok',
            'content': '合法云端笔记正文',
            'date': '2026-11-12T08:00:00.000Z',
            'last_modified': '2026-11-12T08:00:00.000Z',
            'is_deleted': 0,
          },
        ],
        'chat': <String, dynamic>{
          'format': 1,
          'sessions': 'corrupted_sessions_payload_$secretMarker',
        },
      };

      final remoteJsonBytes = utf8.encode(jsonEncode(brokenRemotePayload));
      final remoteZip = ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile(
              'backup_data.json',
              remoteJsonBytes.length,
              remoteJsonBytes,
            ),
          ),
      );

      var putCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        final response = request.response;
        if (request.uri.path.endsWith('thoughtecho_sync.zip')) {
          switch (request.method) {
            case 'PROPFIND':
              response.statusCode = 207;
              response.write('''
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
<d:propstat><d:prop><d:getetag>"rev-err-1"</d:getetag>
<d:getcontentlength>${remoteZip.length}</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''');
            case 'GET':
              response.add(remoteZip);
            case 'PUT':
              putCount++;
              response.statusCode = 204;
            default:
              response.statusCode = 405;
          }
        } else {
          response.statusCode = 207;
        }
        await response.close();
      });

      final webdav = WebDAVSyncService.forTesting();
      addTearDown(webdav.dispose);
      webdav.attachAssistantDataSync(assistantSync);
      await webdav.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://webdav.example.invalid/dav/',
        username: 'test-user',
        password: 'synthetic-password',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: true,
      );

      await HttpOverrides.runWithHttpOverrides(
        () => webdav.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );

      // 1. 同步状态为 failed，绝未发生任何 PUT 上传（保护云端快照不被覆盖），且同步水位未推进
      expect(webdav.syncStatus, WebDAVSyncStatus.failed);
      expect(putCount, 0);
      expect(appPrefs.getString('webdav_last_sync_time'), initialWatermark);
      expect(webdav.lastSyncTime, initialWatermark);

      // 2. Step 4a 已提交的合法笔记保留在本地，不丢失
      final notes = await rawNotesDb.query('quotes');
      expect(notes.map((n) => n['id']).toList(), <String>['remote_note_ok']);

      // 3. 错误提示严格脱敏，绝不出现对话内容
      expect(webdav.lastSyncError, isNotNull);
      expect(webdav.lastSyncError, isNot(contains(secretMarker)));
    });

    test(
        '问题2：WebDAV 三设备链路（A 开启记忆上传 -> B 关闭记忆同步新笔记上传 -> C 开启记忆拉取），B 既不泄露本机休眠记忆也不抹掉云端 A 的记忆与墓碑',
        () async {
      List<int>? cloudZipBytes;
      var etagCounter = 1;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final response = request.response;
        if (request.uri.path.endsWith('thoughtecho_sync.zip')) {
          switch (request.method) {
            case 'PROPFIND':
              if (cloudZipBytes == null) {
                response.statusCode = 404;
              } else {
                response.statusCode = 207;
                response.write('''
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
<d:propstat><d:prop><d:getetag>"rev-chain-$etagCounter"</d:getetag>
<d:getcontentlength>${cloudZipBytes!.length}</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''');
              }
            case 'GET':
              if (cloudZipBytes == null) {
                response.statusCode = 404;
              } else {
                response.add(cloudZipBytes!);
              }
            case 'PUT':
              cloudZipBytes = body;
              etagCounter++;
              response.statusCode = 204;
            default:
              response.statusCode = 405;
          }
        } else {
          response.statusCode = 207;
        }
        await response.close();
      });

      Future<void> resetLocalNotesForDevice() async {
        await rawNotesDb.delete('quote_tags');
        await rawNotesDb.delete('quotes');
        await rawNotesDb.delete('quote_tombstones');
      }

      Future<void> runWebDavStep({
        required bool memoryEnabled,
        required String stepTag,
        required Future<void> Function(
          ChatSessionService chat,
          AgentMemoryService mem,
          SettingsService settings,
        ) prepare,
        required Future<void> Function(
          ChatSessionService chat,
          AgentMemoryService mem,
        ) verify,
      }) async {
        final stepDir =
            await Directory.systemTemp.createTemp('webdav_step_${stepTag}_');
        await AppPreferencesService().clear();
        SharedPreferences.resetStatic();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final stepSettings =
            SettingsService(await SharedPreferences.getInstance());
        await stepSettings.setRequireBiometricForHidden(false);

        final stepChat = ChatSessionService(
          databasePath: p.join(stepDir.path, 'chat.db'),
        );
        await stepChat.init();
        final stepMem = AgentMemoryService(
          settingsService: stepSettings,
          databasePath: p.join(stepDir.path, 'agent_memory.db'),
        );
        final stepAssistant = AssistantDataSyncService(
          chatSessionService: stepChat,
          agentMemoryService: stepMem,
          settingsService: stepSettings,
          databaseService: databaseService,
        );

        final webdav = WebDAVSyncService.forTesting();
        try {
          await prepare(stepChat, stepMem, stepSettings);
          await stepSettings.setAgentMemoryEnabled(memoryEnabled);

          webdav.attachAssistantDataSync(stepAssistant);
          await webdav.saveSettings(
            enabled: true,
            provider: 'custom',
            url: 'https://webdav.example.invalid/dav/',
            username: 'test-user',
            password: 'synthetic-password',
            syncOnLaunch: false,
            syncOnChange: false,
            syncOnCellular: false,
            syncNotesOnlyOnCellular: true,
          );

          await HttpOverrides.runWithHttpOverrides(
            () => webdav.triggerSync(),
            _LoopbackHttpOverrides(server.port),
          );
          expect(
            webdav.syncStatus,
            WebDAVSyncStatus.success,
            reason: webdav.lastSyncError,
          );
          await verify(stepChat, stepMem);
        } finally {
          webdav.dispose();
          await stepChat.close();
          stepChat.dispose();
          stepMem.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (await stepDir.exists()) {
            await stepDir.delete(recursive: true);
          }
        }
      }

      await resetLocalNotesForDevice();
      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'note_from_a',
        'content': '设备 A 创建的笔记',
        'date': '2026-11-15T08:00:00.000Z',
        'last_modified': '2026-11-15T08:00:00.000Z',
        'is_deleted': 0,
      });

      late String profKeepId;
      late String profDeletedId;
      late String factFromAId;

      // Step 1：设备 A（开启记忆）创建画像、事实与删除墓碑并上传到 WebDAV
      await runWebDavStep(
        memoryEnabled: true,
        stepTag: 'A',
        prepare: (chat, mem, settings) async {
          await settings.setAgentMemoryEnabled(true);
          final keep = await mem.rememberProfile(
            kind: AgentMemoryKind.preference,
            directive: '设备 A 上传的云端共享画像',
            observedAt: DateTime.utc(2026, 11, 15, 8, 0),
          );
          final toForget = await mem.rememberProfile(
            kind: AgentMemoryKind.feedback,
            directive: '设备 A 已删除并写墓碑的画像',
            observedAt: DateTime.utc(2026, 11, 15, 8, 5),
          );
          await mem.forgetProfile(toForget.id);
          final fact = await mem.addFact(content: '设备 A 上传的长期事实');
          profKeepId = keep.id;
          profDeletedId = toForget.id;
          factFromAId = fact.id;
        },
        verify: (_, __) async {
          expect(cloudZipBytes, isNotNull);
        },
      );

      // Step 2：设备 B（本地曾有私密休眠记忆，但当前关闭记忆开关）新增笔记并执行 WebDAV 同步
      await resetLocalNotesForDevice();
      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'note_from_b',
        'content': '设备 B 关闭记忆时新增的笔记',
        'date': '2026-11-16T09:00:00.000Z',
        'last_modified': '2026-11-16T09:00:00.000Z',
        'is_deleted': 0,
      });

      await runWebDavStep(
        memoryEnabled: false,
        stepTag: 'B',
        prepare: (chat, mem, settings) async {
          // 先在 B 本机写入一条休眠记忆，随后在 runWebDavStep 中关闭记忆开关：验证绝不泄露到云端！
          await settings.setAgentMemoryEnabled(true);
          await mem.rememberProfile(
            kind: AgentMemoryKind.identity,
            directive: '设备 B 本机休眠记忆绝不可上传泄露',
          );
        },
        verify: (_, __) async {
          final bQuotes = await rawNotesDb.query('quotes');
          expect(
            bQuotes.map((q) => q['id']).toSet(),
            equals(<String>{'note_from_a', 'note_from_b'}),
          );
        },
      );

      // Step 3：设备 C（开启记忆，且预置那条被 A 删掉的旧画像）从 WebDAV 同步
      await resetLocalNotesForDevice();

      await runWebDavStep(
        memoryEnabled: true,
        stepTag: 'C',
        prepare: (chat, mem, settings) async {
          await settings.setAgentMemoryEnabled(true);
          await mem.mergeMemorySection(<String, dynamic>{
            'format': 1,
            'profile': <Map<String, Object?>>[
              <String, Object?>{
                'id': profDeletedId,
                'kind': 'feedback',
                'directive': '设备 A 已删除并写墓碑的画像',
                'observed_at': '2026-11-15T08:05:00.000Z',
                'updated_at': '2026-11-15T08:05:00.000Z',
                'status': 'active',
              },
            ],
          });
        },
        verify: (_, mem) async {
          // C 同时拿到了 A 与 B 的两条笔记
          final cQuotes = await rawNotesDb.query('quotes');
          expect(
            cQuotes.map((q) => q['id']).toSet(),
            equals(<String>{'note_from_a', 'note_from_b'}),
          );
          // C 完整拿到了 A 的保留画像与事实，A 的删除墓碑生效删掉了 profDeletedId，且绝无 B 的本机休眠记忆！
          final activeProfiles = await mem.activeProfile();
          expect(
            activeProfiles.map((p) => p.id).toList(),
            <String>[profKeepId],
          );
          expect(
            (await mem.allFacts()).map((f) => f.id).toList(),
            <String>[factFromAId],
          );
        },
      );
    });

    test(
        '问题3 & 二.2：WebDAV 拉取到 {"agent_memory": {"profile": {}}} 时中止同步且 PUT=0，BackupService 覆盖恢复自动重载活跃 AppTheme',
        () async {
      final appPrefs = AppPreferencesService();
      const initialWatermark = '2026-11-01T00:00:00.000Z';
      await appPrefs.setString('webdav_last_sync_time', initialWatermark);

      final malformedMemoryPayload = <String, dynamic>{
        'categories': <Object?>[],
        'quotes': <Object?>[],
        'agent_memory': <String, dynamic>{
          'format': 1,
          'profile': <String, Object?>{},
        },
      };
      final remoteBytes = utf8.encode(jsonEncode(malformedMemoryPayload));
      final remoteZip = ZipEncoder().encode(
        Archive()
          ..addFile(
            ArchiveFile('backup_data.json', remoteBytes.length, remoteBytes),
          ),
      );

      var putCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        final response = request.response;
        if (request.uri.path.endsWith('thoughtecho_sync.zip')) {
          switch (request.method) {
            case 'PROPFIND':
              response.statusCode = 207;
              response.write('''
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
<d:propstat><d:prop><d:getetag>"rev-bad-mem"</d:getetag>
<d:getcontentlength>${remoteZip.length}</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''');
            case 'GET':
              response.add(remoteZip);
            case 'PUT':
              putCount++;
              response.statusCode = 204;
            default:
              response.statusCode = 405;
          }
        } else {
          response.statusCode = 207;
        }
        await response.close();
      });

      final webdav = WebDAVSyncService.forTesting();
      addTearDown(webdav.dispose);
      webdav.attachAssistantDataSync(assistantSync);
      await webdav.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://webdav.example.invalid/dav/',
        username: 'test-user',
        password: 'synthetic-password',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: true,
      );

      await HttpOverrides.runWithHttpOverrides(
        () => webdav.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );
      expect(webdav.syncStatus, WebDAVSyncStatus.failed);
      expect(putCount, 0);
      expect(appPrefs.getString('webdav_last_sync_time'), initialWatermark);

      // 同时验证 BackupService 覆盖恢复自动联动 AppTheme.reloadCurrentInstance()
      await appPrefs.setString('theme_style', 'plain');
      final exportedPlainSettings = settingsService.getAllSettingsForBackup();
      await appPrefs.setString('theme_style', 'paper');
      final activeTheme = AppTheme();
      addTearDown(activeTheme.dispose);
      await activeTheme.initialize();
      expect(activeTheme.themeStyle, ThemeStyle.paper);

      final restoreJsonFile =
          File(p.join(tempDir.path, 'theme_auto_sync.json'));
      await restoreJsonFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': '2.0.0',
          'notes': <String, dynamic>{
            'categories': <Object?>[],
            'quotes': <Object?>[],
          },
          'settings': exportedPlainSettings,
        }),
      );
      await backupService.importData(
        restoreJsonFile.path,
        clearExisting: true,
        merge: false,
      );
      expect(activeTheme.themeStyle, ThemeStyle.plain);
    });

    test(
        'Devin 审查回归 #19：覆盖恢复（JSON 与带媒体 ZIP）遇到损坏的 chat 或 agent_memory 段时前置拒绝，本机原有笔记、偏好、媒体、会话与记忆毫发无损',
        () async {
      // 1. 预置本机原有笔记、偏好设置、对话会话与长期记忆
      await rawNotesDb.insert('quotes', <String, Object?>{
        'id': 'local_protected_note',
        'content': '本机受保护笔记正文',
        'date': '2026-11-20T08:00:00.000Z',
        'last_modified': '2026-11-20T08:00:00.000Z',
        'is_deleted': 0,
      });
      await settingsService.setUserNickname('受保护原昵称');
      final protectedSession = await chatService.createSession(
        sessionType: 'agent',
        title: '受保护本机会话',
      );
      await chatService.addMessage(
        protectedSession.id,
        ChatMessage(
          id: 'protected_msg_1',
          isUser: true,
          role: 'user',
          content: '受保护本机消息',
          timestamp: DateTime.utc(2026, 11, 20, 8, 5),
        ),
      );
      final protectedProfile = await memoryService.rememberProfile(
        kind: AgentMemoryKind.preference,
        directive: '受保护本机画像指令',
        observedAt: DateTime.utc(2026, 11, 20, 8, 10),
      );

      // 必须落在 BackupService 解压媒体的真实 getApplicationDocumentsDirectory()/media/images 下
      final appDocDir = await getApplicationDocumentsDirectory();
      final mediaRootDir = Directory(p.join(appDocDir.path, 'media'));
      addTearDown(() async {
        if (await mediaRootDir.exists()) {
          await mediaRootDir.delete(recursive: true);
        }
      });
      final mediaSubDir =
          await Directory(p.join(mediaRootDir.path, 'images')).create(
        recursive: true,
      );
      final existingMediaFile = File(p.join(mediaSubDir.path, 'keep.png'));
      final injectedMediaFile = File(
        p.join(mediaSubDir.path, 'injected_bad.png'),
      );
      await existingMediaFile.writeAsBytes(const <int>[1, 2, 3, 4]);
      if (await injectedMediaFile.exists()) {
        await injectedMediaFile.delete();
      }

      Future<void> verifyAllLocalStateIntact() async {
        final notes = await rawNotesDb.query('quotes');
        expect(
          notes.map((n) => n['id']).toList(),
          <String>['local_protected_note'],
        );
        expect(settingsService.userNickname, '受保护原昵称');
        final sessions = await chatService.getAllSessions();
        expect(sessions.map((s) => s.id).toList(), <String>[
          protectedSession.id,
        ]);
        final msgs = await chatService.getMessages(protectedSession.id);
        expect(msgs.map((m) => m.id).toList(), <String>['protected_msg_1']);
        final profiles = await memoryService.activeProfile();
        expect(profiles.map((e) => e.id).toList(), <String>[
          protectedProfile.id,
        ]);
      }

      // 构造前半段（notes / settings / chat）完全合法，但后半段 agent_memory 损坏的备份包
      Map<String, dynamic> buildBadPayload({required bool badChat}) {
        return <String, dynamic>{
          'version': '2.0.0',
          'notes': <String, dynamic>{
            'categories': <Object?>[],
            'quotes': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'incoming_wiper_note',
                'content': '不应落盘的覆盖笔记',
                'date': '2026-11-21T00:00:00.000Z',
                'last_modified': '2026-11-21T00:00:00.000Z',
                'is_deleted': 0,
              },
            ],
          },
          'settings': <String, Object?>{
            'user_nickname': '不应覆盖的新昵称',
          },
          'chat': badChat
              ? <String, Object?>{'format': 1, 'sessions': <String, Object?>{}}
              : <String, Object?>{
                  'format': 1,
                  'sessions': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'incoming_wiper_session',
                      'session_type': 'agent',
                      'title': '不应落盘的覆盖会话',
                      'created_at': '2026-11-21T00:00:00.000000Z',
                      'last_active_at': '2026-11-21T00:00:00.000000Z',
                      'updated_at': '2026-11-21T00:00:00.000000Z',
                    },
                  ],
                  'messages': <Object?>[],
                  'tombstones': <Object?>[],
                },
          'agent_memory': badChat
              ? <String, Object?>{'format': 1, 'profile': <Object?>[]}
              : <String, Object?>{'format': 1, 'profile': <String, Object?>{}},
        };
      }

      // 2. 验证 .json 覆盖恢复前置拒绝（损坏 agent_memory 与损坏 chat）
      for (final badChat in <bool>[false, true]) {
        final badJsonFile = File(
          p.join(tempDir.path, 'bad_restore_${badChat ? 'chat' : 'mem'}.json'),
        );
        await badJsonFile.writeAsString(
          jsonEncode(buildBadPayload(badChat: badChat)),
        );
        await expectLater(
          () => backupService.importData(
            badJsonFile.path,
            clearExisting: true,
            merge: false,
          ),
          throwsA(anything),
        );
        await verifyAllLocalStateIntact();
      }

      // 3. 验证带媒体条目的 .zip 覆盖恢复在媒体解压前即前置拒绝（既不覆盖同名旧文件，也不落盘新注入文件）
      for (final badChat in <bool>[false, true]) {
        final payloadBytes = utf8.encode(
          jsonEncode(buildBadPayload(badChat: badChat)),
        );
        const overwriteBytes = <int>[9, 9, 9, 9];
        const injectedBytes = <int>[8, 8, 8, 8];
        final archive = Archive()
          ..addFile(
            ArchiveFile('backup_data.json', payloadBytes.length, payloadBytes),
          )
          ..addFile(
            ArchiveFile(
              'media/images/keep.png',
              overwriteBytes.length,
              overwriteBytes,
            ),
          )
          ..addFile(
            ArchiveFile(
              'media/images/injected_bad.png',
              injectedBytes.length,
              injectedBytes,
            ),
          );
        final badZipFile = File(
          p.join(tempDir.path, 'bad_restore_${badChat ? 'chat' : 'mem'}.zip'),
        );
        await badZipFile.writeAsBytes(ZipEncoder().encode(archive));
        await expectLater(
          () => backupService.importData(
            badZipFile.path,
            clearExisting: true,
            merge: false,
          ),
          throwsA(anything),
        );
        await verifyAllLocalStateIntact();
        expect(await existingMediaFile.readAsBytes(), <int>[1, 2, 3, 4]);
        expect(await injectedMediaFile.exists(), isFalse);
      }

      // 4. 验证包含合法 chat.message_shards 描述符的云端主包（JSON 与带媒体 ZIP）在覆盖恢复预检阶段即被拦截，
      //    绝不提前清空笔记、AI 分析报告、偏好设置或解压覆盖媒体文件
      final trackingAiDb = _NoopAIAnalysisDbService();
      final trackedBackupService = BackupService(
        databaseService: databaseService,
        settingsService: settingsService,
        aiAnalysisDbService: trackingAiDb,
        assistantDataSyncService: assistantSync,
      );
      final shardedMainOnlyPayload = <String, dynamic>{
        'version': '2.0.0',
        'notes': <String, dynamic>{
          'categories': <Object?>[],
          'quotes': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'incoming_wiper_note_sharded',
              'content': '不应落盘的分片覆盖笔记',
              'date': '2026-11-21T00:00:00.000Z',
              'last_modified': '2026-11-21T00:00:00.000Z',
              'is_deleted': 0,
            },
          ],
        },
        'ai_analyses': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'incoming_wiper_analysis',
            'title': '不应导入的分析',
            'content': '不应导入的正文',
          },
        ],
        'settings': <String, Object?>{
          'user_nickname': '不应覆盖的分片昵称',
        },
        'chat': <String, Object?>{
          'format': 1,
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'incoming_sharded_session',
              'session_type': 'agent',
              'title': '缺少外部聊天分片的主包会话',
              'created_at': '2026-11-21T00:00:00.000000Z',
              'last_active_at': '2026-11-21T00:00:00.000000Z',
              'updated_at': '2026-11-21T00:00:00.000000Z',
            },
          ],
          'messages': <Object?>[],
          'message_shards': <Map<String, Object?>>[
            <String, Object?>{
              'file':
                  'shard_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.zip',
              'sha256':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          ],
          'tombstones': <Object?>[],
        },
        'agent_memory': <String, Object?>{'format': 1, 'profile': <Object?>[]},
      };

      final shardedJsonFile = File(
        p.join(tempDir.path, 'sharded_sync_main_only.json'),
      );
      await shardedJsonFile.writeAsString(jsonEncode(shardedMainOnlyPayload));
      await expectLater(
        () => trackedBackupService.importData(
          shardedJsonFile.path,
          clearExisting: true,
          merge: false,
        ),
        throwsA(anything),
      );
      await verifyAllLocalStateIntact();
      expect(trackingAiDb.deleteAllCalls, 0);
      expect(trackingAiDb.importCalls, 0);

      final shardedBytes = utf8.encode(jsonEncode(shardedMainOnlyPayload));
      const badMediaOverwrite = <int>[7, 7, 7, 7];
      final shardedArchive = Archive()
        ..addFile(
          ArchiveFile('backup_data.json', shardedBytes.length, shardedBytes),
        )
        ..addFile(
          ArchiveFile(
            'media/images/keep.png',
            badMediaOverwrite.length,
            badMediaOverwrite,
          ),
        );
      final shardedZipFile = File(
        p.join(tempDir.path, 'thoughtecho_sync_sharded_only.zip'),
      );
      await shardedZipFile.writeAsBytes(ZipEncoder().encode(shardedArchive));
      await expectLater(
        () => trackedBackupService.importData(
          shardedZipFile.path,
          clearExisting: true,
          merge: false,
        ),
        throwsA(anything),
      );
      await verifyAllLocalStateIntact();
      expect(trackingAiDb.deleteAllCalls, 0);
      expect(trackingAiDb.importCalls, 0);
      expect(await existingMediaFile.readAsBytes(), <int>[1, 2, 3, 4]);
    });
  });

  group('WebDAV 大体量对话历史自动分片同步（chat_shards）', () {
    test('同步 JSON 超过分片阈值时自动切分上传 chat_shards，对端拉取校验 SHA-256 流式合并全部消息并清理过期分片',
        () async {
      WebDAVSyncService.chatShardThresholdBytesForTesting = 900;
      WebDAVSyncService.maxChatShardJsonBytesForTesting = 700;
      addTearDown(() {
        WebDAVSyncService.chatShardThresholdBytesForTesting = null;
        WebDAVSyncService.maxChatShardJsonBytesForTesting = null;
      });

      // 设备 A 写入多条会话与消息，使完整同步 JSON 超过 900 字节并切分为多个分片
      final createdSessionIds = <String>[];
      for (var s = 0; s < 3; s++) {
        final session = await chatService.createSession(
          sessionType: 'agent',
          title: '分片测试会话_$s',
        );
        createdSessionIds.add(session.id);
        for (var m = 0; m < 3; m++) {
          await chatService.addMessage(
            session.id,
            ChatMessage(
              id: 'shard_msg_${s}_$m',
              content: '分片消息正文_${s}_${m}_${'内容填充' * 30}',
              isUser: m.isEven,
              role: m.isEven ? 'user' : 'assistant',
              timestamp: DateTime.utc(2026, 11, 20, 8, s * 10 + m),
            ),
          );
        }
      }

      const staleShardName =
          'shard_0000000000000000000000000000000000000000000000000000000000000000.zip';
      final remoteFiles = <String, List<int>>{
        '/dav/thoughtecho/chat_shards/$staleShardName': <int>[1, 2, 3],
      };
      final remoteModified = <String, DateTime>{
        '/dav/thoughtecho/chat_shards/$staleShardName':
            DateTime.utc(2026, 1, 1, 0, 0, 0),
      };
      final deletedPaths = <String>[];
      final putShardPaths = <String>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final path = request.uri.path;
        final response = request.response;
        response.headers.set(
          HttpHeaders.dateHeader,
          HttpDate.format(DateTime.now().toUtc()),
        );
        switch (request.method) {
          case 'MKCOL':
            response.statusCode = 201;
          case 'PROPFIND':
            if (path.endsWith('/thoughtecho/chat_shards') ||
                path.endsWith('/thoughtecho/chat_shards/')) {
              final shardEntries = remoteFiles.keys
                  .where((k) => k.startsWith('/dav/thoughtecho/chat_shards/'))
                  .map((k) {
                final mod = remoteModified[k];
                final modXml = mod != null
                    ? '<d:getlastmodified>${HttpDate.format(mod)}</d:getlastmodified>'
                    : '';
                return '<d:response><d:href>$k</d:href>'
                    '<d:propstat><d:prop>'
                    '<d:getcontentlength>${remoteFiles[k]!.length}</d:getcontentlength>'
                    '$modXml'
                    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
                    '</d:response>';
              }).join();
              response.statusCode = 207;
              response.write(
                '<d:multistatus xmlns:d="DAV:">'
                '<d:response><d:href>/dav/thoughtecho/chat_shards/</d:href></d:response>'
                '$shardEntries'
                '</d:multistatus>',
              );
            } else if (remoteFiles.containsKey(path)) {
              response.statusCode = 207;
              response.write(
                '<d:multistatus xmlns:d="DAV:"><d:response>'
                '<d:href>$path</d:href>'
                '<d:propstat><d:prop><d:getetag>"etag-${remoteFiles[path]!.length}"</d:getetag>'
                '<d:getcontentlength>${remoteFiles[path]!.length}</d:getcontentlength>'
                '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
                '</d:response></d:multistatus>',
              );
            } else if (path.endsWith('/thoughtecho') ||
                path.endsWith('/thoughtecho/') ||
                path.endsWith('/dav') ||
                path.endsWith('/dav/')) {
              response.statusCode = 207;
              response.write('<d:multistatus xmlns:d="DAV:"></d:multistatus>');
            } else {
              response.statusCode = 404;
            }
          case 'GET':
            final data = remoteFiles[path];
            if (data == null) {
              response.statusCode = 404;
            } else {
              response.statusCode = 200;
              response.add(data);
            }
          case 'PUT':
            remoteFiles[path] = body;
            remoteModified[path] = DateTime.now().toUtc();
            if (path.startsWith('/dav/thoughtecho/chat_shards/')) {
              putShardPaths.add(path);
            }
            response.statusCode = 204;
          case 'DELETE':
            deletedPaths.add(path);
            remoteFiles.remove(path);
            remoteModified.remove(path);
            response.statusCode = 204;
          default:
            response.statusCode = 405;
        }
        await response.close();
      });

      // 1. 设备 A 触发上传：主包 messages 置空并写入多个 message_shards，过期分片被清理
      final webdavA = WebDAVSyncService.forTesting();
      addTearDown(webdavA.dispose);
      webdavA.attachAssistantDataSync(assistantSync);
      await webdavA.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://webdav.example.invalid/dav/',
        username: 'test-user',
        password: 'synthetic-password',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: true,
      );

      await HttpOverrides.runWithHttpOverrides(
        () => webdavA.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );
      expect(
        webdavA.syncStatus,
        WebDAVSyncStatus.success,
        reason: webdavA.lastSyncError,
      );

      final mainZipBytes = remoteFiles['/dav/thoughtecho/thoughtecho_sync.zip'];
      expect(mainZipBytes, isNotNull);
      final mainPayload =
          WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
        mainZipBytes!,
      );
      final uploadedChat = mainPayload['chat'] as Map<String, dynamic>;
      expect(uploadedChat['messages'] as List, isEmpty);
      final uploadedShards = uploadedChat['message_shards'] as List;
      expect(uploadedShards.length, greaterThanOrEqualTo(2));
      expect(
        deletedPaths,
        contains('/dav/thoughtecho/chat_shards/$staleShardName'),
      );
      final firstRunShardNames = uploadedShards
          .map((e) => (e as Map<String, dynamic>)['file'] as String)
          .toList();
      final putCountAfterFirstSync = putShardPaths.length;
      expect(putCountAfterFirstSync, equals(firstRunShardNames.length));

      // 1b. 消息未变化时隔一秒再次触发同步：分片哈希与文件名完全不变，且云端已存在分片跳过重复 PUT
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await HttpOverrides.runWithHttpOverrides(
        () => webdavA.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );
      expect(webdavA.syncStatus, WebDAVSyncStatus.success);
      final secondMainPayload =
          WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
        remoteFiles['/dav/thoughtecho/thoughtecho_sync.zip']!,
      );
      final secondRunShardNames = ((secondMainPayload['chat']
              as Map<String, dynamic>)['message_shards'] as List)
          .map((e) => (e as Map<String, dynamic>)['file'] as String)
          .toList();
      expect(secondRunShardNames, equals(firstRunShardNames));
      expect(
        putShardPaths.length,
        equals(putCountAfterFirstSync),
        reason: '消息未变时不应重复 PUT 相同内容寻址分片',
      );
      expect(
        deletedPaths.where(
          (k) => firstRunShardNames.any(k.endsWith),
        ),
        isEmpty,
      );

      // 2. 全新设备 B 拉取分片主包，逐片下载校验 SHA-256 并完整恢复 3 个会话共 9 条消息
      final dirB = await Directory.systemTemp.createTemp('peer_b_sharded_');
      final rawNotesDbB = await databaseFactory.openDatabase(
        p.join(dirB.path, 'notes_b.db'),
      );
      await DatabaseSchemaManager().createTables(rawNotesDbB);
      DatabaseService.setTestDatabase(rawNotesDbB);
      final dbServiceB = DatabaseService();
      await dbServiceB.init();
      final chatB = ChatSessionService(
        databasePath: p.join(dirB.path, 'chat_b.db'),
      );
      await chatB.init();
      final memB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirB.path, 'mem_b.db'),
      );
      final assistantSyncB = AssistantDataSyncService(
        chatSessionService: chatB,
        agentMemoryService: memB,
        settingsService: settingsService,
        databaseService: dbServiceB,
      );
      final webdavB = WebDAVSyncService.forTesting();
      try {
        await AppPreferencesService().remove('webdav_last_sync_time');
        webdavB.attachAssistantDataSync(assistantSyncB);
        await webdavB.saveSettings(
          enabled: true,
          provider: 'custom',
          url: 'https://webdav.example.invalid/dav/',
          username: 'test-user',
          password: 'synthetic-password',
          syncOnLaunch: false,
          syncOnChange: false,
          syncOnCellular: false,
          syncNotesOnlyOnCellular: true,
        );

        await HttpOverrides.runWithHttpOverrides(
          () => webdavB.triggerSync(),
          _LoopbackHttpOverrides(server.port),
        );
        expect(
          webdavB.syncStatus,
          WebDAVSyncStatus.success,
          reason: webdavB.lastSyncError,
        );

        final sessionsOnB = await chatB.getAllSessions();
        expect(
          sessionsOnB.map((s) => s.id).toSet(),
          equals(createdSessionIds.toSet()),
        );
        for (var s = 0; s < 3; s++) {
          final msgs = await chatB.getMessages(createdSessionIds[s]);
          expect(msgs, hasLength(3));
          expect(
            msgs.map((m) => m.id).toSet(),
            equals(<String>{
              'shard_msg_${s}_0',
              'shard_msg_${s}_1',
              'shard_msg_${s}_2',
            }),
          );
        }
      } finally {
        webdavB.dispose();
        await chatB.close();
        chatB.dispose();
        memB.dispose();
        await rawNotesDbB.close();
        DatabaseService.setTestDatabase(rawNotesDb);
        if (await dirB.exists()) {
          await dirB.delete(recursive: true);
        }
      }
    });

    test(
        '双客户端并发交叉：客户端 A 从分片退回内联上传且其目录清理晚于客户端 B 暂存新分片执行时，B 的新分片不被误删且最终主包引用的全部分片均可下载恢复',
        () async {
      WebDAVSyncService.chatShardThresholdBytesForTesting = 900;
      WebDAVSyncService.maxChatShardJsonBytesForTesting = 700;
      addTearDown(() {
        WebDAVSyncService.chatShardThresholdBytesForTesting = null;
        WebDAVSyncService.maxChatShardJsonBytesForTesting = null;
        WebDAVSyncService.chatShardStaleCleanupMinAgeForTesting = null;
      });

      // 初始化设备 A 的大体量会话（使其首轮同步走分片上传）
      final sessionA = await chatService.createSession(
        sessionType: 'agent',
        title: '设备A大体积会话',
      );
      for (var i = 0; i < 6; i++) {
        await chatService.addMessage(
          sessionA.id,
          ChatMessage(
            id: 'dev_a_msg_$i',
            content: '设备A消息正文_${i}_${'填充块' * 40}',
            isUser: i.isEven,
            role: i.isEven ? 'user' : 'assistant',
            timestamp: DateTime.utc(2026, 11, 20, 9, i),
          ),
        );
      }

      var etagSeq = 1;
      final remoteFiles = <String, List<int>>{};
      final remoteEtags = <String, String>{};
      final remoteModified = <String, DateTime>{};
      final deletedShardPaths = <String>[];
      Completer<void>? pauseCleanupListGate;
      Completer<void>? cleanupListPausedSignal;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final path = request.uri.path;
        final response = request.response;
        response.headers.set(
          HttpHeaders.dateHeader,
          HttpDate.format(DateTime.now().toUtc()),
        );
        switch (request.method) {
          case 'MKCOL':
            response.statusCode = 201;
          case 'PROPFIND':
            if (path.endsWith('/thoughtecho/chat_shards') ||
                path.endsWith('/thoughtecho/chat_shards/')) {
              final gate = pauseCleanupListGate;
              final signal = cleanupListPausedSignal;
              if (gate != null && signal != null && !signal.isCompleted) {
                signal.complete();
                await gate.future;
              }
              final shardEntries = remoteFiles.keys
                  .where((k) => k.startsWith('/dav/thoughtecho/chat_shards/'))
                  .map((k) {
                final mod = remoteModified[k] ?? DateTime.now().toUtc();
                return '<d:response><d:href>$k</d:href>'
                    '<d:propstat><d:prop>'
                    '<d:getcontentlength>${remoteFiles[k]!.length}</d:getcontentlength>'
                    '<d:getlastmodified>${HttpDate.format(mod)}</d:getlastmodified>'
                    '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
                    '</d:response>';
              }).join();
              response.statusCode = 207;
              response.write(
                '<d:multistatus xmlns:d="DAV:">'
                '<d:response><d:href>/dav/thoughtecho/chat_shards/</d:href></d:response>'
                '$shardEntries'
                '</d:multistatus>',
              );
            } else if (remoteFiles.containsKey(path)) {
              response.statusCode = 207;
              response.write(
                '<d:multistatus xmlns:d="DAV:"><d:response>'
                '<d:href>$path</d:href>'
                '<d:propstat><d:prop><d:getetag>${remoteEtags[path]}</d:getetag>'
                '<d:getcontentlength>${remoteFiles[path]!.length}</d:getcontentlength>'
                '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
                '</d:response></d:multistatus>',
              );
            } else if (path.endsWith('/thoughtecho') ||
                path.endsWith('/thoughtecho/') ||
                path.endsWith('/dav') ||
                path.endsWith('/dav/')) {
              response.statusCode = 207;
              response.write('<d:multistatus xmlns:d="DAV:"></d:multistatus>');
            } else {
              response.statusCode = 404;
            }
          case 'GET':
            final data = remoteFiles[path];
            if (data == null) {
              response.statusCode = 404;
            } else {
              if (remoteEtags.containsKey(path)) {
                response.headers
                    .set(HttpHeaders.etagHeader, remoteEtags[path]!);
              }
              response.statusCode = 200;
              response.add(data);
            }
          case 'PUT':
            final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
            if (ifMatch != null &&
                remoteEtags.containsKey(path) &&
                ifMatch != remoteEtags[path]) {
              response.statusCode = 412;
              break;
            }
            remoteFiles[path] = body;
            final newEtag = '"etag-${etagSeq++}"';
            remoteEtags[path] = newEtag;
            remoteModified[path] = DateTime.now().toUtc();
            response.headers.set(HttpHeaders.etagHeader, newEtag);
            response.statusCode = 204;
          case 'DELETE':
            deletedShardPaths.add(path);
            remoteFiles.remove(path);
            remoteEtags.remove(path);
            remoteModified.remove(path);
            response.statusCode = 204;
          default:
            response.statusCode = 405;
        }
        await response.close();
      });

      final webdavA = WebDAVSyncService.forTesting();
      addTearDown(webdavA.dispose);
      webdavA.attachAssistantDataSync(assistantSync);
      await webdavA.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://webdav.example.invalid/dav/',
        username: 'test-user',
        password: 'synthetic-password',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: true,
      );

      // 步骤 1：客户端 A 首轮上传分片主包
      await HttpOverrides.runWithHttpOverrides(
        () => webdavA.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );
      expect(webdavA.syncStatus, WebDAVSyncStatus.success);

      // 步骤 2：客户端 A 删除该大体积会话，使同步包缩小为内联模式；
      //         拦截其主包发布后的 chat_shards 目录清理请求，模拟清理滞后于客户端 B 的新分片暂存
      await chatService.deleteSession(sessionA.id);
      pauseCleanupListGate = Completer<void>();
      cleanupListPausedSignal = Completer<void>();

      final syncAFuture = HttpOverrides.runWithHttpOverrides(
        () => webdavA.triggerSync(),
        _LoopbackHttpOverrides(server.port),
      );
      await cleanupListPausedSignal.future;

      // 此时 A 的内联主包已经写上云端，但 A 的 _cleanupStaleRemoteChatShards 尚未列目录；
      // 启动客户端 B：读取 A 的内联主包、暂存上传 B 自己的大体积聊天分片并发布 B 的新主包
      final dirPeer = await Directory.systemTemp.createTemp('peer_bc_race_');
      final chatB = ChatSessionService(
        databasePath: p.join(dirPeer.path, 'chat_b.db'),
      );
      await chatB.init();
      final memB = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirPeer.path, 'mem_b.db'),
      );
      final assistantSyncB = AssistantDataSyncService(
        chatSessionService: chatB,
        agentMemoryService: memB,
        settingsService: settingsService,
        databaseService: databaseService,
      );
      final webdavB = WebDAVSyncService.forTesting();

      final chatC = ChatSessionService(
        databasePath: p.join(dirPeer.path, 'chat_c.db'),
      );
      await chatC.init();
      final memC = AgentMemoryService(
        settingsService: settingsService,
        databasePath: p.join(dirPeer.path, 'mem_c.db'),
      );
      final assistantSyncC = AssistantDataSyncService(
        chatSessionService: chatC,
        agentMemoryService: memC,
        settingsService: settingsService,
        databaseService: databaseService,
      );
      final webdavC = WebDAVSyncService.forTesting();

      try {
        final sessionB = await chatB.createSession(
          sessionType: 'agent',
          title: '设备B保留的大体积会话',
        );
        for (var i = 0; i < 6; i++) {
          await chatB.addMessage(
            sessionB.id,
            ChatMessage(
              id: 'dev_b_msg_$i',
              content: '设备B分片消息正文_${i}_${'长内容段落' * 40}',
              isUser: i.isEven,
              role: i.isEven ? 'user' : 'assistant',
              timestamp: DateTime.utc(2026, 11, 20, 11, i),
            ),
          );
        }

        webdavB.attachAssistantDataSync(assistantSyncB);
        await webdavB.saveSettings(
          enabled: true,
          provider: 'custom',
          url: 'https://webdav.example.invalid/dav/',
          username: 'test-user',
          password: 'synthetic-password',
          syncOnLaunch: false,
          syncOnChange: false,
          syncOnCellular: false,
          syncNotesOnlyOnCellular: true,
        );

        // 放行后续 PROPFIND（让 B 能正常列目录暂存分片），等 B 完成发布后再恢复 A 的挂起清理
        final heldCleanupGate = pauseCleanupListGate;
        pauseCleanupListGate = null;

        await HttpOverrides.runWithHttpOverrides(
          () => webdavB.triggerSync(),
          _LoopbackHttpOverrides(server.port),
        );
        expect(
          webdavB.syncStatus,
          WebDAVSyncStatus.success,
          reason: webdavB.lastSyncError,
        );

        final finalMainPayload =
            WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
          remoteFiles['/dav/thoughtecho/thoughtecho_sync.zip']!,
        );
        final finalShardFiles = ((finalMainPayload['chat']
                as Map<String, dynamic>)['message_shards'] as List)
            .map((e) => (e as Map<String, dynamic>)['file'] as String)
            .toList();
        expect(finalShardFiles, isNotEmpty);

        // 释放 A 滞后的目录清理：B 新上传的分片受宽限期保护，绝不能被 A 误删
        heldCleanupGate.complete();
        await syncAFuture;
        expect(webdavA.syncStatus, WebDAVSyncStatus.success);
        for (final shardFile in finalShardFiles) {
          expect(
            remoteFiles.containsKey('/dav/thoughtecho/chat_shards/$shardFile'),
            isTrue,
            reason: 'B 引用的分片 $shardFile 不应被 A 的滞后清理误删',
          );
        }
        expect(deletedShardPaths, isEmpty);

        // 步骤 3：第三台全新客户端 C 同步下载 B 的主包及全部分片，验证所有引用分片完整可下载
        webdavC.attachAssistantDataSync(assistantSyncC);
        await webdavC.saveSettings(
          enabled: true,
          provider: 'custom',
          url: 'https://webdav.example.invalid/dav/',
          username: 'test-user',
          password: 'synthetic-password',
          syncOnLaunch: false,
          syncOnChange: false,
          syncOnCellular: false,
          syncNotesOnlyOnCellular: true,
        );
        await HttpOverrides.runWithHttpOverrides(
          () => webdavC.triggerSync(),
          _LoopbackHttpOverrides(server.port),
        );
        expect(
          webdavC.syncStatus,
          WebDAVSyncStatus.success,
          reason: webdavC.lastSyncError,
        );
        final msgsOnC = await chatC.getMessages(sessionB.id);
        expect(msgsOnC, hasLength(6));
      } finally {
        final lingeringGate = pauseCleanupListGate;
        if (lingeringGate != null && !lingeringGate.isCompleted) {
          lingeringGate.complete();
        }
        webdavB.dispose();
        webdavC.dispose();
        await chatB.close();
        chatB.dispose();
        memB.dispose();
        await chatC.close();
        chatC.dispose();
        memC.dispose();
        if (await dirPeer.exists()) {
          await dirPeer.delete(recursive: true);
        }
      }
    });
  });
}

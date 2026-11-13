import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/providers/app_providers.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/agent_tools/explore_notes_tool.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';

import '../../test_harness.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  String? get localeCode => 'zh';

  @override
  bool get dreamingAfterInsightEnabled => false;

  @override
  bool get dreamingOnIdleEnabled => false;

  @override
  bool get agentMemoryEnabled => true;

  @override
  bool get dreamingEnabled => false;

  @override
  int get agentMemoryGeneration => 1;

  @override
  String get userNickname => 'TestUser';

  @override
  bool get syncSkipConfirm => false;

  final AppSettings _settings = AppSettings();

  @override
  AppSettings get appSettings => _settings;

  void Function()? _identityAliasesProvider;

  @override
  void setIdentityAliasesProvider(void Function()? provider) {
    _identityAliasesProvider = provider;
  }

  void Function()? get identityAliasesProvider => _identityAliasesProvider;

  @override
  void refreshIdentityAliases() {}

  @override
  Future<String?> getCustomString(String key) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  VoidCallback? onLocalDataChanged;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocationService extends ChangeNotifier implements LocationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWeatherService extends ChangeNotifier implements WeatherService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClipboardService extends ChangeNotifier implements ClipboardService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnifiedLogService extends ChangeNotifier
    implements UnifiedLogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAppTheme extends ChangeNotifier implements AppTheme {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAIAnalysisDatabaseService extends ChangeNotifier
    implements AIAnalysisDatabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnectivityService extends ChangeNotifier
    implements ConnectivityService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFeatureGuideService extends ChangeNotifier
    implements FeatureGuideService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSmartPushService extends ChangeNotifier implements SmartPushService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatSessionService extends ChangeNotifier
    implements ChatSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMMKVService implements MMKVService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyTool extends AgentTool {
  final String toolName;
  _DummyTool(this.toolName);

  @override
  String get name => toolName;

  @override
  String get description => 'Dummy description';

  @override
  bool get isReadOnly => true;

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async => ToolResult(
        toolCallId: toolCall.id,
        content: 'dummy',
      );
}

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(TestHarness.tearDown);

  group('Service in-place updateDependencies unit tests', () {
    test(
        'AgentService.updateDependencies updates references and tools in-place',
        () async {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final tool1 = _DummyTool('tool_1');
      final tool2 = _DummyTool('tool_2');

      final agent = AgentService(
        settingsService: s1,
        tools: [tool1],
      );

      expect(agent.settingsService, equals(s1));
      expect(agent.tools.length, equals(1));
      expect(agent.tools.first.name, equals('tool_1'));

      final eventsList = <AgentEvent>[];
      final subscription = agent.events.listen(eventsList.add);

      // Perform in-place update
      agent.updateDependencies(
        settingsService: s2,
        tools: [tool2],
      );

      expect(agent.settingsService, equals(s2));
      expect(agent.tools.length, equals(1));
      expect(agent.tools.first.name, equals('tool_2'));

      // Event stream remains functional
      agent.requestStop();
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      agent.dispose();
    });

    test(
        'AgentService.updateDependencies reuses existing AskUserTool instance and preserves prompt handler',
        () async {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final initialAskUser = AskUserTool();
      final agent = AgentService(
        settingsService: s1,
        tools: [initialAskUser, _DummyTool('tool_1')],
      );

      var handlerInvoked = false;
      agent.setAskUserHandler((request) async {
        handlerInvoked = true;
        return AskUserResponse.cancelled();
      });

      final newAskUser = AskUserTool();
      agent.updateDependencies(
        settingsService: s2,
        tools: [newAskUser, _DummyTool('tool_2')],
      );

      // AskUserTool instance must be preserved across in-place dependency updates
      final currentAskUser = agent.findTool<AskUserTool>();
      expect(identical(currentAskUser, initialAskUser), isTrue);
      expect(identical(currentAskUser, newAskUser), isFalse);

      // Verify the handler registered before updateDependencies remains active
      await currentAskUser?.execute(
        ToolCall(
          id: 'call_test',
          name: 'ask_user',
          arguments: {
            'questions': [
              {
                'question': 'Are you sure?',
                'options': [
                  {'label': 'Yes'},
                  {'label': 'No'},
                ],
              }
            ],
          },
        ),
      );
      expect(handlerInvoked, isTrue);

      agent.dispose();
    });

    test(
        'AgentService preserves AskUserTool active prompt and allows cancellation after updateDependencies',
        () async {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final initialAskUser = AskUserTool();
      final agent = AgentService(
        settingsService: s1,
        tools: [initialAskUser],
      );

      final userChoiceCompleter = Completer<AskUserResponse>();
      agent.setAskUserHandler((request) => userChoiceCompleter.future);

      final executeFuture = agent.findTool<AskUserTool>()!.execute(
            ToolCall(
              id: 'prompt_1',
              name: 'ask_user',
              arguments: {
                'questions': [
                  {
                    'question': 'Confirm?',
                    'options': [
                      {'label': 'A'},
                      {'label': 'B'},
                    ],
                  }
                ],
              },
            ),
          );

      // Verify active prompt is waiting
      expect(initialAskUser.hasActivePrompt, isTrue);

      // Update dependencies while prompt is active
      agent.updateDependencies(
        settingsService: s2,
        tools: [AskUserTool()],
      );

      // Active prompt is still held by the preserved tool
      expect(agent.findTool<AskUserTool>()!.hasActivePrompt, isTrue);

      // Cancel through tool cancellation (as happens on stop/cancellation)
      agent.tools.first.cancel();

      final result = await executeFuture;
      expect(result.content, contains('用户取消了本次选择'));
      expect(initialAskUser.hasActivePrompt, isFalse);

      agent.dispose();
    });

    test('AIService.updateDependencies updates settings and memory in-place',
        () {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final aiService = AIService(settingsService: s1);

      expect(aiService.settingsService, equals(s1));
      expect(aiService.memoryService, isNull);

      aiService.updateDependencies(settingsService: s2);
      expect(aiService.settingsService, equals(s2));
    });

    test('NoteSyncService.updateDependencies updates dependencies in-place',
        () {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final db1 = _FakeDatabaseService();
      final db2 = _FakeDatabaseService();
      final aiDb1 = _FakeAIAnalysisDatabaseService();
      final aiDb2 = _FakeAIAnalysisDatabaseService();
      final backup1 = BackupService(
        databaseService: db1,
        settingsService: s1,
        aiAnalysisDbService: aiDb1,
      );
      final backup2 = BackupService(
        databaseService: db2,
        settingsService: s2,
        aiAnalysisDbService: aiDb2,
      );

      final noteSync = NoteSyncService(
        backupService: backup1,
        databaseService: db1,
        settingsService: s1,
        aiAnalysisDbService: aiDb1,
      );

      expect(noteSync.backupService, equals(backup1));
      expect(noteSync.databaseService, equals(db1));
      expect(noteSync.settingsService, equals(s1));
      expect(noteSync.aiAnalysisDbService, equals(aiDb1));

      noteSync.updateDependencies(
        backupService: backup2,
        databaseService: db2,
        settingsService: s2,
        aiAnalysisDbService: aiDb2,
      );

      expect(noteSync.backupService, equals(backup2));
      expect(noteSync.databaseService, equals(db2));
      expect(noteSync.settingsService, equals(s2));
      expect(noteSync.aiAnalysisDbService, equals(aiDb2));
    });

    test(
        'AgentMemoryService.updateDependencies rebinds identity aliases provider',
        () {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();

      final memory = AgentMemoryService(
        settingsService: s1,
        databasePath: inMemoryDatabasePath,
      );

      expect(s1.identityAliasesProvider, isNotNull);
      expect(s2.identityAliasesProvider, isNull);

      memory.updateDependencies(settingsService: s2);

      expect(memory.settingsService, equals(s2));
      expect(s1.identityAliasesProvider, isNull);
      expect(s2.identityAliasesProvider, isNotNull);
    });

    test(
        'InsightHistoryService.updateDependencies updates settings and aiAnalysisDbService in-place',
        () {
      final s1 = _FakeSettingsService();
      final s2 = _FakeSettingsService();
      final db1 = _FakeAIAnalysisDatabaseService();
      final db2 = _FakeAIAnalysisDatabaseService();

      final insightService = InsightHistoryService(
        settingsService: s1,
        aiAnalysisDbService: db1,
      );
      expect(insightService.settingsService, equals(s1));
      expect(insightService.aiAnalysisDbService, equals(db1));

      insightService.updateDependencies(
        settingsService: s2,
        aiAnalysisDbService: db2,
      );
      expect(insightService.settingsService, equals(s2));
      expect(insightService.aiAnalysisDbService, equals(db2));
    });
  });

  group('AppProviders ProxyProvider in-place rebinding integration tests', () {
    testWidgets(
        'upstream SettingsService/DatabaseService notifyListeners() updates AgentService._tools and NoteSyncService._backupService in-place',
        (tester) async {
      final settingsService = _FakeSettingsService();
      final databaseService = _FakeDatabaseService();
      final locationService = _FakeLocationService();
      final weatherService = _FakeWeatherService();
      final clipboardService = _FakeClipboardService();
      final unifiedLogService = _FakeUnifiedLogService();
      final appTheme = _FakeAppTheme();
      final aiAnalysisDbService = _FakeAIAnalysisDatabaseService();
      final connectivityService = _FakeConnectivityService();
      final featureGuideService = _FakeFeatureGuideService();
      final smartPushService = _FakeSmartPushService();
      final chatSessionService = _FakeChatSessionService();
      final mmkvService = _FakeMMKVService();
      final servicesInitialized = ValueNotifier<bool>(true);

      late BuildContext capturedContext;

      await tester.pumpWidget(
        MultiProvider(
          providers: buildAppProviders(
            settingsService: settingsService,
            databaseService: databaseService,
            locationService: locationService,
            weatherService: weatherService,
            clipboardService: clipboardService,
            unifiedLogService: unifiedLogService,
            appTheme: appTheme,
            aiAnalysisDbService: aiAnalysisDbService,
            connectivityService: connectivityService,
            featureGuideService: featureGuideService,
            smartPushService: smartPushService,
            chatSessionService: chatSessionService,
            mmkvService: mmkvService,
            servicesInitialized: servicesInitialized,
          ),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              // Touch the providers so they are instantiated
              context.watch<AgentService>();
              context.watch<NoteSyncService>();
              context.watch<AIService>();
              context.watch<AgentMemoryService>();
              context.watch<InsightHistoryService>();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final initialAgent = capturedContext.read<AgentService>();
      final initialNoteSync = capturedContext.read<NoteSyncService>();
      final initialAiService = capturedContext.read<AIService>();
      final initialMemory = capturedContext.read<AgentMemoryService>();
      final initialInsight = capturedContext.read<InsightHistoryService>();

      final initialTools = initialAgent.tools;
      final initialBackup = initialNoteSync.backupService;

      // Find AgentTools to verify their lifecycle
      final initialExploreTool = initialAgent.findTool<ExploreNotesTool>();
      final initialAskUserTool = initialAgent.findTool<AskUserTool>();
      expect(initialExploreTool, isNotNull);
      expect(initialAskUserTool, isNotNull);

      // 1. Trigger SettingsService notifyListeners()
      settingsService.notifyListeners();
      await tester.pump();

      final agentAfterSettings = capturedContext.read<AgentService>();
      final noteSyncAfterSettings = capturedContext.read<NoteSyncService>();
      final aiAfterSettings = capturedContext.read<AIService>();
      final memoryAfterSettings = capturedContext.read<AgentMemoryService>();
      final insightAfterSettings =
          capturedContext.read<InsightHistoryService>();

      // Instances MUST remain identical (in-place rebinding, no destruction)
      expect(identical(initialAgent, agentAfterSettings), isTrue,
          reason: 'AgentService must not be recreated');
      expect(identical(initialNoteSync, noteSyncAfterSettings), isTrue,
          reason: 'NoteSyncService must not be recreated');
      expect(identical(initialAiService, aiAfterSettings), isTrue,
          reason: 'AIService must not be recreated');
      expect(identical(initialMemory, memoryAfterSettings), isTrue,
          reason: 'AgentMemoryService must not be recreated');
      expect(identical(initialInsight, insightAfterSettings), isTrue,
          reason: 'InsightHistoryService must not be recreated');

      // Internal dependencies MUST be replaced with new instances
      expect(identical(initialTools, agentAfterSettings.tools), isFalse,
          reason: 'AgentService._tools must be updated');
      expect(
          identical(initialExploreTool,
              agentAfterSettings.findTool<ExploreNotesTool>()),
          isFalse,
          reason:
              'Tools inside AgentService must be newly constructed instances');
      expect(
          identical(
              initialAskUserTool, agentAfterSettings.findTool<AskUserTool>()),
          isTrue,
          reason:
              'AskUserTool instance must be preserved across settings update');
      expect(identical(initialBackup, noteSyncAfterSettings.backupService),
          isFalse,
          reason: 'NoteSyncService._backupService must be updated');

      final toolsAfterSettings = agentAfterSettings.tools;
      final exploreToolAfterSettings =
          agentAfterSettings.findTool<ExploreNotesTool>();
      final backupAfterSettings = noteSyncAfterSettings.backupService;

      // 2. Trigger DatabaseService notifyListeners()
      databaseService.notifyListeners();
      await tester.pump();

      final agentAfterDb = capturedContext.read<AgentService>();
      final noteSyncAfterDb = capturedContext.read<NoteSyncService>();

      expect(identical(initialAgent, agentAfterDb), isTrue,
          reason: 'AgentService remains unchanged instance on DB update');
      expect(identical(initialNoteSync, noteSyncAfterDb), isTrue,
          reason: 'NoteSyncService remains unchanged instance on DB update');

      // Tools and BackupService must be refreshed again
      expect(identical(toolsAfterSettings, agentAfterDb.tools), isFalse,
          reason: 'AgentService._tools must be replaced again on DB update');
      expect(
          identical(exploreToolAfterSettings,
              agentAfterDb.findTool<ExploreNotesTool>()),
          isFalse,
          reason: 'ExploreNotesTool must be replaced again on DB update');
      expect(
          identical(initialAskUserTool, agentAfterDb.findTool<AskUserTool>()),
          isTrue,
          reason:
              'AskUserTool instance must remain preserved across DB update');
      expect(identical(backupAfterSettings, noteSyncAfterDb.backupService),
          isFalse,
          reason:
              'NoteSyncService._backupService must be replaced again on DB update');
    });
  });
}

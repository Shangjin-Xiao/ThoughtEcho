import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../services/ai_analysis_database_service.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../services/clipboard_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/feature_guide_service.dart';
import '../services/insight_history_service.dart';
import '../services/location_service.dart';
import '../services/mmkv_service.dart';
import '../services/note_sync_service.dart';
import '../services/settings_service.dart';
import '../services/smart_push_service.dart';
import '../services/unified_log_service.dart';
import '../services/weather_service.dart';
import '../services/webdav_sync_service.dart';
import '../theme/app_theme.dart';
import '../controllers/search_controller.dart';
import '../services/chat_session_service.dart';
import '../services/openai_stream_service.dart';
import '../services/agent_service.dart';
import '../services/agent_tool.dart';
import '../services/agent_tools/explore_notes_tool.dart';
import '../services/agent_tools/get_app_context_tool.dart';
import '../services/agent_tools/get_note_detail_tool.dart';
import '../services/agent_tools/propose_note_create_tool.dart';
import '../services/agent_tools/propose_note_edit_tool.dart';
import '../services/agent_tools/web_fetch_tool.dart';
import '../services/agent_tools/web_search_tool.dart';
import '../services/web_fetch_service.dart';

/// 构建 Agent 工具列表
List<AgentTool> _buildAgentTools(
  SettingsService settingsService,
  DatabaseService db,
  LocationService locationService,
  WeatherService weatherService,
) {
  return [
    ExploreNotesTool(db),
    GetTagsTool(db),
    GetLocationWeatherTool(
      locationService: locationService,
      weatherService: weatherService,
    ),
    GetNoteDetailTool(db),
    WebSearchTool(settingsService),
    WebFetchTool(WebFetchService()),
    ProposeNoteCreateTool(db),
    ProposeNoteEditTool(db),
  ];
}

/// 构建应用级别的所有 Provider
List<SingleChildWidget> buildAppProviders({
  required SettingsService settingsService,
  required DatabaseService databaseService,
  required LocationService locationService,
  required WeatherService weatherService,
  required ClipboardService clipboardService,
  required UnifiedLogService unifiedLogService,
  required AppTheme appTheme,
  required AIAnalysisDatabaseService aiAnalysisDbService,
  required ConnectivityService connectivityService,
  required FeatureGuideService featureGuideService,
  required SmartPushService smartPushService,
  required ChatSessionService chatSessionService,
  required MMKVService mmkvService,
  required ValueNotifier<bool> servicesInitialized,
}) {
  return [
    ChangeNotifierProvider(create: (_) => settingsService),
    // 兼容性说明：DatabaseService现在有dispose方法，但Provider会自动处理
    ChangeNotifierProvider(create: (_) => databaseService),
    ChangeNotifierProvider(create: (_) => locationService),
    ChangeNotifierProvider(create: (_) => weatherService),
    ChangeNotifierProvider(create: (_) => clipboardService),
    ChangeNotifierProvider(create: (_) => unifiedLogService),
    ChangeNotifierProvider(create: (_) => appTheme),
    ChangeNotifierProvider(create: (_) => aiAnalysisDbService),
    ChangeNotifierProvider(create: (_) => connectivityService),
    ChangeNotifierProvider(create: (_) => featureGuideService),
    ChangeNotifierProvider(create: (_) => smartPushService),
    ChangeNotifierProvider(create: (_) => chatSessionService),
    ChangeNotifierProvider<OpenAIStreamService>(
      create: (_) => OpenAIStreamService(),
    ),
    ChangeNotifierProxyProvider4<SettingsService, DatabaseService,
        LocationService, WeatherService, AgentService>(
      create: (context) => AgentService(
        settingsService: context.read<SettingsService>(),
        tools: _buildAgentTools(
          context.read<SettingsService>(),
          context.read<DatabaseService>(),
          context.read<LocationService>(),
          context.read<WeatherService>(),
        ),
      ),
      update: (context, settings, db, location, weather, previous) =>
          previous ??
          AgentService(
            settingsService: settings,
            tools: _buildAgentTools(settings, db, location, weather),
          ),
    ),
    ChangeNotifierProvider(create: (_) => NoteSearchController()),
    ChangeNotifierProvider(create: (_) => WebDAVSyncService()),
    ChangeNotifierProxyProvider<SettingsService, InsightHistoryService>(
      create: (context) => InsightHistoryService(
        settingsService: context.read<SettingsService>(),
      ),
      update: (context, settingsService, insightHistoryService) =>
          insightHistoryService ??
          InsightHistoryService(settingsService: settingsService),
    ),
    Provider.value(value: mmkvService), // 使用 Provider.value 提供 MMKVService
    // 提供初始化状态的值（debug 下必须使用 ListenableProvider）
    ListenableProvider<ValueNotifier<bool>>.value(value: servicesInitialized),
    ValueListenableProvider<bool>.value(value: servicesInitialized),
    ChangeNotifierProxyProvider<SettingsService, AIService>(
      create: (context) =>
          AIService(settingsService: context.read<SettingsService>()),
      update: (context, settings, previous) =>
          previous ?? AIService(settingsService: settings),
    ),
    ProxyProvider3<DatabaseService, SettingsService, AIAnalysisDatabaseService,
        BackupService>(
      update: (context, dbService, settingsService, aiService, previous) =>
          BackupService(
        databaseService: dbService,
        settingsService: settingsService,
        aiAnalysisDbService: aiService,
      ),
    ),
    ChangeNotifierProxyProvider4<BackupService, DatabaseService,
        SettingsService, AIAnalysisDatabaseService, NoteSyncService>(
      create: (context) => NoteSyncService(
        backupService: context.read<BackupService>(),
        databaseService: context.read<DatabaseService>(),
        settingsService: context.read<SettingsService>(),
        aiAnalysisDbService: context.read<AIAnalysisDatabaseService>(),
      ),
      update: (
        context,
        backupService,
        databaseService,
        settingsService,
        aiAnalysisDbService,
        previous,
      ) =>
          previous ??
          NoteSyncService(
            backupService: backupService,
            databaseService: databaseService,
            settingsService: settingsService,
            aiAnalysisDbService: aiAnalysisDbService,
          ),
    ),
  ];
}

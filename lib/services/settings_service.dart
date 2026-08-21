import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/release_highlights.dart';
import '../models/ai_settings.dart';
import '../models/anniversary_participation.dart';
import '../models/app_settings.dart';
import '../models/multi_ai_settings.dart'; // 新增 MultiAISettings 导入
import '../models/local_ai_settings.dart'; // 新增 LocalAISettings 导入
import '../models/thoughter_entry.dart'; // 新增 ThoughterPageMode
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/utils/sentry_database_tracing.dart';
import 'package:thoughtecho/utils/sentry_helper.dart';
import 'package:thoughtecho/utils/sentry_network_tracing.dart';
import '../utils/lww_utils.dart';

import '../services/mmkv_service.dart';
import 'excerpt_intent_service.dart';

class SettingsService extends ChangeNotifier {
  static const ExcerptIntentService _excerptIntentService =
      ExcerptIntentService();
  static const String _aiSettingsKey = 'ai_settings';
  static const String _multiAiSettingsKey = 'multi_ai_settings'; // 新增
  static const String _localAiSettingsKey = 'local_ai_settings'; // 新增本地AI设置
  static const String _appSettingsKey = 'app_settings';
  static const String _exploreAiAssistantModeKey = 'explore_ai_assistant_mode';
  static const String _noteAiAssistantModeKey = 'note_ai_assistant_mode';
  static const String _themeModeKey = 'theme_mode';
  // 旧Key，用于迁移检查，迁移完成后可以考虑移除
  static const String _databaseMigrationCompleteKey =
      'database_migration_complete';
  // 新Key，表示初始数据库设置（包括首次创建或升级）是否已在引导流程中完成
  static const String _initialDatabaseSetupCompleteKey =
      'initial_database_setup_complete';
  // 使用应用安装标记替代版本号
  static const String _appInstalledKey = 'app_installed_v2';
  static const String _appUpgradedKey = 'app_upgraded_v2';
  final SharedPreferences _prefs; // 保留以支持数据迁移
  final MMKVService _mmkv = MMKVService(); // 使用MMKV作为主要存储
  late AISettings _aiSettings;
  late AppSettings _appSettings;
  late ThemeMode _themeMode;
  late MultiAISettings _multiAISettings; // 新增多provider设置
  late LocalAISettings _localAISettings; // 新增本地AI设置

  // 迁移标志，只执行一次数据迁移
  static const String _migrationCompleteKey = 'mmkv_migration_complete';

  static const String _lastVersionKey = 'lastVersion';
  static const String _deviceIdKey = 'device_id_v1'; // 新增：设备唯一ID缓存键
  static const String _syncSkipConfirmKey = 'sync_skip_confirm';
  static const String _syncDefaultIncludeMediaKey =
      'sync_default_include_media';
  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;
  MultiAISettings get multiAISettings => _multiAISettings; // 新增getter
  LocalAISettings get localAISettings => _localAISettings; // 新增本地AI设置getter
  static const String _dontShowAgentExperimentalNoticeKey =
      'dont_show_agent_experimental_notice';

  /// 用户最后一次看过更新说明时的版本号。
  ///
  /// 存版本号而不是「看过没有」的布尔：布尔答不了「他上次用的是哪一版」，
  /// 跨版本升级（3.6.5 直接升到 4.1.0）时就没法把中间几版的内容一起补上。
  static const String _lastSeenReleaseVersionKey = 'last_seen_release_version';

  bool get syncSkipConfirm => _mmkv.getBool(_syncSkipConfirmKey) ?? false;
  bool get syncDefaultIncludeMedia =>
      _mmkv.getBool(_syncDefaultIncludeMediaKey) ?? true;
  bool get dontShowAgentExperimentalNotice =>
      _mmkv.getBool(_dontShowAgentExperimentalNoticeKey) ?? false;

  Future<void> setDontShowAgentExperimentalNotice(bool value) async {
    await _mmkv.setBool(_dontShowAgentExperimentalNoticeKey, value);
    notifyListeners();
  }

  /// Thoughter 长期记忆开关。默认开启。
  ///
  /// 关闭只停止读写，**不清空已有记忆**——关开关和删数据是两件事，清空必须由
  /// 用户在设置页显式触发。
  static const String _agentMemoryEnabledKey = 'agent_memory_enabled';

  /// 「Thoughter 会记住你的偏好」这条一次性说明是否显示过。
  static const String _agentMemoryNoticeShownKey = 'agent_memory_notice_shown';

  /// 用户希望 Thoughter 称呼自己的名字。用户在设置里显式填写，
  /// 作为画像块里的 identity 行注入；只存本机，不进备份与同步。
  static const String _userNicknameKey = 'user_nickname';

  bool get agentMemoryEnabled => _mmkv.getBool(_agentMemoryEnabledKey) ?? true;

  /// 写入失败时抛出：这个开关的默认值是 true，静默失败会让用户以为已经关掉，
  /// 下次启动却发现记忆还在读写——隐私开关不能糊弄过去。
  Future<void> setAgentMemoryEnabled(bool value) async {
    final success = await _mmkv.setBool(_agentMemoryEnabledKey, value);
    if (!success) {
      AppLogger.e(
        'Thoughter 记忆开关保存失败：MMKV setBool 返回 false（value=$value）',
        source: 'SettingsService',
      );
      throw StateError('保存 Thoughter 记忆开关失败');
    }
    notifyListeners();
  }

  String get userNickname => _mmkv.getString(_userNicknameKey) ?? '';

  /// 写入失败时抛出：静默失败会让用户以为称呼已生效，对话里却一直没有。
  Future<void> setUserNickname(String value) async {
    final success = await _mmkv.setString(_userNicknameKey, value.trim());
    if (!success) {
      AppLogger.e(
        '用户称呼保存失败：MMKV setString 返回 false',
        source: 'SettingsService',
      );
      throw StateError('保存用户称呼失败');
    }
    notifyListeners();
  }

  bool get agentMemoryNoticeShown =>
      _mmkv.getBool(_agentMemoryNoticeShownKey) ?? false;

  /// 写入失败时抛出，让调用方能记一笔——否则用户每次进 Thoughter 都会被同一条
  /// 提示拦住，而没有任何线索。
  Future<void> setAgentMemoryNoticeShown(bool value) async {
    final success = await _mmkv.setBool(_agentMemoryNoticeShownKey, value);
    if (!success) {
      throw StateError('保存 Thoughter 记忆提示已读标记失败');
    }
    notifyListeners();
  }

  /// 用户最后一次看过更新说明时的版本号，读不到时给一个兜底基线。
  ///
  /// 这个字段是 4.0.0 才加的，所以**存量用户第一次升上来一定读不到值**，
  /// 必须从别处推。唯一可用的线索是 [AppSettings.sentryDisclosureShown]：
  /// 它为 true 说明用户见过 3.7.0 才有的崩溃诊断披露，即至少用过 3.7.0；
  /// 为 false 则按比任何登记条目都旧处理，把内容全部补给他。
  ///
  /// 推导只发生一次——[ReleaseNotesPage.checkAndShow] 看完就会落盘真实版本号。
  /// 边界情况是装了 3.7.0 之后从没打开过首页的用户会多看一句诊断说明，
  /// 相比漏掉隐私告知，这个方向的误差是可接受的那一边。
  String get lastSeenReleaseVersion {
    final stored = _mmkv.getString(_lastSeenReleaseVersionKey);
    if (stored != null && stored.isNotEmpty) return stored;
    return _appSettings.sentryDisclosureShown
        ? ReleaseHighlights.sentryDisclosureVersion
        : ReleaseHighlights.earliestVersion;
  }

  /// 写失败不抛：最坏结果是下次冷启动再展示一遍更新说明，不值得打断启动流程，
  /// 但要留下日志，否则「每次启动都弹」会查不到原因。
  ///
  /// **异常也要按写失败处理**：`MMKVService.setString` 重试三次后是 `rethrow`，
  /// 而这个方法挂在首页启动路径上（[ReleaseNotesPage.checkAndShow]），
  /// 让它抛出去等于用一次记账失败换掉整个启动检查。
  Future<void> setLastSeenReleaseVersion(String version) async {
    // 每次冷启动都会调一次（见 ReleaseNotesPage.checkAndShow），值没变就别写、
    // 更别通知——否则每次启动都要白白重建一遍所有监听者。
    if (_mmkv.getString(_lastSeenReleaseVersionKey) == version) return;

    if (!await _writeLastSeenReleaseVersion(version)) return;
    notifyListeners();
  }

  /// 落盘已读版本，失败与异常都只记日志。返回是否写成功。
  ///
  /// 首次安装分支（[_loadSettings]）也走它：那里原来写的是 `setBool`（内部吞异常），
  /// 换成会 rethrow 的 `setString` 之后，不接住就等于让一次写失败掀掉整个设置加载。
  Future<bool> _writeLastSeenReleaseVersion(String version) async {
    try {
      final success =
          await _mmkv.setString(_lastSeenReleaseVersionKey, version);
      if (!success) {
        AppLogger.w(
          '更新说明已读版本保存失败：MMKV setString 返回 false（version=$version）',
          source: 'SettingsService',
        );
      }
      return success;
    } catch (e, stackTrace) {
      AppLogger.w(
        '更新说明已读版本保存异常（version=$version）',
        error: e,
        stackTrace: stackTrace,
        source: 'SettingsService',
      );
      return false;
    }
  }

  ThoughterPageMode get exploreAiAssistantMode =>
      AIAssistantPageModeStorage.fromStorage(
        _mmkv.getString(_exploreAiAssistantModeKey),
      ) ??
      ThoughterPageMode.chat;

  ThoughterPageMode get noteAiAssistantMode =>
      AIAssistantPageModeStorage.fromStorage(
        _mmkv.getString(_noteAiAssistantModeKey),
      ) ??
      ThoughterPageMode.noteChat;

  // 周期报告洞察是否使用AI（流式）
  bool get reportInsightsUseAI => _appSettings.reportInsightsUseAI;
  Future<void> setReportInsightsUseAI(bool enabled) async {
    _appSettings = _appSettings.copyWith(reportInsightsUseAI: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 今日思考是否使用AI（默认开启）
  bool get todayThoughtsUseAI => _appSettings.todayThoughtsUseAI;
  Future<void> setTodayThoughtsUseAI(bool enabled) async {
    _appSettings = _appSettings.copyWith(todayThoughtsUseAI: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> setExploreAiAssistantMode(ThoughterPageMode mode) async {
    await _mmkv.setString(_exploreAiAssistantModeKey, mode.storageValue);
    notifyListeners();
  }

  Future<void> setNoteAiAssistantMode(ThoughterPageMode mode) async {
    await _mmkv.setString(_noteAiAssistantModeKey, mode.storageValue);
    notifyListeners();
  }

  // 是否启用 Sentry 诊断与性能上报
  bool get sentryEnabled => _appSettings.sentryEnabled;
  Future<void> setSentryEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(sentryEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    SentryDatabaseTracing.configure(enabled: enabled);
    SentryNetworkTracing.configure(enabled: enabled);
    SentryHelper.startIfEnabled(enabled);
    notifyListeners();
  }

  // Sentry 错误日志上报提示弹窗是否已显示过
  bool get sentryDisclosureShown => _appSettings.sentryDisclosureShown;
  Future<void> setSentryDisclosureShown(bool shown) async {
    _appSettings = _appSettings.copyWith(sentryDisclosureShown: shown);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  int get trashRetentionDays => _appSettings.trashRetentionDays;
  String? get trashRetentionLastModified =>
      _appSettings.trashRetentionLastModified;

  Future<void> setTrashRetentionDays(int days, {DateTime? modifiedAt}) async {
    final normalizedDays = AppSettings.normalizeTrashRetentionDays(days);
    final modified = (modifiedAt ?? DateTime.now()).toUtc().toIso8601String();
    _appSettings = _appSettings.copyWith(
      trashRetentionDays: normalizedDays,
      trashRetentionLastModified: modified,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<bool> applyIncomingTrashSettings(
    Map<String, dynamic>? incoming,
  ) async {
    if (incoming == null) {
      return false;
    }

    if (!incoming.containsKey('retention_days')) {
      return false;
    }

    final dynamic rawDays = incoming['retention_days'];
    int? parsedDays;
    if (rawDays is int) {
      parsedDays = rawDays;
    } else if (rawDays is num) {
      if (rawDays != rawDays.toInt()) {
        logWarning('忽略非整数的回收站保留期: $rawDays', source: 'SettingsService');
        return false;
      }
      parsedDays = rawDays.toInt();
    } else if (rawDays is String) {
      parsedDays = int.tryParse(rawDays);
    }

    if (parsedDays == null) {
      return false;
    }

    if (!AppSettings.allowedTrashRetentionDays.contains(parsedDays)) {
      logWarning('忽略非法的回收站保留期: $parsedDays', source: 'SettingsService');
      return false;
    }

    final incomingDays = AppSettings.normalizeTrashRetentionDays(parsedDays);
    final incomingLastModified = incoming['last_modified']?.toString();
    String? normalizedIncomingTimestamp;
    if (incomingLastModified != null && incomingLastModified.isNotEmpty) {
      if (!LWWUtils.isValidTimestamp(incomingLastModified)) {
        logWarning(
          '忽略无效的回收站保留期时间戳: $incomingLastModified',
          source: 'SettingsService',
        );
        return false;
      }
      normalizedIncomingTimestamp = LWWUtils.normalizeTimestamp(
        incomingLastModified,
      );
    } else {
      // 输入无时间戳：只有本地也无时间戳时才接受（直接赋值），否则跳过
      final localLastModified = _appSettings.trashRetentionLastModified;
      final hasLocalTimestamp =
          localLastModified != null && localLastModified.isNotEmpty;
      if (hasLocalTimestamp) {
        // 本地有时间戳，远端无时间戳 → 跳过导入
        return false;
      }
      // 本地也无时间戳 → 直接接受输入值，不设置时间戳
      _appSettings = _appSettings.copyWith(trashRetentionDays: incomingDays);
      await _mmkv.setString(
        _appSettingsKey,
        json.encode(_appSettings.toJson()),
      );
      notifyListeners();
      return true;
    }

    final decision = LWWDecisionMaker.makeDecision(
      localTimestamp: _appSettings.trashRetentionLastModified,
      remoteTimestamp: normalizedIncomingTimestamp,
    );

    if (!decision.shouldUseRemote) {
      return false;
    }

    _appSettings = _appSettings.copyWith(
      trashRetentionDays: incomingDays,
      trashRetentionLastModified: normalizedIncomingTimestamp,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
    return true;
  }

  // 折叠时优先显示加粗内容
  bool get prioritizeBoldContentInCollapse =>
      _appSettings.prioritizeBoldContentInCollapse;
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {
    _appSettings = _appSettings.copyWith(
      prioritizeBoldContentInCollapse: enabled,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否显示心形按钮
  bool get showFavoriteButton => _appSettings.showFavoriteButton;
  Future<void> setShowFavoriteButton(bool enabled) async {
    _appSettings = _appSettings.copyWith(showFavoriteButton: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否仅使用本地笔记作为一言
  bool get useLocalQuotesOnly => _appSettings.useLocalQuotesOnly;
  Future<void> setUseLocalQuotesOnly(bool enabled) async {
    _appSettings = _appSettings.copyWith(useLocalQuotesOnly: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 每日一言 provider
  String get dailyQuoteProvider => _appSettings.dailyQuoteProvider;
  Future<void> setDailyQuoteProvider(String provider) async {
    _appSettings = _appSettings.copyWith(dailyQuoteProvider: provider);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // API Ninjas 分类选择
  List<String> get apiNinjasCategories => _appSettings.apiNinjasCategories;
  Future<void> setApiNinjasCategories(List<String> categories) async {
    _appSettings = _appSettings.copyWith(apiNinjasCategories: categories);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否显示笔记编辑时间
  bool get showNoteEditTime => _appSettings.showNoteEditTime;
  Future<void> setShowNoteEditTime(bool enabled) async {
    _appSettings = _appSettings.copyWith(showNoteEditTime: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 无网/离线时的一言回退数据源
  String get offlineQuoteSource => _appSettings.offlineQuoteSource;
  Future<void> setOfflineQuoteSource(String source) async {
    _appSettings = _appSettings.copyWith(offlineQuoteSource: source);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否显示精确时间（时:分）
  bool get showExactTime => _appSettings.showExactTime;
  Future<void> setShowExactTime(bool enabled) async {
    _appSettings = _appSettings.copyWith(showExactTime: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者模式：首次打开后首次滑动卡顿监测开关
  bool get enableFirstOpenScrollPerfMonitor =>
      _appSettings.enableFirstOpenScrollPerfMonitor;
  Future<void> setEnableFirstOpenScrollPerfMonitor(bool enabled) async {
    _appSettings = _appSettings.copyWith(
      enableFirstOpenScrollPerfMonitor: enabled,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者实验：记录页卡片禁用阴影
  bool get noteListDisableCardShadows =>
      _appSettings.noteListDisableCardShadows;
  Future<void> setNoteListDisableCardShadows(bool enabled) async {
    _appSettings = _appSettings.copyWith(noteListDisableCardShadows: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者实验：记录页折叠遮罩禁用背景模糊
  bool get noteListDisableBackdropBlur =>
      _appSettings.noteListDisableBackdropBlur;
  Future<void> setNoteListDisableBackdropBlur(bool enabled) async {
    _appSettings = _appSettings.copyWith(noteListDisableBackdropBlur: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者实验：AddNoteDialog 自动聚焦开关
  bool get addNoteDialogAutoFocus => _appSettings.addNoteDialogAutoFocus;
  Future<void> setAddNoteDialogAutoFocus(bool enabled) async {
    _appSettings = _appSettings.copyWith(addNoteDialogAutoFocus: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者实验：AddNoteDialog 延迟获取位置/天气元数据开关
  bool get addNoteDialogDeferAutoMetadata =>
      _appSettings.addNoteDialogDeferAutoMetadata;
  Future<void> setAddNoteDialogDeferAutoMetadata(bool enabled) async {
    _appSettings = _appSettings.copyWith(
      addNoteDialogDeferAutoMetadata: enabled,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者实验：记录页添加/更新卡片动画类型 ('scale' 或 'slide')
  String get noteInsertAnimationType => _appSettings.noteInsertAnimationType;
  Future<void> setNoteInsertAnimationType(String type) async {
    _appSettings = _appSettings.copyWith(noteInsertAnimationType: type);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 记录页折叠卡片里媒体的显示方式，取值见 [NoteCardMediaStyle]。
  ///
  /// 三种版式的折叠 Document 不同（inline 保留嵌入、另两种摘掉），缓存失效由
  /// `QuoteContent` 把版式并进 Document / Controller 的缓存键来保证——服务层
  /// 不反向依赖 widget 层去清缓存。
  String get noteCardMediaStyle => _appSettings.noteCardMediaStyle;
  Future<void> setNoteCardMediaStyle(String style) async {
    _appSettings = _appSettings.copyWith(
      noteCardMediaStyle: NoteCardMediaStyle.normalize(style),
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 语言设置：获取当前语言代码（null 表示跟随系统）
  String? get localeCode => _appSettings.localeCode;

  /// 设置语言代码，null 表示跟随系统
  Future<void> setLocale(String? localeCode) async {
    if (localeCode == null) {
      _appSettings = _appSettings.copyWith(clearLocale: true);
    } else {
      _appSettings = _appSettings.copyWith(localeCode: localeCode);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 隐藏笔记功能设置
  bool get enableHiddenNotes => _appSettings.enableHiddenNotes;
  Future<void> setEnableHiddenNotes(bool enabled) async {
    _appSettings = _appSettings.copyWith(enableHiddenNotes: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 访问隐藏笔记是否需要生物识别验证
  bool get requireBiometricForHidden => _appSettings.requireBiometricForHidden;
  Future<void> setRequireBiometricForHidden(bool enabled) async {
    _appSettings = _appSettings.copyWith(requireBiometricForHidden: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 添加笔记时自动勾选位置
  bool get autoAttachLocation => _appSettings.autoAttachLocation;
  Future<void> setAutoAttachLocation(bool enabled) async {
    _appSettings = _appSettings.copyWith(autoAttachLocation: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 添加笔记时自动勾选天气
  bool get autoAttachWeather => _appSettings.autoAttachWeather;
  Future<void> setAutoAttachWeather(bool enabled) async {
    _appSettings = _appSettings.copyWith(autoAttachWeather: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 是否启用从外部文本摘录到应用
  bool get excerptIntentEnabled => _appSettings.excerptIntentEnabled;
  Future<void> setExcerptIntentEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(excerptIntentEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    await _syncExcerptIntentEntryPoint();
    notifyListeners();
  }

  // 默认作者（自动填充）
  String? get defaultAuthor => _appSettings.defaultAuthor;
  Future<void> setDefaultAuthor(String? author) async {
    if (author == null || author.isEmpty) {
      _appSettings = _appSettings.copyWith(clearDefaultAuthor: true);
    } else {
      _appSettings = _appSettings.copyWith(defaultAuthor: author);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 默认出处（自动填充）
  String? get defaultSource => _appSettings.defaultSource;
  Future<void> setDefaultSource(String? source) async {
    if (source == null || source.isEmpty) {
      _appSettings = _appSettings.copyWith(clearDefaultSource: true);
    } else {
      _appSettings = _appSettings.copyWith(defaultSource: source);
    }
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 默认标签 ID 列表（自动填充）
  List<String> get defaultTagIds => _appSettings.defaultTagIds;
  Future<void> setDefaultTagIds(List<String> tagIds) async {
    _appSettings = _appSettings.copyWith(defaultTagIds: tagIds);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 参与过的周年庆典记录
  List<AnniversaryParticipation> get anniversaryParticipation =>
      _appSettings.anniversaryParticipation;

  // 参与过的庆典届数（升序）
  List<int> get anniversaryShownYears => _appSettings.anniversaryShownYears;

  /// 记下第 [year] 届庆典已参与。已经有记录的届数不覆盖，保留首次时间。
  Future<void> markAnniversaryShown(
    int year, {
    DateTime? seenAt,
    String? appVersion,
  }) async {
    if (year <= 0 || _appSettings.anniversaryShownYears.contains(year)) {
      return;
    }
    final records = [
      ..._appSettings.anniversaryParticipation,
      AnniversaryParticipation(
        year: year,
        seenAt: (seenAt ?? DateTime.now()).toUtc(),
        appVersion: appVersion,
      ),
    ]..sort((a, b) => a.year.compareTo(b.year));
    _appSettings = _appSettings.copyWith(anniversaryParticipation: records);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 庆典动画是否启用（开发者模式控制）
  bool get anniversaryAnimationEnabled =>
      _appSettings.anniversaryAnimationEnabled;
  Future<void> setAnniversaryAnimationEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(anniversaryAnimationEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 开发者模式模拟的周年届数，0 表示按真实日期判断
  int get anniversarySimulatedYear => _appSettings.anniversarySimulatedYear;
  Future<void> setAnniversarySimulatedYear(int year) async {
    _appSettings = _appSettings.copyWith(
      anniversarySimulatedYear: year < 0 ? 0 : year,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 开发者模式的「模拟周年庆典」开关：一步切换模拟届数并清空参与记录。
  ///
  /// 两件事得一起做 —— 只设届数的话，「每届只自动播一次」会拿旧记录把启动弹窗挡掉，
  /// 开关就等于只换了张横幅；关闭时同样清一遍，免得模拟产生的记录混进真实数据。
  Future<void> setAnniversarySimulationEnabled(
    bool enabled, {
    required int year,
  }) async {
    _appSettings = _appSettings.copyWith(
      anniversarySimulatedYear: enabled ? (year < 1 ? 1 : year) : 0,
      anniversaryParticipation: const [],
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 清空庆典参与记录（开发者模式使用）。
  ///
  /// 连带清掉老用户标记，模拟「新用户第一次看到庆典」。
  Future<void> resetAnniversaryParticipation() async {
    _appSettings = _appSettings.copyWith(anniversaryParticipation: const []);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 跳过非全屏编辑器，直接进入全屏编辑器
  bool get skipNonFullscreenEditor => _appSettings.skipNonFullscreenEditor;
  Future<void> setSkipNonFullscreenEditor(bool enabled) async {
    _appSettings = _appSettings.copyWith(skipNonFullscreenEditor: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 默认导出格式配置
  String get exportFormat => _appSettings.exportFormat;
  Future<void> setExportFormat(String format) async {
    final validatedFormat =
        const ['card', 'pdf'].contains(format) ? format : 'card';
    _appSettings = _appSettings.copyWith(exportFormat: validatedFormat);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  SettingsService(this._prefs);

  /// 创建SettingsService实例的静态工厂方法
  static Future<SettingsService> create() async {
    // 获取SharedPreferences实例
    final prefs = await SharedPreferences.getInstance();
    // 创建SettingsService实例
    final service = SettingsService(prefs);
    // 初始化 MMKVService
    await service._mmkv.init();
    // 加载设置
    await service._loadSettings();
    // 返回初始化完成的实例
    return service;
  }

  Future<void> setSyncSkipConfirm(bool value) async {
    await _mmkv.setBool(_syncSkipConfirmKey, value);
    notifyListeners();
  }

  Future<void> setSyncDefaultIncludeMedia(bool value) async {
    await _mmkv.setBool(_syncDefaultIncludeMediaKey, value);
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    // 检查是否需要迁移数据
    await _migrateDataIfNeeded();

    // 检查应用是否是首次安装或升级
    final bool wasInstalledBefore = _mmkv.getBool(_appInstalledKey) ?? false;

    // 如果是首次安装，标记为已安装
    if (!wasInstalledBefore) {
      logDebug('检测到首次安装，将重置引导页面状态');
      await _mmkv.setBool(_appInstalledKey, true);
      // 新装用户没有「更新」可言：把已读版本直接记成当前登记表的最新版，
      // 免得他刚走完引导页就被一页「更新内容」拦住。写失败只记日志——
      // 代价是这个新用户下次启动会被当成老用户看一次更新说明，
      // 不值得让整个设置加载失败。
      await _writeLastSeenReleaseVersion(ReleaseHighlights.latestVersion);

      // 首次安装时，载入应用默认设置
      _loadAppSettings();
      _appSettings = _appSettings.copyWith(
        hasCompletedOnboarding: false,
        sentryDisclosureShown: true, // 新安装用户不弹窗
      );
      await _mmkv.setString(
        _appSettingsKey,
        json.encode(_appSettings.toJson()),
      );
    } else {
      // 检查是否有升级标记
      final hasUpgradeTag = _mmkv.getBool(_appUpgradedKey) ?? false;

      // 如果设置了升级标记，刷新引导状态
      if (hasUpgradeTag) {
        logDebug('检测到应用升级标记，将重置引导页面状态');

        // 重置升级标记
        await _mmkv.setBool(_appUpgradedKey, false);

        // 重置引导状态，但保留其他设置
        _loadAppSettings();
        _appSettings = _appSettings.copyWith(hasCompletedOnboarding: false);
        await _mmkv.setString(
          _appSettingsKey,
          json.encode(_appSettings.toJson()),
        );
      }
    }
    // 继续加载其他设置
    await _loadAISettings();
    await _loadMultiAISettings(); // 新增
    await _loadLocalAISettings(); // 新增本地AI设置加载
    _loadAppSettings();
    _loadThemeMode();

    await _secureLegacyApiKey();
    await _syncExcerptIntentEntryPoint();

    notifyListeners();
  }

  Future<void> _syncExcerptIntentEntryPoint() async {
    if (kIsWeb) {
      return;
    }

    await _excerptIntentService.syncEntryPointEnabled(
      _appSettings.excerptIntentEnabled,
    );
  }

  // 加载AI设置（简化版，主要用于向后兼容）
  Future<void> _loadAISettings() async {
    final String? aiSettingsJson =
        _mmkv.getString(_aiSettingsKey) ?? _prefs.getString(_aiSettingsKey);

    if (aiSettingsJson != null) {
      final Map<String, dynamic> settingsMap = json.decode(aiSettingsJson);
      _aiSettings = AISettings.fromJson(settingsMap);
    } else {
      _aiSettings = AISettings.defaultSettings();
      await _mmkv.setString(_aiSettingsKey, json.encode(_aiSettings.toJson()));
    }
  }

  /// 修复：加载应用设置，增加数据验证和迁移安全性
  void _loadAppSettings() {
    try {
      final String? appSettingsJson =
          _mmkv.getString(_appSettingsKey) ?? _prefs.getString(_appSettingsKey);

      if (appSettingsJson != null) {
        try {
          final jsonData = json.decode(appSettingsJson);
          _appSettings = AppSettings.fromJson(jsonData);

          // 验证设置的完整性
          if (!_validateAppSettings(_appSettings)) {
            logDebug('应用设置验证失败，重置为默认设置');
            _appSettings = AppSettings.defaultSettings();
            unawaited(_saveAppSettings());
          } else {
            // 确保一言类型不为空，如果为空则设置为默认全选
            if (_appSettings.hitokotoType.isEmpty) {
              _appSettings = AppSettings.defaultSettings();
              unawaited(_saveAppSettings());
              logDebug('检测到一言类型为空，已重置为默认全选值');
            }
          }
        } catch (e) {
          logDebug('解析应用设置JSON失败: $e，使用默认设置');
          _appSettings = AppSettings.defaultSettings();
          unawaited(_saveAppSettings());
        }
      } else {
        _appSettings = AppSettings.defaultSettings();
        unawaited(_saveAppSettings());
        logDebug('首次启动，已初始化默认一言类型设置: ${_appSettings.hitokotoType}');
      }
    } catch (e) {
      logDebug('加载应用设置失败: $e，使用默认设置');
      _appSettings = AppSettings.defaultSettings();
    }
  }

  /// 修复：验证应用设置的完整性
  bool _validateAppSettings(AppSettings settings) {
    try {
      // 验证必要字段
      if (settings.hitokotoType.isEmpty) return false;
      if (settings.dailyQuoteProvider.isEmpty) return false;

      // 验证默认起始页面值
      if (settings.defaultStartPage < 0 || settings.defaultStartPage > 2) {
        return false;
      }

      // 验证其他关键设置
      return true;
    } catch (e) {
      logDebug('验证应用设置时出错: $e');
      return false;
    }
  }

  /// 修复：安全保存应用设置
  ///
  /// MMKV 写入是异步的且返回是否成功，必须 await 并检查返回值，
  /// 否则 try/catch 是死代码、写入失败会被静默吞掉。
  Future<void> _saveAppSettings() async {
    try {
      final success = await _mmkv.setString(
        _appSettingsKey,
        json.encode(_appSettings.toJson()),
      );
      if (!success) {
        AppLogger.e(
          '保存应用设置失败：MMKV setString 返回 false（key=$_appSettingsKey）',
          source: 'SettingsService',
        );
      }
    } catch (e, s) {
      AppLogger.e(
        '保存应用设置异常',
        error: e,
        stackTrace: s,
        source: 'SettingsService',
      );
    }
  }

  // 加载主题模式
  void _loadThemeMode() {
    // 加载主题模式 - 优先从MMKV读取
    String? themeModeString = _mmkv.getString(_themeModeKey);

    // 如果MMKV中没有，则从SharedPreferences加载
    if (themeModeString == null || themeModeString.isEmpty) {
      dynamic themeModeValue = _prefs.get(_themeModeKey);
      themeModeString = themeModeValue?.toString();
    }

    if (themeModeString != null && themeModeString.isNotEmpty) {
      try {
        _themeMode = ThemeMode.values.byName(themeModeString);
      } catch (e) {
        _themeMode = ThemeMode.system; // 默认回退到系统主题
      }
    } else {
      _themeMode = ThemeMode.system; // 默认 ThemeMode.system
    }
  }

  // 将数据从SharedPreferences迁移到MMKV (只在首次升级后执行一次)
  Future<void> _migrateDataIfNeeded() async {
    // 检查是否已经完成迁移
    if (_mmkv.getBool(_migrationCompleteKey) == true) {
      logDebug('数据迁移已完成，不再重复执行');
      return;
    }

    logDebug('开始从SharedPreferences迁移数据到MMKV...');

    try {
      // 迁移AI设置
      final aiSettings = _prefs.getString(_aiSettingsKey);
      if (aiSettings != null) {
        await _mmkv.setString(_aiSettingsKey, aiSettings);
        logDebug('AI设置已迁移到MMKV');
      }

      // 迁移应用设置
      final appSettings = _prefs.getString(_appSettingsKey);
      if (appSettings != null) {
        await _mmkv.setString(_appSettingsKey, appSettings);
        logDebug('应用设置已迁移到MMKV');
      }

      // 迁移主题设置
      final themeMode = _prefs.getString(_themeModeKey);
      if (themeMode != null) {
        await _mmkv.setString(_themeModeKey, themeMode);
        logDebug('主题设置已迁移到MMKV');
      }

      // 检查旧的数据库迁移Key，如果存在且为true，则设置新的Key，但保留旧Key以保持兼容性
      if (_mmkv.containsKey(_databaseMigrationCompleteKey)) {
        final oldMigrationComplete =
            _mmkv.getBool(_databaseMigrationCompleteKey) ?? false;
        if (oldMigrationComplete) {
          await _mmkv.setBool(_initialDatabaseSetupCompleteKey, true);
          logDebug('已将旧的数据库迁移完成标记同步到新的初始设置完成标记');
        }
        // 注意：保留旧Key以保持兼容性，不移除
      }

      // 标记迁移完成
      await _mmkv.setBool(_migrationCompleteKey, true);
      logDebug('所有设置数据已成功迁移到MMKV');
    } catch (e) {
      logDebug('迁移数据失败: $e');
      // 失败不阻塞应用运行，下次启动会重试
    }
  }

  Future<void> updateAISettings(AISettings settings) async {
    // Security: Ensure we don't persist API key in plaintext in legacy AISettings
    if (settings.apiKey.isNotEmpty) {
      _aiSettings = settings.copyWith(apiKey: '');
    } else {
      _aiSettings = settings;
    }
    final Map<String, dynamic> settingsMap = _aiSettings.toJson();
    settingsMap.remove('apiKey');
    await _mmkv.setString(_aiSettingsKey, json.encode(settingsMap));
    notifyListeners();
  }

  Future<void> updateAppSettings(AppSettings settings) async {
    _appSettings = settings;
    await _mmkv.setString(_appSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _mmkv.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  // 设置应用升级标记，用于触发显示引导页
  Future<void> setAppUpgraded() async {
    await _mmkv.setBool(_appUpgradedKey, true);
  }

  /// 设置初始数据库设置（创建/升级）已完成
  Future<void> setInitialDatabaseSetupComplete(bool isComplete) async {
    await _mmkv.setBool(_initialDatabaseSetupCompleteKey, isComplete);
    logDebug('初始数据库设置完成状态设置为: $isComplete');
    // notifyListeners(); // 根据需要决定是否通知监听器
  }

  /// 检查初始数据库设置（创建/升级）是否已完成
  bool isInitialDatabaseSetupComplete() {
    // 默认返回 false，确保只有显式设置后才为 true
    return _mmkv.getBool(_initialDatabaseSetupCompleteKey) ?? false;
  }

  // 设置数据库迁移是否完成
  Future<void> setDatabaseMigrationComplete(bool isComplete) async {
    await _mmkv.setBool(_databaseMigrationCompleteKey, isComplete);
  }

  // 检查数据库迁移是否已完成
  bool isDatabaseMigrationComplete() {
    return _mmkv.getBool(_databaseMigrationCompleteKey) ?? false;
  }

  // 通过检查应用设置中的引导完成标志判断用户是否完成了引导
  bool hasCompletedOnboarding() {
    return _appSettings.hasCompletedOnboarding;
  }

  // 设置用户是否完成了引导流程
  Future<void> setHasCompletedOnboarding(bool completed) async {
    _appSettings = _appSettings.copyWith(hasCompletedOnboarding: completed);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  // 获取AI卡片生成功能是否启用
  bool get aiCardGenerationEnabled {
    return _appSettings.aiCardGenerationEnabled;
  }

  // 设置AI卡片生成功能是否启用
  Future<void> setAICardGenerationEnabled(bool enabled) async {
    _appSettings = _appSettings.copyWith(aiCardGenerationEnabled: enabled);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 获取上次记录的版本号
  String? getAppVersion() {
    return _mmkv.getString(_lastVersionKey);
  }

  /// 设置当前版本号
  Future<void> setAppVersion(String version) async {
    await _mmkv.setString(_lastVersionKey, version);
  }

  // 加载多provider AI设置
  Future<void> _loadMultiAISettings() async {
    final String? multiAiSettingsJson = _mmkv.getString(_multiAiSettingsKey);

    if (multiAiSettingsJson != null) {
      try {
        final Map<String, dynamic> settingsMap = json.decode(
          multiAiSettingsJson,
        );
        _multiAISettings = MultiAISettings.fromJson(settingsMap);
      } catch (e) {
        logDebug('加载多provider设置失败: $e');
        _multiAISettings = MultiAISettings.defaultSettings();
        await saveMultiAISettings(_multiAISettings);
      }
    } else {
      _multiAISettings = MultiAISettings.defaultSettings();
      await saveMultiAISettings(_multiAISettings);
    }
  }

  /// 保存多provider AI设置
  Future<void> saveMultiAISettings(MultiAISettings settings) async {
    _multiAISettings = settings;

    // 保存到MMKV存储
    await _mmkv.setString(_multiAiSettingsKey, json.encode(settings.toJson()));

    notifyListeners();
  }

  /// 更新多provider AI设置
  Future<void> updateMultiAISettings(MultiAISettings settings) async {
    await saveMultiAISettings(settings);
  }

  /// 加载本地AI设置
  Future<void> _loadLocalAISettings() async {
    final String? localAiSettingsJson = _mmkv.getString(_localAiSettingsKey);

    if (localAiSettingsJson != null) {
      try {
        final Map<String, dynamic> settingsMap = json.decode(
          localAiSettingsJson,
        );
        _localAISettings = LocalAISettings.fromJson(settingsMap);
      } catch (e) {
        logDebug('加载本地AI设置失败: $e');
        _localAISettings = LocalAISettings.defaultSettings();
        await saveLocalAISettings(_localAISettings);
      }
    } else {
      _localAISettings = LocalAISettings.defaultSettings();
      await saveLocalAISettings(_localAISettings);
    }
  }

  /// 保存本地AI设置
  Future<void> saveLocalAISettings(LocalAISettings settings) async {
    _localAISettings = settings;
    await _mmkv.setString(_localAiSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  /// 更新本地AI设置
  Future<void> updateLocalAISettings(LocalAISettings settings) async {
    await saveLocalAISettings(settings);
  }

  /// 获取所有设置数据用于备份
  Map<String, dynamic> getAllSettingsForBackup() {
    return {
      'ai_settings': _aiSettings.toJson(),
      'multi_ai_settings': _multiAISettings.toJson(),
      'local_ai_settings': _localAISettings.toJson(),
      'app_settings': _appSettings.toJson(),
      'theme_mode': _themeMode.index,
      'device_id': getOrCreateDeviceId(),
    };
  }

  /// 从备份数据恢复所有设置
  Future<void> restoreAllSettingsFromBackup(
    Map<String, dynamic> backupData,
  ) async {
    try {
      // 恢复AI设置
      if (backupData.containsKey('ai_settings')) {
        final aiSettingsJson =
            backupData['ai_settings'] as Map<String, dynamic>;
        final aiSettings = AISettings.fromJson(aiSettingsJson);
        await updateAISettings(aiSettings);
      }

      // 恢复多provider AI设置
      if (backupData.containsKey('multi_ai_settings')) {
        final multiAiSettingsJson =
            backupData['multi_ai_settings'] as Map<String, dynamic>;
        final multiAiSettings = MultiAISettings.fromJson(multiAiSettingsJson);
        await saveMultiAISettings(multiAiSettings);
      }

      // 恢复本地AI设置
      if (backupData.containsKey('local_ai_settings')) {
        final localAiSettingsJson =
            backupData['local_ai_settings'] as Map<String, dynamic>;
        final localAiSettings = LocalAISettings.fromJson(localAiSettingsJson);
        await saveLocalAISettings(localAiSettings);
      }

      // 恢复应用设置
      if (backupData.containsKey('app_settings')) {
        final appSettingsJson =
            backupData['app_settings'] as Map<String, dynamic>;
        final appSettings = AppSettings.fromJson(appSettingsJson);
        await updateAppSettings(appSettings);
      }

      // 恢复主题模式
      if (backupData.containsKey('theme_mode')) {
        final themeModeIndex = backupData['theme_mode'] as int;
        final themeMode = ThemeMode.values[themeModeIndex];
        await updateThemeMode(themeMode);
      }

      // 恢复/记录 device_id（不覆盖本地已有，仅在本地不存在时写入，保持源ID可用于审计）
      if (backupData.containsKey('device_id')) {
        final remoteId = backupData['device_id'];
        if ((_mmkv.getString(_deviceIdKey) ?? '').isEmpty &&
            remoteId is String &&
            remoteId.isNotEmpty) {
          await _mmkv.setString(_deviceIdKey, remoteId);
        }
      }

      logDebug('设置数据恢复完成');
    } catch (e) {
      AppLogger.e('设置数据恢复失败', error: e, source: 'SettingsService');
      rethrow;
    }
  }

  /// 获取或生成设备唯一ID（持久化）
  String getOrCreateDeviceId() {
    final existing = _mmkv.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final newId =
        '${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode.toRadixString(16)}';
    // 同步方法内无法 await，使用 unawaited + 内部自处理错误，避免写入失败被静默吞掉
    unawaited(_persistDeviceId(newId));
    return newId;
  }

  /// 持久化设备ID，写入失败时明确记录（设备ID丢失会导致同步身份漂移）
  Future<void> _persistDeviceId(String deviceId) async {
    try {
      final success = await _mmkv.setString(_deviceIdKey, deviceId);
      if (!success) {
        AppLogger.e(
          '设备ID持久化失败：MMKV setString 返回 false，下次启动可能生成新的设备ID',
          source: 'SettingsService',
        );
      }
    } catch (e, s) {
      AppLogger.e(
        '设备ID持久化异常',
        error: e,
        stackTrace: s,
        source: 'SettingsService',
      );
    }
  }

  /// 获取自定义字符串设置
  Future<String?> getCustomString(String key) async {
    await _mmkv.init();
    return _mmkv.getString(key);
  }

  /// 设置自定义字符串设置
  Future<void> setCustomString(String key, String value) async {
    await _mmkv.init();
    await _mmkv.setString(key, value);
  }

  /// 迁移遗留的明文API密钥到安全存储
  Future<void> _secureLegacyApiKey() async {
    if (_aiSettings.apiKey.isEmpty) {
      // 安全起见，如果在 _prefs 中还残留包含 apiKey 的 json，也要清理
      try {
        final legacyJson = _prefs.getString(_aiSettingsKey);
        if (legacyJson != null && legacyJson.contains('"apiKey"')) {
          final Map<String, dynamic> settingsMap = json.decode(legacyJson);
          if (settingsMap.containsKey('apiKey')) {
            settingsMap.remove('apiKey');
            final success = await _prefs.setString(
              _aiSettingsKey,
              json.encode(settingsMap),
            );
            if (success) {
              logDebug(
                'Cleared residual legacy API key from SharedPreferences.',
              );
            } else {
              logWarning(
                'Failed to save cleared settings to SharedPreferences: setString returned false',
                source: 'SettingsService',
              );
            }
          }
        }
      } catch (e) {
        logWarning(
          'Failed to clear residual legacy API key from SharedPreferences: $e',
          source: 'SettingsService',
        );
      }
      return;
    }

    // 确定要迁移到的服务商 ID，如果没有选中则回退到 openai 或 default
    String? providerId = _multiAISettings.currentProviderId;
    if (providerId == null) {
      // 优先寻找 openai，否则找第一个不是 default 的，如果都没有则回退到 openai
      final providers = _multiAISettings.providers;
      if (providers.any((p) => p.id == 'openai')) {
        providerId = 'openai';
      } else {
        final nonDefault = providers.where((p) => p.id != 'default');
        providerId = nonDefault.isNotEmpty ? nonDefault.first.id : 'openai';
      }
      logDebug(
        'No current provider selected. Defaulting migration to provider: $providerId',
      );
    }

    final apiKeyManager = APIKeyManager();

    try {
      // 检查安全存储中是否已有密钥
      final hasSecureKey = await apiKeyManager.hasValidProviderApiKey(
        providerId,
      );

      if (hasSecureKey) {
        // 安全存储中已有密钥，遗留的明文密钥是冗余的，可以直接清除
        logDebug('Found redundant plaintext API key in AISettings. Clearing.');
      } else {
        // 安全存储中没有密钥，尝试迁移
        await apiKeyManager.saveProviderApiKey(providerId, _aiSettings.apiKey);
        logDebug(
          'Migrated legacy plaintext API key to SecureStorage for provider: $providerId',
        );
      }
    } catch (e) {
      logWarning(
        'Error securing legacy API key: $e',
        source: 'SettingsService',
      );
      // 即使出错，也会继续执行清除操作，以保证 fail-secure (安全失败)
    }

    // 无条件清除明文密钥（Fail-Secure机制）
    // 从内存和 MMKV 中清除
    _aiSettings = _aiSettings.copyWith(apiKey: '');

    // 移除 apiKey 字段（不仅是设为空字符串，而是彻底删除）
    final Map<String, dynamic> settingsMap = _aiSettings.toJson();
    settingsMap.remove('apiKey');
    final clearedJsonString = json.encode(settingsMap);

    bool mmkvSuccess = false;
    // 写入 MMKV 增加 try-catch 和结果校验，防止失败或静默失败阻断 SharedPreferences 清理
    try {
      final success = await _mmkv.setString(_aiSettingsKey, clearedJsonString);
      if (success) {
        mmkvSuccess = true;
        logDebug('Legacy plaintext API key cleared from MMKV.');
      } else {
        logDebug(
          'MMKV setString returned false. Retrying removal via remove().',
        );
        mmkvSuccess = await _mmkv.remove(_aiSettingsKey);
        if (mmkvSuccess) {
          logDebug('Legacy plaintext API key removed from MMKV.');
        } else {
          logWarning(
            'Failed to remove legacy API key from MMKV: remove returned false',
            source: 'SettingsService',
          );
        }
      }
    } catch (e) {
      logWarning(
        'Failed to clear legacy API key from MMKV: $e',
        source: 'SettingsService',
      );
    }

    bool prefsSuccess = false;
    // 彻底：同时从 SharedPreferences 中彻底清除
    try {
      // 更新或删除 _prefs 中的 _aiSettingsKey 以彻底消灭明文密钥
      prefsSuccess = await _prefs.setString(_aiSettingsKey, clearedJsonString);
      if (prefsSuccess) {
        logDebug(
            'Legacy plaintext API key also cleared from SharedPreferences.');
      } else {
        logWarning(
          'Failed to clear legacy API key from SharedPreferences: setString returned false',
          source: 'SettingsService',
        );
      }
    } catch (e) {
      logWarning(
        'Failed to clear legacy API key from SharedPreferences: $e',
        source: 'SettingsService',
      );
    }

    if (mmkvSuccess && prefsSuccess) {
      logDebug(
        'Legacy plaintext API key completely cleared from AISettings storage layers.',
      );
    } else {
      logWarning(
        'Legacy plaintext API key was NOT completely cleared from all storage layers.',
        source: 'SettingsService',
      );
    }
  }
}

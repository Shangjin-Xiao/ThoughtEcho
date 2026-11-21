import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';
import '../models/quote_model.dart';
import '../models/ai_provider_settings.dart';
import '../models/ai_task.dart';
import '../models/weather_data.dart';
import '../models/thoughter_entry.dart';
import '../models/chat_session.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/openai_stream_service.dart';
import '../services/settings_service.dart';
import '../services/smart_push_service.dart';
import '../services/chat_session_service.dart';
import '../services/insight_history_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';
import '../utils/icon_utils.dart';
import '../utils/ai_prompt_manager.dart';
import '../utils/ai_request_helper.dart';
import '../utils/report_period_labels.dart';
import '../utils/report_period_utils.dart';
import '../utils/string_utils.dart';
import '../constants/app_constants.dart'; // 导入应用常量
import '../theme/app_semantic_colors.dart';
import '../theme/theme_style.dart';
import '../gen_l10n/app_localizations.dart';
import '../widgets/ai/experimental_badge.dart';
import 'map_memory_page.dart';
import 'thoughter_page.dart';
import 'thoughter/session_history_page.dart';

part 'explore/explore_data_loading.dart';
part 'explore/explore_time_selector.dart';
part 'explore/explore_overview.dart';
part 'explore/explore_stats.dart';
part 'explore/explore_thoughter_entry.dart';
part 'explore/explore_map_entry.dart';

/// 探索页：底部导航第三个 tab，聚合周期洞察与 Thoughter 入口。
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  // 时间范围选择
  String _selectedPeriod = 'week'; // week, month, year
  DateTime _selectedDate = DateTime.now();

  // 数据状态
  List<Quote> _periodQuotes = [];
  bool _isLoadingData = false;

  // 新增：周期"最多"统计与洞察
  String? _mostDayPeriod; // 晨曦/午后/黄昏/夜晚
  String? _mostWeather; // 晴/雨/多云
  String? _mostTopTag; // 标签名
  int _totalWordCount = 0;
  String? _notesPreview;

  // 新增：用于显示的中文文本和图标
  String? _mostDayPeriodDisplay; // 时段的中文显示
  IconData? _mostDayPeriodIcon; // 时段图标
  String? _mostWeatherDisplay; // 天气的中文显示
  IconData? _mostWeatherIcon; // 天气图标
  Object? _mostTopTagIcon; // 标签图标（IconData 或 emoji 字符串）

  String _insightText = '';
  bool _insightLoading = false;
  StreamSubscription<String>? _insightSub;

  // 当前洞察对应的数据签名，用于避免同一份数据反复重生成
  String? _insightSignature;

  // 最近的 Thoughter 会话。探索页入口每次都开新会话（只有笔记入口会恢复），
  // 所以这里把最近几条列出来，让对话有连续性而不是每次白纸一张。
  List<ChatSession> _recentSessions = const [];
  Map<String, ChatSessionOverview> _recentSessionOverviews = const {};
  static const int _recentSessionLimit = 2;

  // 流式洞察的节流缓冲：避免每个 chunk 都 setState 触发整页重排
  String _insightPending = '';
  Timer? _insightFlushTimer;
  static const Duration _insightFlushInterval = Duration(milliseconds: 120);

  // 新增：控制动画是否应该执行的标志
  bool _shouldAnimateOverview = true;
  String _dataKey = ''; // 用于跟踪数据版本

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  DatabaseService? _databaseService;
  SettingsService? _settingsService;
  String? _lastPeriodicInsightConfigKey;

  // 并发/重复加载防护：数据库在启动与同步期间会连续 notifyListeners 多次，
  // 若每次都重新拉数据并把整页切回 loading，页面就会来回闪。
  int _loadToken = 0;
  int _insightToken = 0;
  String? _activeInsightScope;
  bool _hasLoadedOnce = false;
  bool _isFetchingQuotes = false;
  bool _isPageVisible = true;
  bool _pendingPeriodicInsightRefresh = false;
  Timer? _reloadDebounce;
  static const Duration _reloadDebounceInterval = Duration(milliseconds: 300);

  static String _periodScopeKey(String period, DateTime date) {
    final range = ReportPeriodUtils.dateRange(period, date);
    if (range == null) return '$period:all';
    final start = range.start.toIso8601String().substring(0, 10);
    final end = range.end.toIso8601String().substring(0, 10);
    return '$period:$start~$end';
  }

  void _invalidateActiveInsight({bool resetDisplay = false}) {
    ++_insightToken;
    _insightSub?.cancel();
    _insightSub = null;
    _insightFlushTimer?.cancel();
    _insightFlushTimer = null;
    _insightPending = '';
    _insightSignature = null;
    _activeInsightScope = null;
    if (resetDisplay && mounted) {
      setState(() {
        _insightText = '';
        _insightLoading = false;
      });
    } else {
      _insightLoading = false;
    }
  }

  static String _normalizePeriodicInsightEndpoint(AIProviderSettings provider) {
    final trimmed = provider.apiUrl.trim();
    if (trimmed.isEmpty) return '';
    if (provider.isAnthropicMessagesApi) {
      final resolved = provider.resolveRequestUrl(trimmed);
      final uri = Uri.tryParse(resolved);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return resolved;
      }
      final port = uri.hasPort && uri.port != 0 ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port${uri.path}';
    }
    try {
      return OpenAIStreamService.normalizeOpenAIBaseUrl(trimmed);
    } on FormatException {
      return trimmed;
    }
  }

  String _periodicInsightProviderSignature(SettingsService settings) {
    final provider =
        settings.multiAISettings.resolveProviderForTask(AITask.periodicInsight);
    if (provider == null) return '-';
    final normalizedEndpoint = _normalizePeriodicInsightEndpoint(provider);
    return '${provider.id}:${provider.model}@$normalizedEndpoint';
  }

  String _buildPeriodicInsightConfigKey(SettingsService settings) {
    final provider =
        settings.multiAISettings.resolveProviderForTask(AITask.periodicInsight);
    final enabledFlag = provider == null ? '-' : '${provider.isEnabled}';
    return '${settings.reportInsightsUseAI}_${enabledFlag}_${_periodicInsightProviderSignature(settings)}';
  }

  bool _computeIsPageVisible() {
    if (!mounted) return false;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return tickerEnabled && routeCurrent;
  }

  void _onSettingsChanged() {
    final settings = _settingsService;
    if (!mounted || settings == null) return;
    final String nextKey;
    try {
      nextKey = _buildPeriodicInsightConfigKey(settings);
    } catch (_) {
      return;
    }
    if (nextKey == _lastPeriodicInsightConfigKey) return;
    _lastPeriodicInsightConfigKey = nextKey;
    _invalidateActiveInsight();
    if (!_computeIsPageVisible()) {
      _pendingPeriodicInsightRefresh = true;
      return;
    }
    _pendingPeriodicInsightRefresh = false;
    if (!_hasLoadedOnce || _isFetchingQuotes) return;
    _computeExtrasAndInsight(++_loadToken);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isVisible = _computeIsPageVisible();
    final becameVisible = !_isPageVisible && isVisible;
    _isPageVisible = isVisible;
    if (becameVisible && _pendingPeriodicInsightRefresh) {
      if (_hasLoadedOnce && !_isFetchingQuotes) {
        _pendingPeriodicInsightRefresh = false;
        _computeExtrasAndInsight(++_loadToken);
      }
    }
  }

  void _onDatabaseChanged() {
    if (!mounted) return;
    // 合并短时间内的多次数据库通知，并且静默刷新（不把已有内容换成整页转圈）
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(_reloadDebounceInterval, () {
      if (!mounted) return;
      _loadPeriodData(showLoading: false);
    });
  }

  @override
  void initState() {
    super.initState();
    try {
      final settings = context.read<SettingsService>();
      _settingsService = settings;
      final period = settings.exploreSelectedPeriod;
      if (period == 'week' || period == 'month' || period == 'year') {
        _selectedPeriod = period;
      }
      _lastPeriodicInsightConfigKey = _buildPeriodicInsightConfigKey(settings);
      _settingsService?.addListener(_onSettingsChanged);
    } catch (_) {}
    _loadPeriodData();
    _loadRecentSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _databaseService = context.read<DatabaseService>();
        _databaseService?.addListener(_onDatabaseChanged);
      }
    });
  }

  @override
  void dispose() {
    _settingsService?.removeListener(_onSettingsChanged);
    _databaseService?.removeListener(_onDatabaseChanged);
    _reloadDebounce?.cancel();
    _insightFlushTimer?.cancel();
    _insightSub?.cancel();
    ++_insightToken;
    super.dispose();
  }

  /// 周期的日期范围文案。周界交给 [ReportPeriodUtils]，别在这里再算一遍——
  /// 两处各算各的时，同一个"周"在标题和查询里可以差出一天。
  String _getDateRangeText(AppLocalizations l10n) =>
      ReportPeriodLabels.rangeText(l10n, _selectedPeriod, _selectedDate);

  /// 完整的周期标签：本周 / 上周 / 8月10日 - 8月16日。
  String _getPeriodLabel(AppLocalizations l10n) =>
      ReportPeriodLabels.label(l10n, _selectedPeriod, _selectedDate);

  /// 获取活跃天数
  int _getActiveDays() {
    final dates = _periodQuotes.map((quote) {
      final date = DateTime.parse(quote.date);
      return DateTime(date.year, date.month, date.day);
    }).toSet();
    return dates.length;
  }

  @override
  Widget build(BuildContext context) => _buildExplorePage(context);
}
